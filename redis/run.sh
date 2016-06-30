#!/bin/ash
#
# Borrowed shamelessly from https://hub.docker.com/r/kubernetes/redis/

launchmaster() {
  if [[ ! -e /data/redis ]]; then
    echo "Redis master data doesn't exist, data won't be persistent!"
    mkdir /data/redis/
  fi
  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
  # IPADDR=0.0.0.0
  sed "s/^bind .*$/bind ${IPADDR}/" /etc/redis/master.conf > /etc/redis/master-tmp.conf
  redis-server /etc/redis/master-tmp.conf
}

launchsentinel() {
  while true; do
    master=$(redis-cli -h ${REDIS_SENTINEL_SERVICE_HOST} -p ${REDIS_SENTINEL_SERVICE_PORT} --csv SENTINEL get-master-addr-by-name redismaster | tr ',' ' ' | cut -d' ' -f1)
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

  echo "sentinel monitor redismaster ${master} 6379 2" > ${sentinel_conf}
  echo "sentinel down-after-milliseconds redismaster 60000" >> ${sentinel_conf}
  echo "sentinel failover-timeout redismaster 180000" >> ${sentinel_conf}
  echo "sentinel parallel-syncs redismaster 1" >> ${sentinel_conf}

  redis-sentinel ${sentinel_conf}
}

launchslave() {
  if [[ ! -e /data/redis ]]; then
    echo "Redis slave data doesn't exist, data won't be persistent!"
    mkdir /data/redis/
  fi
  while true; do
    master=$(redis-cli -h ${REDIS_SENTINEL_SERVICE_HOST} -p ${REDIS_SENTINEL_SERVICE_PORT} --csv SENTINEL get-master-addr-by-name redismaster | tr ',' ' ' | cut -d' ' -f1)
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

  sed -i "s/%master-ip%/${master}/" /etc/redis/slave.conf
  sed -i "s/%master-port%/6379/" /etc/redis/slave.conf
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
