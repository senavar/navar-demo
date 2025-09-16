import os
import threading
import time
from flask import Flask
from .repository import mongo_connectivity_diagnostics
from . import azure_blob
from .azure_blob import blob_connectivity_diagnostics

def create_app(test_config=None):
    # create and configure the app
    app = Flask(__name__, instance_relative_config=True)
    
    # Load configuration from config.py
    # Make sure you have a config.py file with a Config class
    # Example: class Config: UPLOAD_FOLDER = 'instance/uploads'
    app.config.from_object('config.Config')

    if test_config is None:
        # load the instance config, if it exists, when not testing
        app.config.from_pyfile('config.py', silent=True)
    else:
        # load the test config if passed in
        app.config.from_mapping(test_config)

    # ensure the instance folder exists
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass
        
    # Ensure the upload folder exists
    # This check is good, but make sure UPLOAD_FOLDER is defined in your config
    if app.config.get('UPLOAD_FOLDER'):
        try:
            os.makedirs(app.config['UPLOAD_FOLDER'])
        except OSError:
            pass

    # REMOVED: The problematic line. The 'birthdays' module does not need initialization.
    # from . import birthdays
    # birthdays.init_app(app)

    # The api blueprint is what needs to be registered.
    from . import api
    app.register_blueprint(api.bp)

    # --- ASYNC STARTUP DIAGNOSTICS ---
    app.logger.info("startup.phase=begin non_blocking_diagnostics=true")

    def _run_diagnostics():
        start_time = time.time()
        try:
            mongo_diag = mongo_connectivity_diagnostics()
            app.logger.info(
                "startup.mongo status configured=%s using=%s ping_ok=%s db=%s collection=%s error=%s", 
                mongo_diag.get('configured'),
                mongo_diag.get('using_mongo'),
                mongo_diag.get('ping_ok'),
                mongo_diag.get('db_name'),
                mongo_diag.get('collection'),
                mongo_diag.get('error')
            )
        except Exception as e:  # pragma: no cover
            app.logger.warning(f"startup.mongo diagnostics failed: {e}")

        try:
            azure_blob.is_configured()  # prime any lazy init
            blob_diag = blob_connectivity_diagnostics()
            app.logger.info(
                "startup.blob status configured=%s container_exists=%s can_list=%s account=%s container=%s error=%s",
                blob_diag.get('configured'),
                blob_diag.get('container_exists'),
                blob_diag.get('can_list'),
                blob_diag.get('account'),
                blob_diag.get('container'),
                blob_diag.get('error')
            )
        except Exception as e:  # pragma: no cover
            app.logger.warning(f"startup.blob diagnostics failed: {e}")
        duration = time.time() - start_time
        app.logger.info("startup.diagnostics.complete duration_seconds=%.3f", duration)

    threading.Thread(target=_run_diagnostics, name="startup-diagnostics", daemon=True).start()

    return app