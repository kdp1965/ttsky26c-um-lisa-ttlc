/* alu2.c - the ALU flags in the corner cases TT07 got wrong (item 7): adc
 * with the carry folded into an 8-bit operand, sub / cmp of a zero operand
 * reporting a borrow, cpi without the signed inversion.  The expected
 * values come from the compiler's own 16-bit arithmetic, which is correct
 * on both chips (it avoids the broken forms). */
#include "harness.h"

/* __sdcccall(0) frames with the compiler's sra, SP at the top byte (the
   second chip's convention, sdcc --rev2): saved RA 0,1(sp), return slot
   2,3(sp), a 4(sp), b 5(sp), c 6(sp).  Results come back as {flag << 8 | A}. */
#define ADC_K(name, k)                                                     \
static unsigned int name(unsigned char a, unsigned char c) __sdcccall(0)  \
{ __asm__("ldax 5(sp)\n\tshr\n\tldax 4(sp)\n\tadc #" k                   \
          "\n\tstax 2(sp)\n\tldac c\n\tstax 3(sp)"); }
ADC_K(adc_00, "0x00")
ADC_K(adc_01, "0x01")
ADC_K(adc_7f, "0x7f")
ADC_K(adc_80, "0x80")
ADC_K(adc_fe, "0xfe")
ADC_K(adc_ff, "0xff")

#define MEM_OP(name, op)                                                   \
static unsigned int name(unsigned char a, unsigned char b, unsigned char c) __sdcccall(0) \
{ __asm__("ldax 6(sp)\n\tshr\n\tldax 4(sp)\n\t" op " 5(sp)"               \
          "\n\tstax 2(sp)\n\tldac c\n\tstax 3(sp)"); }
MEM_OP(add_m, "add")
MEM_OP(sub_m, "sub")
MEM_OP(cmp_m, "cmp")

/* cmp: Z in bit 8 */
static unsigned int cmp_z(unsigned char a, unsigned char b) __sdcccall(0)
{ __asm__("ldax 4(sp)\n\tcmp 5(sp)\n\tstax 2(sp)\n\tldac z\n\tstax 3(sp)"); }
/* cmp then if slt: 1 if a < b as signed bytes */
static unsigned int cmp_slt(unsigned char a, unsigned char b) __sdcccall(0)
{ __asm__("ldax 4(sp)\n\tcmp 5(sp)\n\tifte slt\n\tldi.p #1\n\tldi.p #0\n\tstax 2(sp)\n\tldi #0\n\tstax 3(sp)"); }
static unsigned int cmp_sgt(unsigned char a, unsigned char b) __sdcccall(0)
{ __asm__("ldax 4(sp)\n\tcmp 5(sp)\n\tifte sgt\n\tldi.p #1\n\tldi.p #0\n\tstax 2(sp)\n\tldi #0\n\tstax 3(sp)"); }

#define CPI_K(name, k)                                                     \
static unsigned int name(unsigned char a) __sdcccall(0)                   \
{ __asm__("ldax 4(sp)\n\tcpi #" k "\n\tldac c\n\tstax 3(sp)\n\tldax 4(sp)\n\tcpi #" k \
          "\n\tifte slt\n\tldi.p #1\n\tldi.p #0\n\tstax 2(sp)"); }
CPI_K(cpi_00, "0x00")
CPI_K(cpi_01, "0x01")
CPI_K(cpi_7f, "0x7f")
CPI_K(cpi_80, "0x80")
CPI_K(cpi_ff, "0xff")

static unsigned char bad;
static void mismatch(const char *what, unsigned int a, unsigned int b, unsigned int got, unsigned int exp)
{
  if (bad < 12) {
    puts("mismatch "); puts(what); putc(' ');
    puthex(a); putc(' '); puthex(b); puts(" got "); puthex(got); puts(" exp "); puthex(exp); putc('\n');
  }
  bad++;
}

