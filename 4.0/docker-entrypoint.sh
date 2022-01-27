#!/bin/bash
set -e

# first arg is `-f` or `--some-option`
# or there are no args
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
	set -- cassandra -f "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
	find "$CASSANDRA_CONF" /var/lib/cassandra /var/log/cassandra \
		\! -user cassandra -exec chown cassandra '{}' +
	exec gosu cassandra "$BASH_SOURCE" "$@"
fi

_ip_address() {
	# scrape the first non-localhost IP address of the container
	# in Swarm Mode, we often get two IPs -- the container IP, and the (shared) VIP, and the container IP should always be first
	ip address | awk '
		$1 != "inet" { next } # only lines with ip addresses
		$NF == "lo" { next } # skip loopback devices
		$2 ~ /^127[.]/ { next } # skip loopback addresses
		$2 ~ /^169[.]254[.]/ { next } # skip link-local addresses
		{
			gsub(/\/.+$/, "", $2)
			print $2
			exit
		}
	'
}

# "sed -i", but without "mv" (which doesn't work on a bind-mounted file, for example)
_sed-in-place() {
	local filename="$1"; shift
	local tempFile
	tempFile="$(mktemp)"
	sed "$@" "$filename" > "$tempFile"
	cat "$tempFile" > "$filename"
	rm "$tempFile"
}

_sed-in-place_ext() {
        local filename="$1";
        key="$2";
        value="$3";
        local tempFile
        tempFile="$(mktemp)"
        egrep -q "^[#]{0,1}\s*?$key\s*?:" $filename && sed -r 's/^(# )?('"$key"':).*/\2 '"$value"'/' "$filename" > "$tempFile" || sed "$ a\\${key}: $value" "$filename" > "$tempFile"
        cat "$tempFile" > "$filename"
        rm "$tempFile"
}

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

	_sed-in-place "$CASSANDRA_CONF/cassandra.yaml" \
		-r 's/(- seeds:).*/\1 "'"$CASSANDRA_SEEDS"'"/'

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
			_sed-in-place "$CASSANDRA_CONF/cassandra.yaml" \
				-r 's/^(# )?('"$yaml"':).*/\2 '"$val"'/'
		fi
	done


	for conf_yaml_var in "${!CASSANDRA_YML_@}"; do
        conf_yaml_key="$(echo "${conf_yaml_var,,}" | sed -e 's/^cassandra_yml_//g')"
        conf_yaml_val="${!conf_yaml_var}"
        if [ "$conf_yaml_val" ]; then
                _sed-in-place_ext "$CASSANDRA_CONF/cassandra.yaml" "$conf_yaml_key" "$conf_yaml_val"
        fi
    done

	for rackdc in dc rack; do
		var="CASSANDRA_${rackdc^^}"
		val="${!var}"
		if [ "$val" ]; then
			_sed-in-place "$CASSANDRA_CONF/cassandra-rackdc.properties" \
				-r 's/^('"$rackdc"'=).*/\1 '"$val"'/'
		fi
	done
fi

exec "$@"
