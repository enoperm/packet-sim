import random
from os import environ

def rng():
    rng = random.Random()
    if 'RNG_SEED' in environ:
        rng.seed(int(environ['RNG_SEED']))

    return rng
