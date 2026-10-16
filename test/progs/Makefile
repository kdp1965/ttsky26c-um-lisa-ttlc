# Test programs for the revision-2 RTL (sdcc -mlisa from lisa-tools; the .hex
# images are committed so the testbenches run without the compiler).
#   make            build *.ihx and the *.hex the flash model / tb_core load
SDCC      ?= ../../../lisa-tools/sdcc-lisa/build/bin/sdcc
SDCC_TEST ?= ../../../lisa-tools/sdcc_test
CFLAGS    ?= -mlisa --debug -I$(SDCC_TEST)

PROGS = hello alu2 reti div16 cache14 dbg

all: $(PROGS:%=%.hex)

%.ihx: %.c $(SDCC_TEST)/harness.h
	$(SDCC) $(CFLAGS) -o $@ $<

# the cache test uses the 32K data space: stack at the top, data low
cache14.ihx: CFLAGS += --tt07-cache

%.hex: %.ihx ../ihx2hex.py
	python3 ../ihx2hex.py $< $@

clean:
	rm -f *.ihx *.hex *.asm *.lst *.rst *.rel *.sym *.map *.lk *.cdb *.adb *.mem *.noi

.PHONY: all clean
.PRECIOUS: %.ihx
