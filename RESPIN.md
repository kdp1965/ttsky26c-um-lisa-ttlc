# LISA revision 2: the TT07 silicon issues and their fixes

The TT07 `tt_um_lisa` chip was characterized on the Tiny Tapeout demo board
(2026-10-05 .. 2026-10-09) with the SDCC port's test suite run on the chip
(`lisa-tools/sdcc_test`, `hw_test.mjs ihx=` / `spiram=`), the LISA Commander
and lisa_ide. `lisa-tools/lisa_sim` models every item below as the silicon
behaves, and `sdcc -mlisa` works around each one; the notes with the
measurements are in `lisa_isa.md` ("TT07 silicon ... notes") and
`tt07-um-lisa-ttlc/lisa-test/README.md` ("TT07 silicon notes"). This file is
the list for this revision: what the silicon does, where it is in the RTL
(line numbers of the copied tree), the fix, and how it is checked.

| #  | Issue | Where | Status |
|----|-------|-------|--------|
| 1  | Data cache aliases X and X ^ 0x4000: 16K of RAM reachable, not 32K | `data_cache8.v` 213 | fixed: cache14 |
| 2  | Read-modify-write (`inx`/`dcx`/`swap`/`swapi`/`shl16`/`shr16`) on a cache miss uses stale data | `data_cache8.v` 223, `lisa_core.v` 681-684 | fixed: test_cachermw (write-first RAM32) |
| 3  | `swap n(sp)` addresses sp + n - 512 | `lisa_core.v` 709, 630 | fixed: swap |
| 4  | BF16 `fadd`/`fsub` wrong on a significand carry-out and on a rounding carry | `fops.v` 145-166, 193-194 | fixed: test/fops |
| 5  | `ret #imm8` loads A from the wrong word | `lisa_core.v` 757, 527 | fixed: reti |
| 6  | Interrupts: predicate and pending `ldx` literal lost; `amode`, `cflag_save`, live `signed_inversion` not shadowed; `ie` unreadable | `lisa_core.v` 1206-1226, 1424 | fixed: test_irqhaz, test_irq, test_irq2 |
| 7  | ALU carry: `adc`/`sub`/`cmp` fold the carry into an 8-bit operand; `cpi` captures no signed inversion | `lisa_core.v` 643-652, 808-817 | fixed: alu2 |
| 8  | Divider: result high byte never stored, stray writes, RA and IX clobbered | `lisa_core.v` 622, 686, 736, 750 | fixed: div16 |
| 9  | A breakpoint halt right after a store drops the store and writes RAM[IX] | `lisa_dbg.v` 433-442, `lisa_core.v` 670, 714 | fixed: test_bp_after_store |
| 10 | The debugger's single step does nothing | `lisa_dbg.v` 441, core pre-decode | fixed: test_single_step |
| 11 | Debugger RAM reads return RAM[IX] with the cache off | `data_cache8.v` 223, core `dbg_ready` | fixed: test_debug_port |
| 12 | TTLC input scan shifts 17 times (every input one position high, bit 15/31/47 lost) | `shift_reg_io.v` 126-160 | fixed: test_ttlc |
| 13 | TTLC: latch pulse cannot load a 74HC166; step bit cannot work; breakpoints one late from the instruction cache | `shift_reg_io.v`, `mc14500b.v`, `ttlc_inst_cache.v` | step and breakpoints fixed: test_ttlc_debug; the 166 latch kept as is |
| 14 | Console UART holds one received byte: characters lost at flash fetch speed | `lisa_uart.v` / `lisa_rx8n.v` | done: test_uart_burst |
| 15 | Reading debug register 0xf advances PC | `lisa_dbg.v` | kept |

Status: open / fixed (the test that shows it, in test/: a program of test/progs, a cocotb test of test/core or the fops bench).

## 1. Data cache bit 14

