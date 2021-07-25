module model.common;

import std.range;
import std.algorithm;
import std.random;

import optional;

public:
@safe:

alias PacketCounts = long[long/* rank */];

struct Algorithm { string name; }
struct Usage { string text; }

struct SimState {
    long[] sumOfInversions;
    long[] inversions;
    long[] lastInQueue;
    long[] received;

    this(size_t queue_count) {
        static foreach(fname; __traits(allMembers, typeof(this))) {{
            alias f = __traits(getMember, this, fname);
            alias T = typeof(f);
            static if(__traits(compiles, new T(queue_count))) f = new T(queue_count);
        }}
    }
}

auto lookup(const(double[]) lower_bounds, const(long) rank)
in(lower_bounds.length > 0)
out(index; index.empty || index.front < lower_bounds.length && index.front >= 0)
out(index; index.empty || lower_bounds[index.front] <= rank)
{
    import std.conv: to;
    foreach(i, const b; lower_bounds.enumerate.retro) if(b <= rank) {
        return some(i.to!long);
    }
    return no!long;
}

version(unittest)
@("queue lookup returns no index when no existing queue could accept the packet")
unittest
{
    const bounds = [2.0, 8];
    const found = bounds.lookup(1);
    assert(found.empty);
}

version(unittest)
@("queue lookup returns expected indices")
unittest
{
    import std.algorithm: map;
    const bounds = [2.0, 8];
    const expected = chain(
        no!long .repeat(2),
        some(0L).repeat(6),
        some(1L).repeat(2),
    ).array;
    const got = iota(10).map!(p => bounds.lookup(p)).array;

    assert(expected == got);
}

SimState receivePacket(SimState sim, const(double[]) lower_bounds, long rank) pure @safe
in(lower_bounds.length > 0, `some bounds shall be given`)
in(lower_bounds.zip(lower_bounds.dropOne).all!(pair => pair[0] <= pair[1]), `bounds shall be in increasing order`)
{
    const target = lower_bounds.lookup(rank).or(some(0L)).front;

    SimState next = sim;
    with(next) {
        const diff =
            lastInQueue[target] > rank && received[target] ?
            lastInQueue[target] - rank : 0;
        sumOfInversions[target] += diff;
        if(diff) ++inversions[target];
        lastInQueue[target] = rank;
        received[target] += 1;
    }
    return next;
}

version(unittest)
@("SimState.receivePacket tracks inversions")
unittest {
    const bounds = [2.0, 4];
    auto s = SimState(bounds.length);

    s = s.receivePacket(bounds, 0);
    s = s.receivePacket(bounds, 1);

    assert(s.inversions == [0, 0], `no inversion within queue`);
    assert(s.sumOfInversions == [0, 0], `no inversion within queue`);

    s = s.receivePacket(bounds, 3);
    s = s.receivePacket(bounds, 1);

    assert(s.inversions == [1, 0], `inversion within queue`);
    assert(s.sumOfInversions == [2, 0], `inversion within queue`);

    s = s.receivePacket(bounds, 1);

    assert(s.inversions == [1, 0], `further packets of same rank do not count as individual inversion`);
    assert(s.sumOfInversions == [2, 0], `further packets of same rank do not count as individual inversion`);

    s = s.receivePacket(bounds, 4);
    s = s.receivePacket(bounds, 1);

    assert(s.inversions == [1, 0], `no inversion across queues`);
    assert(s.sumOfInversions == [2, 0], `no inversion across queues`);
}

interface AdaptationAlgorithm {
    double[] adapt(
        const(double[]) currentBounds,
        const(PacketCounts) byRank,
        const long receivedRank,
        const Optional!long targetQueue,
        in SimState previousState, const ulong time
    );
}

interface QueueBoundsInitialization {
    double[] initialBounds(long queueCount);
}

mixin template UniformBoundsInitialization(alias maxRank) {
    double[] initialBounds(long queueCount) {
        import std.conv: to;
        import std.math: ceil;
        auto step = maxRank(this).to!double / queueCount;
        auto bounds =
            0.only.chain(
                iota(1, queueCount)
                .map!(i => ceil(i * step).to!double)
            )
            .array;
        return bounds;
    }
}
