#!/usr/bin/env sh

    logger -p user.info "backing up ${DB_NAME}..."

    start=$(date +%s)
    runny $(PGPASSWORD=${DB_USERPASSWORD} pg_dump --host=${DB_HOST} --username=${DB_USER} --create --clean ${DB_OPTIONS} --dbname=${DB_NAME} > /tmp/${DB_NAME}.sql)
    end=$(date +%s)

    logger -p user.info "${DB_NAME} backed up ($(stat -c %s /tmp/${DB_NAME}.sql) bytes) in $(expr ${end} - ${start}) seconds."

    runny gzip -f /tmp/${DB_NAME}.sql
    runny s3cmd put /tmp/${DB_NAME}.sql.gz ${S3_BUCKET}
#    runny aws s3 cp /tmp/${DB_NAME}.sql.gz ${S3_BUCKET}

    logger -p user.info "${DB_NAME} backup stored in ${S3_BUCKET}."