static const unsigned char bset[] = { 0x00, 0x01, 0x02, 0x7f, 0x80, 0x81, 0xfe, 0xff };

void main(void)
{
  unsigned int a, i, c, got, exp;
  unsigned char b;

  /* adc #k over every A and both carries */
  for (a = 0; a < 256; a++)
    for (c = 0; c < 2; c++) {
      got = adc_ff(a, c); exp = a + 0xff + c; if (got != exp) mismatch("adc ff", a, c, got, exp);
      got = adc_00(a, c); exp = a + 0x00 + c; if (got != exp) mismatch("adc 00", a, c, got, exp);
      if ((a & 15) == 7) {
        got = adc_01(a, c); exp = a + 0x01 + c; if (got != exp) mismatch("adc 01", a, c, got, exp);
        got = adc_7f(a, c); exp = a + 0x7f + c; if (got != exp) mismatch("adc 7f", a, c, got, exp);
        got = adc_80(a, c); exp = a + 0x80 + c; if (got != exp) mismatch("adc 80", a, c, got, exp);
        got = adc_fe(a, c); exp = a + 0xfe + c; if (got != exp) mismatch("adc fe", a, c, got, exp);
      }
    }
  CHECK(1, bad == 0);
  bad = 0;

  /* add (no carry in, by design), sub, cmp against a set of operands */
  for (a = 0; a < 256; a += 3)
    for (i = 0; i < sizeof bset; i++) {
      b = bset[i];
      for (c = 0; c < 2; c++) {
        got = add_m(a, b, c); exp = a + b; if (got != exp) mismatch("add", a, b, got, exp);
        got = sub_m(a, b, c); exp = ((a - b - c) & 0xff) | ((a < (unsigned int)b + c) ? 0x100 : 0);
        if (got != exp) mismatch("sub", a, b | (c << 8), got, exp);
        got = cmp_m(a, b, c); exp = a | ((a < b) ? 0x100 : 0); if (got != exp) mismatch("cmp", a, b, got, exp);
      }
      got = cmp_z(a, b); exp = a | ((a == b) ? 0x100 : 0); if (got != exp) mismatch("cmp z", a, b, got, exp);
      got = cmp_slt(a, b); exp = ((signed char)a < (signed char)b) ? 1 : 0; if (got != exp) mismatch("cmp slt", a, b, got, exp);
      got = cmp_sgt(a, b); exp = ((signed char)a > (signed char)b) ? 1 : 0; if (got != exp) mismatch("cmp sgt", a, b, got, exp);
    }
  CHECK(2, bad == 0);
  bad = 0;

  /* cpi #k: C = unsigned borrow, if slt = signed */
  for (a = 0; a < 256; a++) {
    got = cpi_00(a); exp = (((signed char)a < (signed char)0x00) ? 1 : 0) | ((a < 0x00) ? 0x100 : 0); if (got != exp) mismatch("cpi 00", a, 0, got, exp);
    got = cpi_01(a); exp = (((signed char)a < (signed char)0x01) ? 1 : 0) | ((a < 0x01) ? 0x100 : 0); if (got != exp) mismatch("cpi 01", a, 0, got, exp);
    got = cpi_7f(a); exp = (((signed char)a < (signed char)0x7f) ? 1 : 0) | ((a < 0x7f) ? 0x100 : 0); if (got != exp) mismatch("cpi 7f", a, 0, got, exp);
    got = cpi_80(a); exp = (((signed char)a < (signed char)0x80) ? 1 : 0) | ((a < 0x80) ? 0x100 : 0); if (got != exp) mismatch("cpi 80", a, 0, got, exp);
    got = cpi_ff(a); exp = (((signed char)a < (signed char)0xff) ? 1 : 0) | ((a < 0xff) ? 0x100 : 0); if (got != exp) mismatch("cpi ff", a, 0, got, exp);
  }
  CHECK(3, bad == 0);
  DONE();
}
