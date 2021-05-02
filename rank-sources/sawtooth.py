#!/usr/bin/env python3


from sys import argv

max_rank = int(argv[1])
packet_count = int(argv[2])

generated = 0
head = 0

while generated < packet_count:
    print(head)
    head = (head + 1 % (max_rank + 1))
    generated += 1
