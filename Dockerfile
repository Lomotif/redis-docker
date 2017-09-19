FROM redis:4-alpine

RUN apk add  --no-cache su-exec

RUN mkdir -p /etc/redis && \
    chgrp redis /etc/redis && \
    chmod g+w /etc/redis


COPY redis/redis.conf /etc/redis/redis.conf
COPY redis/entrypoint.sh /entrypoint.sh
COPY redis/run.sh /run.sh

CMD ["/run.sh"]
ENTRYPOINT ["/entrypoint.sh"]