`data_cache8.v` is the 8-line, 16-byte-line cache the chip has (`data_cache.v`
is the earlier 4-line one; both define `module data_cache`, the TT07 test
Makefile compiled the 4-line one, so the taped-out cache never ran in
simulation). Line 213 builds the SPI address of a line with bit 14 from
`cache_map[1]` when `cache_map_sel == 3`; after the move to 8 lines that is
`d_addr[5]`, not `d_addr[14]` (`cache_map[2]`), so the RAM sees
`{d_addr[5], d_addr[13:0]}` and addresses X and X ^ 0x4000 share a RAM
location through two different cache lines. Lines 214-216 (the `cache_map_sel`
0..2 variants) take the same bit.

Fix: `cache_map[2]` in 213 (and the matching bit in 214-216), the map bits
re-derived from the line geometry. Verify: a cocotb test with the SPI RAM
model on CE1 writing X and X ^ 0x4000 then reading both (`sdcc_test/test_cache*.c`
and `test_ptroff` through the cache on the chip are the program-level checks).

## 2. RMW on a cache miss

`inx`/`dcx` (`lisa_core.v` 681-682: `d_o = d_i ± 1`, combinational from the
read data), `shl16`/`shr16` (683-684), `swap`/`swapi` write back a function
of `d_i` in the cycle the cache reports a hit. After a miss the cache raises
`d_ready` (`data_cache8.v` 223: `d_valid && cache_hit`) in the first cycle
the line is valid, but the RAM's read data for that address arrives a cycle
later (the fill state machine drove the RAM address until then), so the write
uses stale `d_i`. A plain load or ALU read on a miss waits correctly; an RMW
on a byte whose line a load just brought in is right. On the chip `inx` on a
missing byte produced a constant garbage value (`test_cachermw.c`).

Fix: hold `d_ready` one more cycle after a fill (so the first hit cycle has
the RAM data), or register the read data for the RMW ops before the write.
Verify: cache test with an RMW on a cold line, and `test_cachermw` (its
`cmp`-before-`inx` workaround removed in a build) through the RAM model.

## 3. `swap n(sp)`

`sp_sum_op` (line 709) includes `op_swap_r & inst[9]`, so the swap's address
is `sp_sum = sp + sp_adder` (638) with `sp_adder` from the default branch of
630, which sign-extends `inst[9:0]`; bit 9 is the SP-select bit of the
operand, so the address is sp + n - 512. The 128-byte RAM hides it (addresses
modulo the size); with the data cache on it exchanges a byte 512 below the
stack (`test_cacherm.c`). `swap n(ix)` and `swapi` are right.

Fix: give `swap` the same `n(sp)` address path as `ldax`/`stax` (the `sp_addr`
path), not the `ads` adder. Verify: a swap on the stack with the cache on.

## 4. BF16 adder

`fops.v`: on a significand carry-out (145-158) `f_res` is built at bits [7:0]
while the result takes the fraction from `f_rounded[8:2]` (194), so the
fraction comes back shifted right by one (1.25 + 1.25 = 2.25, 1.75 + 1.75 =
2.75). The rounding is `f_res + 2` (193: round up whenever a guard bit is
set), and its carry out of the fraction wraps to 0 without the exponent
moving (2^-35 - 1.625·2^-44 came back as 2^-36). Both on the subtraction path
too. The taped-out netlist also differs from the committed `fops.v` in a few
of 49 random additions, so the RTL is not even what is on the chip.
`fmul` (truncating), `fdiv` (Goldschmidt, within an ulp), `fcmp`, `itof`,
`ftoi` are fine, modelled in `lisa_sim/bf16.cxx`.

Fix: build the carry-out case aligned with the no-carry case
(`{2'b0, significand_add[9:2], |significand_add[1:0]}` style), renormalize
(exponent + 1, fraction 0) when the rounding carries into bit 9, and round to
nearest even. Verify: a unit testbench for `fops` against a Python bfloat16
reference (round to nearest even) over random operands and the known cases,
then `sdcc_test/test_bf16` with `<lisa/bf16.h>`'s hardware add.

## 5. `ret #imm8`

`op_reti_r: acc_load_val = {1'b1, inst[7:0]}` (757) takes the immediate from
`inst` in the exec state, but `ret_taken` (527) is combinational on the
instruction word and the return's fetch has already replaced `inst` by the
low byte of the instruction at the return address (seen on the chip; the
compiler therefore pays two words, `ldi #v ; ret`, for each byte of constant
data in code space - `lisa-tools/sdcc-lisa/src/lisa/PLAN.md`).

