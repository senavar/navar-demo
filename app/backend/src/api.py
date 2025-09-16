import os
import uuid
from flask import (
    Blueprint,
    jsonify,
    request,
    url_for,
    current_app,
    send_from_directory,
)
from werkzeug.utils import secure_filename
from .repository import (
    get_all_birthdays,
    add_new_birthday,
    get_birthday_by_id,
    update_birthday_in_db,
    delete_birthday_from_db,
    mongo_status,
)
from . import azure_blob

# --- BLUEPRINT SETUP ---
bp = Blueprint('api', __name__, url_prefix='/api')

# --- HELPER FUNCTIONS ---
def allowed_file(filename):
    """Checks if the file extension is allowed."""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in {'png', 'jpg', 'jpeg'}

def delete_picture_file(filename):
    """Deletes local file or blob (best effort)."""
    if not filename:
        return
    if azure_blob.is_configured():
        azure_blob.delete_blob(filename)
        return
    try:  # local fallback
        upload_folder = os.path.join(current_app.instance_path, 'uploads')
        os.remove(os.path.join(upload_folder, filename))
    except (FileNotFoundError, OSError):
        pass

# --- API ROUTES ---

@bp.route('/birthdays', methods=['GET'])
def get_birthdays():
    """Retrieves all birthdays and adds full URLs for profile pictures."""
    birthdays_list = get_all_birthdays()
    for b in birthdays_list:
        pic = b.get('profile_picture')
        if pic:
            if azure_blob.is_configured():
                b['profile_picture_url'] = azure_blob.get_blob_url(pic)
            else:
                b['profile_picture_url'] = url_for('api.uploaded_file', filename=pic, _external=True)
    return jsonify(birthdays_list)

@bp.route('/healthz', methods=['GET'])
def healthz():
    """Basic health endpoint for liveness/readiness probes.
    Returns 200 always; could be extended to check Mongo / blob in future."""
    return jsonify({"status": "ok"})

@bp.route('/storage-status', methods=['GET'])
def storage_status():
    """Diagnostics endpoint exposing storage backend status (Mongo vs JSON)."""
    status = mongo_status()
    # Add blob status too
    status["blob_configured"] = azure_blob.is_configured()
    return jsonify(status)

@bp.route('/birthdays', methods=['POST'])
def create_birthday():
    """Adds a new birthday, handling an optional file upload.

    Supports multipart/form-data (primary) and application/json (fallback) to ease
    debugging when proxies strip multipart bodies.
    """
    # Log request envelope (non-PII) for diagnostics
    try:
        current_app.logger.info(
            "create_birthday inbound content_type=%s len_form=%d len_files=%d", 
            request.content_type,
            len(request.form or {}),
            len(request.files or {}),
        )
    except Exception:
        pass

    unique_filename = None
    # Handle optional picture
    if 'profile_picture' in request.files:
        file = request.files['profile_picture']
        if file and file.filename != '' and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            unique_filename = f"{uuid.uuid4()}_{filename}"
            if azure_blob.is_configured():
                blob_name, _ = azure_blob.upload_image(file, unique_filename)
                if blob_name:
                    unique_filename = blob_name
                else:
                    return jsonify({"message": "Image upload failed"}), 500
            else:
                upload_folder = os.path.join(current_app.instance_path, 'uploads')
                os.makedirs(upload_folder, exist_ok=True)
                file.save(os.path.join(upload_folder, unique_filename))
        elif file and file.filename != '':
            return jsonify({"message": "Invalid file type"}), 400

    # Extract payload (form first, JSON fallback)
    payload_source = 'form'
    if (request.is_json and not request.form) or (request.is_json and 'name' not in request.form):
        data = request.get_json(silent=True) or {}
        payload_source = 'json'
        raw_name = (data.get('name') or '').strip()
        year_raw = data.get('year')
        month_raw = data.get('month')
        day_raw = data.get('day')
    else:
        raw_name = (request.form.get('name') or '').strip()
        year_raw = request.form.get('year')
        month_raw = request.form.get('month')
        day_raw = request.form.get('day')

    # Coerce / validate
    errors = []
    name = raw_name
    try:
        year = int(year_raw) if year_raw not in (None, '') else None
    except ValueError:
        errors.append("Year must be an integer")
        year = None
    try:
        month = int(month_raw) if month_raw not in (None, '') else None
    except ValueError:
        errors.append("Month must be an integer")
        month = None
    try:
        day = int(day_raw) if day_raw not in (None, '') else None
    except ValueError:
        errors.append("Day must be an integer")
        day = None

    if not name:
        errors.append("Name is required")
    if year is None or year < 1900 or year > 2100:
        errors.append("Year must be a 4-digit number between 1900 and 2100")
    if month is None or month < 1 or month > 12:
        errors.append("Month must be between 1 and 12")
    if day is None or day < 1 or day > 31:
        errors.append("Day must be between 1 and 31")

    # Calendar validation
    if not errors and all(v is not None for v in (year, month, day)):
        from datetime import date
        try:
            date(year, month, day)
        except ValueError as ve:
            errors.append(f"Invalid calendar date: {ve}")

    if errors:
        try:
            current_app.logger.warning(
                "create_birthday validation_errors=%s source=%s", errors, payload_source
            )
        except Exception:
            pass
        return jsonify({
            "message": "Validation failed",
            "errors": errors,
            "source": payload_source
        }), 400

    new_person = {
        "name": name,
        "year": year,
        "month": month,
        "day": day,
        "profile_picture": unique_filename
    }

    added = add_new_birthday(new_person)
    return jsonify({"message": "Birthday added successfully", "person": added}), 201

