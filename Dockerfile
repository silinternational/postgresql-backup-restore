# With Python 3.12.4 on Alpine 3.20, s3cmd 2.4.0 fails with an AttributeError.
# See ITSE-1440 for details.
FROM python:3.12.4-alpine

# Current version of s3cmd is in edge/testing repo
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories

# Install everything via repo because repo & pip installs can break things
RUN apk update \
 && apk add --no-cache \
            bash \
            postgresql14-client \
            py3-magic \
            py3-dateutil \
            curl \
            jq 
            
RUN wget https://github.com/s3tools/s3cmd/archive/refs/tags/v2.4.0.tar.gz \
            && tar xzf v2.4.0.tar.gz \
            && cd s3cmd-2.4.0 \
            && python setup.py install \
            && cd .. \
            && rm -rf s3cmd-2.4.0 v2.4.0.tar.gz
# Install sentry-cli
RUN curl -sL https://sentry.io/get-cli/ | bash

COPY application/ /data/
WORKDIR /data

CMD ["./entrypoint.sh"]