Fix: latch imm8 when the instruction is decoded and load A from the latch.
Verify: a program with `ret #imm8` returning into code whose low byte differs
from imm8; then `sdcc -mlisa`'s `--reti` option (stride 1 constants).

## 6. Interrupts

`lisa_core.v` 1206: an interrupt is taken in the exec state of every
single-stage instruction with `ie & cond[1]`, `cond[1]` being the value before
that instruction's own update, IA <= PC + 1, flags shadowed, PC <= vector,
`cond` left as the instruction set it. So: after an `if`/`ifte`/`iftt` the
predicate is lost (the vector word executes under `cond[0]`, and after `rets`
the predicated instruction runs unconditionally); `ldx` is two single-stage
passes (1424, `ldx_stage_two`) and an interrupt after the first word loads IX
with the vector word and executes the literal as an opcode on return. `rets`
restores `cflag`/`zflag` and `signed_inv_save` from the shadows but the live
`signed_inversion` becomes 0, `cflag_save` and `amode` are not shadowed,
`ie` cannot be read. Confirmed on the chip (`test_irqhaz.c`: 2 lost
predicates, 1 corrupted `ldx` in 20 ms with a 1 ms timer). `isr_jump` keeping
RA across the vector `jal` (1050) is right.

Fix: take an interrupt only when `cond == 2'b11` and no `ldx`/`lddiv`/`div`
stage two is pending (or shadow `cond` and the pending literal); shadow
`amode` and `cflag_save` with the flags, restore the live `signed_inversion`
from a shadow on `rets`; expose `ie` in `ldirq` (bit 3). Verify: `test_irqhaz`
and `test_irq` from `sdcc_test` on the RTL (`lisa_sim --fixed-irq` is the
reference model).

## 7. ALU carry

`acc_sum = acc + acc_adder` (652) with `acc_adder` an 8-bit operand that
already contains the carry-in: `adc #k` adds `(k + C) & 0xff` (645: `adc
#0xff` with C = 1 adds 0 and clears C), `sub M` adds `~((M + C) & 0xff) + 1`
(647: M = 0, C = 0 reports a borrow), `cmp M` with M = 0 reports a borrow
(648), and `cpi #k` sets C from a comparator but never captures
`signed_inversion` (808-817; only `add`/`adc`/`sub`/`cmp` do). A is always
right; only C and signed ordering are wrong. `add M` has no carry-in: that is
by design (`adc` is the carry form), keep it.

Fix: a 9-bit adder with a real carry-in (`acc + operand + cin`: cin = C for
`adc`, ~C for `sub`, 1 for `cmp`/`cpi` with the operand inverted), and
`cpi` capturing `signed_inversion` like `cmp`. The compiler's TT07 sequences
(`adc #0; add M`, `ldc 1; adc #~k`, the `cpi #1` guard) stay correct on the
fixed core. Verify: an exhaustive 256 x 256 x 2 testbench of `adc`/`sub`/`cmp`/
`cpi` flags against the reference, then `sdcc_test` (`test_arith*`,
`test_regress`).

## 8. Divider

Probed with `test_divprobe.c`: `lddiv`, `div`, `rem` compute right, but (1)
the result's high byte never reaches memory (the stage-two store on
`div_ready`, 686/750, does not land); (2) when the word in the instruction
register at completion has bit 1 clear (the offset word of the two-word form
for offsets 0, 1, 4, 5, ..., or the one-word `div 1`/`rem 1`) the result's
low byte is written to a stray address (IX + offset with IX already 0, or SP
+ 0x101); (3) every division leaves IX = 0 and RA = the 16-bit result (15
bits) with `ra_cond` set. `sdcc -mlisa` relies on (3): it inlines `div 3` and
the `2(sp)`/`3(sp)` forms and reads a 16-bit result from RA.

Fix: make the stage-two store of the high byte land and remove the stray
write; then decide the register side effects: keep "RA = result, IX = 0" as
the architected behaviour (the compiler already uses it; RA would need its
16th bit) or restore RA and IX. Decision needed before the fix. Verify:
`test_divprobe` and `arith-rand` on the RTL with the chosen semantics in
`lisa_sim` (`div_aftermath`).

