#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# TODO update to 11 for 4.0 (https://issues.apache.org/jira/browse/CASSANDRA-9608)
defaultJavaVersion='8'
declare -A javaVersions=(
	#[2.2]='8'
)

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	possibleVersions=( $(
		git ls-remote --tags 'https://gitbox.apache.org/repos/asf/cassandra.git' "refs/tags/cassandra-$version*" \
			| cut -d/ -f3- \
			| cut -d^ -f1 \
			| cut -d- -f2- \
			| sort -urV
	) )

	fullVersion=
	sha512=
	for possibleVersion in "${possibleVersions[@]}"; do
		if sha512="$(wget -qO- "https://downloads.apache.org/cassandra/$possibleVersion/apache-cassandra-$possibleVersion-bin.tar.gz.sha512" | grep -oE '[a-f0-9]{128}')" && [ -n "$sha512" ]; then
			fullVersion="$possibleVersion"
			break
		fi
	done
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: failed to find full version for $version"
		exit 1
	fi

	echo "$version: $fullVersion"

	javaVersion="${javaVersions[$version]:-$defaultJavaVersion}"
	cp -a docker-entrypoint.sh "$version/"
	sed \
		-e "s/%%CASSANDRA_VERSION%%/$fullVersion/g" \
		-e "s/%%CASSANDRA_SHA512%%/$sha512/g" \
		-e "s/%%JAVA_VERSION%%/$javaVersion/g" \
		Dockerfile.template > "$version/Dockerfile"

	# remove the "/docker-entrypoint.sh" backwards-compatibility symlink in Cassandra 3.12+
	case "$version" in
		2.*|3.0|3.11) ;;
		*) sed -i '/^RUN .* \/docker-entrypoint.sh # backwards compat$/d' "$version/Dockerfile" ;;
	esac
	# TODO once Cassandra 2.x and 3.x are deprecated, we should remove this from the template itself (and remove this code too)

	# python3 is only supported in 4.0+
	# https://issues.apache.org/jira/browse/CASSANDRA-10190
	case "$version" in
		2.* | 3.*)
			sed -i 's/python3/python/g' "$version/Dockerfile"
			;;
	esac
done
