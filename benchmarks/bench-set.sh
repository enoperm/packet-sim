#!/usr/bin/env bash

set -xeo pipefail

benchmark() {
    local benchfile="${1}"
    local outdir="${benchfile%/*}"
    local outfile="${benchfile##/${outdir}}"
    outfile="${outfile%.txt}.jsonl"

    local packet_count="${2}"
    local queue_count
    local max_rank

    shift 2

    queue_count=$(grep -Po '\d+(?=q)' <<< "${benchfile}")

    max_rank=$(grep -Po '\d+(?=r)' <<< "${benchfile}")
    max_rank=$(( max_rank - 1 ))

    ../eval-parallel.sh "${queue_count}" "${benchfile}" < <("${@}" "${max_rank}" "${packet_count}") > "${outfile}"
}

main() {
    local defs_dir="${1:?must specify location of benchmark definitions}"
    local packet_count="${2:?must specify packet count}"
    shift 2

    for benchfile in "${defs_dir}"/*.txt; do
        benchmark "${benchfile}" "${packet_count}" "${*}"
    done
}

main "${@}"
