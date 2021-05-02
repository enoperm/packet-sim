#!/usr/bin/env python3


from sys import argv

max_rank = int(argv[1])
packet_count = int(argv[2])

generated = 0
direction = 1
head = 0

while generated < packet_count:
    print(head)
    head += direction

    if head == max_rank or head == 0:
        print(head)  # to make distribution more uniform
        generated += 1
        direction *= -1

    generated += 1
