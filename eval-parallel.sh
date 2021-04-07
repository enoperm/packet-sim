#!/usr/bin/env bash

if [ "${#}" -lt 2 ]; then
cat <<USAGE
    usage: ${0} <number-of-queues> <specs-file>
    packet ranks are taken from standard input
USAGE
exit 1
fi

nqueues="${1:?must set number of queues}"
specs="${2:?must configure algorithms to test}"

parallel \
    -I{} -n1 \
    -a "${specs}" \
    --tee --pipe --line-buffer \
    </dev/stdin \
    ./packet-sim "${nqueues}" {}
