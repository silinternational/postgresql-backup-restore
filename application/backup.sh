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

get_parameter() {
    local parameter_name="$1"
    local value

    value=$(aws ssm get-parameter --name "${parameter_name}" --query "Parameter.Value" --output text) || return $?
    echo "${value}"
}

# Initialize required variables from Parameter Store
init_parameters() {
    log "INFO" "Fetching parameters from Parameter Store"
    
    # Database connection parameters
    DB_HOST=$(get_parameter "/postgresql-backup/DB_HOST") || return $?
    DB_USER=$(get_parameter "/postgresql-backup/DB_USER") || return $?
    DB_USERPASSWORD=$(get_parameter "/postgresql-backup/DB_USERPASSWORD") || return $?
    DB_NAME=$(get_parameter "/postgresql-backup/DB_NAME") || return $?
    DB_OPTIONS=$(get_parameter "/postgresql-backup/DB_OPTIONS") || return $?
    
    # S3 parameters
    S3_BUCKET=$(get_parameter "/postgresql-backup/S3_BUCKET") || return $?
    
    # B2 parameters
    if [ -n "${B2_BUCKET}" ]; then
        B2_APPLICATION_KEY_ID=$(get_parameter "/postgresql-backup/B2_APPLICATION_KEY_ID") || return $?
        B2_APPLICATION_KEY=$(get_parameter "/postgresql-backup/B2_APPLICATION_KEY") || return $?
        B2_HOST=$(get_parameter "/postgresql-backup/B2_HOST") || return $?
    fi

    #Export variables
    export DB_HOST DB_USER DB_USERPASSWORD DB_NAME S3_BUCKET DB_OPTIONS
    export B2_BUCKET B2_APPLICATION_KEY_ID B2_APPLICATION_KEY B2_HOST
    
    log "INFO" "Parameters initialized successfully"

}

MYNAME="postgresql-backup-restore";
STATUS=0;

log "INFO" "${MYNAME}: backup: Started";

# Initialize parameters from Parameter Store
if ! init_parameters; then
    error_message="${MYNAME}: FATAL: Failed to retrieve parameters from Parameter Store"
    log "ERROR" "${error_message}"
    error_to_sentry "${error_message}" "parameter_store" "1"
    exit 1
fi

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
