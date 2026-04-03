#!/bin/bash

set -uo pipefail

# ==============================
# CONFIG (SANITIZED / SAMPLE VALUES)
# ==============================
DB_NAME="your_database_name"
DB_USER="your_database_user"
DB_PASS="your_secure_password"
DB_HOST="your.database.host"

BACKUP_DIR="/path/to/backup/dir"
TMP_DIR="/tmp/mysql_backup"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

LOG_FILE="/path/to/log/db_backup.log"

FROM_EMAIL="sender@example.com"
TO_EMAILS="recipient1@example.com,recipient2@example.com"

S3_BUCKET="s3://your-bucket-name/path/"

FINAL_FILE="${BACKUP_DIR}/${DB_NAME}_${DATE}.sql.gz"

LARGE_TABLES=("large_table_name")

# ==============================
# TIME TRACKING
# ==============================
START_TIME=$(date)
START_TS=$(date +%s)

# ==============================
# FUNCTIONS
# ==============================

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

send_email() {
    SUBJECT="$1"
    BODY="$2"

    (
    echo "From: $FROM_EMAIL"
    echo "To: $TO_EMAILS"
    echo "Subject: $SUBJECT"
    echo ""
    echo -e "$BODY"
    ) | msmtp -t >> "$LOG_FILE" 2>&1
}

run_dump() {
    OUT_FILE=$1
    shift

    for i in {1..3}; do
        log "Running: $* (Attempt $i)"

        if "$@" > "$OUT_FILE" 2>>"$LOG_FILE"; then
            return 0
        fi

        log "Attempt $i failed..."
        sleep 5
    done

    send_email "❌ DB Backup FAILED" "
Backup failed after 3 attempts.

Command:
$*

Time: $(date)

Log:
$LOG_FILE"
    exit 1
}

verify_dump() {
    FILE=$1
    tail -n 1 "$FILE" | grep -q "Dump completed"
}

# ==============================
# START EMAIL
# ==============================

send_email "🔄 DB Backup Started - $DB_NAME" "
Backup process started

Database: $DB_NAME
Start Time: $START_TIME
Backup File: $FINAL_FILE
Server: $(hostname)
"

# ==============================
# START PROCESS
# ==============================
mkdir -p "$BACKUP_DIR" "$TMP_DIR"
log "Starting backup..."

SCHEMA_FILE="$TMP_DIR/schema.sql"
DATA_FILE="$TMP_DIR/data.sql"

# ==============================
# SCHEMA
# ==============================
run_dump "$SCHEMA_FILE" mysqldump \
    -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" \
    --no-data "$DB_NAME"

verify_dump "$SCHEMA_FILE" || {
    send_email "❌ Schema Failed" "Schema corrupted"
    exit 1
}

# ==============================
# DATA
# ==============================
IGNORE_ARGS=""
for T in "${LARGE_TABLES[@]}"; do
    IGNORE_ARGS+=" --ignore-table=${DB_NAME}.${T}"
done

run_dump "$DATA_FILE" mysqldump \
    -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" \
    --single-transaction --quick \
    $IGNORE_ARGS \
    "$DB_NAME"

verify_dump "$DATA_FILE" || {
    send_email "❌ Data Failed" "Data corrupted"
    exit 1
}

# ==============================
# LARGE TABLES
# ==============================
LARGE_FILES=()

for TABLE in "${LARGE_TABLES[@]}"; do
    FILE="$TMP_DIR/${TABLE}.sql"

    run_dump "$FILE" mysqldump \
        -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" \
        --single-transaction --quick \
        "$DB_NAME" "$TABLE"

    verify_dump "$FILE" || {
        send_email "❌ Large Table Failed" "$TABLE corrupted"
        exit 1
    }

    LARGE_FILES+=("$FILE")
done

# ==============================
# MERGE + COMPRESS
# ==============================
MERGED="$TMP_DIR/full_backup.sql"
cat "$SCHEMA_FILE" "$DATA_FILE" "${LARGE_FILES[@]}" > "$MERGED"

gzip "$MERGED"
mv "${MERGED}.gz" "$FINAL_FILE"

# ==============================
# VERIFY BACKUP
# ==============================
gzip -t "$FINAL_FILE" || {
    send_email "❌ Backup Corrupted" "Backup file is corrupted: $FINAL_FILE"
    exit 1
}

BACKUP_END_TIME=$(date)
BACKUP_END_TS=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TS - START_TS))

FILE_SIZE=$(du -h "$FINAL_FILE" | cut -f1)

# ==============================
# BACKUP COMPLETE EMAIL
# ==============================

send_email "✅ Backup Completed - $DB_NAME" "
Backup completed successfully

Database: $DB_NAME
File: $FINAL_FILE
Size: $FILE_SIZE

Start Time: $START_TIME
End Time: $BACKUP_END_TIME
Time Taken: ${BACKUP_DURATION} seconds

🚀 Upload to AWS S3 starting...

S3 Path: $S3_BUCKET$(basename $FINAL_FILE)
Upload Start Time: $(date)
"

# ==============================
# S3 UPLOAD
# ==============================
UPLOAD_START_TS=$(date +%s)

if aws s3 cp "$FINAL_FILE" "$S3_BUCKET" >> "$LOG_FILE" 2>&1; then
    log "Uploaded to S3"
else
    send_email "❌ S3 Upload Failed" "
Upload failed

File: $FINAL_FILE
Time: $(date)"
    exit 1
fi

UPLOAD_END_TS=$(date +%s)
UPLOAD_DURATION=$((UPLOAD_END_TS - UPLOAD_START_TS))

TOTAL_DURATION=$((UPLOAD_END_TS - START_TS))

# ==============================
# CLEAN LOCAL
# ==============================
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

# ==============================
# FINAL SUCCESS EMAIL
# ==============================

send_email "🎉 Backup + Upload SUCCESS - $DB_NAME" "
✅ Database backup and upload completed successfully

Database: $DB_NAME

Local File:
$FINAL_FILE

S3 Location:
$S3_BUCKET$(basename $FINAL_FILE)

⏱ Total Time: ${TOTAL_DURATION} seconds
📦 Backup Time: ${BACKUP_DURATION} sec
☁ Upload Time: ${UPLOAD_DURATION} sec

Status: SUCCESS
Completed At: $(date)
"

log "Backup completed successfully"