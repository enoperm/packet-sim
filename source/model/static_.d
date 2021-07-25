module model.static_;

import std.range;
import std.algorithm;
import std.random;

import optional;

public import model.common;

public:
@safe:

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

version(unittest) {
private:
import std;
    @("static: setup function parses queue bounds")
    unittest {
        assert(setup_static("0,4"));
    }

    @("static: algorithm always sets the same bounds")
    unittest {
        const inputs = [4, 3, 2, 3];
        immutable expected = [
            [0.0, 4],
            [0.0, 4],
            [0.0, 4],
            [0.0, 4],
        ];

        auto _static = new Static([0L, 4]);
        auto current = [0.0, 0];
        foreach(i, input; inputs) {
            current = _static.adapt(current, null, input, some(0L), SimState(), i);
            assert(current == expected[i], format!`%s: %s -> %s`(i, input, current));
        }
    }
}
