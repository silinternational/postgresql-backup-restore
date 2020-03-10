#!/usr/bin/env sh

STATUS=0

echo "postgresql-backup-restore: restore: Started"

# Does the database exist?
echo "postgresql-backup-restore: checking for DB ${DB_NAME}"
result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --list | grep ${DB_NAME})
if [ -z "${result}" ]; then
    message="Database "${DB_NAME}" on host "${DB_HOST}" does not exist."
    echo "postgresql-backup-restore: FATAL: ${message}"
    exit 1
fi

# Ensure the database user exists.
echo "postgresql-backup-restore: checking for DB user ${DB_USER}"
result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --command='\du' | grep ${DB_USER})
if [ -z "${result}" ]; then
    result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --command="create role ${DB_USER} with login password '${DB_USERPASSWORD}' inherit;")
    if [ "${result}" != "CREATE ROLE" ]; then
        message="Create role command failed: ${result}"
        echo "postgresql-backup-restore: FATAL: ${message}"
        exit 1
    fi
fi

echo "postgresql-backup-restore: changing DB ownership to ${DB_USER}"
result=$(psql --host=${DB_HOST} --username=${DB_ROOTUSER} --command="alter database ${DB_NAME} owner to ${DB_USER};")
if [ "${result}" != "ALTER DATABASE" ]; then
    message="Alter database command failed: ${result}"
    echo "postgresql-backup-restore: FATAL: ${message}"
    exit 1
fi

echo "postgresql-backup-restore: restoring ${DB_NAME}"

start=$(date +%s)
s3cmd get -f ${S3_BUCKET}/${DB_NAME}.sql.gz /tmp/${DB_NAME}.sql.gz || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    echo "postgresql-backup-restore: FATAL: Copy backup of ${DB_NAME} from ${S3_BUCKET} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    exit $STATUS
else
    echo "postgresql-backup-restore: Copy backup of ${DB_NAME} from ${S3_BUCKET} completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
gunzip -f /tmp/${DB_NAME}.sql.gz || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    echo "postgresql-backup-restore: FATAL: Decompressing backup of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    exit $STATUS
else
    echo "postgresql-backup-restore: Decompressing backup of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
psql --host=${DB_HOST} --username=${DB_USER} --dbname=${DB_NAME} ${DB_OPTIONS}  < /tmp/${DB_NAME}.sql || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
    echo "postgresql-backup-restore: FATAL: Restore of ${DB_NAME} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
    exit $STATUS
else
    echo "postgresql-backup-restore: Restore of ${DB_NAME} completed in $(expr ${end} - ${start}) seconds."
fi

echo "postgresql-backup-restore: restore: Completed"
exit $STATUS
