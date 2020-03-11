FROM alpine:3.11

RUN apk update \
 && apk add --no-cache \
            bash \
            postgresql \
            postgresql-client \
            python py-pip \
 && pip install s3cmd python-magic

COPY application/ /data/
WORKDIR /data

CMD ["./entrypoint.sh"]
