module model.spring;

import std.range;
import std.algorithm;
import std.random;

import optional;

public import model.common;

public:
@safe:

final class Static : AdaptationAlgorithm {
private:
    const(double[]) bounds;
public:
    this(double[] bounds) pure {
        this.bounds = bounds;
    }

    double[] adapt(
        const(double[]) currentBounds,
        const(PacketCounts) byRank,
        const long receivedRank,
        const Optional!long targetQueue,
        in SimState previousState,
        const ulong time
    ) pure {
        return this.bounds.dup;
    }
}
@Algorithm("static")
@Usage(
`
An "adaptation algorithm" that always keeps queue bounds at their initially configured values.
This adaptation algorithm requires you to configure queue bounds manually.
Instantiation: <name>:static:${queue_bounds}
    where ${queue_bounds} is a comma-separated list of bounds.
    example: 1,2,4

The number of bounds must be the same as the configured number of queues.
`)
AdaptationAlgorithm setup_static(string spec) pure {
    import std.algorithm: map;
    import std.conv: to;
    import std.string: strip;
    return new Static(spec.split(',').map!strip.map!(to!double).array);
}
