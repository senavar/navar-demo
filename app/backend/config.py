import os

class Config:
    # Define the absolute path for the instance folder
    INSTANCE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'instance')
    
    # Define the upload folder within the instance path
    UPLOAD_FOLDER = os.path.join(INSTANCE_PATH, 'uploads')
    
    # The path to the birthdays JSON file
    BIRTHDAYS_FILE = os.path.join(INSTANCE_PATH, 'birthdays.json')