## 9. Breakpoint after a store

A store sets `d_we_r` in exec and the RAM write completes in the next fetch
cycle. `brk_halt` (`lisa_dbg.v` 433-437) is combinational on `pc ==
breakpoint` and `stop` (442) rises in that same cycle; while stopped the core
drives `d_addr = ix` (`lisa_core.v` 714) and `d_o = dbg_di[7:0]` (670). The
store is lost and RAM[IX] gets the debugger's last data byte (measured:
stopped after `push a`, the slot kept its old contents and RAM[IX] got the
data byte of the resume command). lisa_ide and the Commander avoid planting a
stop right after a store (`Cdb::safe_stop`); an asynchronous halt can still
hit it.

Fix: let a pending write complete before the debugger takes the data bus
(gate the `stop` takeover of `d_addr`/`d_o`/`d_we` on `!d_we_r`, or register
`brk_halt` so the halt lands after the write cycle). Verify: a breakpoint
right after `push a`/`sta` in a cocotb test, RAM checked afterwards
(`hw_test.mjs hazard=` is the chip version).

## 10. Single step

Register 0 bit 2 pulses `cont` (`lisa_dbg.v` 441) for one clock; the core's
pre-decode state sees `stop` again and returns to fetch, so no instruction
executes and PC does not move. Debuggers step by breakpoints on every
successor address instead.

Fix: hold the resume until one instruction retires (a `step_pending` cleared
by the exec state). Verify: step over a `br`, a `jal`, an `ldx`, a store.

## 11. Debugger RAM reads with the cache off

With the cache disabled `d_ready` is a constant 1 (`data_cache8.v` 223), so
the core answers a register-6 read in the access's first clock, before the
pipelined address register and the RAM have seen the debugger's address; the
value latched is the RAM output for the idle address, IX. Debuggers read RAM
by writing the address to IX first.

