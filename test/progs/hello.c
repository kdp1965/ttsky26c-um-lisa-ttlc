/* hello.c - the bring-up image of the testbenches: a banner at reset, then
 * "ready" and an echo of whatever arrives on the UART. */
#include "harness.h"

void main(void)
{
  puts("\nLISA rev 2: hello from sdcc -mlisa\n");
  puts("ready\n");
  for (;;) {
    while (!(UART_STATUS & 1))
      ;
    putc(UART_TX);
  }
}
