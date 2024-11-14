#!/usr/bin/env bash

# Function to send error to Sentry
send_error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"
    
    if [ -n "${SENTRY_DSN}" ]; then
        wget -q --header="Content-Type: application/json" \
             --post-data="{
                \"message\": \"${error_message}\",
                \"level\": \"error\",
                \"extra\": {
                    \"database\": \"${db_name}\",
                    \"status_code\": \"${status_code}\",
                    \"hostname\": \"$(hostname)\"
                    }
    }" \
             -O - "${SENTRY_DSN}"
    fi
}

MYNAME="postgresql-backup-restore"
STATUS=0

echo "${MYNAME}: backup: Started"

echo "${MYNAME}: Backing up ${DB_NAME}"

start=$(date +%s)
$(PGPASSWORD=${DB_USERPASSWORD} pg_dump --host=${DB_HOST} --username=${DB_USER} --create --clean ${DB_OPTIONS} --dbname=${DB_NAME} > /tmp/${DB_NAME}.sql) || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    echo "${error_message}"
    send_error_to_sentry "${error_message}" "${STATUS}" "${DB_NAME}"   
    exit $STATUS
else
    echo "${MYNAME}: Backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${DB_NAME}.sql) bytes)."
fi

start=$(date +%s)
gzip -f /tmp/${DB_NAME}.sql || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Compressing backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    echo "${error_message}"
    send_error_to_sentry "${error_message}" "${STATUS}" "${DB_NAME}"
    exit $STATUS
else
    echo "${MYNAME}: Compressing backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
s3cmd put /tmp/${DB_NAME}.sql.gz ${S3_BUCKET} || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    error_message="${MYNAME}: FATAL: Copy backup to ${S3_BUCKET} of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    echo "${error_message}"
    send_error_to_sentry "${error_message}" "${STATUS}" "${DB_NAME}"
    exit $STATUS
else
    echo "${MYNAME}: Copy backup to ${S3_BUCKET} of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
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
        echo "${error_message}"
        send_error_to_sentry "${error_message}" "${STATUS}"
        exit $STATUS
    else
        echo "${MYNAME}: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
    fi
fi

echo "${MYNAME}: backup: Completed"
