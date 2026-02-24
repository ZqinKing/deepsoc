#!/bin/bash
set -e

# Wait for MySQL to be ready
echo "Waiting for MySQL..."
max_retries=30
retries=0
while ! python -c "
import os
import pymysql
from urllib.parse import urlparse

db_url = os.environ.get('DATABASE_URL')
if not db_url:
    print('DATABASE_URL not set')
    exit(1)

# Extract connection info from URL: mysql+pymysql://user:pass@host:port/db
url = urlparse(db_url.replace('mysql+pymysql', 'mysql'))
try:
    conn = pymysql.connect(
        host=url.hostname,
        port=url.port or 3306,
        user=url.username,
        password=url.password,
        database=url.path.lstrip('/')
    )
    conn.close()
    exit(0)
except Exception as e:
    exit(1)
" > /dev/null 2>&1; do
    retries=$((retries+1))
    if [ $retries -ge $max_retries ]; then
        echo "Error: MySQL not ready after $max_retries attempts"
        exit 1
    fi
    echo "MySQL unavailable - sleeping (attempt $retries/$max_retries)..."
    sleep 2
done
echo "MySQL is up!"

# Wait for RabbitMQ to be ready
echo "Waiting for RabbitMQ..."
retries=0
while ! python -c "
import os
import pika

host = os.environ.get('RABBITMQ_HOST', 'localhost')
port = int(os.environ.get('RABBITMQ_PORT', 5672))
user = os.environ.get('RABBITMQ_USER', 'guest')
password = os.environ.get('RABBITMQ_PASSWORD', 'guest')

try:
    credentials = pika.PlainCredentials(user, password)
    parameters = pika.ConnectionParameters(host=host, port=port, credentials=credentials)
    connection = pika.BlockingConnection(parameters)
    connection.close()
    exit(0)
except Exception as e:
    exit(1)
" > /dev/null 2>&1; do
    retries=$((retries+1))
    if [ $retries -ge $max_retries ]; then
        echo "Error: RabbitMQ not ready after $max_retries attempts"
        exit 1
    fi
    echo "RabbitMQ unavailable - sleeping (attempt $retries/$max_retries)..."
    sleep 2
done
echo "RabbitMQ is up!"

# Check if database needs initialization
echo "Checking database status..."
DB_INITIALIZED=$(python -c "
import os
import pymysql
from urllib.parse import urlparse
import sys

db_url = os.environ.get('DATABASE_URL')
url = urlparse(db_url.replace('mysql+pymysql', 'mysql'))
try:
    conn = pymysql.connect(
        host=url.hostname,
        port=url.port or 3306,
        user=url.username,
        password=url.password,
        database=url.path.lstrip('/')
    )
    cursor = conn.cursor()
    cursor.execute('SHOW TABLES')
    tables = cursor.fetchall()
    conn.close()
    # If no tables exist, DB is not initialized
    if not tables:
        sys.stdout.write('0')
    else:
        sys.stdout.write('1')
except Exception as e:
    sys.stdout.write('0')
")

if [ "$DB_INITIALIZED" = "0" ]; then
    echo "Database is empty. Initializing database with demo data..."
    python main.py -init-with-demo
    echo "Database initialization complete!"
else
    echo "Database already initialized."
fi

# Start all agents
echo "Starting DeepSOC web server and all agents..."
exec python tools/run_all_agents.py
