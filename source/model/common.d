module model.common;

import std.range;
import std.algorithm;
import std.random;
import std.typecons: Flag, Yes, No;

import optional;

public:
@safe:

alias PacketCounts = long[long/* rank */];

struct Algorithm { string name; }
struct Usage { string text; }

alias QueueLookupFunction = Optional!long function(const(double[]) bounds, const(long) rank);

struct SimState {
public:
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

auto lookup(Flag!"fuzzy" fuzzy = No.fuzzy)(const(double[]) lower_bounds, const(long) rank)
in(lower_bounds.length > 0)
out(index; index.empty || index.front < lower_bounds.length && index.front >= 0)
out(index; index.empty || lower_bounds[index.front] <= rank + (fuzzy ? 1 : 0))
{
    import std.conv: to;
    auto target = no!long;
    static if(fuzzy)
        auto delta = 0.0;

    foreach(i, const b; lower_bounds.enumerate.retro) if(b <= rank) {
        target = some(i.to!long);
        static if(fuzzy) if(i + 1 < lower_bounds.length) {
            delta = lower_bounds[i+1] - rank;
        }
        break;
    }

    static if(fuzzy) {
        if(!target.empty && delta <= 1.0) {
            import std.random: uniform01;
            auto spilloverProbablity = 1.0 - delta;
            auto roll = uniform01();
            int bump = roll < spilloverProbablity;
            bump &= (target.front + 1) < lower_bounds.length;
            target += bump;
        }
    }

    return target;
}

alias lookupFuzzy = lookup!(Yes.fuzzy);

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

version(unittest)
@("in the integer bounds case, fuzzy queue lookup matches the deterministic behaviour")
unittest
{
    import std.algorithm: map;
    const bounds = [2.0, 8];
    const expected = chain(
        no!long .repeat(2),
        some(0L).repeat(6),
        some(1L).repeat(2),
    ).array;
    const got = iota(10).map!(p => bounds.lookupFuzzy(p)).array;

    assert(expected == got);
}

SimState receivePacket(SimState sim, const(double[]) lower_bounds, long rank, long target) pure @safe
in(lower_bounds.length > 0, `some bounds shall be given`)
in(lower_bounds.zip(lower_bounds.dropOne).all!(pair => pair[0] <= pair[1]), `bounds shall be in increasing order`)
{
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

version(unittest) {
    @("SimState.receivePacket tracks inversions")
    unittest {
        const bounds = [2.0, 4];
        auto s = SimState(bounds.length);

        s = s.receivePacket(bounds, 0, 0);
        s = s.receivePacket(bounds, 1, 0);

        assert(s.inversions == [0, 0], `no inversion within queue`);
        assert(s.sumOfInversions == [0, 0], `no inversion within queue`);

        s = s.receivePacket(bounds, 3, 0);
        s = s.receivePacket(bounds, 1, 0);

        assert(s.inversions == [1, 0], `inversion within queue`);
        assert(s.sumOfInversions == [2, 0], `inversion within queue`);

        s = s.receivePacket(bounds, 1, 0);

        assert(s.inversions == [1, 0], `further packets of same rank do not count as individual inversion`);
        assert(s.sumOfInversions == [2, 0], `further packets of same rank do not count as individual inversion`);

        s = s.receivePacket(bounds, 4, 1);
        s = s.receivePacket(bounds, 1, 0);

        assert(s.inversions == [1, 0], `no inversion across queues`);
        assert(s.sumOfInversions == [2, 0], `no inversion across queues`);
    }

    @("Fuzzy lookup uses the fractional part of the next lowest bound as probability of spillover")
    unittest {
        import std;

        const bounds = [0.0, 1.5];

        ulong[2] counts;
        auto input =
            iota(10000)
            .map!(_ => 1);

        foreach(const i; input) {
            const target = bounds.lookupFuzzy(i).front;
            counts[target]++;
        }

        enum epsilon = 0.01;
        sort(counts[]);
        assert((counts.back / counts.front - 1) <= epsilon);
    }
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
