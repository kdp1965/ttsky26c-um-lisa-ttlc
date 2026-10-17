/* swap.c - swap a,n(sp) exchanges A with the byte at sp + n (item 3: TT07
 * used sp + n - 512, which only the 128-byte RAM's wrap-around hid); swap
 * n(ix) and swapi for comparison. */
#include "harness.h"

static unsigned char sp_val, sp_slot;
static unsigned char g;

static void probe_sp(void) __naked
{
  __asm
    ldi  #0x80
    push a                  ; 0(sp) = 0x80 (SP at the pushed byte)
    ldi  #0x11
    swap 0(sp)              ; A <- 0x80, 0(sp) <- 0x11
    sta  _sp_val
    pop  a
    sta  _sp_slot
    ret
  __endasm;
}

static unsigned char probe_ix(void) __naked
{
  __asm
    ldi  #0x22
    sta  _g
    ldx  #_g
    ldi  #0x33
    swap 0(ix)              ; A <- 0x22, g <- 0x33
    ret
  __endasm;
}

static unsigned char probe_i(void) __naked
{
  __asm
    ldi  #0x44
    sta  _g
    ldi  #0x55
    swapi _g                ; A <- 0x44, g <- 0x55
    ret
  __endasm;
}

void main(void)
{
  probe_sp();
  CHECK(1, sp_val == 0x80);
  CHECK(2, sp_slot == 0x11);
  CHECK(3, probe_ix() == 0x22);
  CHECK(4, g == 0x33);
  CHECK(5, probe_i() == 0x44);
  CHECK(6, g == 0x55);
  DONE();
}
