#!/usr/bin/env bash
set -Eeuo pipefail

defaultJavaVersion='11'
declare -A javaVersions=(
	[2.2]='8'
	[3.0]='8'
	[3.11]='8'
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	export version

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
	export fullVersion sha512

	export javaVersion="${javaVersions[$version]:-$defaultJavaVersion}"

	echo "$version: $fullVersion"

	json="$(jq <<<"$json" -c '
		.[env.version] = {
			version: env.fullVersion,
			sha512: env.sha512,
			java: env.javaVersion,
		}
	')"
done

jq <<<"$json" -S . > versions.json
