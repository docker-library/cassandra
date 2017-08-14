# About this Repo

This is the Git repo of the Docker image of [Webscam Cassandra](https://hub.docker.com/r/webscam/cassandra/) a fork of the Official [cassandra](https://registry.hub.docker.com/_/cassandra/) Docker image, with modifications for working with [Docker Swarm Mode](https://docs.docker.com/engine/swarm/).

See [the Docker Hub Official Cassandra page](https://registry.hub.docker.com/_/cassandra/) for further settings on how to use this Docker image and for information regarding contributing and issues.

# Docker Swarm mode

Since Docker 1.12 automatic service orchestration through the docker engine swarm mode was introduced. This help with service scaling, availability, and service discovery. In initial releases of docker however there were a number of issues making the automation of a Cassandra cluster difficult:
1. The default configuration is to have the container traffic routed and load balanced through a virtual ip and a mesh network. This introduces two problems for deploying a cluster of Cassandra machines using swarm mode:
1. It is hard to get the containers to seed of the virtual IP in the dns record.
2. A new interface is introduced for the default `ingress network` which breaks the advertised `hostname` functions using `hostname -i` as you may get one of the 3 interfaces.

Later versions of docker seem to have fixed these issues and a number of other stability issues, as such the approach outlined here only works on docker 17.03.0 and above.

# Usage

## Single Node/ No Mount Point
Starting a test swarm
```bash
docker swarm init
docker network create -d overlay mynetwork
```

Start the cassandra service
```bash
docker service create \
  --name cassandra \
  --network mynetwork \
  -e HEAP_NEWSIZE=12M \
  -e MAX_HEAP_SIZE=64M \
  webscam/cassandra:swarm_test
```
Scale the cassandra service
```bash
docker service scale cassandra=2
docker service scale cassandra=3
```
Scale one at a time else cassandra will complain about bootstrapping more than one service at once.

Check the status of the cluster
```bash
docker exec -it $(docker ps | grep cassandra.1 | awk '{print $1}') nodetool status
```

## Many nodes with volume mount
Setup a docker swarm test cluster
```bash
# create nodes
docker-machine create -d virtualbox master
docker-machine create -d virtualbox node1
docker-machine create -d virtualbox node2
# get config
master_conf=$(docker-machine config master)
node1_conf=$(docker-machine config node1)
node2_conf=$(docker-machine config node2)

# link nodes into swarm
master_ip=$(docker-machine ip master)
docker $master_conf swarm init --advertise-addr $master_ip
join_token=$(docker $master_conf swarm join-token worker -q)
join_cmd=$(echo "swarm join --token $join_token $master_ip:2377")
docker $node1_conf $join_cmd
docker $node2_conf $join_cmd

# make network
eval $(docker-machine env master)
docker network create -d overlay your_overlay_network
```

Start the cassandra service

```bash
# make sure file system exists
docker service create --name makedir -t \
  --mode global \
  --mount type=bind,dst=/home,src=/home \
  alpine sh -c "mkdir -p /home/cassandra; sh"

# create service
docker service create \
  --name cassandra \
  --network 'your_overlay_network' \
	--update-delay 40s \
  --mode global \
  --mount type=bind,target=/var/lib/cassandra,source=/home/cassandra \
  webscam/cassandra:swarm_test
```

You'll notice that we set the orchestration to global mode, so that there is only one Cassandra container per node in the swarm. Here we also mounted an ssd/hdd partition on the host machine for the containers data directory for persistent storage/ improved performance.

# Configuration options

## `CASSANDRA_SEEDS`

This variable is the comma-separated list of IP addresses used by gossip for bootstrapping new nodes joining a cluster. It will set the seeds value of the [`seed_provider`](http://docs.datastax.com/en/cassandra/3.0/cassandra/configuration/configCassandra_yaml.html#configCassandra_yaml__seed_provider) option in `cassandra.yaml`.

If set to `auto` the script will detect the IP's of the cluster from the `tasks.$SERVICE_NAME` DNS entry see below.

The `CASSANDRA_BROADCAST_ADDRESS` will be added the the seeds passed in so that the sever will talk to itself if no other tasks exist.

Default setting `auto`

## `SERVICE_NAME`

The name of the service to look for DNS records of associated Cassandra tasks when bootstrapping a cluster in docker swarm mode. The script will get a list of IPs by looking at the DNS records for `tasks.$SERVICE_NAME`.

Default setting `cassandra`

# Maintenance Considerations

The setup scripts in this repository will try to bootstrap and replace nodes in a sensible manor. However reading the [source documentation on node management](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/operationsTOC.html), is worth it if your data is important to you.

## Node replacement

In the case of an unmounted/ non persistent service we will attempt to replace the node with the [method described here](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/ops_replace_live_node.html#opsReplaceLiveNodeAlternate) if the node dies. This only works if docker decides to bring the dead service up with the same ip address of the previous container, other wise you may still need to decommission the dead service as below.

However in the case of persistent/ multi node setup there are two cases which may need to be accounted for.

1. The service on a node dies and is automatically replaced (`/var/lib/cassandra` persisted)
2. The node running the docker engine dies (loss of `/var/lib/cassandra`)

In case 1 the service should just rejoin the cassandra cluster as normal, even if the ip address changes. However in case 2 there is no easy way of knowing when the new swarm node is added if the intention is to scale the cassandra service or to replace the dead node. If the the physical node was lost as in case 1 you need to manually run through the [method described here.](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/opsReplaceNode.html) Of course this assumes that you set the *replication factor to greater than 1* on all your tables.

Before adding the new node you should decommission or remove the old node to let cassandra bootstrap normally. See [RemoveNode](http://docs.datastax.com/en/cassandra/2.1/cassandra/tools/toolsRemoveNode.html)

## Node repair

It is [recommended in the doculentation](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/opsRepairNodesTOC.html) that the cluster needs to have `nodetool repair` run sequentially on each node of the cluster at an interval of `gc_grace_period`. This is a PITA to script so until such a point I have a script/cron job which can orchestrate its self to run `nodetool repair`  exclusively, sequentially one at a time on each service, this is an operation which requires scripting/ intervention from outside of the service.
