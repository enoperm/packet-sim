# Queue bounds adaptation algorithm simulator

## Dependencies:

As far as I am aware, the only build dependency is [dub](https://dub.pm),
a package manager/build system for the [D programming language](https://dlang.org).

## Testing

```sh
dub test
```

## Running

Building and running:
```sh
dub build
./packet-sim number-of-queues <name:spec> [name:spec]*
```

To list the currently available algorithms, you may use
```sh
./packet-sim --long-help
```

The generic format is `{instance-name}:{algorithm-name}{:algorithm-config}`
Of those, only `algorithm-config` is optional.

* `instance-name` is how the configured algorithm instance will be named on the output.
* `algorithm-name` specifies the algorithm to instantiate.
* `algorithm-config` tells the algorithm how to behave. The format of this value is algorithm-specific.

Packet ranks are read from stdin, one unsigned, ASCII encoded 64 integer per line.
The simulation runs until EOF.

All algorithms receive the same packets, in the same order.
After all algorithms have processed the packet, the current state of the simulation 
for each of the algorithms is written to stdout in `jsonl` format (JSON, one object per line).
