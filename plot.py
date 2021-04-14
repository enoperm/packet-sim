#!/usr/bin/env python3

def main(args):
    import pandas as pd
    import numpy as np
    import matplotlib.pyplot as plt

    source_file = args[1]
    destination_file = args[2]

    whole_by_alg = {}

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

    linestyles = ('solid', 'dotted', 'dashed', 'dashdot')

    plt.title(source_file)
    plt.xlabel('packets processed')
    plt.ylabel('inversion count')
    plt.figure(figsize=(10, 5))

    for (i, (alg, data)) in enumerate(whole_by_alg.items()):
        plt.plot(
            range(len(data)), data,
            label=alg,
            alpha=0.6, linestyle=linestyles[i % 4]
        )

    plt.legend()
    plt.savefig(destination_file)


if __name__ == '__main__':
    from sys import argv, stderr
    if len(argv) < 3:
        print(f'usage: {argv[0]} <sim-data> <saved-plot>', file=stderr)
        exit(1)

    main(argv)
