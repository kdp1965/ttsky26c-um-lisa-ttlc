/* cache14.c - the data cache maps the whole 32K: X and X ^ 0x4000 are
 * different bytes after their lines have been written back (item 1: TT07
 * took bit 14 of the line's RAM address from address bit 5).  Needs the
 * cache on (CACHE=1).  Lines: index = {addr[14], addr[5:4]}, 16 bytes;
 * 0x0100 and 0x4100 sit in lines 0 and 4, 0x0140 / 0x4140 evict them. */
#include "harness.h"

/* the frames as sdcc --rev2 lays them out: SP at the top byte, a at 0(sp) */
static void poke(unsigned int a, unsigned char v) __naked
{
  __asm
    ldxx 0(sp)
    ldax 2(sp)
    stax 0(ix)
    ret
  __endasm;
}

static unsigned char peek(unsigned int a) __naked
{
  __asm
    ldxx 0(sp)
    ldax 0(ix)
    ret
  __endasm;
}

void main(void)
{
  poke(0x0100, 0x55);
  poke(0x4100, 0xaa);
  poke(0x0140, 0x01);          /* evict both lines: the dirty data goes to RAM */
  poke(0x4140, 0x02);
  CHECK(1, peek(0x0100) == 0x55);
  CHECK(2, peek(0x4100) == 0xaa);
  poke(0x0108, 0x33);
  poke(0x4108, 0x44);
  poke(0x0148, 0x03);
  poke(0x4148, 0x04);
  CHECK(3, peek(0x4108) == 0x44);
  CHECK(4, peek(0x0108) == 0x33);
  CHECK(5, peek(0x0140) == 0x01);
  CHECK(6, peek(0x4140) == 0x02);
  DONE();
}
