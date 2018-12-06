#!/usr/bin/env sh

# hostname:port:database:username:password
echo ${DB_HOST}:*:*:${DB_USER}:${DB_USERPASSWORD}      > /root/.pgpass
echo ${DB_HOST}:*:*:${DB_ROOTUSER}:${DB_ROOTPASSWORD} >> /root/.pgpass
chmod 600 /root/.pgpass

if [ "${LOGENTRIES_KEY}" ]; then
    sed -i /etc/rsyslog.conf -e "s/LOGENTRIESKEY/${LOGENTRIES_KEY}/"
    rsyslogd
    sleep 10 # ensure rsyslogd is running before we may need to send logs to it
else
    logger -p user.error  "Missing LOGENTRIES_KEY environment variable"
fi

# default to every day at 2 am when no schedule is provided
echo "${CRON_SCHEDULE:=0 2 * * *} runny /data/${MODE}.sh" >> /etc/crontabs/root

runny $1
