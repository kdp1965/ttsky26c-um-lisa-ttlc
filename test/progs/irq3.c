/*
 * test_irq.c - a timer 1 interrupt on the TT07 peripherals (tt07.h).
 *
 * The handler counts ticks and clears the request; main runs a known
 * computation while the interrupts land anywhere in it, then checks the
 * result and that the ticks stop after the source is masked.  Exercises
 * __interrupt, the vector table, the handler's save/restore of A, IX,
 * RA and the flags (hardware shadows) and __critical.
 */
#include "harness.h"
/* irq3.c: test_irq.c with the values of check 3 printed */
#include <tt07.h>

volatile unsigned int ticks;    /* 16 bits: check 3 holds past 255 ticks */
volatile unsigned int isr_sum;

void timer1_isr(void) __interrupt(LISA_INT_TIMER1)
{
  unsigned int t = isr_sum;
  ticks++;
  t += 0x0101;                  /* some carry arithmetic of its own */
  isr_sum = t;
  INT_STATUS = INT_TIMER1;      /* acknowledge */
}

static unsigned long work(unsigned int n)
{
  unsigned long acc = 1;
  unsigned int i;
  signed char s = -3;
  for (i = 0; i < n; i++)
    {
      acc = acc * 3 + i;        /* multi-byte carries */
      acc ^= (unsigned long)(s * (signed char)(i & 7)) << 8;   /* signed 8x8 product */
      acc -= (unsigned int)(i >> 3);
      s = (signed char)(s - 1);
    }
  return acc;
}

int main(void)
{
  unsigned long expect, got;
  unsigned int t0, t1;

  expect = work(300);           /* without interrupts */

  TIMER1_CTRL = 0;
  TIMER1_PREDIV_LO = 0x1f;      /* 50 MHz / 32: fast enough to interrupt the work many times */
  TIMER1_PREDIV_HI = 0x00;
  TIMER1_DIV_LO = 100;          /* a tick every 3200 clocks: lisa_sim runs work(300) in ~135K cycles
                                   (40 ticks); the RTL testbenches take 3-25x longer and the handler
                                   itself ~50 instructions, so 640 clocks (DIV 20) overflowed a byte
                                   counter on the core bench and never left the handler on the chip */
  TIMER1_DIV_HI = 0;
  INT_STATUS = 0xff;
  ticks = 0;
  isr_sum = 0;
  INT_ENABLE = INT_TIMER1;
  TIMER1_CTRL = TIMER_CTRL_ENABLE;
  lisa_ei();

  got = work(300);              /* with interrupts landing anywhere in it */
  CHECK(1, got == expect);
  CHECK(2, ticks > 2);
  __critical {                  /* a tick between the two reads would split them */
    t0 = ticks;
    got = isr_sum;
  }
  puts("ticks "); puthex(t0); puts(" isr_sum "); puthex(got); putc('\n');
  CHECK(3, got == (unsigned int)(t0 * 0x0101u));

  __critical {                  /* no tick can land in here */
    t0 = ticks;
    work(20);
    t1 = ticks;
  }
  CHECK(4, t0 == t1);

  INT_ENABLE = 0;               /* mask the source: the counting stops */
  t0 = ticks;
  work(50);
  t1 = ticks;
  CHECK(5, t0 == t1);

  lisa_di();
  TIMER1_CTRL = 0;
  DONE();
  return 0;
}
