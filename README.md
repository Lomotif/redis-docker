
# Setup

Ensure the necessary directories are set up

    $ bin/bootstrap redis      # Create /etc/redis
    $ bin/bootstrap redis_db   # Create /mnt/data/redis/db

# Configuration

Copy the provided redis configuration file to the (newly created?) `/etc/redis`, and edit as necessary

    $ sudo cp redis/redis.conf /etc/redis

If needed, copy a redis `.rdb` file into the data directory

    $ sudo cp /path/to/dump.rdb /mnt/data/redis/db/dump.rdb

These two folders will be mounted in the container at run time

# Running

We set two special options on the `docker run` command

    --ulimit nofile=10032

    We bump the number of file descriptors in order to bump the number of open connections

    --cpuset-cpus="2,3"

    Set the CPU affinity to two specific CPUs. While Redis is single-threaded, we set affinity
    to two CPUs since Redis will spin up background threads/process for flushing to disk.
    Through this, we attempt to avoid conflict with other containers/apps on the system.


    $ docker run -d -v /etc/redis:/etc/redis:ro -v /mnt/data/redis/db:/var/redis/db --ulimit nofile=10032 --cpuset-cpus="2,3" --name redis lomotif/redis
