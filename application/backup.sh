#!/usr/bin/env bash

# Initialize logging with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Generate UUID v4
generate_uuid() {
    if [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        date +%s%N | sha256sum | head -c 32
    fi
}

# Parse Sentry DSN
parse_sentry_dsn() {
    local dsn=$1
    # Extract components using basic string manipulation
    local project_id=$(echo "$dsn" | sed 's/.*\///')
    local key=$(echo "$dsn" | sed 's|https://||' | sed 's/@.*//')
    local host=$(echo "$dsn" | sed 's|https://[^@]*@||' | sed 's|/.*||')
    echo "$project_id|$key|$host"
}

# Function to send error to Sentry
error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"
    
    # Check if SENTRY_DSN is set
    if [ -z "${SENTRY_DSN:-}" ]; then
        log "ERROR: SENTRY_DSN not set"
        return 1
    fi

    # Parse DSN
    local dsn_parts=($(parse_sentry_dsn "$SENTRY_DSN" | tr '|' ' '))
    local project_id="${dsn_parts[0]}"
    local key="${dsn_parts[1]}"
    local host="${dsn_parts[2]}"

    # Generate event ID and timestamp
    local event_id=$(generate_uuid)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # Create JSON payload
    local payload=$(cat <<EOF
{
    "event_id": "${event_id}",
    "timestamp": "${timestamp}",
    "level": "error",
    "message": "${error_message}",
    "logger": "postgresql-backup",
    "platform": "bash",
    "environment": "production",
    "tags": {
        "database": "${db_name}",
        "status_code": "${status_code}",
        "host": "$(hostname)"
    },
    "extra": {
        "script_path": "$0",
        "timestamp": "${timestamp}"
    }
}
EOF
)

    # Send to Sentry
    local response
    response=$(curl -s -X POST \
        "https://${host}/api/${project_id}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${key}, sentry_client=bash-script/1.0" \
        -d "${payload}" 2>&1)

    if [ $? -ne 0 ]; then
        log "ERROR: Failed to send event to Sentry: ${response}"
        return 1
    fi

    log "Error event sent to Sentry: ${error_message}"
}

MYNAME="postgresql-backup-restore"
STATUS=0

log "${MYNAME}: backup: Started"

log "${MYNAME}: Backing up ${DB_NAME}"

start=$(date +%s)
$(PGPASSWORD=${DB_USERPASSWORD} pg_dump --host=${DB_HOST} --username=${DB_USER} --create --clean ${DB_OPTIONS} --dbname=${DB_NAME} > /tmp/${DB_NAME}.sql) || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    log "${error_message}"
    error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}"
    exit $STATUS
else
    log "${MYNAME}: Backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${DB_NAME}.sql) bytes)."
fi

start=$(date +%s)
gzip -f /tmp/${DB_NAME}.sql || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Compressing backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    log "${error_message}"
    error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}"
    exit $STATUS
else
    log "${MYNAME}: Compressing backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
s3cmd put /tmp/${DB_NAME}.sql.gz ${S3_BUCKET} || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Copy backup to ${S3_BUCKET} of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    log "${error_message}"
    error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}"
    exit $STATUS
else
    log "${MYNAME}: Copy backup to ${S3_BUCKET} of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

if [ "${B2_BUCKET}" != "" ]; then
    start=$(date +%s)
    s3cmd \
        --access_key=${B2_APPLICATION_KEY_ID} \
        --secret_key=${B2_APPLICATION_KEY} \
        --host=${B2_HOST} \
        --host-bucket='%(bucket)s.'"${B2_HOST}" \
        put /tmp/${DB_NAME}.sql.gz s3://${B2_BUCKET}/${DB_NAME}.sql.gz
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="${MYNAME}: FATAL: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        log "${error_message}"
        error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}"
        exit $STATUS
    else
        log "${MYNAME}: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
    fi
fi

log "${MYNAME}: backup: Completed"
