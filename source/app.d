import std;
import std.traits;

import optional;

import model;

void main(string[] args) {
    auto configAttempt = configure(args);
    if(configAttempt.empty) return;

    auto config = configAttempt.front;

    PacketCounts countsByRank;
    countsByRank[0] = 0; // force init AA to make sure initial emitstate does not contain nulls

    auto sampleInterval = environment.get("SAMPLE_INTERVAL", "1").to!ulong;

    auto simStates =
        config.algorithms
        .byKey
        .map!(alg => tuple(alg, SimState(config.queueCount)))
        .assocArray;

    auto bounds =
        config.algorithms
        .byKey
        .map!(alg => tuple(alg, 0.to!double.repeat(config.queueCount).array))
        .assocArray
    ;

    // TODO/IMPROVE?: current output contains a lot of redundant information, but it is easy to process
    void emitState(R, S)(R output, ulong t, S selector) {
        import asdf: serializeToJson;
        import std.traits: FieldNameTuple;
        static struct ReportedState {
            ulong time;
            string algorithm;
            double[] bounds;
            static foreach(memName; FieldNameTuple!SimState) {
                mixin(q{
                    %s %s;
                }.format(typeof(mixin(q{SimState.%s}.format(memName))).stringof, memName));
            }
        }
        ReportedState s = {
            time: t,
            algorithm: selector,
            bounds: bounds[selector],
        };
        static foreach(memName; FieldNameTuple!SimState) {
            mixin(q{
                s.%1$s = simStates[selector].%1$s;
            }.format(memName));
        }
        output.put(s.serializeToJson);
        output.put('\n');
    }

    foreach(alg; config.algorithms.byKey) {
        auto impl = config.algorithms[alg];
        if(auto bi = cast(QueueBoundsInitialization)impl) {
            bounds[alg] = bi.initialBounds(config.queueCount);
        }
    }

    {
        auto output = stdout.lockingTextWriter;
        foreach(alg; config.algorithms.byKey) emitState(output, 0, alg);
    }

    auto incoming =
        stdin
        .byLine
        .map!(line => line.strip)
        .filter!(line => !line.empty)
        .filter!(line => line.all!(c => c.isDigit))
        .map!(to!uint);

    foreach(time, packet; incoming.enumerate(1)) {
        countsByRank[packet] += 1;

        foreach(kvp; config.algorithms.byKeyValue) {
            auto name = kvp.key;
            auto alg = kvp.value;
            auto target = bounds[name].lookup(packet);
            bounds[name] = alg.adapt(bounds[name], countsByRank, packet, target, simStates[name], time);
            simStates[name] = simStates[name].receivePacket(bounds[name], packet);
        }

        if(time % sampleInterval == 0) {
            auto output = stdout.lockingTextWriter;
            foreach(alg; config.algorithms.byKey) {
                emitState(output, time, alg);
            }
        }
    }
}

auto printDetailedHelp() @trusted {
    writefln!`%s algorithm%s available`(algorithmsByName.length, algorithmsByName.length == 1 ? " is" : "s are");
    writeln(`Usage for each of the available algorithms:`);
    foreach(name; algorithmsByName.byKey) {
        writeln('-'.repeat(24));
        writefln!"Algorithm: %s\n%s"(name, algorithmsByName[name].usage);
    }
}

auto configure(const(string[]) args) @trusted {
    static struct SimConfig {
        ulong queueCount;
        AdaptationAlgorithm[string] algorithms;
    }

    auto printUsage() @trusted {
        stderr.writefln!`usage: %s (--long-help|queue-count <name:algorithm-spec> [name:algorithm-spec]*`(args[0], );
    }

    if(args.canFind("--long-help")) {
        printUsage();
        printDetailedHelp();
        return no!SimConfig;
    }

    if(args.length < 3) {
        printUsage();
        return no!SimConfig;
    }

    SimConfig c;

    try { c.queueCount = args[1].to!uint; }
    catch(Exception e) {
        stderr.writefln!`failed to interpret %s as a queue count.`(args[1].escapeShellFileName);
        return no!SimConfig;
    }

    const algorithmConfigPattern = `^(?P<name>[\w_\-\s]+):(?P<spec>\S+)$`.regex;
    foreach(arg; args[2..$]) {
        auto result = arg.matchFirst(algorithmConfigPattern);

        auto name = result[`name`];
        auto spec = result[`spec`];


        enforce(name, `must specify algorithm to instantiate`);

        auto alg = configureAlgorithm(spec);
        if(alg.empty) {
            stderr.writefln!`failed to instantiate algorithm from %s`(arg.escapeShellFileName);
            return no!SimConfig;
        }
        c.algorithms[name] = alg.front;
    }

    return some(c);
}

alias AlgorithmConstructor = AdaptationAlgorithm function(string) pure;
struct AlgorithmInfo {
    string name;
    string usage;
    AlgorithmConstructor constructor;
}

AlgorithmInfo[string] algorithmsByName;

static this() {
    AlgorithmInfo[string] a;
    foreach(alg; getSymbolsByUDA!(model, model.Algorithm)) {{
        auto name = getUDAs!(alg, model.Algorithm)[$-1].name;
        auto usage = `no usage information available`;
        if(hasUDA!(alg, model.Usage)) {
            usage = getUDAs!(alg, model.Usage)[$-1].text;
        }

        a[name] = AlgorithmInfo(
            name,
            usage,
            (spec) => alg(spec)
        );
    }}

    algorithmsByName = a;
}

auto configureAlgorithm(string spec) {
    auto pieces = spec.findSplit(":");
    auto algorithmName = pieces[0];
    auto algorithmSettings = pieces[$-1];

    auto instance = no!AdaptationAlgorithm;
    if(auto alg = algorithmName in algorithmsByName) {
        try { instance = some(alg.constructor(algorithmSettings)); }
        catch(Exception e) { stderr.writefln!`while setting up %s, caught %s`(spec.escapeShellFileName, e); }
    } else {
        stderr.writefln!`attempted to instantiate unknown adaptation algorithm %s, available:`(
            algorithmName.escapeShellFileName
        );
        foreach(algName; algorithmsByName.byKey) { stderr.writeln(algName); }
    }
    return instance;
}
