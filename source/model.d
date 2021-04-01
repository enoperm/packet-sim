module model;

import std.range;
import std.algorithm;
import std.random;

import optional;

public:
@safe:

struct SimState {
    ulong[] inversions;
    ulong[] lastInQueue;
    ulong[] received;

    this(size_t queue_count) {
        static foreach(fname; __traits(allMembers, typeof(this))) {{
            alias f = __traits(getMember, this, fname);
            alias T = typeof(f);
            static if(__traits(compiles, new T(queue_count))) f = new T(queue_count);
        }}
    }
}

auto lookup(const(ulong[]) lower_bounds, const(ulong) rank)
in(lower_bounds.length > 0)
out(index; index.empty || index.front < lower_bounds.length && index.front >= 0)
out(index; index.empty || lower_bounds[index.front] <= rank)
{
    foreach(i, const b; lower_bounds.enumerate.retro) if(b <= rank) {
        return some(i);
    }
    return no!size_t;
}

version(unittest)
@("queue lookup returns no index when no existing queue could accept the packet")
unittest
{
    const bounds = [2UL, 8];
    const found = bounds.lookup(1);
    assert(found.empty);
}

version(unittest)
@("queue lookup returns expected indices")
unittest
{
    import std.algorithm: map;
    const bounds = [2UL, 8];
    const expected = chain(
        no!ulong .repeat(2),
        some(0UL).repeat(6),
        some(1UL).repeat(2),
    ).array;
    const got = iota(10).map!(p => bounds.lookup(p)).array;

    assert(expected == got);
}

SimState receivePacket(SimState sim, const(ulong[]) lower_bounds, ulong rank) pure @safe
in(lower_bounds.length > 0, `some bounds shall be given`)
in(lower_bounds.zip(lower_bounds.dropOne).all!(pair => pair[0] <= pair[1]), `bounds shall be in increasing order`)
{
    const target = lower_bounds.lookup(rank).or(some(0UL)).front;

    SimState next = sim;
    with(next) {
        const inversionHappened = received[target] > 0 && rank < lastInQueue[target];
        inversions[target] += inversionHappened ? 1 : 0;
        lastInQueue[target] = rank;
        received[target] += 1;
    }
    return next;
}

version(unittest)
@("SimState.receivePacket tracks inversions")
unittest {
    const bounds = [2UL, 4];
    auto s = SimState(bounds.length);

    s = s.receivePacket(bounds, 0);
    s = s.receivePacket(bounds, 1);

    assert(s.inversions == [0, 0], `no inversion within queue`);

    s = s.receivePacket(bounds, 3);
    s = s.receivePacket(bounds, 1);

    assert(s.inversions == [1, 0], `inversion within queue`);

    // TODO: needs to be redone to support both edge and level triggered inversion tracking.
    s = s.receivePacket(bounds, 1);
    assert(s.inversions == [1, 0], `further packets of same rank do not count as individual inversion`);

    s = s.receivePacket(bounds, 4);
    s = s.receivePacket(bounds, 1);
    assert(s.inversions == [1, 0], `no inversion across queues`);
}

alias PacketCounts = ulong[ulong/* rank */];

interface AdaptationAlgorithm {
    ulong[] adapt(const(ulong[]) currentBounds, const(PacketCounts) byRank, const ulong receivedRank) pure;
}

struct Algorithm { string name; }
struct Usage { string text; }


final class Static : AdaptationAlgorithm {
private:
    const(ulong[]) bounds;
public:
    this(ulong[] bounds) pure {
        this.bounds = bounds;
    }

    ulong[] adapt(const(ulong[]) currentBounds, const(PacketCounts) byRank, const ulong receivedRank) pure {
        return this.bounds.dup;
    }
}

final class PushUpPushDown : AdaptationAlgorithm {
public:
    ulong[] adapt(const(ulong[]) currentBounds, const(PacketCounts) byRank, const ulong receivedRank) pure {
        import std.algorithm;
        import std.array;

        auto bounds = currentBounds.dup;

        auto pushDown() {
            pragma(inline, true);

            immutable cost = bounds.front - receivedRank;
            foreach(ref b; bounds) b -= cost;
        }

        auto pushUp(ulong target) {
            pragma(inline, true);
            bounds[target] = receivedRank;
        }

        if(receivedRank < bounds.front) pushDown();
        else {
            auto target = currentBounds.lookup(receivedRank);
            if(target.empty) target = some(bounds.back);
            pushUp(target.front);
        }

        return bounds;
    }
}


@Algorithm("static")
@Usage(
`
An "adaptation algorithm" that always keeps queue bounds at their initially configured values.
This adaptation algorithm requires you to configure queue bounds manually.
Instantiation: <name>:static,${queue_bounds}
    where ${queue_bounds} is a comma-separated list of bounds.
    example: 1,2,4

The number of bounds must be the same as the configured number of queues.
`)
AdaptationAlgorithm setup_static(string spec) pure {
    import std.algorithm: map;
    import std.conv: to;
    import std.string: strip;
    return new Static(spec.split(',').map!strip.map!(to!ulong).array);
};

@Algorithm("pupd")
@Usage(
`
This adaptation algorithm does not expose any configuration.
Instantiation: <name>:pupd
`)
AdaptationAlgorithm setup_pupd(string spec) pure {
    cast(void)spec; // not used by pupd
    return new PushUpPushDown();
};

version(unittest) {
private:
import std;

    @("pupd: NSDI '20 example input produces known expected output")
    unittest {
        const inputs = [4UL, 3, 2, 3];
        immutable expected = [
            [0UL, 4],
            [3UL, 4],
            [2UL, 3],
            [2UL, 3],
        ];

        auto pupd = setup_pupd("");
        ulong[] current = [0UL, 0];
        foreach(i, input; inputs) {
            current = pupd.adapt(current, null, input);
            assert(current == expected[i], format!`%s: %s -> %s`(i, input, current));
        }
    }

    @("static: setup function parses queue bounds")
    unittest {
        assert(setup_static("0,4"));
    }

    @("static: algorithm always sets the same bounds")
    unittest {
        const inputs = [4, 3, 2, 3];
        immutable expected = [
            [0UL, 4],
            [0UL, 4],
            [0UL, 4],
            [0UL, 4],
        ];

        auto _static = new Static([0UL, 4]);
        ulong[] current = [0UL, 0];
        foreach(i, input; inputs) {
            current = _static.adapt(current, null, input);
            assert(current == expected[i], format!`%s: %s -> %s`(i, input, current));
        }
    }
}
