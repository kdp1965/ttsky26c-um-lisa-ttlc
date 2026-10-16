# test_fops.py - fadd (item 4) and fmul against the exact bf16 reference.
import random
import cocotb
from cocotb.triggers import ClockCycles

import bf16

CASES = [
    (0x3fa0, 0x3fa0),   # 1.25 + 1.25 = 2.5 (TT07: 2.25)
    (0x3fe0, 0x3fe0),   # 1.75 + 1.75 = 3.5 (TT07: 2.75)
    (0x3f80, 0x3f80),   # 1 + 1
    (0x3f80, 0xbf80),   # 1 - 1 = +0
    (0x3f80, 0x3c00),   # 1 + 2^-7: a rounding tie, to even -> 1
    (0x3f81, 0x3c00),   # (1 + 2^-7) + 2^-7
    (0x3f80, 0x3b80),   # 1 + 2^-8 (half an ulp): tie -> 1
    (0x3f80, 0x3b81),   # 1 + 2^-8 * (1 + 2^-7): above the tie -> 1 + 2^-7
    (0x3fff, 0x3c00),   # 1.9921875 + 2^-7: carry into the exponent
    (0x3fff, 0x3b80),   # 1.9921875 + 2^-8: rounds up to 2
    (0x4000, 0xbfff),   # 2 - 1.9921875 = 2^-7
    (0x7f7f, 0x7f7f),   # max + max = inf
    (0x7f80, 0xff80),   # inf - inf = nan
    (0x0080, 0x0080),   # smallest normal + itself
    (0x0040, 0x0040),   # subnormal + subnormal = smallest normal
    (0x3f80, 0x0001),   # 1 + the smallest subnormal
    (0x1e00, 0x9e00),   # x - x = 0
    (0x1e00, 0x1e00),
    (0xc1a0, 0x4120),   # -20 + 10
    (0x4120, 0xc1a0),
]


def rnd_bf16(normal_only=True):
    s = random.getrandbits(1)
    e = random.randint(1, 254) if normal_only else random.randint(0, 254)
    f = random.getrandbits(7)
    return (s << 15) | (e << 7) | f


async def settle(dut, a, b, rtz=0):
    dut.a.value = a
    dut.b.value = b
    dut.round_to_zero.value = rtz
    await ClockCycles(dut.clk, 2)       # the operand flags are registered


async def start(dut):
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


def check(dut, name, a, b, got, exp, errors, limit=12):
    if isinstance(exp, str):
        ok = exp == 'nan' and (got & 0x7fff) > 0x7f80 or \
             exp == 'inf' and got == 0x7f80 or exp == '-inf' and got == 0xff80
    else:
        ok = got == exp
    if not ok:
        if len(errors) < limit:
            dut._log.error('%s 0x%04x, 0x%04x: got 0x%04x, expected %s' % (name, a, b, got, bf16.fmt(exp)))
        errors.append((a, b, got, exp))


@cocotb.test()
async def test_fadd(dut):
    """fadd, round to nearest even: directed cases and random normals"""
    await start(dut)
    errors = []
    for a, b in CASES:
        await settle(dut, a, b)
        check(dut, 'fadd', a, b, int(dut.sum.value), bf16.add(a, b), errors)
    random.seed(1)
    for _ in range(3000):
        a, b = rnd_bf16(), rnd_bf16()
        if random.random() < 0.5:                 # close exponents: the interesting ones
            b = (b & 0x80ff) | ((((a >> 7) & 0xff) + random.randint(-9, 9)) % 254 + 1 << 7)
        await settle(dut, a, b)
        check(dut, 'fadd', a, b, int(dut.sum.value), bf16.add(a, b), errors)
    assert not errors, '%d of %d additions wrong' % (len(errors), len(CASES) + 3000)


@cocotb.test()
async def test_fadd_rtz(dut):
    """fadd with amode[2]: toward zero"""
    await start(dut)
    errors = []
    random.seed(2)
    for _ in range(1500):
        a, b = rnd_bf16(), rnd_bf16()
        b = (b & 0x80ff) | ((((a >> 7) & 0xff) + random.randint(-9, 9)) % 254 + 1 << 7)
        await settle(dut, a, b, rtz=1)
        check(dut, 'fadd rtz', a, b, int(dut.sum.value), bf16.add(a, b, 'rtz'), errors)
    assert not errors, '%d of 1500 wrong' % len(errors)


@cocotb.test()
async def test_fadd_subnormal(dut):
    """fadd with subnormal operands and results"""
    await start(dut)
    errors = []
    random.seed(3)
    for _ in range(600):
        a = rnd_bf16(normal_only=False) & 0x80ff | (random.randint(0, 3) << 7)
        b = rnd_bf16(normal_only=False) & 0x80ff | (random.randint(0, 3) << 7)
        await settle(dut, a, b)
        check(dut, 'fadd subnormal', a, b, int(dut.sum.value), bf16.add(a, b), errors)
    assert not errors, '%d of 600 wrong' % len(errors)


@cocotb.test()
async def test_fmul(dut):
    """fmul truncates (as documented): the product rounded toward zero"""
    await start(dut)
    errors = []
    random.seed(4)
    for _ in range(2000):
        a, b = rnd_bf16(), rnd_bf16()
        await settle(dut, a, b)
        check(dut, 'fmul', a, b, int(dut.product.value), bf16.mul(a, b, 'rtz'), errors)
    assert not errors, '%d of 2000 products wrong' % len(errors)