Fix: a one-cycle `dbg_ready` after the address is presented when the cache is
disabled (the enabled cache's multi-cycle ready is right). Verify: register
6/7 reads of a pattern with the cache off.

## 12. TTLC 17-sample scan

`shift_reg_io.v` state `SHIFT_IO`: the input shift is keyed on `!shift_clk &&
clk_count == 0`, right for the 16 rising edges, but after the 16th falling
edge the FSM waits one more clock period before `LATCH` (154-160) with the
toggle suppressed by `last_clk` (126) while the shift condition is still true;
the `shift_count` decrement (150) is gated with `!last_clk`, the shift is not.
The register keeps the last 16 of 17 samples: every input one position too
high, bits 15/31/47 lost, input 0 constant. The Commander's emulator plays
this back; Ken's Pmod respin adds a 74HC175 dummy stage for the TT07 chip.

Fix: `&& !last_clk` on the input shift condition. Verify: a 74HC165/74HC595
chain model in a cocotb test (loopback of a pattern through the 48 outputs
and 48 inputs); then the Commander's 16-sample mode on the chip.

## 13. TTLC: latch, step, breakpoints

* The latch pulse is low with the shift clock still; a 74HC166 loads only on a
  clock edge while /PE is low (a 74HC165's /PL is asynchronous). Left as it
  is: a clock pulse inside the latch window would be a 17th edge to every
  existing emulator and Pmod, and the Pmods use the 165.
* `ttlc_halt = !run | step` blocked the fetch whose `ttlc_i_ready` would clear
  `step`. Now (`debug_regs.v`) the step lifts the halt until one fetch
  (`ttlc_exec`, from `tt_um_lisa.v`), then clears run; a run or step written
  passes a breakpoint on the current PC (`ttlc_skip`).
* The breakpoint compare used to clear `run` a clock after the PC reached the
  address; now `ttlc_halt` is combinational on the match, so the TTLC halts
  with the PC at the breakpoint, before its instruction. And the PC change of
  a `jmp`/`rtn`/`nopf` lands in the clock(s) after its fetch even when the
  fetch was the last one allowed (`mc14500_pcen` = run or its two delayed
  copies): a stepped jump jumps. test_ttlc_debug: a breakpoint at 5 halts at
  5 twice round the loop, three steps go 6, 7, 8, stepping round the loop
  comes back to 0 through the nopf.
* `mc14500b.v`'s WRITE strobe was two flops resetting each other
  asynchronously, which the LibreLane flow's Yosys check reported as a logic
  loop (the first GDS run of this repository failed on it); it is one
  falling-edge flop now, with the same timing (test_ttlc writes through it).

## 14. Console UART receive buffer

The core needs ~1-3 ms per received character with the flash in plain SPI
(the receive loop's instruction fetches), the UART holds one byte, so bursts
lose every other character (the monitor). A small receive FIFO (4-8 bytes)
in `lisa_uart.v`, or at least a double buffer, with an overrun flag, makes
interactive programs usable without pacing. Improvement, not a bug.

## 15. Register 0xf

Any access to the "current opcode" register increments PC (`dbg_inc`, meant
for loading code). By design; keep, and keep it out of the debuggers' polls
(documented in the Commander README).

## Verification (test/, see test/README.md)

* `test/core/`: tb_core.v, the core with the chip's registered data bus, the
  8-line cache, the RAM32 (write-first, as the DFFRAM macro reads), the QSPI
  sequencer with a QSPI RAM model on CE1 and the peripherals; instructions
  straight from an array, the debug port driven from Python. `make
  IHX=<prog.ihx> [CACHE=1]` runs a program to ALL PASSED; `make
  IHX=../progs/dbg.ihx` runs the debugger tests (breakpoint after a store,
  single step, halt / resume, RAM reads); `irq3` with `TRACEPC=` /
  `TRACEWIN=` prints a non-intrusive trace.
* `test/`: tb.v, the whole chip with a flash model (the image from
  `+FIRMWARE=`), a QSPI RAM on CE1, the debug UART and the TTLC's three
  74HC595 / 74HC165 chains. `make` runs the debugger, hello's banner and a
  burst of characters; `make TTLC=1` the loopback through the chains and the
  TTLC's breakpoints and step; `make IHX=<prog.ihx>` a program through the
  SPI fetch (Verilator: test_core in 10 s).
* `test/fops/`: fadd and fmul against an exact bfloat16 reference.
* `test/progs/`: the probe programs built by `sdcc -mlisa`, the `.hex`
  committed. `test/run_suite.sh [core|chip] [CACHE=1]` runs the SDCC suite.
* Still to do on the toolchain side: a `lisa_sim` mode for these semantics,
  `sdcc -mlisa`'s option for the shorter sequences (`ret #imm8` constants,
  the plain `adc`/`sub`/`cmp` forms, the 16-bit divider result without the
  mask), `ldamode` in the assembler and simulator, and the ISA document.

## Decisions (Ken, 2026-10-15)

* 8, the divider: whatever gives the most efficient code, with a compiler
  option for the fixed core. So: no memory write of the result at all (the
  high-byte store was broken and the stray write goes with it); the 16-bit
  result stays in RA with its bit 15 in `ra_cond`, so `xchg ra` gives the
  whole result in IX (`txau` then reads bits 15:8, no `andi #0x7f`) and
  `stxx` stores it; IX is 0 afterwards as on TT07. `sdcc -mlisa` keeps the
  TT07 sequences by default and gets an option (`--rev2`, name to be
  settled) for the shorter ones.
* 6, interrupts: shadow everything the handler would otherwise have to save
  (amode, cflag_save, the live signed inversion, as `lisa_sim --fixed-irq`
  already models) and expose `ie`.
* The RAM: the RAM32 DFFRAM macro, as on TT07 (the local flow). To look at:
  the macro's read path is 1088 `ebufn_2` tri-state buffers (the 32:1
  column mux per output bit, ~13.6K um2) next to 1024 `dlxtp_1` latches
  (~14K um2) in a 401.6 x 136 um = 54.6K um2 block that is a third decap
  (825 `decap_12`); an AND-OR (mux2 tree) read path would be about half
  the area of the tri-states, so a recompiled macro could come in around
  40K um2. Not started.
* 14: an 8-byte UART receive FIFO.
* `amode` becomes readable.
* 7: `add` stays carry-less (confirmed 2026-10-06).
