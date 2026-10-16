/* reti.c - ret #imm8 loads A with the immediate.  On TT07 A got the low byte
 * of the instruction at the return address instead (item 5). */
#include "harness.h"

/* returns to an adx (A untouched, low byte 0x11) and then returns A */
static unsigned char probe(void) __naked
{
  __asm
    sra
    jal  retimm
    adx  #0x11
    lra
    ret
retimm:
    reti #0x5a
  __endasm;
}

/* predicated off: neither the return nor the load may happen */
static unsigned char probe_skipped(void) __naked
{
  __asm
    sra
    ldi  #0x77
    jal  retimm2
    adx  #0x22
    lra
    ret
retimm2:
    ldc  #0
    if   c
    reti #0x5a
    ldi  #0x99
    ret
  __endasm;
}

void main(void)
{
  CHECK(1, probe() == 0x5a);
  CHECK(2, probe_skipped() == 0x99);
  DONE();
}
