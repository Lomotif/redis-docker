#!/bin/sh
#
# Borrowed shamelessly from https://hub.docker.com/r/kubernetes/redis/

export REDIS_MASTER_NAME=${REDIS_MASTER_NAME:-redismaster}
export PORT=${REDIS_PORT:-6379}
export MAXMEMORY=${REDIS_MAXMEMORY:-1000000000}

# Evaluating variable indirection in sh
# Ref: http://stackoverflow.com/a/1014604
export REDIS_SENTINEL_HOST=${REDIS_SENTINEL_HOST}
if [ ! ${REDIS_SENTINEL_HOST} ] && [ ${REDIS_SENTINEL_SERVICE_NAME} ]; then
  SENTINEL_HOST=$(echo "${REDIS_SENTINEL_SERVICE_NAME}_SERVICE_HOST" | tr '[a-z]' '[A-Z]' | tr '-' '_')
  REDIS_SENTINEL_HOST=$(eval "echo \$${SENTINEL_HOST}")
fi

export REDIS_SENTINEL_PORT=${REDIS_SENTINEL_PORT}
if [ ! ${REDIS_SENTINEL_PORT} ] && [ ${REDIS_SENTINEL_SERVICE_NAME} ]; then
  SENTINEL_PORT=$(echo "${REDIS_SENTINEL_SERVICE_NAME}_SERVICE_PORT" | tr '[a-z]' '[A-Z]' | tr '-' '_')
  REDIS_SENTINEL_PORT=$(eval "echo \$$SENTINEL_PORT")
fi

launchmaster() {
  if [[ ! -e /data/redis ]]; then
    echo "Redis master data doesn't exist, data won't be persistent!"
    mkdir /data/redis/
  fi
  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
  # IPADDR=0.0.0.0
  sed -i "s/^bind .*$/bind ${IPADDR}/" /etc/redis/master.conf
  sed -i "s/%maxmemory%/${MAXMEMORY}/" /etc/redis/master.conf
  redis-server /etc/redis/master.conf
}

launchsentinel() {
  while true; do
    master=$(redis-cli -h ${REDIS_SENTINEL_HOST} -p ${REDIS_SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} | tr ',' ' ' | cut -d' ' -f1)
    if [[ ${master} ]]; then
      master="${master//\"}"
    else
      master=$(hostname -i)
    fi

    redis-cli -h ${master} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done

  sentinel_conf=/etc/redis/sentinel.conf
#  curl http://${KUBERNETES_RO_SERVICE_HOST}:${KUBERNETES_RO_SERVICE_PORT}/api/v1beta1/endpoints/redis-master | python /sentinel.py > ${sentinel_conf}

  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)

  echo "bind ${IPADDR}" > ${sentinel_conf}
  echo "sentinel monitor ${REDIS_MASTER_NAME} ${master} ${PORT} 2" >> ${sentinel_conf}
  echo "sentinel down-after-milliseconds ${REDIS_MASTER_NAME} 30000" >> ${sentinel_conf}
  echo "sentinel failover-timeout ${REDIS_MASTER_NAME} 60000" >> ${sentinel_conf}
  echo "sentinel parallel-syncs ${REDIS_MASTER_NAME} 1" >> ${sentinel_conf}

  redis-sentinel ${sentinel_conf}
}

launchslave() {
  if [[ ! -e /data/redis ]]; then
    echo "Redis slave data doesn't exist, data won't be persistent!"
    mkdir /data/redis/
  fi
  while true; do
    master=$(redis-cli -h ${REDIS_SENTINEL_HOST} -p ${REDIS_SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} | tr ',' ' ' | cut -d' ' -f1)
    if [[ ${master} ]]; then
      master="${master//\"}"
    else
      echo "Failed to find master."
      sleep 60
      exit 1
    fi
    redis-cli -h ${master} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done

  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
  sed -i "s/^bind .*$/bind ${IPADDR}/" /etc/redis/slave.conf
  sed -i "s/%master-ip%/${master}/" /etc/redis/slave.conf
  sed -i "s/%master-port%/${PORT}/" /etc/redis/slave.conf
  sed -i "s/%maxmemory%/${MAXMEMORY}/" /etc/redis/slave.conf
  redis-server /etc/redis/slave.conf
}

if [[ "${MASTER}" == "true" ]]; then
  launchmaster
  exit 0
fi

if [[ "${SENTINEL}" == "true" ]]; then
  launchsentinel
  exit 0
fi

launchslave
