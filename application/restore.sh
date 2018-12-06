#!/usr/bin/env sh

# Does the database exist?
logger -p user.info "checking for DB ${DB_NAME}..."
result=$(psql --host=${DB_HOST} --user=${DB_ROOTUSER} --list | grep ${DB_NAME})
if [ -z "${result}" ]; then
    message="Database "${DB_NAME}" on host "${DB_HOST}" does not exist."
    logger -p 1 -t application.crit "${message}"
    exit 1
fi

# Ensure the database user exists.
logger -p user.info "checking for DB user ${DB_USER}..."
result=$(psql --host=${DB_HOST} --user=${DB_ROOTUSER} --command='\du' | grep ${DB_USER})
if [ -z "${result}" ]; then
    result=$(psql --host=${DB_HOST} --user=${DB_ROOTUSER} --command="create role ${DB_USER} with login password '${DB_PASSWORD}' inherit;")
    if [ "${result}" != "CREATE ROLE" ]; then
        message="Create role command failed: ${result}"
        logger -p 1 -t application.crit "${message}"
        exit 1
    fi

    result=$(psql --host=${DB_HOST} --user=${DB_ROOTUSER} --command="alter database ${DB_NAME} owner to ${DB_USER};")
    if [ "${result}" != "ALTER DATABASE" ]; then
        message="Alter database command failed: ${result}"
        logger -p 1 -t application.crit "${message}"
        exit 1
    fi
fi

logger -p user.info "restoring ${DB_NAME}..."

runny s3cmd get -f ${S3_BUCKET}/${DB_NAME}.sql.gz /tmp/${DB_NAME}.sql.gz
runny gunzip -f /tmp/${DB_NAME}.sql.gz

start=$(date +%s)
runny psql --host=${DB_HOST} --username=${DB_USER} ${DB_OPTIONS}  < /tmp/${DB_NAME}.sql
end=$(date +%s)

logger -p user.info "${DB_NAME} restored in $(expr ${end} - ${start}) seconds."
