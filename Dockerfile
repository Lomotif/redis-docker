FROM redis:alpine

RUN mkdir -p /etc/redis \
	&& mkdir -p /var/redis/db \
	&& chown redis.redis /var/redis/db

RUN apk add  --no-cache su-exec

VOLUME /var/redis/db
WORKDIR /var/redis/db

COPY redis/redis.conf /etc/redis/redis.conf
COPY redis/entrypoint.sh /entrypoint.sh

CMD ["redis-server", "/etc/redis/redis.conf"]
ENTRYPOINT ["/entrypoint.sh"]



