# Docker Swarm mode

Since Docker 1.12 automatic service orchestration through the docker engine swarm mode was introduced. This help with service scaling, availability, and service discovery. In initial releases of docker however there were a number of issues making the automation of a Cassandra cluster difficult:
- 1 The default configuration is to have the container traffic routed and load balanced through a virtual ip and a mesh network. This introduces two problems for deploying a cluster of Cassandra machines using swarm mode:
1. It is hard to get the containers to seed of the virtual IP in the dns record.
2. A new interface is introduced for the default `ingress network` which breaks the advertised `hostname` functions using `hostname -i` as you may get one of the 3 interfaces.

Later versions of docker seem to have fixed these issues and a number of other stability issues, as such the approach outlined here only really works on docker 17.03.0 and above.

## Starting a test swarm
```bash
#!/bin/bash
docker service create \
  --name cassandra \
  --network mynetwork \
  -e HEAP_NEWSIZE=12M \
  -e MAX_HEAP_SIZE=64M \
  webscam/cassandra:swarm_test
```

## Many nodes with volume mount
```bash
docker service create \
  --name cassandra \
  --network 'your_overlay_network' \
  --mode global \
  --mount type=volume,target=/var/lib/cassandra,source=/mnt/c/cassandra \
  webscam/cassandra:swarm_test
```

You'll notice that we set the orchestration to global mode, so that there is only one Cassandra container per node in the swarm. Here we also mounted an ssd partition on the host machine for the containers data directory for improved performance.

# Configuration options

## `CASSANDRA_SEEDS`

This variable is the comma-separated list of IP addresses used by gossip for bootstrapping new nodes joining a cluster. It will set the seeds value of the [`seed_provider`](http://docs.datastax.com/en/cassandra/3.0/cassandra/configuration/configCassandra_yaml.html#configCassandra_yaml__seed_provider) option in `cassandra.yaml`.

If set to `auto` the script will detect the IP's of the cluster from the `tasks.$SERVICE_NAME` DNS entry see below.

The `CASSANDRA_BROADCAST_ADDRESS` will be added the the seeds passed in so that the sever will talk to itself if no other tasks exist.

Default setting `auto`

## `SERVICE_NAME`

The name of the service to look for DNS records of associated Cassandra tasks when bootstrapping a cluster in docker swarm mode. The script will get a list of IPs by looking at the DNS records for `tasks.$SERVICE_NAME`.

Default setting `cassandra`
