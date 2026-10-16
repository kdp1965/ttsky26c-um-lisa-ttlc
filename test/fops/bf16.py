"""bf16.py - an exact bfloat16 reference: bits <-> Fraction, rounding to
nearest even or toward zero."""
from fractions import Fraction

INF = float('inf')


def to_frac(bits):
    """the value of a bf16 pattern: a Fraction, or 'inf'/'-inf'/'nan'"""
    s = (bits >> 15) & 1
    e = (bits >> 7) & 0xff
    f = bits & 0x7f
    if e == 255:
        return 'nan' if f else ('-inf' if s else 'inf')
    if e == 0:
        v = Fraction(f, 1 << 7) * Fraction(1, 1 << 126)
    else:
        v = (1 + Fraction(f, 1 << 7)) * (Fraction(1 << (e - 127)) if e >= 127 else Fraction(1, 1 << (127 - e)))
    return -v if s else v


def from_frac(x, mode='rne', sign=0):
    """the bf16 pattern nearest x (a Fraction); mode 'rne' or 'rtz'; sign
    is used for a zero result"""
    if x == 0:
        return sign << 15
    s = 1 if x < 0 else 0
    m = -x if s else x
    # 2^e <= m < 2^(e+1)
    e = m.numerator.bit_length() - m.denominator.bit_length()
    if Fraction(2) ** e > m:
        e -= 1
    while m >= Fraction(2) ** (e + 1):
        e += 1
    if e < -126:
        e = -126
    scale = Fraction(2) ** (e - 7)
    q = m / scale                      # 128 <= q < 256 for a normal result
    n = q.numerator // q.denominator
    r = q - n
    if mode == 'rne':
        if r > Fraction(1, 2) or (r == Fraction(1, 2) and (n & 1)):
            n += 1
    if n == 256:
        e += 1
        n = 128
    if e > 127:
        return (s << 15) | 0x7f80
    if n < 128:                        # subnormal
        return (s << 15) | n
    return (s << 15) | ((e + 127) << 7) | (n - 128)


def add(a_bits, b_bits, mode='rne'):
    a, b = to_frac(a_bits), to_frac(b_bits)
    if a == 'nan' or b == 'nan':
        return 'nan'
    if isinstance(a, str) or isinstance(b, str):
        if isinstance(a, str) and isinstance(b, str) and a != b:
            return 'nan'
        return a if isinstance(a, str) else b
    x = a + b
    if x == 0:
        # exact zero: +0 unless both are -0
        sign = 1 if ((a_bits >> 15) & (b_bits >> 15)) else 0
        return from_frac(x, mode, sign)
    return from_frac(x, mode)


def mul(a_bits, b_bits, mode='rtz'):
    """fmul truncates, and flushes subnormal operands and results to zero"""
    a, b = to_frac(a_bits), to_frac(b_bits)
    s = ((a_bits ^ b_bits) >> 15) & 1
    if a == 'nan' or b == 'nan':
        return 'nan'
    if isinstance(a, str) or isinstance(b, str):
        if (isinstance(a, str) and b == 0) or (isinstance(b, str) and a == 0):
            return 'nan'
        return '-inf' if s else 'inf'
    if ((a_bits >> 7) & 0xff) == 0 or ((b_bits >> 7) & 0xff) == 0:
        return s << 15
    p = a * b
    if abs(p) < Fraction(1, 1 << 126):
        return s << 15
    return from_frac(p, mode, s)


def fmt(v):
    return v if isinstance(v, str) else '0x%04x' % v
