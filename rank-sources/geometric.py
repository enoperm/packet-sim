#!/usr/bin/env python3

from sys import argv
from rng import rng

max_rank = int(argv[1])
ranks = max_rank + 1

max_weight = 1 << ranks
relative_weights = [max_weight >> i for i in range(ranks)]
total_weight = sum(relative_weights)
packet_count = int(argv[2])

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

random = rng()
for i in range(packet_count):
    rand_value = random.random()
    for (mb, rank) in bounds:
        if rand_value <= mb:
            print(rank)
            break
