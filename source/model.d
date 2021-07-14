module model;

import std.range;
import std.algorithm;
import std.random;

import optional;

public import types;

import costfns;

public:
@safe:

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

auto lookup(const(long[]) lower_bounds, const(long) rank)
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
    const bounds = [2L, 8];
    const found = bounds.lookup(1);
    assert(found.empty);
}

version(unittest)
@("queue lookup returns expected indices")
unittest
{
    import std.algorithm: map;
    const bounds = [2L, 8];
    const expected = chain(
        no!long .repeat(2),
        some(0L).repeat(6),
        some(1L).repeat(2),
    ).array;
    const got = iota(10).map!(p => bounds.lookup(p)).array;

    assert(expected == got);
}

SimState receivePacket(SimState sim, const(long[]) lower_bounds, long rank) pure @safe
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
    const bounds = [2L, 4];
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
    long[] adapt(const(long[]) currentBounds, const(PacketCounts) byRank, const long receivedRank, in SimState previousState, const ulong time);
}

interface QueueBoundsInitialization {
    long[] initialBounds(long queueCount);
}

mixin template UniformBoundsInitialization(alias maxRank) {
    long[] initialBounds(long queueCount) {
        import std.conv: to;
        import std.math: ceil;
        auto step = maxRank(this).to!double / queueCount;
        auto bounds =
            0.only.chain(
                iota(1, queueCount)
                .map!(i => ceil(i * step).to!long)
            )
            .array;
        return bounds;
    }
}

struct Algorithm { string name; }
struct Usage { string text; }


final class Static : AdaptationAlgorithm {
private:
    const(long[]) bounds;
public:
    this(long[] bounds) pure {
        this.bounds = bounds;
    }

    long[] adapt(const(long[]) currentBounds, const(PacketCounts) byRank, const long receivedRank, in SimState previousState, const ulong time) pure {
        return this.bounds.dup;
    }
}


