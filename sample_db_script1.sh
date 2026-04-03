#!/bin/bash
#
# MySQL Database Backup Script (Sample Template)
# Description:
# - Takes MySQL dump
# - Compresses it
# - Uploads to AWS S3
# - Sends email notification
# - Retains backups for X days
#

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

# Database Configuration
DB_HOST="localhost"
DB_USER="your_db_user"
DB_PASS="your_db_password"          # 🔐 Replace with env variable or .my.cnf
DB_NAME="your_database_name"

# Backup Storage
BACKUP_DIR="/path/to/backup/directory"
S3_BUCKET="your-s3-bucket-name"
S3_PREFIX="backup-folder"

# Retention Policy
RETENTION_DAYS=7

# File Naming
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${DB_NAME}_${TIMESTAMP}.sql.gz"
LOG_FILE="${BACKUP_DIR}/backup.log"

# ─── SMTP / Email Configuration ──────────────────────────────────────────────

SMTP_HOST="smtp.example.com"
SMTP_PORT=465
SMTP_USER="your_email@example.com"
SMTP_PASS="your_email_password"
SMTP_FROM='"Backup System" <no-reply@example.com>'
SMTP_TO="recipient@example.com"

# ─── Logging Function ────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ─── Email Function ──────────────────────────────────────────────────────────

send_email() {
    local subject="$1"
    local body="$2"

    local message="From: ${SMTP_FROM}\r\nTo: ${SMTP_TO}\r\nSubject: ${subject}\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n${body}"

    echo -e "$message" | curl --silent --ssl-reqd \
        --url "smtps://${SMTP_HOST}:${SMTP_PORT}" \
        --user "${SMTP_USER}:${SMTP_PASS}" \
        --mail-from "${SMTP_USER}" \
        --mail-rcpt "${SMTP_TO}" \
        --upload-file -
}

# ─── Error Handler ───────────────────────────────────────────────────────────

cleanup_on_error() {
    log "ERROR: Backup failed!"

    send_email "[FAILED] Backup Error" \
        "<p>Backup process failed. Check logs at ${LOG_FILE}</p>"

    rm -f "${BACKUP_DIR}/${BACKUP_FILE}"
    exit 1
}

trap cleanup_on_error ERR

# ─── Pre-checks ──────────────────────────────────────────────────────────────

mkdir -p "$BACKUP_DIR"

command -v mysqldump >/dev/null || { log "mysqldump not found"; exit 1; }
command -v aws >/dev/null || { log "aws cli not found"; exit 1; }
command -v curl >/dev/null || { log "curl not found"; exit 1; }

# ─── Step 1: Database Backup ─────────────────────────────────────────────────

log "Starting backup..."

TEMP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.tmp.gz"

mysqldump \
    --host="$DB_HOST" \
    --user="$DB_USER" \
    --password="$DB_PASS" \
    --single-transaction \
    --quick \
    "$DB_NAME" | gzip -9 > "$TEMP_FILE"

# Validate backup
gzip -t "$TEMP_FILE" || {
    log "Backup file is corrupt!"
    exit 1
}

# Move to final file
mv "$TEMP_FILE" "${BACKUP_DIR}/${BACKUP_FILE}"

FILESIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
log "Backup created: ${BACKUP_FILE} (${FILESIZE})"

# ─── Step 2: Upload to S3 ───────────────────────────────────────────────────

log "Uploading to S3..."

aws s3 cp \
    "${BACKUP_DIR}/${BACKUP_FILE}" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_FILE}"

log "Upload complete."

# ─── Step 3: Cleanup Old Backups ─────────────────────────────────────────────

log "Cleaning old backups..."

# Local cleanup
find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete

# S3 cleanup
aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | while read -r line; do
    FILE_DATE=$(echo "$line" | awk '{print $1}')
    FILE_NAME=$(echo "$line" | awk '{print $4}')

    if [[ -n "$FILE_NAME" ]]; then
        FILE_TS=$(date -d "$FILE_DATE" +%s)
        CUTOFF_TS=$(date -d "-${RETENTION_DAYS} days" +%s)

        if (( FILE_TS < CUTOFF_TS )); then
            aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/${FILE_NAME}"
        fi
    fi
done

# ─── Step 4: Success Email ───────────────────────────────────────────────────

send_email "[SUCCESS] Backup Completed" \
    "<p>Backup successful: ${BACKUP_FILE} (${FILESIZE})</p>"

log "Backup process completed successfully."