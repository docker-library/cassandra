#!/bin/bash
set -e

# execute a cql file as a string statement to cqlsh
_execute() {
	statement=$(<$1)	
	until echo "$statement" | cqlsh; do
		echo "cqlsh: Cassandra is unavailable - retry later"
		sleep 2
	done 
}

# determing how to execute the file based on extention
_process_init_file() {
	local f="$1"; shift

	case "$f" in
 		*.sh)     echo "$0: running $f"; . "$f" ;; 
		*.cql)    echo "$0: running $f"; _execute "$f"; echo ;;
		*.cql.gz) echo "$0: running $f"; gunzip -c "$f" | _execute; echo ;;
		*)        echo "$0: ignoring $f" ;;
	esac
}

_check_files() {
	until cqlsh -e 'describe cluster'; do 
		# processing the files in the data directory
		echo "cassandra not ready, will wait";
		sleep 2
	done 
	echo "cassandra ready, processing files";
	for f in ./data/*; do
		echo "processing file $f"
		_process_init_file "$f"
	done 
}

# first arg is `-f` or `--some-option`
# or there are no args
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
	set -- cassandra -f "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
	chown -R cassandra /var/lib/cassandra /var/log/cassandra "$CASSANDRA_CONFIG"
	exec gosu cassandra "$BASH_SOURCE" "$@"
fi

_ip_address() {
	# scrape the first non-localhost IP address of the container
	# in Swarm Mode, we often get two IPs -- the container IP, and the (shared) VIP, and the container IP should always be first
	ip address | awk '
		$1 == "inet" && $NF != "lo" {
			gsub(/\/.+$/, "", $2)
			print $2
			exit
		}
	'
}

# when there is a ./data directory mounted, we want to process the files in it.
# first test if the "data" directory exists and contains files
if [ -d "./data" ]; then
	if [ ! -z "$(ls -A /.data)" ]; then
		exec "$@" &
		# if there is an init-db.cql file, we probably want it to be executed first	
		# I rename it because scripts are executed in alphabetic order
		if [ -e /data/init-db.cql ] 
		then
			echo "Found an init-db.cql file"	
			mv /data/init-db.cql /data/1-init-db.cql
		fi
		_check_files
		# after the files are loaded, restart cassandra with the normal settings.
		pkill -f 'java.*cassandra'
	fi
fi 

if [ "$1" = 'cassandra' ]; then
	: ${CASSANDRA_RPC_ADDRESS='0.0.0.0'}

	: ${CASSANDRA_LISTEN_ADDRESS='auto'}
	if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
		CASSANDRA_LISTEN_ADDRESS="$(_ip_address)"
	fi

	: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}

	if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
		CASSANDRA_BROADCAST_ADDRESS="$(_ip_address)"
	fi
	: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

	if [ -n "${CASSANDRA_NAME:+1}" ]; then
		: ${CASSANDRA_SEEDS:="cassandra"}
	fi
	: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}
	
sed -ri 's/(- seeds:).*/\1 "'"$CASSANDRA_SEEDS"'"/' "$CASSANDRA_CONFIG/cassandra.yaml"

	for yaml in \
		broadcast_address \
		broadcast_rpc_address \
		cluster_name \
		endpoint_snitch \
		listen_address \
		num_tokens \
		rpc_address \
		start_rpc \
	; do
		var="CASSANDRA_${yaml^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
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
