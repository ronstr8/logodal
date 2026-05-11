#!/bin/bash
# Logodal Database Import Script
# This script imports a SQL backup into the PostgreSQL pod.
# Usage: ./scripts/import-db.sh [backup_file.sql]
# If no file is provided, it defaults to reading from STDIN (piped).

NAMESPACE="logodal"
BACKUP_FILE=${1:-/dev/stdin}

echo "🔍 Finding PostgreSQL pod..."
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=logodal,app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].metadata.name}")

if [ -z "$POD_NAME" ]; then
    echo "❌ Error: Could not find PostgreSQL pod in namespace $NAMESPACE."
    exit 1
fi

echo "🔐 Fetching superuser password..."
POSTGRES_PASSWORD=$(kubectl get secret postgresql -n "$NAMESPACE" -o jsonpath="{.data.postgres-password}" | base64 --decode)

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "❌ Error: Could not fetch postgres password from secret."
    exit 1
fi

echo "🧹 Dropping and re-creating 'logodal' database..."
kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS logodal WITH (FORCE);"
kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "CREATE DATABASE logodal OWNER logodal_backend;"

echo "🚀 Importing data into $POD_NAME..."
# Connect to 'logodal' database for the import
# We use the postgres superuser to ensure permissions for role handling etc.
cat "$BACKUP_FILE" | kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d logodal

if [ $? -eq 0 ]; then
    echo "✅ Import successful!"
else
    echo "❌ Import failed."
    exit 1
fi
