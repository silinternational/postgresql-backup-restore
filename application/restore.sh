#!/usr/bin/env sh

MYNAME="postgresql-backup-restore"
STATUS=0

echo "${MYNAME}: restore: Started"

# Ensure the database user exists.
echo "${MYNAME}: checking for DB user ${DB_USER}"
result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --command='\du' | grep ${DB_USER})
if [ -z "${result}" ]; then
    result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --command="create role ${DB_USER} with login password '${DB_USERPASSWORD}' inherit;")
    if [ "${result}" != "CREATE ROLE" ]; then
        message="Create role command failed: ${result}"
        echo "${MYNAME}: FATAL: ${message}"
        exit 1
    fi
fi

# Delete database if it exists.
echo "${MYNAME}: checking for DB ${DB_NAME}"
result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --list | grep ${DB_NAME})
if [ -z "${result}" ]; then
    message="Database "${DB_NAME}" on host "${DB_HOST}" does not exist."
    echo "${MYNAME}: INFO: ${message}"
else
    echo "${MYNAME}: deleting database ${DB_NAME}"
    result=$(psql --host=${DB_HOST} --dbname=postgres --username=${DB_ROOTUSER} --command="DROP DATABASE ${DB_NAME};")
    if [ "${result}" != "DROP DATABASE" ]; then
        message="Drop database command failed: ${result}"
        echo "${MYNAME}: FATAL: ${message}"
        exit 1
    fi
fi

echo "${MYNAME}: copying database ${DB_NAME} backup from ${S3_BUCKET}"
start=$(date +%s)
s3cmd get -f ${S3_BUCKET}/${DB_NAME}.sql.gz /tmp/${DB_NAME}.sql.gz || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    echo "${MYNAME}: FATAL: Copy backup of ${DB_NAME} from ${S3_BUCKET} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    exit $STATUS
else
    echo "${MYNAME}: Copy backup of ${DB_NAME} from ${S3_BUCKET} completed in $(expr ${end} - ${start}) seconds."
fi

echo "${MYNAME}: decompressing backup of ${DB_NAME}"
start=$(date +%s)
gunzip -f /tmp/${DB_NAME}.sql.gz || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    echo "${MYNAME}: FATAL: Decompressing backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    exit $STATUS
else
    echo "${MYNAME}: Decompressing backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

echo "${MYNAME}: restoring ${DB_NAME}"
start=$(date +%s)
psql --host=${DB_HOST} --username=${DB_ROOTUSER} --dbname=postgres ${DB_OPTIONS}  < /tmp/${DB_NAME}.sql || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    echo "${MYNAME}: FATAL: Restore of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    exit $STATUS
else
    echo "${MYNAME}: Restore of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

echo "${MYNAME}: restore: Completed"
exit $STATUS
