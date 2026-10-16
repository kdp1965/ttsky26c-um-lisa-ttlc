/* dbg.c - a loop for the debugger tests (test_core.py: breakpoints right
 * after stores, single step, RAM reads).  The immediates are unique in the
 * image so the test can find the instructions. */
#include "harness.h"

volatile unsigned char g1, g2;

void main(void)
{
  puts("dbg\n");
  __asm
loop:
    ldi  #0xc1
    sta  _g1
    ldi  #0xc2
    sta  _g2
    push a
    ldi  #0xc3
    pop  a
    adx  #0x15
    br   loop
  __endasm;
}
