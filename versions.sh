#!/usr/bin/env bash
set -Eeuo pipefail

# https://cassandra.apache.org/doc/5.0/cassandra/installing/installing.html#prerequisites
# https://cassandra.apache.org/doc/4.1/cassandra/getting_started/installing.html#prerequisites
# https://github.com/apache/cassandra/blob/cassandra-5.0.6/build.xml#L48
defaultJavaVersion='17'
declare -A javaVersions=(
	[4.0]='11' # https://github.com/apache/cassandra/blob/cassandra-4.0.19/build.xml#L212-L221
	[4.1]='11' # https://github.com/apache/cassandra/blob/cassandra-4.1.10/build.xml#L227-L236
)
defaultSuite='trixie'
declare -A suites=(
	# https://issues.apache.org/jira/browse/CASSANDRA-19206: "cqlsh breaks with Python 3.12" ("ModuleNotFoundError: No module named 'six.moves'")
	[4.0]='bookworm'
	[4.1]='bookworm'
	# "Warning: unsupported version of Python, required 3.6-3.11 but found 3.12"
	# https://github.com/apache/cassandra/commit/8fd44ca8fc9e0b0e94932bcd855e2833bf6ca3cb#diff-8d8ae48aaf489a8a0e726d3e4a6230a26dcc76e7c739e8e3968e3f65c995d148
	# https://issues.apache.org/jira/browse/CASSANDRA-19245?focusedCommentId=17803539#comment-17803539
	# https://github.com/apache/cassandra/blob/cassandra-5.0.6/bin/cqlsh#L65
	[5.0]='bookworm'
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

	export javaVersion="${javaVersions[$version]:-$defaultJavaVersion}" # TODO scrape this from build.xml upstream directly?
	export suite="${suites[$version]:-$defaultSuite}"

	echo "$version: $fullVersion"

	json="$(jq <<<"$json" -c '
		.[env.version] = {
			version: env.fullVersion,
			sha512: env.sha512,
			java: {
				version: env.javaVersion,
			},
			debian: {
				version: env.suite,
			},
		}
	')"
done

jq <<<"$json" . > versions.json
