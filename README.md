
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

    $ docker run -d -v /etc/redis:/etc/redis:ro -v /mnt/data/redis/db:/var/redis/db --name redis lomotif/redis
