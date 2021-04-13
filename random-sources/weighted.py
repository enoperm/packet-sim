#!/usr/bin/env python3

from sys import argv
from random import random

relative_weights = [int(w) for w in argv[1].split(',')]
total_weight = sum(relative_weights)
packet_count = int(argv[2])

max_rank = len(relative_weights) - 1

probabilities = [*(
    (relative_weights[step]/total_weight, step)
    for step
    in range(0, max_rank + 1)
    if relative_weights[step] > 0
)]

bounds = [
    (sum(w for (w, _) in probabilities[0:i+1]), rank)
    for (i, (width, rank))
    in enumerate(probabilities)
]

for i in range(packet_count):
    rand_value = random()
    for (mb, rank) in bounds:
        if rand_value <= mb:
            print(rank)
            break
