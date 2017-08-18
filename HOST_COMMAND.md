# Networking
In docker 1.12 swarm mode was introduced. This enables automatic scheduling of containers as instances join or leave the swarm network. However this new mode introduces a new overlay network to the container called ingress, which may result in differing output of the `hostname -i` command. Therefor finer control of the advertised network is necessary.

For cassandra to work we need to specify the listening address and the broadcast address.

## Cassandra Listen Address

You can configure the addresses cassandra listens on in 3 different ways

- explicitly, using `CASSANDRA_LISTEN_ADDRESS`
- Setting the global `HOSTNAME_COMMAND` and `CASSANDRA_LISTEN_ADDRESS` set to `auto`,

 e.g. `HOSTNAME_COMMAND="route -n | awk '/UG[ \t]/{print $$2}'"`
- via a command, using `CASSANDRA_LISTEN_ADDRESS_COMMAND`

When using commands, make sure you review the "Variable Substitution" section in https://docs.docker.com/compose/compose-file/

If CASSANDRA_ADVERTISED_HOST_NAME is specified, it takes precedence over HOSTNAME_COMMAND

## Cassandra Broadcast Address

You can configure the address cassandra broadcasts to advertise its self to the rest of the cluster in 3 different ways:

- explicitly, using `CASSANDRA_BROADCAST_ADDRESS`
- Setting the global `HOSTNAME_COMMAND` and `CASSANDRA_BROADCAST_ADDRESS` set to `auto`
- or via `CASSANDRA_BROADCAST_ADDRESS_COMMAND`

## Host name commands

### local
ip of the gateway:

`HOSTNAME_COMMAND=route -n | awk '/UG[ \t]/{print $$2}'`

all ip addresses for the container:

`HOSTNAME_COMMAND=hostname -i`
### interface
to get the IP of a specific interface `eth2` in this case:

`HOSTNAME_COMMAND=ip r | awk '{ ip[$3] = $NF } END { print ( "eth2" in ip ? ip["eth2"] : ip["eth0"] ) }'`

### AWS
For AWS deployment, you can use the Metadata service to get the container host's IP:

`HOSTNAME_COMMAND=wget -t3 -T2 -qO-  http://169.254.169.254/latest/meta-data/local-ipv4`
Reference: [http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html]
