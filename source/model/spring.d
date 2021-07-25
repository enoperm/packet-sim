module model.spring;

import std.range;
import std.algorithm;
import std.random;

import optional;

public import model.common;

public:
@safe:

final class SpringInversionHeuristic : AdaptationAlgorithm, QueueBoundsInitialization {
private:
    long maxRank;
    long sampleSize;
    double alpha;
    double sensitivity;

    long[] previousInversions;
    double[] previousDelta;

public:
    this(long maxRank, long sampleSize, double alpha, double sensitivity) pure {
        this.maxRank = maxRank;
        this.sampleSize = sampleSize;
        this.alpha = alpha;
        this.sensitivity = sensitivity;
    }

    double[] adapt(
        const(double[]) currentBounds,
        const(PacketCounts) byRank,
        const long receivedRank,
        const Optional!long targetQueue,
        in SimState previousState,
        const ulong time
    ) {
        import std.conv: to;
        import std.algorithm;
        import std.array;
        import std.typecons: Tuple, tuple;


        auto bounds = currentBounds.dup;

        if(time % sampleSize) return bounds;
        scope(exit)
            this.previousInversions =
                previousState
                .inversions
                .dup;

        if(previousInversions.empty)
            this.previousInversions =
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

        auto delta =
            previousState
            .inversions
            .zip(this.previousInversions)
            .map!(tup => tup[0] - tup[1])
            .map!(to!double)
            .zip(this.previousDelta)
            // (1 - \alpha) * k_{t}(i-1) + \alpha * k_{t}(i)
            .map!(tup => (1 - this.alpha) * tup[1] + tup[0])
            .array;

        scope(exit) this.previousDelta = delta;

        auto forces =
            delta.front.only
            .chain(delta)
            .chain(delta.back.only);

        const scalingFactor =
            (this.sensitivity * this.maxRank) /
            (bounds.length.to!double*this.sampleSize);

        auto delta_f =
            forces
            .zip(forces.dropOne)
            .map!(tup => tup[1] - tup[0]) // S_{i+1}(r) - S_{i}(l)
            .map!(delta_f => delta_f * scalingFactor)
            .array
        ;

        // do note that the lowest queue bound is always zero,
        bounds[1..$] =
            bounds[1..$]
            .zip(delta_f)
            .map!(tup => tup[0] + tup[1])
            .map!(b => min(b, this.maxRank).max(1.0))
            .map!(to!double)
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

@Algorithm(`springh-inversion`)
@Usage(
`
See IV/C.
Instantiation: <name>:springh-inversion:${max_rank},${sample_size},${alpha},${sensitivity}
`)
AdaptationAlgorithm setup_spring(string spec) pure {
    import std.conv: to;
    import std.exception: enforce;
    auto pieces = spec.split(',');
    enforce(pieces.length == 4, `invalid arguments`);
    auto maxRank = pieces[0].to!long;
    auto sampleSize = pieces[1].to!long;
    auto alpha = pieces[2].to!double;
    auto sensitivity = pieces[3].to!double;
    return new SpringInversionHeuristic(maxRank, sampleSize, alpha, sensitivity);
}
