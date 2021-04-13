module costfns;

import std.algorithm;
import std.range;
import std.array;
import std.conv;

import optional;

import types;

public:

alias CostFunction = double function(Optional!ulong lower, Optional!ulong upper, const PacketCounts byRank) pure;
enum Cost;

@Cost
auto upper_estimate(Optional!ulong lower, Optional!ulong upper, const PacketCounts byRank) @safe pure {
    if(lower.empty || upper.empty) return -double.infinity;
    const total = byRank.byValue.sum;
    const P_i =
        iota(lower.front, upper.front)
        .map!(p => p in byRank ? byRank[p] : 0)
        .sum.to!double / total;

    return P_i * (upper.front - lower.front - 1) / 2;
}

@Cost
auto exact(Optional!ulong lower, Optional!ulong upper, const PacketCounts byRank) @safe pure {
    if(lower.empty || upper.empty) return -double.infinity;

    const total = byRank.byValue.sum;
    const queueCounts =
        iota(lower.front, upper.front)
        .map!(p => p in byRank ? byRank[p] : 0)
        .array;

    const P_i = queueCounts.sum.to!double / total;

    const probabilities =
        queueCounts
        .map!(c => c.to!double / total)
        .array;

    return
        iota(lower.front, upper.front)
        .map!((a) =>
            // avoid division by zero if no packets are likely to arrive
            P_i == 0 ? 0 :
                iota(a + 1, upper.front)
                .map!(b => probabilities[a - lower.front] * probabilities[b - lower.front] * (b - a))
                .sum / P_i
        )
        .sum;
}