@bp.route('/birthdays/<int:id>', methods=['PUT'])
def update_birthday(id):
    """Updates an existing birthday, including picture management."""
    person = get_birthday_by_id(id)
    if not person:
        return jsonify({"message": "Birthday not found"}), 404
    try:
        update_data = {
            "name": request.form['name'],
            "year": int(request.form['year']),
            "month": int(request.form['month']),
            "day": int(request.form['day']),
        }
    except (KeyError, ValueError) as e:
        return jsonify({"message": f"Invalid form data provided: {e}"}), 400

    # Check for picture deletion flag from the frontend
    if request.form.get('delete_picture') == 'true':
        delete_picture_file(person.get('profile_picture'))
        update_data['profile_picture'] = None
    
    # Check for a new file upload
    if 'profile_picture' in request.files:
        file = request.files['profile_picture']
        if file and file.filename != '' and allowed_file(file.filename):
            delete_picture_file(person.get('profile_picture'))
            filename = secure_filename(file.filename)
            unique_filename = str(uuid.uuid4()) + '_' + filename
            if azure_blob.is_configured():
                blob_name, _ = azure_blob.upload_image(file, unique_filename)
                if not blob_name:
                    return jsonify({"message": "Image upload failed"}), 500
                update_data['profile_picture'] = blob_name
            else:
                upload_folder = os.path.join(current_app.instance_path, 'uploads')
                os.makedirs(upload_folder, exist_ok=True)
                file.save(os.path.join(upload_folder, unique_filename))
                update_data['profile_picture'] = unique_filename
        elif file and file.filename != '':
            return jsonify({"message": "Invalid file type"}), 400

    updated_person = update_birthday_in_db(id, update_data)
    return jsonify(updated_person)

@bp.route('/birthdays/<int:id>', methods=['DELETE'])
def delete_birthday(id):
    """Deletes a birthday and its associated picture with robust error handling."""
    person = get_birthday_by_id(id)
    if not person:
        return jsonify({"message": "Birthday not found"}), 404

    try:
        # First, attempt to remove the record from the database.
        # This is the most critical part of the operation.
        was_deleted = delete_birthday_from_db(id)
        
        if was_deleted:
            # If the DB record was successfully removed, then delete the picture file.
            # This order is safer; an orphan file is better than an orphan DB record.
            delete_picture_file(person.get('profile_picture'))
            return jsonify({"message": "Birthday deleted successfully"}), 200
        else:
            # This can happen in rare race conditions.
            return jsonify({"message": "Birthday not found during deletion process"}), 404

    except Exception as e:
        # If an error occurs (e.g., during the atomic write), catch it.
        # The atomic write ensures the original DB file is not corrupted.
        current_app.logger.error(f"Error deleting birthday {id}: {e}")
        return jsonify({"message": "An internal server error occurred. The birthday was not deleted."}), 500

@bp.route('/uploads/<filename>')
def uploaded_file(filename):
    """Serves uploaded files from the instance/uploads directory."""
    upload_folder = os.path.join(current_app.instance_path, 'uploads')
    return send_from_directory(upload_folder, filename)