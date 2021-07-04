module fixpoint;

import std.conv: to;
import std.meta: AliasSeq;
import std.traits: isInstanceOf, TemplateArgsOf;

// infinitely big fixpoint binary number,
// with a compile-time set number of bits representing the rational part.
struct Q(ulong N) {
    import std.bigint: BigInt;
    import std.traits: isIntegral, isFloatingPoint;

    private BigInt storage;
    enum equalityDelta = 0.0001;

    this(T)(T val) if(isFloatingPoint!T) {
        import std.conv: to;
        this.storage = BigInt(to!long(val * 2^^N));
    }

    this(T)(T val) if(isIntegral!T) {
        import std.conv: to;
        this.storage = BigInt(val) << N;
    }

    auto opBinary(string op)(const ref Q other) {
        enum K = BigInt(1) << (N - 1);

        auto storage = this.storage;
        static if(op != "/") {
            mixin(`storage = storage ` ~ op ~ ` other.storage;`);
        }

        static if(op == "*") {
            storage += K;
            storage = storage >> N;
        }

        static if(op == "/") {
            auto sigLhs = storage & (BigInt(1) << N);
            auto sigRhs = other.storage & (BigInt(1) << N);

            storage <<= N;

            if(!!sigLhs == !!sigRhs) {
                storage += (other.storage >> 1);
            } else {
                storage -= (other.storage >> 1);
            }
            storage /= other.storage;
        }

        Q result;
        result.storage = storage;

        return result;
    }

    auto opBinary(string op, T)(const ref T other) if(!isInstanceOf!(Q, T)) {
        import std.conv: to;
        auto asQ = Q(T);
        mixin(`return this ` ~ op ~ ` asQ;`);
    }

    public auto asInteger() {
        return this.storage >> N;
    }

    public auto approxEqual(double delta = equalityDelta, T)(T other) if(!isInstanceOf!(Q, T)) {
        import std.conv: to;
        auto asQ = Q(other);
        return this.approxEqual!(delta)(asQ);
    }

    public auto approxEqual(double delta = equalityDelta)(Q other) {
        import std.math: abs;
        enum delta = Q(delta);
        return abs(this.storage - other.storage) <= delta.storage;
    }
}

alias Q16 = Q!16;
alias Q32 = Q!32;

version(unittest):

mixin template Testcases(alias T) if(isInstanceOf!(Q, T)) {
    @(`Q` ~ TemplateArgsOf!T[0].to!string ~ `: addition and subtraction`)
    unittest {
        import std.math: abs;

        T a = 0.42;
        T b = 0.32;

        T sum = a + b;
        T diffPos = a - b;
        T diffNeg = b - a;

        // result as expected
        // there is some error as the resolution of
        // the floating point representation differs
        // from that of the fixed point one,
        // so this assertion compares the fixed point representations,
        // allowing a very slight delta in the rational part.
        // this testcase also demonstrates how to use a custom delta value.
        enum delta = 0.001;
        assert(sum.approxEqual!delta(0.74));
        assert(diffPos.approxEqual!delta(+0.10));
        assert(diffNeg.approxEqual!delta(-0.10));

        // does not modify the inputs
        assert(a == T(0.42));
        assert(b == T(0.32));
    }

    @(`Q` ~ TemplateArgsOf!T[0].to!string ~ `: multiplication and division`)
    unittest {
        T a = T(0.2);
        T b = T(0.5);

        T prod = a * b;
        T quotAB = a / b;
        T quotBA = b / a;

        // some asserts might also pass
        // if a bug causes all internal values
        // to be zero
        assert(quotAB.storage != 0);
        assert(quotBA.storage != 0);
        assert(prod.storage != 0);

        // result as expected
        assert(prod.approxEqual(0.10));
        assert(quotAB.approxEqual(T(0.2/0.5)));
        assert(quotBA.approxEqual(T(0.5/0.2)));

        // does not modify the inputs
        assert(a == T(0.2));
        assert(b == T(0.5));
    }
}

static foreach(T; AliasSeq!(Q16, Q32)) {
    mixin Testcases!T;
}
