#!/usr/bin/env python3
"""ihx2hex.py in.ihx out.hex - Intel HEX (sdcc -mlisa: byte addresses, 2 per
word, little endian) to the $readmemh byte format the spiflash model loads
(@byteaddr then hex bytes).  Also accepts one 4-digit opcode per line
(lisa_ld) and the @addr format itself."""
import sys

def parse(path):
    mem = {}
    base = 0
    lines = open(path).read().splitlines()
    if not lines:
        return mem
    if lines[0].startswith(':'):
        for ln in lines:
            ln = ln.strip()
            if not ln.startswith(':'):
                continue
            b = bytes.fromhex(ln[1:])
            n, addr, typ = b[0], (b[1] << 8) | b[2], b[3]
            data = b[4:4 + n]
            if typ == 0:
                for i, v in enumerate(data):
                    mem[base + addr + i] = v
            elif typ == 1:
                break
            elif typ == 2:
                base = ((data[0] << 8) | data[1]) << 4
            elif typ == 4:
                base = ((data[0] << 8) | data[1]) << 16
    elif lines[0].startswith('@'):
        addr = 0
        for ln in lines:
            for tok in ln.split():
                if tok.startswith('@'):
                    addr = int(tok[1:], 16)
                else:
                    mem[addr] = int(tok, 16)
                    addr += 1
    else:                                   # one opcode per line, word addresses
        pc = 0
        for ln in lines:
            ln = ln.strip()
            if not ln or ln.startswith(('#', ';', '//')):
                continue
            w = int(ln.split()[0], 16)
            mem[2 * pc] = w & 0xff
            mem[2 * pc + 1] = w >> 8
            pc += 1
    return mem

def main():
    mem = parse(sys.argv[1])
    out = open(sys.argv[2], 'w')
    last = None
    line = []
    for a in sorted(mem):
        if a != last:
            if line:
                out.write(' '.join(line) + '\n')
                line = []
            out.write('@%X\n' % a)
        line.append('%02X' % mem[a])
        if len(line) == 32:
            out.write(' '.join(line) + '\n')
            line = []
        last = a + 1
    if line:
        out.write(' '.join(line) + '\n')
    out.close()
    print('%s: %d bytes, top 0x%X' % (sys.argv[2], len(mem), max(mem) if mem else 0))

if __name__ == '__main__':
    main()
