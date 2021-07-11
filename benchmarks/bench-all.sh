#!/usr/bin/env bash

export RNG_SEED=42
export SAMPLE_INTERVAL=10000
export PACKET_COUNT=1000000

# invocation:
# directory with txt files, used by GNU parallel to invoke the simulator,
# followed by number of packets,
# followed by a source of packet ranks.
./bench-set.sh uniform   ${PACKET_COUNT} ../rank-sources/uniform.py
./bench-set.sh triangle  ${PACKET_COUNT} ../rank-sources/triangle.py
./bench-set.sh geometric ${PACKET_COUNT} ../rank-sources/geometric.py
