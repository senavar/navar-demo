import json
import os
import uuid
from flask import current_app

def get_birthdays_db_path():
    """Returns the absolute path to the birthdays.json file."""
    return os.path.join(current_app.instance_path, 'birthdays.json')

def get_all_birthdays():
    """
    Reads all birthdays from the JSON file.
    Returns an empty list if the file doesn't exist.
    """
    db_path = get_birthdays_db_path()
    try:
        with open(db_path, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []

def write_birthdays_to_db(birthdays):
    """
    Writes the entire list of birthdays to the JSON file atomically to prevent corruption.
    """
    db_path = get_birthdays_db_path()
    temp_path = db_path + '.tmp'
    os.makedirs(current_app.instance_path, exist_ok=True)
    
    try:
        # Write to a temporary file first
        with open(temp_path, 'w') as f:
            json.dump(birthdays, f, indent=2)
        # If the write is successful, atomically replace the original file
        os.replace(temp_path, db_path)
    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise e

def add_new_birthday(new_person):
    """Adds a new birthday to the JSON file, assigning a unique ID."""
    birthdays = get_all_birthdays()
    # Ensure ID is an integer
    new_person['id'] = int(uuid.uuid4().int & (1<<31)-1)
    birthdays.append(new_person)
    write_birthdays_to_db(birthdays)
    return new_person

def get_birthday_by_id(birthday_id):
    """Finds and returns a single birthday by its ID, handling type differences."""
    birthdays = get_all_birthdays()
    for person in birthdays:
        # MODIFIED: Compare string versions to avoid type mismatch (e.g., 123 vs "123")
        if str(person.get('id')) == str(birthday_id):
            return person
    return None

def update_birthday_in_db(birthday_id, update_data):
    """
    Finds a birthday by its ID, updates its data, and saves the changes.
    """
    birthdays = get_all_birthdays()
    person_to_update = None
    for person in birthdays:
        # MODIFIED: Compare string versions for a robust lookup
        if str(person.get('id')) == str(birthday_id):
            person.update(update_data)
            person_to_update = person
            break
    
    if person_to_update:
        write_birthdays_to_db(birthdays)
        return person_to_update
    
    return None

def delete_birthday_from_db(birthday_id):
    """
    Finds a birthday by its ID, removes it from the list, and saves the changes.
    Returns True on success, False if not found.
    """
    birthdays = get_all_birthdays()
    original_length = len(birthdays)
    
    # MODIFIED: Compare string versions to ensure the correct item is removed
    birthdays_after_deletion = [p for p in birthdays if str(p.get('id')) != str(birthday_id)]
    
    if len(birthdays_after_deletion) < original_length:
        write_birthdays_to_db(birthdays_after_deletion)
        return True
        
    return False