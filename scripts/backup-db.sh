#!/bin/bash
# Logodal Database Backup Script
# This script dumps the Logodal database to a timestamped SQL file.

NAMESPACE="logodal"
DB_NAME="logodal"
DB_USER="logodal_backend"
BACKUP_DIR="backup"

mkdir -p "$BACKUP_DIR"

echo "🔍 Finding PostgreSQL pod..."
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=logodal,app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].metadata.name}")

if [ -z "$POD_NAME" ]; then
    echo "❌ Error: Could not find PostgreSQL pod in namespace $NAMESPACE."
    exit 1
fi

echo "🔐 Fetching database password..."
# Fetch the 'password' key for the logodal_backend user
DB_PASSWORD=$(kubectl get secret postgresql -n "$NAMESPACE" -o jsonpath="{.data.password}" | base64 --decode)

if [ -z "$DB_PASSWORD" ]; then
    echo "❌ Error: Could not fetch database password from secret."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/logodal_${TIMESTAMP}.sql"

echo "🚀 Dumping $DB_NAME database to $BACKUP_FILE..."
# Use pg_dump inside the pod
# Flags for easiest restore: --clean --if-exists --no-owner --no-privileges
kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$DB_PASSWORD" pg_dump -U "$DB_USER" -d "$DB_NAME" \
    --clean --if-exists --no-owner --no-privileges > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Backup successful: $BACKUP_FILE"
    # Create/update a 'latest' symlink if on dynamic FS, but for now just inform
    echo "💡 You can restore this using: cat $BACKUP_FILE | ./scripts/import-db.sh"
else
    echo "❌ Backup failed."
    rm -f "$BACKUP_FILE"
    exit 1
fi
