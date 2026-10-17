/* div16.c - the divider's 16-bit result (item 8): after div / rem the
 * whole result is in RA, bit 15 in ra_cond, so `xchg ra; txau` reads the
 * high byte without a mask; nothing is written to memory.  On TT07 the
 * high byte's bit 7 (ra_cond) was always set, the one-word `div 1` wrote
 * A to SP + 0x101 and `div 0, 1(sp)` to address 1. */
#include "harness.h"

volatile unsigned char canary0, canary1;

/* __sdcccall(0) with the compiler's sra, SP at the top byte (sdcc --rev2):
   saved RA 0,1(sp), the return slot 2,3(sp), n at 4,5(sp), d at 6,7(sp);
   push a puts the byte at 0(sp) */
#define RAWDIV(name, op, form, pops)                                 \
static unsigned int name(unsigned int n, unsigned int d) __sdcccall(0) \
{                                                                      \
  __asm__("ldax 5(sp)\n\tpush a\n\tldax 5(sp)\n\tlddiv 0(sp)\n\tads #1\n\t" \
          "ldax 7(sp)\n\tpush a\n\tpush a\n\tldax 8(sp)\n\t"           \
          op " " form "\n\tads #" pops "\n\t"                          \
          "xchg ra\n\ttxa\n\tstax 2(sp)\n\ttxau\n\tstax 3(sp)");       \
}

RAWDIV(raw_div, "div", "0, 1(sp)", "2")     /* 16 / 16 */
RAWDIV(raw_rem, "rem", "0, 1(sp)", "2")
RAWDIV(raw_div1, "div", "0, 0(sp)", "2")    /* the other offset word (TT07 wrote to address 1 with 1(sp)) */
RAWDIV(raw_div8, "div", "1", "2")           /* 16 / A */

void main(void)
{
  canary0 = 0x5a;
  canary1 = 0xa5;
  CHECK(1, raw_div(60000, 3) == 20000);
  CHECK(2, raw_div(0xffff, 2) == 0x7fff);
  CHECK(3, raw_div(0xffff, 1) == 0xffff);
  CHECK(4, raw_div(0x8000, 1) == 0x8000);
  CHECK(5, raw_div(0xc350, 0x0064) == 500);
  CHECK(6, raw_rem(0x8001, 0x8002) == 0x8001);
  CHECK(7, raw_rem(60001, 7) == 60001 % 7);
  CHECK(8, raw_div1(60000, 3) == 20000);
  CHECK(9, raw_div8(50000, 7) == 50000 / 7);
  CHECK(10, raw_div8(0xffff, 1) == 0xffff);
  CHECK(11, canary0 == 0x5a && canary1 == 0xa5);
  /* the compiler's own sequences */
  {
    volatile unsigned int a = 54321, b = 123;
    volatile unsigned char c = 9;
    CHECK(12, a / b == 441);
    CHECK(13, a % b == 54321 % 123);
    CHECK(14, a / c == 54321 / 9);
    CHECK(15, a % c == 54321 % 9);
    CHECK(16, (signed int)-3000 / (signed int)7 == -428);
  }
  DONE();
}
