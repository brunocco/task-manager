#!/bin/bash
# ==============================================
# SETUP COMPLETO - Caso de Uso Task Manager
# Rodar na VM do laboratório (192.168.98.10)
# ==============================================

# 1. Criar diretório do projeto
mkdir -p /home/aluno/task-manager
cd /home/aluno/task-manager

# 2. Inicializar repositório Git
git init
git config --global user.name "Bruno Cesar"
git config --global user.email "bruno_cco@hotmail.com"

# 3. Criar requirements.txt
cat > requirements.txt <<'EOF'
Flask==2.3.2
Flask-Bcrypt==1.0.1
Flask-Login==0.6.3
Flask-SQLAlchemy==3.1.1
Flask-WTF==1.2.1
WTForms==3.1.1
Jinja2==3.1.2
SQLAlchemy==2.0.36
Werkzeug==2.3.8
MarkupSafe==2.1.3
itsdangerous==2.1.2
EOF

# 4. Criar estrutura de diretórios
mkdir -p todo_project/todo_project/static/css
mkdir -p todo_project/todo_project/templates/errors
mkdir -p tests
mkdir -p prometheus
mkdir -p grafana/data

# 5. Criar __init__.py
cat > todo_project/todo_project/__init__.py <<'EOF'
import logging
import logging.handlers
import platform
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_bcrypt import Bcrypt

app = Flask(__name__)
app.config['SECRET_KEY'] = '45cf93c4d41348cd9980674ade9a7356'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///site.db'

db = SQLAlchemy(app)

login_manager = LoginManager(app)
login_manager.login_view = 'login'
login_manager.login_message_category = 'danger'

bcrypt = Bcrypt(app)

# Logging via syslog (Linux) ou stream (Windows)
if platform.system() == 'Linux':
    syslog_handler = logging.handlers.SysLogHandler(address='/dev/log')
    syslog_handler.setLevel(logging.INFO)
    formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
    syslog_handler.setFormatter(formatter)
    app.logger.addHandler(syslog_handler)
else:
    stream_handler = logging.StreamHandler()
    stream_handler.setLevel(logging.INFO)
    formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
    stream_handler.setFormatter(formatter)
    app.logger.addHandler(stream_handler)
app.logger.setLevel(logging.INFO)

from todo_project import routes
EOF

# 6. Criar models.py
cat > todo_project/todo_project/models.py <<'EOF'
from todo_project import db, login_manager
from datetime import datetime
from flask_login import UserMixin


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(20), unique=True, nullable=False)
    password = db.Column(db.String(60), nullable=False)
    tasks = db.relationship('Task', backref='author', lazy=True)

    def __repr__(self):
        return f"User('{self.username}')"


class Task(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    content = db.Column(db.String(100), nullable=False)
    date_posted = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)

    def __repr__(self):
        return f"Task('{self.content}', '{self.date_posted}', '{self.user_id}')"
EOF

# 7. Criar forms.py
cat > todo_project/todo_project/forms.py <<'EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, SubmitField
from wtforms.validators import DataRequired, EqualTo, Length, ValidationError
from todo_project.models import User
from flask_login import current_user


class RegistrationForm(FlaskForm):
    username = StringField(label='Username', validators=[DataRequired(), Length(min=3, max=10)])
    password = PasswordField(label='Password', validators=[DataRequired()])
    confirm_password = PasswordField(label='Confirm Password', validators=[DataRequired(), EqualTo('password')])
    submit = SubmitField(label='Register')

    def validate_username(self, username):
        user = User.query.filter_by(username=username.data).first()
        if user:
            raise ValidationError('Username Exists')


class LoginForm(FlaskForm):
    username = StringField(label='Username', validators=[DataRequired(), Length(min=3, max=10)])
    password = PasswordField(label='Password', validators=[DataRequired()])
    submit = SubmitField(label='Login')


class UpdateUserInfoForm(FlaskForm):
    username = StringField(label='Username', validators=[DataRequired(), Length(min=3, max=10)])
    submit = SubmitField(label='Update Info')

    def validate_username(self, username):
        if username.data != current_user.username:
            user = User.query.filter_by(username=username.data).first()
            if user:
                raise ValidationError('Username Exists')


class UpdateUserPassword(FlaskForm):
    old_password = PasswordField(label='Enter Old Password', validators=[DataRequired()])
    new_password = PasswordField(label='Enter New Password', validators=[DataRequired()])
    submit = SubmitField(label='Change password')


class TaskForm(FlaskForm):
    task_name = StringField(label='Task Description', validators=[DataRequired()])
    submit = SubmitField(label='Add Task')


