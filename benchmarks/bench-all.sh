#!/usr/bin/env bash

export RNG_SEED=42
export SAMPLE_INTERVAL=10000

# invocation:
# directory with txt files, used by GNU parallel to invoke the simulator,
# followed by number of packets,
# followed by a source of packet ranks.
./bench-set.sh uniform 1000000 ../rank-sources/sawtooth.py
./bench-set.sh geometric 1000000 ../rank-sources/geometric.py
