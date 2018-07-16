#!/usr/bin/env sh

for dbName in ${DB_NAMES}; do
    logger -p user.info "restoring ${dbName}..."

    runny s3cmd get -f ${S3_BUCKET}/${dbName}.sql.gz /tmp/${dbName}.sql.gz
    runny gunzip -f /tmp/${dbName}.sql.gz

    start=$(date +%s)
    runny psql --host=${DB_HOST} --username=${DB_USER} ${DB_OPTIONS}  < /tmp/${dbName}.sql
    end=$(date +%s)

    logger -p user.info "${dbName} restored in $(expr ${end} - ${start}) seconds."
done
