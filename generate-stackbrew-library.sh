#!/bin/bash
set -eu

declare -A aliases=(
	[2.2]='2'
	[3.11]='3 latest'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

cat <<-EOH
# this file is generated via https://github.com/docker-library/cassandra/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/cassandra.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version in "${versions[@]}"; do
	commit="$(dirCommit "$version")"

	fullVersion="$(git show "$commit":"$version/Dockerfile" | awk '$1 == "ENV" && $2 == "CASSANDRA_VERSION" { print $3; exit }')"

	versionAliases=( $fullVersion )
	if [ "$version" != "$fullVersion" ]; then
		versionAliases+=( $version )
	fi
	versionAliases+=( ${aliases[$version]:-} )

	# $ wget -qO- 'https://dl.bintray.com/apache/cassandra/dists/311x/Release' | grep '^Architectures:'
	# Architectures: i386 amd64
	arches='amd64 i386'

	# https://github.com/docker-library/cassandra/pull/116#issuecomment-326650640
	# Exception (java.lang.RuntimeException) encountered during startup: java.lang.RuntimeException: java.util.concurrent.ExecutionException: java.lang.NoClassDefFoundError: Could not initialize class com.sun.jna.Native
	# java.lang.RuntimeException: java.lang.RuntimeException: java.util.concurrent.ExecutionException: java.lang.NoClassDefFoundError: Could not initialize class com.sun.jna.Native
	if [ "$version" != '2.2' ]; then
		# on arm64, 2.1 works fine
		arches+=' arm64v8'
	fi
	if [[ "$version" != 2.* ]]; then
		# on ppc64le, 2.x both fail
		arches+=' ppc64le'
	fi

	arches="$(echo "$arches" | xargs -n1 | sort)"

	echo
	cat <<-EOE
		Tags: $(join ', ' "${versionAliases[@]}")
		Architectures: $(join ', ' $arches)
		GitCommit: $commit
		Directory: $version
	EOE
done
