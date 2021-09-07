#!/bin/bash
set -eu

declare -A aliases=(
	[3.11]='3'
	[4.0]='4 latest'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

# sort version numbers with highest first
IFS=$'\n'; set -- $(sort -rV <<<"$*"); unset IFS

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

getArches() {
	local repo="$1"; shift
	local officialImagesUrl='https://github.com/docker-library/official-images/raw/master/library/'

	eval "declare -g -A parentRepoToArches=( $(
		find -name 'Dockerfile' -exec awk '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|.*\/.*)(:|$)/ {
					print "'"$officialImagesUrl"'" $2
				}
			' '{}' + \
			| sort -u \
			| xargs bashbrew cat --format '[{{ .RepoName }}:{{ .TagName }}]="{{ join " " .TagEntry.Architectures }}"'
	) )"
}
getArches 'cassandra'

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

for version; do
	export version

	fullVersion="$(jq -r '.[env.version].version' versions.json)"

	versionAliases=( $fullVersion )
	if [ "$version" != "$fullVersion" ]; then
		versionAliases+=( $version )
	fi
	versionAliases+=( ${aliases[$version]:-} )

	parent="$(awk 'toupper($1) == "FROM" { print $2 }' "$version/Dockerfile")"
	arches="${parentRepoToArches[$parent]}"

	# s390x is not actually supported
	# https://github.com/docker-library/cassandra/pull/116#issuecomment-326654542
	# https://github.com/docker-library/cassandra/issues/193
	# https://issues.apache.org/jira/browse/CASSANDRA-11054
	arches="$(sed -r -e 's/ s390x / /g' <<<" $arches ")"

	# riscv64 doesn't have a proper Java port yet
	arches="$(sed -r -e 's/ riscv64 / /g' <<<" $arches ")"

	arches="$(xargs -n1 <<<"$arches" | sort)"

	commit="$(dirCommit "$version")"

	echo
	cat <<-EOE
		Tags: $(join ', ' "${versionAliases[@]}")
		Architectures: $(join ', ' $arches)
		GitCommit: $commit
		Directory: $version
	EOE
done
