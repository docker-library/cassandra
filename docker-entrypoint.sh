#!/bin/bash
set -e

# first arg is `-f` or `--some-option`
if [ "${1:0:1}" = '-' ]; then
	set -- cassandra -f "$@"
fi

if [ "$1" = 'cassandra' ]; then
	# TODO detect if this is a restart if necessary
	: ${CASSANDRA_LISTEN_ADDRESS='auto'}
	if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
		CASSANDRA_LISTEN_ADDRESS="$(hostname --ip-address)"
	fi
	
	: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}
	
	if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
		CASSANDRA_BROADCAST_ADDRESS="$(hostname --ip-address)"
	fi
	
	sed -ri 's/^(# )?(listen_address:).*/\2 '"$CASSANDRA_LISTEN_ADDRESS"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
	sed -ri 's/^(# )?(broadcast_address:).*/\2 '"$CASSANDRA_BROADCAST_ADDRESS"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
	sed -ri 's/^(# )?(broadcast_rpc_address:).*/\2 '"$CASSANDRA_BROADCAST_ADDRESS"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
	
	if [ "$CASSANDRA_SEEDS" ]; then
		CASSANDRA_SEEDS="$CASSANDRA_SEEDS,$CASSANDRA_BROADCAST_ADDRESS"
	else
		CASSANDRA_SEEDS="$CASSANDRA_BROADCAST_ADDRESS"
	fi
	sed -ri 's/(- seeds:) "127.0.0.1"/\1 "'"$CASSANDRA_SEEDS"'"/' "$CASSANDRA_CONFIG/cassandra.yaml"
	
	if [ "$CASSANDRA_CLUSTER_NAME" ]; then
		sed -ri 's/^(cluster_name:).*/\1 '"$CASSANDRA_CLUSTER_NAME"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
	fi
	
	if [ "$CASSANDRA_NUM_TOKENS" ]; then
		sed -ri 's/^(num_tokens:).*/\1 '"$CASSANDRA_NUM_TOKENS"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
	fi
fi

exec "$@"