final class PushUpPushDown : AdaptationAlgorithm {
public:
    long[] adapt(const(long[]) currentBounds, const(PacketCounts) byRank, const long receivedRank, in SimState previousState, const ulong time) pure {
        import std.algorithm;
        import std.array;

        auto bounds = currentBounds.dup;

        auto pushDown() {
            pragma(inline, true);

            immutable cost = bounds.front - receivedRank;
            foreach(ref b; bounds) b -= cost;
        }

        auto pushUp(long target) {
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

final class SpringInversionHeuristic : AdaptationAlgorithm, QueueBoundsInitialization {
private:
    long maxRank;
    long sampleSize;
    double alpha;
    double sensitivity;

    long[] previous;
    double[] previousDelta;

public:
    this(long maxRank, long sampleSize, double alpha, double sensitivity) pure {
        this.maxRank = maxRank;
        this.sampleSize = sampleSize;
        this.alpha = alpha;
        this.sensitivity = sensitivity;
    }

    long[] adapt(const(long[]) currentBounds, const(PacketCounts) byRank, const long receivedRank, in SimState previousState, const ulong time) {
        import std.conv: to;
        import std.algorithm;
        import std.array;
        import std.typecons: Tuple, tuple;


        auto bounds = currentBounds.dup;

        if(time % sampleSize) return bounds;
        scope(exit)
            this.previous =
                previousState
                .inversions
                .dup;

        if(previous.empty)
            this.previous =
                previousState
                .inversions
                .map!(_ => 0L)
                .array;

        if(previousDelta.empty)
            this.previousDelta =
                previousState
                .inversions
                .map!(_ => 0.0)
                .array;

        debug import std.stdio: stderr;
        auto delta =
            previousState
            .inversions
            .zip(this.previous)
            .map!(tup => tup[0] - tup[1])
            .map!(to!double)
            .zip(this.previousDelta)
            // (1 - \alpha) * k_{t}(i-1) + \alpha * k_{t}(i)
            .map!(tup => (1 - this.alpha) * tup[1] + this.alpha * tup[0])
            .array;

        scope(exit) this.previousDelta = delta;

        auto forces =
            delta.front.only
            .chain(delta)
            .chain(delta.back.only);

        const scalingFactor = (this.sensitivity * this.maxRank.to!double) / (bounds.length*this.sampleSize);
        import std.math: round;
        auto delta_f =
            forces
            .zip(forces.dropOne)
            .map!(tup => tup[1] - tup[0]) // S_{i+1}(r) - S_{i}(l)
            .map!(delta_f => delta_f * scalingFactor)
            .tee!(t => { debug stderr.writeln(t); }())
            .map!round
            .array
        ;

        debug {
            import std;
            stderr.writeln(" > ", bounds);
            stderr.writeln("#> ", previousState.inversions);
            stderr.writeln("~> ", delta);
            stderr.writeln("+> ", forces);
            stderr.writeln("~~ ", delta_f);
        }

        // do note that the lowest queue bound is always zero,
        bounds[1..$] =
            bounds[1..$]
            .zip(delta_f)
            .map!(tup => tup[0] + tup[1])
            .map!(b => min(b, this.maxRank).max(1.0))
            .map!(to!long)
            .array;
        bounds[0] = 0;

        // since we do not otherwise ensure that bounds to not "swap places" with each other,
        // let's sort them before returning.
        // this should be roughly equivalent to having elastic collisions between the bounds.
        sort(bounds);

        return bounds;
    }

    mixin UniformBoundsInitialization!(instance => instance.maxRank);
}

final class ApproximateBalancedBuckets : AdaptationAlgorithm, QueueBoundsInitialization {
private:
    long maxRank;
    long sampleSize;
    PacketCounts previous;

public:
    this(long maxRank, long sampleSize) pure {
        this.maxRank = maxRank;
        this.sampleSize = sampleSize;
    }

    long[] adapt(const(long[]) currentBounds, const(PacketCounts) byRank, const long receivedRank, in SimState previousState, const ulong time) {
        import std.conv: to;
        import std.algorithm;
        import std.array;
        import std.typecons: Tuple, tuple;

        auto bounds = currentBounds.dup;
        if(time % sampleSize) return bounds;
        scope(exit)
            previous =
                byRank
                .byKey
                .map!(k => tuple(k, byRank[k].to!long))
                .assocArray;

        PacketCounts delta;
        foreach(rank; byRank.byKey) {
            const count = byRank[rank];
            delta[rank] = count - previous.get(rank, 0);
        }
        // The actual implementation would maintain its own state,
        // but this simulator already keeps track of all the information we need,
        // so let's convert from that instead.
        auto sampled = new long[currentBounds.length*2];
        auto receivedRanks = delta.byKey.array.sort;

        alias T = Tuple!(long, "lower", long, "upper");
        auto buckets =
            currentBounds
            .zip(currentBounds[1..$].chain(only(this.maxRank)))
            .map!((queueBounds) {
                auto queueMin = queueBounds[0];
                auto queueMax = queueBounds[1];
                auto queueMid = (queueMin+queueMax)/2;

                return [
                    T(queueMin, queueMid),
                    T(queueMid, queueMax),
                ];
            })
            .joiner
            .enumerate
            .cache;

        foreach(rank; receivedRanks) {
            long bucket;
            T bucketBounds;

            assert(!buckets.empty);
            {
                auto t = buckets.front;
                bucket = t[0];
                bucketBounds = t[1];
            }

            if(rank >= bucketBounds.upper) {
                buckets.popFront;
                continue;
            }
            sampled[bucket] += delta[rank];
        }

        // TODO:
        // We can already implement 
        for(auto placed = 0; placed < sampled.length; ++placed) {
        }

        return bounds;
    }

    mixin UniformBoundsInitialization!(instance => instance.maxRank);
}

final class PerPacket : AdaptationAlgorithm, QueueBoundsInitialization {
private:
    CostFunction costOfInversion;
    long maxRank;

    enum Action {
        None = 0b000,

        DownshiftPre = 0b100,
        DownshiftSucc = 0b101,
        UpshiftPre = 0b110,
        UpshiftSucc = 0b111,
    }

    static auto isUp(Action a) pure {
        return a & 0b010;
    }

    static auto isDown(Action a) pure {
        return !isUp(a);
    }

    static auto isSucc(Action a) pure {
        return a & 0b001;
    }

    static auto isPre(Action a) pure {
        return !isSucc(a);
    }

public:
    this(string costfn, long maxRank) pure {
        this.maxRank = maxRank;
        modeSwitch: final switch(costfn) {
            import std.traits: getSymbolsByUDA;
            import std.string: format;

            static foreach(cfn; getSymbolsByUDA!(costfns, costfns.Cost)) {
                mixin(q{
                case "%1$s":
                    this.costOfInversion = cast(CostFunction)&%1$s;
                    break modeSwitch;
                }.format(__traits(identifier, cfn)));
            }
        }
    }

    invariant { assert(this.costOfInversion !is null); }

    long[] adapt(const(long[]) currentBounds, const(PacketCounts) byRank, const long receivedRank, in SimState previousState, const ulong time) pure {
        import std.traits: EnumMembers;
        import std.algorithm;
        import std.array;

        // indices into the currently evaluated bounds for each action
        enum Pre      = 0;
        enum Self     = 1;
        enum Succ     = 2;
        enum SuccSucc = 3;

        auto targetQueue = currentBounds.lookup(receivedRank).front;

        Optional!(long)[4][Action] bounds;
        Optional!double estimatedBestCost;
        Action estimatedBest = Action.None;

        static foreach(a; EnumMembers!Action) { bounds.require(a); }

        with(Action) {
            if(targetQueue > 0) {
                bounds[None][Pre] = some(currentBounds[targetQueue - 1]);
            }

            {
                const tail = currentBounds[targetQueue+1..$].length;

                if(tail >= 2) bounds[None][SuccSucc] = some(currentBounds[targetQueue + 2]);
                if(tail >= 1) bounds[None][Succ]     = some(currentBounds[targetQueue + 1]);
            }
            bounds[None][Self] = some(currentBounds[targetQueue]);

            static foreach(a; EnumMembers!Action) static if(a != None) {
                bounds[a][] = bounds[None];
            }

            static foreach(a; EnumMembers!Action) static if(a != None) {{
                static if(isDown(a)) {
                    alias modifyBound = (ref b) => (b.empty || b == 0) ? b : --b;
                } else static if(isUp(a)) {
                    alias modifyBound = (ref b) => (b.empty || b == long.max) ? b : ++b;
                } else static assert(false, a);

                static if(isPre(a)) {
                    modifyBound(bounds[a][Self]);
                } else static if(isSucc(a)) {
                    modifyBound(bounds[a][Succ]);
                } else static assert(false, a);
            }}

            static foreach(a; EnumMembers!Action) {{
                auto actionEstimates = (bounds, byRank) pure @trusted {
                    return
                        [
                            bounds[0..2],
                            bounds[1..3],
                            bounds[2..4],
                        ]
                        .map!(b => costOfInversion(b[0], b[1], byRank))
                        .array;
                }(bounds[a], byRank);

                const estimatedCost =
                    actionEstimates
                    .fold!((a, b) => max(a, b));

                if(estimatedBestCost.empty || estimatedCost < estimatedBestCost.front) {
                    estimatedBest = a;
                    estimatedBestCost = some(estimatedCost);
                }
            }}
        }

        auto newBounds = currentBounds.dup;

        auto change = bounds[estimatedBest];
        auto tail = newBounds[targetQueue+1..$].length;
        if(!change[Pre].empty)      newBounds[targetQueue - 1] = change[Pre].front;
                                    newBounds[targetQueue - 0] = change[Self].front;
        if(!change[Succ].empty)     newBounds[targetQueue + 1] = change[Succ].front;
        if(!change[SuccSucc].empty) newBounds[targetQueue + 2] = change[SuccSucc].front;

        return newBounds;
    }

    mixin UniformBoundsInitialization!(instance => instance.maxRank);
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
    return new Static(spec.split(',').map!strip.map!(to!long).array);
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


@Algorithm("per-packet")
@Usage(
`
This adaptation algorithm may use various cost functions,
and requires the maximum received rank as a parameter.
Instantiation: <name>:perpacket:(exact|upper_estimate),${max_rank}
`)
AdaptationAlgorithm setup_per_packet(string spec) pure {
    import std.conv: to;
    import std.exception: enforce;
    auto pieces = spec.split(',');
    enforce(pieces.length == 2, `invalid arguments`);
    return new PerPacket(pieces.front, pieces.back.to!long);
}

@Algorithm("abb")
@Usage(
`
This adaptation algorithm attempts to uniformly balance incoming packets across all queues,
and requires the maximum received rank
as well as a sample size that determines the number of packets considered during rebalancing as a parameter.
Instantiation: <name>:abb:${max_rank},${sample_size}
`)
AdaptationAlgorithm setup_abb(string spec) pure {
    import std.conv: to;
    import std.exception: enforce;
    auto pieces = spec.split(',');
    enforce(pieces.length == 2, `invalid arguments`);
    return new ApproximateBalancedBuckets(pieces.front.to!long, pieces.back.to!long);
}

@Algorithm("springh-inversion")
@Usage(
`
See IV/C.
Instantiation: <name>:springh-inversion:${max_rank},${sample_size},${alpha},${sensitivity}
`)
AdaptationAlgorithm setup_springh_inversion(string spec) pure {
    import std.conv: to;
    import std.exception: enforce;
    auto pieces = spec.split(',');
    enforce(pieces.length == 4, `invalid arguments`);
    debug {
        import std;
        stderr.writeln("AAAAA ", pieces);
    }
    return new SpringInversionHeuristic(pieces[0].to!long, pieces[1].to!long, pieces[2].to!double, pieces[3].to!double);
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
        long[] current = [0L, 0];
        foreach(i, input; inputs) {
            current = pupd.adapt(current, null, input, SimState(), i);
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
            [0L, 4],
            [0L, 4],
            [0L, 4],
            [0L, 4],
        ];

        auto _static = new Static([0L, 4]);
        long[] current = [0L, 0];
        foreach(i, input; inputs) {
            current = _static.adapt(current, null, input, SimState(), i);
            assert(current == expected[i], format!`%s: %s -> %s`(i, input, current));
        }
    }
}