class UpdateTaskForm(FlaskForm):
    task_name = StringField(label='Update Task Description', validators=[DataRequired()])
    submit = SubmitField(label='Save Changes')
EOF

# 8. Criar routes.py
cat > todo_project/todo_project/routes.py <<'EOF'
from flask import render_template, url_for, flash, redirect, request
from todo_project import app, db, bcrypt
from todo_project.forms import (LoginForm, RegistrationForm, UpdateUserInfoForm,
                                UpdateUserPassword, TaskForm, UpdateTaskForm)
from todo_project.models import User, Task
from flask_login import login_required, current_user, login_user, logout_user


@app.errorhandler(404)
def error_404(error):
    return (render_template('errors/404.html'), 404)

@app.errorhandler(403)
def error_403(error):
    return (render_template('errors/403.html'), 403)

@app.errorhandler(500)
def error_500(error):
    return (render_template('errors/500.html'), 500)


@app.route("/")
@app.route("/about")
def about():
    return render_template('about.html', title='About')


@app.route("/login", methods=['POST', 'GET'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('all_tasks'))

    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(username=form.username.data).first()
        if user and bcrypt.check_password_hash(user.password, form.password.data):
            login_user(user)
            app.logger.info(f'LOGIN SUCCESS: user={form.username.data} ip={request.remote_addr}')
            flash('Login Successfull', 'success')
            return redirect(url_for('all_tasks'))
        else:
            app.logger.warning(f'LOGIN FAILED: user={form.username.data} ip={request.remote_addr}')
            flash('Login Unsuccessful. Please check Username Or Password', 'danger')

    return render_template('login.html', title='Login', form=form)


@app.route("/logout")
def logout():
    logout_user()
    return redirect(url_for('login'))


@app.route("/register", methods=['POST', 'GET'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('all_tasks'))

    form = RegistrationForm()
    if form.validate_on_submit():
        hashed_password = bcrypt.generate_password_hash(form.password.data).decode('utf-8')
        user = User(username=form.username.data, password=hashed_password)
        db.session.add(user)
        db.session.commit()
        app.logger.info(f'USER REGISTERED: user={form.username.data}')
        flash(f'Account Created For {form.username.data}', 'success')
        return redirect(url_for('login'))

    return render_template('register.html', title='Register', form=form)


@app.route("/all_tasks")
@login_required
def all_tasks():
    tasks = User.query.filter_by(username=current_user.username).first().tasks
    return render_template('all_tasks.html', title='All Tasks', tasks=tasks)


@app.route("/add_task", methods=['POST', 'GET'])
@login_required
def add_task():
    form = TaskForm()
    if form.validate_on_submit():
        task = Task(content=form.task_name.data, author=current_user)
        db.session.add(task)
        db.session.commit()
        app.logger.info(f'TASK CREATED: user={current_user.username} task={form.task_name.data}')
        flash('Task Created', 'success')
        return redirect(url_for('add_task'))
    return render_template('add_task.html', form=form, title='Add Task')


@app.route("/all_tasks/<int:task_id>/update_task", methods=['GET', 'POST'])
@login_required
def update_task(task_id):
    task = Task.query.get_or_404(task_id)
    form = UpdateTaskForm()
    if form.validate_on_submit():
        if form.task_name.data != task.content:
            task.content = form.task_name.data
            db.session.commit()
            flash('Task Updated', 'success')
            return redirect(url_for('all_tasks'))
        else:
            flash('No Changes Made', 'warning')
            return redirect(url_for('all_tasks'))
    elif request.method == 'GET':
        form.task_name.data = task.content
    return render_template('add_task.html', title='Update Task', form=form)


@app.route("/all_tasks/<int:task_id>/delete_task")
@login_required
def delete_task(task_id):
    task = Task.query.get_or_404(task_id)
    db.session.delete(task)
    db.session.commit()
    flash('Task Deleted', 'info')
    return redirect(url_for('all_tasks'))


@app.route("/account", methods=['POST', 'GET'])
@login_required
def account():
    form = UpdateUserInfoForm()
    if form.validate_on_submit():
        if form.username.data != current_user.username:
            current_user.username = form.username.data
            db.session.commit()
            flash('Username Updated Successfully', 'success')
            return redirect(url_for('account'))
    elif request.method == 'GET':
        form.username.data = current_user.username

    return render_template('account.html', title='Account Settings', form=form)


@app.route("/account/change_password", methods=['POST', 'GET'])
@login_required
def change_password():
    form = UpdateUserPassword()
    if form.validate_on_submit():
        if bcrypt.check_password_hash(current_user.password, form.old_password.data):
            current_user.password = bcrypt.generate_password_hash(form.new_password.data).decode('utf-8')
            db.session.commit()
            flash('Password Changed Successfully', 'success')
            redirect(url_for('account'))
        else:
            flash('Please Enter Correct Password', 'danger')

    return render_template('change_password.html', title='Change Password', form=form)
EOF

# 9. Criar run.py
cat > todo_project/run.py <<'EOF'
from todo_project import app, db
import os

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
EOF

# 10. Criar templates HTML
cat > todo_project/todo_project/templates/layout.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>{% if title %}{{ title }} - Task Manager{% else %}Task Manager{% endif %}</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/main.css') }}">
</head>
<body>
    <nav>
        <a href="{{ url_for('about') }}">Home</a>
        {% if current_user.is_authenticated %}
        <a href="{{ url_for('all_tasks') }}">Tasks</a>
        <a href="{{ url_for('add_task') }}">Add Task</a>
        <a href="{{ url_for('account') }}">Account</a>
        <a href="{{ url_for('logout') }}">Logout</a>
        {% else %}
        <a href="{{ url_for('login') }}">Login</a>
        <a href="{{ url_for('register') }}">Register</a>
        {% endif %}
    </nav>
    <div class="container">
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                <div class="alert alert-{{ category }}">{{ message }}</div>
                {% endfor %}
            {% endif %}
        {% endwith %}
        {% block content %}{% endblock %}
    </div>
</body>
</html>
EOF

cat > todo_project/todo_project/templates/login.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>Login</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    <div>{{ form.username.label }} {{ form.username() }}</div>
    <div>{{ form.password.label }} {{ form.password() }}</div>
    <div>{{ form.submit() }}</div>
</form>
<p>Don't have an account? <a href="{{ url_for('register') }}">Register</a></p>
{% endblock %}
EOF

cat > todo_project/todo_project/templates/register.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>Register</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    <div>{{ form.username.label }} {{ form.username() }}</div>
    <div>{{ form.password.label }} {{ form.password() }}</div>
    <div>{{ form.confirm_password.label }} {{ form.confirm_password() }}</div>
    <div>{{ form.submit() }}</div>
</form>
{% endblock %}
EOF

cat > todo_project/todo_project/templates/about.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>Task Manager</h2>
<p>Sistema de gerenciamento de tarefas pessoais.</p>
{% endblock %}
EOF

cat > todo_project/todo_project/templates/all_tasks.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>All Tasks</h2>
{% for task in tasks %}
<div class="task">
    <p>{{ task.content }} - {{ task.date_posted.strftime('%Y-%m-%d') }}</p>
    <a href="{{ url_for('update_task', task_id=task.id) }}">Edit</a>
    <a href="{{ url_for('delete_task', task_id=task.id) }}">Delete</a>
</div>
{% endfor %}
{% endblock %}
EOF

cat > todo_project/todo_project/templates/add_task.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>{{ title }}</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    <div>{{ form.task_name.label }} {{ form.task_name() }}</div>
    <div>{{ form.submit() }}</div>
</form>
{% endblock %}
EOF

cat > todo_project/todo_project/templates/account.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>Account Settings</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    <div>{{ form.username.label }} {{ form.username() }}</div>
    <div>{{ form.submit() }}</div>
</form>
<a href="{{ url_for('change_password') }}">Change Password</a>
{% endblock %}
EOF

cat > todo_project/todo_project/templates/change_password.html <<'EOF'
{% extends "layout.html" %}
{% block content %}
<h2>Change Password</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    <div>{{ form.old_password.label }} {{ form.old_password() }}</div>
    <div>{{ form.new_password.label }} {{ form.new_password() }}</div>
    <div>{{ form.submit() }}</div>
</form>
{% endblock %}
EOF

cat > todo_project/todo_project/templates/errors/404.html <<'EOF'
{% extends "layout.html" %}
{% block content %}<h2>Page Not Found (404)</h2>{% endblock %}
EOF

cat > todo_project/todo_project/templates/errors/403.html <<'EOF'
{% extends "layout.html" %}
{% block content %}<h2>Forbidden (403)</h2>{% endblock %}
EOF

cat > todo_project/todo_project/templates/errors/500.html <<'EOF'
{% extends "layout.html" %}
{% block content %}<h2>Server Error (500)</h2>{% endblock %}
EOF

# 11. Criar CSS básico
cat > todo_project/todo_project/static/css/main.css <<'EOF'
body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #f4f4f4; }
nav { background: #333; padding: 10px; }
nav a { color: white; margin-right: 15px; text-decoration: none; }
.container { max-width: 800px; margin: 20px auto; padding: 20px; background: white; border-radius: 5px; }
.alert { padding: 10px; margin: 10px 0; border-radius: 3px; }
.alert-success { background: #d4edda; color: #155724; }
.alert-danger { background: #f8d7da; color: #721c24; }
.alert-info { background: #d1ecf1; color: #0c5460; }
.alert-warning { background: #fff3cd; color: #856404; }
.task { padding: 10px; margin: 5px 0; background: #f9f9f9; border-left: 3px solid #333; }
input, button { margin: 5px 0; padding: 8px; }
button, input[type="submit"] { background: #333; color: white; border: none; cursor: pointer; }
EOF

# 12. Criar Dockerfile
cat > Dockerfile <<'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY todo_project/ ./todo_project/

EXPOSE 8080

CMD ["python", "todo_project/run.py"]
EOF

# 13. Criar .dockerignore
cat > .dockerignore <<'EOF'
.git/
.github/
tests/
prometheus/
grafana/
*.md
__pycache__/
*.pyc
EOF

# 14. Criar teste unitário
cat > tests/test_app.py <<'EOF'
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
EOF

# 15. Criar prometheus.yml
cat > prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'task-manager'
    static_configs:
      - targets: ['192.168.98.10:8080']
EOF

# 16. Criar docker-compose.yml (app + prometheus + grafana)
cat > docker-compose.yml <<'EOF'
version: '3'
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    image: task-manager
    container_name: task-manager
    ports:
      - 8080:8080
    restart: always

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    restart: always
    volumes:
      - ./prometheus:/etc/prometheus
    ports:
      - 9090:9090

  grafana:
    image: grafana/grafana
    container_name: grafana
    restart: always
    user: "1001:1001"
    environment:
      GF_SECURITY_ADMIN_USER: 'admin'
      GF_SECURITY_ADMIN_PASSWORD: 'admin'
      GF_USERS_ALLOW_SIGN_UP: 'false'
    volumes:
      - ./grafana/data:/var/lib/grafana
    ports:
      - 3000:3000
    depends_on:
      - prometheus
EOF

# 17. Criar GitHub Actions workflow
mkdir -p .github/workflows

cat > .github/workflows/ci-cd.yml <<'EOF'
name: CI/CD Pipeline

on:
  push:
    branches: [master, main]
  pull_request:
    branches: [master, main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t task-manager:latest .

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install -r requirements.txt && pip install pytest
      - name: Run tests
        run: python -m pytest tests/ -v

  bandit_sast:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install Bandit
        run: pip install bandit
      - name: Run Bandit SAST
        run: bandit -r todo_project/ -ll -f json -o bandit_report.json || true
      - name: Show results
        run: bandit -r todo_project/ -ll || true
      - uses: actions/upload-artifact@v4
        with:
          name: bandit-report
          path: bandit_report.json

  dependency_check:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install Safety
        run: pip install safety
      - name: Run Dependency Check
        run: safety check -r requirements.txt || true

  dast_zap:
    runs-on: ubuntu-latest
    needs: [build, bandit_sast]
    steps:
      - uses: actions/checkout@v4
      - name: Build and run app
        run: |
          docker build -t task-manager:latest .
          docker run -d -p 8080:8080 --name app task-manager:latest
          sleep 10
      - name: Run OWASP ZAP
        run: |
          docker run --rm --network host ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t http://localhost:8080 || true
      - name: Stop app
        run: docker stop app

  deploy:
    runs-on: ubuntu-latest
    needs: [dast_zap]
    if: github.ref == 'refs/heads/master' || github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - name: Deploy (simulado)
        run: echo "Deploy em staging concluido - app pronta para producao"
EOF

# 18. Criar .gitignore
cat > .gitignore <<'EOF'
__pycache__/
*.pyc
*.db
.pytest_cache/
*.json
grafana/data/
EOF

# 19. Permissões do Grafana
sudo chown -R 1001:1001 /home/aluno/task-manager/grafana/data

echo ""
echo "=========================================="
echo "SETUP CONCLUIDO!"
echo "=========================================="
echo ""
echo "Proximos passos:"
echo "1. docker build -t task-manager ."
echo "2. docker run -d -p 8080:8080 --name task-manager task-manager"
echo "3. Acessar http://192.168.98.10:8080"
echo "4. git add . && git commit -m 'Initial commit'"
echo "5. git remote add origin https://github.com/SEU_USUARIO/task-manager.git"
echo "6. git branch -M main && git push -u origin main"
echo "=========================================="
