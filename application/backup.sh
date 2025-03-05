#!/usr/bin/env bash

# Initialize logging with timestamp
log() {
    local level="$1";
    local message="$2";
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level}: ${message}";
}

# Sentry reporting with validation and backwards compatibility
error_to_sentry() {
    local error_message="$1";
    local db_name="$2";
    local status_code="$3";

    # Check if SENTRY_DSN is configured - ensures backup continues
    if [ -z "${SENTRY_DSN:-}" ]; then
        log "DEBUG" "Sentry logging skipped - SENTRY_DSN not configured";
        return 0;
    fi

    # Validate SENTRY_DSN format
    if ! [[ "${SENTRY_DSN}" =~ ^https://[^@]+@[^/]+/[0-9]+$ ]]; then
        log "WARN" "Invalid SENTRY_DSN format - Sentry logging will be skipped";
        return 0;
    fi

    # Attempt to send event to Sentry
    if sentry-cli send-event \
        --message "${error_message}" \
        --level error \
        --tag "database:${db_name}" \
        --tag "status:${status_code}"; then
        log "DEBUG" "Successfully sent error to Sentry - Message: ${error_message}, Database: ${db_name}, Status: ${status_code}";
    else
        log "WARN" "Failed to send error to Sentry, but continuing backup process";
    fi

    return 0;
}

# Function to get parameter from Parameter Store
get_parameter() {
    local parameter_name="$1"
    local value

    value=$(aws ssm get-parameter \
        --name "/${APP_NAME}/${APP_ENV}/${parameter_name}" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$value"
        return 0
    fi
    return 1
}

# Initialize sensitive parameters with fallback to environment variables
init_parameters() {
    log "INFO" "Initializing sensitive parameters"
    
    # Try Parameter Store first, fallback to environment variable
    DB_USERPASSWORD=$(get_parameter "DB_USERPASSWORD") || DB_USERPASSWORD="${DB_USERPASSWORD}"
    
    # Check if we found a password
    if [ -z "${DB_USERPASSWORD}" ]; then
        log "ERROR" "Database password not found in Parameter Store or environment variable"
        return 1
    fi

    export DB_USERPASSWORD
    
    log "INFO" "Sensitive parameters initialized successfully"
}

MYNAME="postgresql-backup-restore";
STATUS=0;

# Initialize parameters before starting backup
init_parameters || {
    error_message="Failed to initialize parameters - DB_USERPASSWORD not found in Parameter Store or environment variables"
    log "ERROR" "${error_message}"
    error_to_sentry "${error_message}" "DB_USERPASSWORD" "1"
    exit 1
}

log "INFO" "${MYNAME}: backup: Started";
log "INFO" "${MYNAME}: Backing up ${DB_NAME}";

start=$(date +%s);
$(PGPASSWORD=${DB_USERPASSWORD} pg_dump --host=${DB_HOST} --username=${DB_USER} --create --clean ${DB_OPTIONS} --dbname=${DB_NAME} > /tmp/${DB_NAME}.sql) || STATUS=$?;
end=$(date +%s);

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds.";
    log "ERROR" "${error_message}";
    error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}";
    exit $STATUS;
else
    log "INFO" "${MYNAME}: Backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${DB_NAME}.sql) bytes).";
fi

# Compression
start=$(date +%s);
gzip -f /tmp/${DB_NAME}.sql || STATUS=$?;
end=$(date +%s);

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Compressing backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds.";
    log "ERROR" "${error_message}";
    error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}";
    exit $STATUS;
else
    log "INFO" "${MYNAME}: Compressing backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds.";
fi

# S3 Upload
start=$(date +%s);
s3cmd put /tmp/${DB_NAME}.sql.gz ${S3_BUCKET} || STATUS=$?;
end=$(date +%s);
if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Copy backup to ${S3_BUCKET} of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds.";
    log "ERROR" "${error_message}";
    error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}";
    exit $STATUS;
else
    log "INFO" "${MYNAME}: Copy backup to ${S3_BUCKET} of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds.";
fi

# Backblaze B2 Upload
if [ "${B2_BUCKET}" != "" ]; then
    start=$(date +%s);
    s3cmd \
    --access_key=${B2_APPLICATION_KEY_ID} \
    --secret_key=${B2_APPLICATION_KEY} \
    --host=${B2_HOST} \
    --host-bucket='%(bucket)s.'"${B2_HOST}" \
    put /tmp/${DB_NAME}.sql.gz s3://${B2_BUCKET}/${DB_NAME}.sql.gz;
    STATUS=$?;
    end=$(date +%s);
    if [ $STATUS -ne 0 ]; then
        error_message="${MYNAME}: FATAL: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds.";
        log "ERROR" "${error_message}";
        error_to_sentry "${error_message}" "${DB_NAME}" "${STATUS}";
        exit $STATUS;
    else
        log "INFO" "${MYNAME}: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds.";
    fi
fi

echo "postgresql-backup-restore: backup: Completed";

log "INFO" "${MYNAME}: backup: Completed";

exit $STATUS;
