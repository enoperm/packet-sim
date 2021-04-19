#!/usr/bin/env python3

from sys import argv
from rng import rng

max_rank = int(argv[1])
packet_count = int(argv[2])

bounds = [*(
    (1/(max_rank + 1) * (step + 1), step)
    for step
    in range(0, max_rank + 1)
)]

random = rng()

for i in range(packet_count):
    rand_value = random.random()
    for (mb, rank) in bounds:
        if rand_value <= mb:
            print(rank)
            break
