FROM redis:4-alpine

RUN apk add  --no-cache su-exec

RUN mkdir -p /etc/redis && \
    chgrp redis /etc/redis && \
    chmod g+w /etc/redis


COPY redis/master.conf /etc/redis/master.conf
COPY redis/slave.conf /etc/redis/slave.conf
COPY redis/entrypoint.sh /entrypoint.sh
COPY redis/run.sh /run.sh

CMD ["/run.sh"]
ENTRYPOINT ["/entrypoint.sh"]



