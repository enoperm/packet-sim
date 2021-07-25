module model.abb;

import std.range;
import std.algorithm;
import std.random;

import optional;

public import model.common;

public:
@safe:

final class ApproximateBalancedBuckets : AdaptationAlgorithm, QueueBoundsInitialization {
private:
    long maxRank;
    long sampleSize;
    PacketCounts previousRanks;

public:
    this(long maxRank, long sampleSize) pure {
        this.maxRank = maxRank;
        this.sampleSize = sampleSize;
    }

    double[] adapt(
        const(double[]) currentBounds,
        const(PacketCounts) byRank,
        const long receivedRank,
        const Optional!long targetQueue,
        in SimState previousState,
        const ulong time
    ) pure {
        import std.conv: to;
        import std.algorithm;
        import std.array;
        import std.typecons: Tuple, tuple;

        auto bounds = currentBounds.dup;
        if(time % sampleSize) return bounds;
        scope(exit)
            this.previousRanks =
                byRank
                .byKey
                .map!(k => tuple(k, byRank[k].to!long))
                .assocArray;

        PacketCounts delta;
        foreach(rank; byRank.byKey) {
            const count = byRank[rank];
            delta[rank] = count - this.previousRanks.get(rank, 0);
        }
        // The actual implementation would maintain its own state,
        // but this simulator already keeps track of all the information we need,
        // so let's convert from that instead.
        auto sampled = new long[currentBounds.length*2];
        auto receivedRanks = delta.byKey.array.sort;

        alias T = Tuple!(real, "lower", real, "upper");
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
        for(auto placed = 0; placed < sampled.length; ++placed) {}

        return bounds;
    }

    mixin UniformBoundsInitialization!(instance => instance.maxRank);
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
