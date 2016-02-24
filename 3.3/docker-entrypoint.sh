#!/bin/bash
set -e

# first arg is `-f` or `--some-option`
if [ "${1:0:1}" = '-' ]; then
	set -- cassandra -f "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
	chown -R cassandra /var/lib/cassandra "$CASSANDRA_CONFIG"
	exec gosu cassandra "$BASH_SOURCE" "$@"
fi

if [ "$1" = 'cassandra' ]; then
	: ${CASSANDRA_RPC_ADDRESS='0.0.0.0'}

	: ${CASSANDRA_LISTEN_ADDRESS='auto'}
	if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
		CASSANDRA_LISTEN_ADDRESS="$(hostname --ip-address)"
	fi

	: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}

	if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
		CASSANDRA_BROADCAST_ADDRESS="$(hostname --ip-address)"
	fi
	: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

	if [ -n "${CASSANDRA_NAME:+1}" ]; then
		: ${CASSANDRA_SEEDS:="cassandra"}
	fi
	: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}
	
	sed -ri 's/(- seeds:) "127.0.0.1"/\1 "'"$CASSANDRA_SEEDS"'"/' "$CASSANDRA_CONFIG/cassandra.yaml"

	for VAR in `env`
	do
	  if [[ $VAR =~ ^CASSANDRA_ && ! ($VAR =~ ^CASSANDRA_VERSION || $VAR =~ ^CASSANDRA_CONFIG || $VAR =~ ^CASSANDRA_SEEDS || $VAR =~ ^CASSANDRA_DC || $VAR =~ ^CASSANDRA_RACK) ]]; then
	    var_name=`echo "$VAR" | sed -r "s/CASSANDRA_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]'`
	    env_var=`echo "$VAR" | sed -r "s/(.*)=.*/\1/g"`
	    if egrep -q "(^|^#)$var_name: " $CASSANDRA_CONFIG/cassandra.yaml; then
	        sed -r -i "s@(^|^#)($var_name): (.*)@\2: ${!env_var}@g" $CASSANDRA_CONFIG/cassandra.yaml #note that no config values may contain an '@' char
	    else
                # Append to bottom of file
	        echo "$var_name: ${!env_var}" >> $CASSANDRA_CONFIG/cassandra.yaml
	    fi
	  fi
	done

	for rackdc in dc rack; do
		var="CASSANDRA_${rackdc^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^('"$rackdc"'=).*/\1 '"$val"'/' "$CASSANDRA_CONFIG/cassandra-rackdc.properties"
		fi
	done
fi

exec "$@"
