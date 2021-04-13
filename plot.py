#!/usr/bin/env python3

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def main(args):
    source_file = args[1]

    whole_by_alg = {}
    min_set = None

    # TODO: use getopt
    data_chunked = pd.read_json(source_file, lines=True, chunksize=100000)
    for chunk in data_chunked:
        chunk['total_inversions'] = np.vectorize(sum)(chunk['inversions'])
        chunk.set_index('time')
        by_alg = chunk.groupby('algorithm')
        for (alg, alg_chunk) in by_alg:
            alg_chunk = alg_chunk.sort_values('time')
            lst = whole_by_alg.get(alg, list())
            lst.extend(alg_chunk['total_inversions'].values)
            whole_by_alg[alg] = lst
            if not min_set or lst[-1] < whole_by_alg[min_set][-1]:
                min_set = alg

    def delta_to_min(dataset):
        min_data = whole_by_alg[min_set]
        for (i, min_i) in zip(dataset, min_data):
            yield i - min_i

    whole_by_alg = {
        alg: [*delta_to_min(data)]
        for (alg, data)
        in whole_by_alg.items()
    }

    for (alg, data) in whole_by_alg.items():
        print(f'[{source_file}] alg: {alg} => {data[-1]}')
        plt.plot(range(len(data)), data, label=alg)

    plt.title(source_file)
    plt.legend()

    plt.show()


if __name__ == '__main__':
    from sys import argv
    main(argv)
