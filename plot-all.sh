#!/usr/bin/env bash

while read -r result; do
    ./plot.py "sum" "${result}" "${result%.jsonl}-sum.svg"
    ./plot.py "count" "${result}" "${result%.jsonl}-count.svg"
done
