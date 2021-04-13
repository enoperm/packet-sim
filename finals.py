#!/usr/bin/env python3

from typing import Any, Dict, Iterable, List


def finals(input_objects: Iterable[str]) -> List[Dict[str, Any]]:
    most_recent_by_alg: Dict[str, Dict[str, Any]] = {}

    for obj in input_objects:
        present = most_recent_by_alg.get(obj['algorithm'])
        if not present or present['time'] < obj['time']:
            most_recent_by_alg[obj['algorithm']] = obj

    return [*most_recent_by_alg.values()]


if __name__ == '__main__':
    from json import loads, dumps
    from sys import stdin

    input_objects = map(lambda ser: loads(ser), stdin)
    for result in finals(input_objects):
        print(dumps(result))
