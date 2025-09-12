import os
from flask import Flask

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

    return app