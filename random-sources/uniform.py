#!/usr/bin/env python3

from sys import argv
from random import random

max_rank = int(argv[1])
packet_count = int(argv[2])

bounds = [*(
    (1/(max_rank + 1) * (step + 1), step)
    for step
    in range(0, max_rank + 1)
)]

for i in range(packet_count):
    rand_value = random()
    for (mb, rank) in bounds:
        if rand_value <= mb:
            print(rank)
            break
