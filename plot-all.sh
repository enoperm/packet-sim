#!/usr/bin/env bash

while read -r result; do
    ./plot.py "${result}" "${result%.jsonl}.svg"
done
