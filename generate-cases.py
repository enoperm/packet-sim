#!/usr/bin/env python3


from enum import Enum, unique
from typing import Dict, List, Tuple, Union


@unique
class Argument(Enum):
    HELP = 'help'
    DISTRIBUTION = 'distribution'
    OUT_DIR = 'out-dir'


def print_usage():
    from sys import argv
    print(
        f'''
usage: {argv[0]}
    -d|--distribution geometric|uniform
    -o|--out-dir directory'''
    )


def query_offline(args: List[str]) -> Dict[str, List[int]]:
    def run():
        from json import loads
        from subprocess import run

        result = run(
            ['./offline-model/offline-model', *args],
            capture_output=True
        )
        assert result.returncode == 0, str(result)

        for line in result.stdout.decode('UTF-8').splitlines():
            yield loads(line)

    return {
        model['name']: [
            int(b)
            for b
            in model['bounds']
        ]
        for model
        in run()
    }


def get_distribution(name: str):
    if name == 'uniform':
        def unif(ranks: int) -> List[int]:
            return [1 for _ in range(ranks)]
        return unif

    if name == 'geometric':
        def geom(ranks: int) -> List[int]:
            max_weight = 1 << ranks
            return [
                max_weight >> i
                for i
                in range(ranks)
            ]
        return geom


def main(config) -> None:
    domain_queues = (2, 3, 5, 7, 11, 17)
    domain_ranks = (13, 19, 23, 31, 37)

    distribution = get_distribution(str(config[Argument.DISTRIBUTION]))

    out_dir = config[Argument.OUT_DIR]

    for k in domain_queues:
        for n in domain_ranks:
            model_name_suffix = f'{k}q-{n}r'
            output_file = f'{out_dir}/bench_{model_name_suffix}.txt'

            with open(output_file, 'w') as output:
                print(f'pupd-{model_name_suffix}:pupd', file=output)
                # print(
                #     f'pp-exact-{model_name_suffix}:per-packet:exact,{n-1}',
                #     file=output
                # )
                # print(
                #     f'pp-estimate-{model_name_suffix}:per-packet:upper_estimate,{n-1}',
                #     file=output
                # )

                d = distribution(ranks=n)
                offline_distribution_parameters = [
                    ','.join([str(v) for v in d]),
                    str(k)
                ]
                offline_models = query_offline(offline_distribution_parameters)

                for (name, bounds) in offline_models.items():
                    bstr = ','.join([str(b) for b in bounds])
                    print(
                        f'static-{name}-{model_name_suffix}:static:{bstr}',
                        file=output
                    )
    pass


if __name__ == '__main__':
    from sys import argv, stderr
    from getopt import getopt, GetoptError

    def getopts() -> List[Tuple[str, str]]:
        try:
            opts, _args = getopt(
                argv[1:], 'd:ho:',
                [
                    a.value
                    for a
                    in Argument
                ]
            )
            return opts

        except GetoptError as e:
            print_usage()
            print(e, file=stderr)
            exit(1)

    def unique_name(arg: str) -> Union[Argument, str]:
        return {
            '-d': Argument.DISTRIBUTION,
            '-o': Argument.OUT_DIR,
            '-h': Argument.HELP,
        }.get(arg, arg)

    opts = getopts()
    config = {
        unique_name(name): arg or True
        for (name, arg)
        in opts
    }

    mandatory_arguments = set((
        Argument.DISTRIBUTION,
        Argument.OUT_DIR,
    ))

    missing_args = mandatory_arguments.difference(set(config.keys()))

    if Argument.HELP in config or missing_args:
        print_usage()
        exit(1)

    main(config)
