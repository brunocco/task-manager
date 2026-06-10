import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'todo_project'))

from todo_project import app, db

def test_app_exists():
    assert app is not None

def test_login_page():
    client = app.test_client()
    response = client.get('/login')
    assert response.status_code == 200

def test_register_page():
    client = app.test_client()
    response = client.get('/register')
    assert response.status_code == 200

def test_protected_page_redirect():
    client = app.test_client()
    response = client.get('/all_tasks', follow_redirects=False)
    assert response.status_code == 302
