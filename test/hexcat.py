#!/usr/bin/env python3
"""hexcat.py out.hex base1 file1 [base2 file2 ...] - several @addr byte images
into one, each placed at its base (a byte address, hex)."""
import sys

def load(path):
    mem = {}
    addr = 0
    for ln in open(path):
        for tok in ln.split():
            if tok.startswith('@'):
                addr = int(tok[1:], 16)
            else:
                mem[addr] = int(tok, 16)
                addr += 1
    return mem

out = sys.argv[1]
mem = {}
args = sys.argv[2:]
for base, path in zip(args[::2], args[1::2]):
    b = int(base, 16)
    for a, v in load(path).items():
        mem[b + a] = v
with open(out, 'w') as f:
    last = None
    line = []
    for a in sorted(mem):
        if a != last:
            if line:
                f.write(' '.join(line) + '\n')
                line = []
            f.write('@%X\n' % a)
        line.append('%02X' % mem[a])
        if len(line) == 32:
            f.write(' '.join(line) + '\n')
            line = []
        last = a + 1
    if line:
        f.write(' '.join(line) + '\n')
print('%s: %d bytes' % (out, len(mem)))
