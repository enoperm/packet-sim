module model.pupd;

import std.range;
import std.algorithm;
import std.random;

import optional;

public import model.common;

public:
@safe:

final class PushUpPushDown : AdaptationAlgorithm {
public:
    double[] adapt(
        const(double[]) currentBounds,
        const(PacketCounts) byRank,
        const long receivedRank,
        const Optional!long targetQueue,
        in SimState previousState,
        const ulong time
    ) pure {
        import std.conv: to;

        auto bounds = currentBounds.dup;

        void pushDown() {
            pragma(inline, true);

            immutable cost = bounds.front - receivedRank;
            foreach(ref b; bounds) b -= cost;
        }

        void pushUp(long target) {
            pragma(inline, true);
            bounds[target] = receivedRank;
        }

        if(receivedRank < bounds.front) pushDown();
        else pushUp(targetQueue.or(some(bounds.back.to!long)).front);

        return bounds;
    }
}

@Algorithm("pupd")
@Usage(
`
This adaptation algorithm does not expose any configuration.
Instantiation: <name>:pupd
`)
AdaptationAlgorithm setup_pupd(string spec) pure {
    cast(void)spec; // not used by pupd
    return new PushUpPushDown();
}

version(unittest) {
private:
import std;

    @("pupd: NSDI '20 example input produces known expected output")
    unittest {
        const inputs = [4L, 3, 2, 3];
        immutable expected = [
            [0L, 4],
            [3L, 4],
            [2L, 3],
            [2L, 3],
        ];

        auto pupd = setup_pupd("");
        double[] current = [0L, 0];
        foreach(i, input; inputs) {
            current = pupd.adapt(current, null, input, SimState(), i);
            assert(current == expected[i], format!`%s: %s -> %s`(i, input, current));
        }
    }
}
