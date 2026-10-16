![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

## LISA (Little ISA) 8-bit microcontroller SoC with TTLC, revision 2

The second tapeout of **LISA**: the `tt_um_lisa` design from Tiny Tapeout 7
([tt07-um-lisa-ttlc](https://github.com/kdp1965/tt07-um-lisa-ttlc)) with the
problems found in that silicon fixed. The TT07 chip was characterized on the
demo board with the SDCC port's test suite, the LISA Commander and lisa_ide
(all in [lisa-tools](https://github.com/kdp1965/lisa-tools)); what was found,
where it is in the RTL and how each item is fixed and verified is in
[RESPIN.md](RESPIN.md). The RTL started as a copy of the TT07 tree at commit
`0d69ac8`.

LISA is a microcontroller built around a custom 8-bit accumulator core
(16-bit instructions, 15-bit program counter, Harvard), with:

   - a debug interface on a UART (auto-detected port and baud rate): registers,
     halt / resume / breakpoints, RAM access, (Q)SPI flash erase and program
   - a (Q)SPI arbiter with four channels: debugger, LISA instruction fetch,
     LISA data (through the data cache), TTLC instruction fetch; two chip
     enables, each SPI or QSPI, flash or RAM, 16- or 24-bit addresses,
     programmable SCLK divider, CE delay, dummy cycles and base addresses
   - 128 bytes of on-chip RAM, used directly or as an 8-line data cache in
     front of a 32 KB SPI RAM
   - a single-line (4 instruction) instruction cache
   - UART (shared with the debugger), a dedicated UART2, two 16-bit timers,
     an 8-bit input port, 8-bit output port, 4-bit bidirectional port, I2C master
   - 8x8 multiplier, 16/16 divider, BF16 multiply / divide / add / compare / convert
   - TTLC, a Tiny Tapeout Logic Controller: an MC14500B-compatible industrial
     control unit with 48 inputs and 48 outputs on external 74HC595 / 74HC165
     chains, a 32-bit store and 8 bits each way to LISA
   - an I/O mux for the pinout

The datasheet text is [docs/info.md](docs/info.md); the instruction set is
described in `lisa_isa.md` in the workspace above this repository.

## Layout

```
src/            the RTL (info.yaml lists the files); src/config.json is the LibreLane config
test/           cocotb testbench: the DUT with a SPI flash model (firmware.hex), a SPI RAM
                model and a UART on the debug port
docs/           datasheet (info.md and its figures)
macros/         the RAM32 DFFRAM macro (GDS, LEF, libs, netlist) of the TT07 chip
harden/         the local LibreLane flow: configure.py, flow.py (+ the macro's stripe step),
                macro.json, the 4x4 floorplan template
```

## Building

`harden/` hardens the design on this machine with LibreLane (the GitHub
runners are an order of magnitude slower than the Mac). It needs a LibreLane
checkout with its nix dev shell (`LIBRELANE`, default
`~/projects/tiny_tapeout/librelane`) and the PDK under `PDK_ROOT` (default
`~/projects/fossi`; `ciel enable --pdk-family sky130 <commit>` with the
commit `librelane/pdk_hashes.yaml` names - open_pdks 8afc834 of 2025-07 for
every LibreLane 3.0.x release so far, the Tiny Tapeout action's 3.0.5
included), as the DFFRAM.librelane work does:

```sh
make -C harden            # the standard Tiny Tapeout flow: the RAM synthesized from src/RAM32.v
make -C harden macro      # with the RAM32 DFFRAM macro (macros/): harden/macro.json places it,
                          # flow.py runs the tile's power stripes over its met4 pins after the PDN
make -C harden shell      # the nix shell itself
make -C harden macro TO=OpenROAD.GlobalRouting   # stop after the congestion report
make -C harden macro TILES=8x2                   # another tile: tt_block_8x2_pg.def, macro_8x2.json
make -C harden macro OVERLAY=trial_fix5.json     # a trial: that JSON's variables merged last
```

`configure.py` builds `config_merged.json` the way tt-support-tools'
`--create-user-config` does (the sources, the tile's die area and floorplan
template from `info.yaml`, over `src/config.json`); results land in
`harden/runs/<tag>/final/`. The build to submit is `make -C harden macro`
(macro.json replays the reference placement, `ANCHOR_CELLS_TABLE`, see
below; `trial_fix6.json` was the same as an overlay); copy its GDS, LEF and
netlist to `gds/`, `lef/` and `pnl/` and run `gds_custom.yaml`.
The macro flow places with `GPL_CELL_PADDING` 2: the slew/fanout repair, CTS
and the hold buffers add 30% to the placed cells and without the padding the
legalizer packs them into 30 um bins over 90% full, where the detailed router
does not converge (RESPIN.md, Hardening). The standard flow does not route on
this tile (its global route needs 128-144% of the met1-met4 resources).
`make -C harden macro TILES=8x2` tries the macro flow on the TT07 tile.
`harden/pdn_macro.tcl` is the macro flow's PDN: the tile's, plus a stripe on
each macro power pin column that is not on a tile stripe (`odb_stripes.py`
then runs the columns over the macro and makes every power pin box pdngen
cut around the macro full height again: Tiny Tapeout's precheck wants each
power port box to reach both edges of the tile). `EXTRA_EXCLUDED_CELLS` in
src/config.json keeps the resizer off the sky130 delay cells, which it
otherwise takes as its fanout buffer. `harden/trial_*.json` are per-run
overlays (`OVERLAY=`), the trials RESPIN.md's Hardening section describes.

Global placement is not deterministic run to run, and a build near the
routability threshold is a lottery (RESPIN.md, the third build). The flow
can therefore pin the registers where a good run had them: `openroad
-python harden/seq_placement.py runs/<good>/final/odb/tt_um_lisa.odb
harden/placements/<good>_seq.json` writes a table keyed by the RTL name on
each register's Q net (which Yosys keeps; the instance numbers change every
run), and with `ANCHOR_SEQ_TABLE` set to it (`trial_fix5.json`) flow.py's
`Project.AnchorSequential` step fixes the registers there before global
placement and `Project.ReleaseAnchors` frees them after it, so the placer
only arranges the logic around that skeleton. Registers the table does not
know place freely. `ANCHOR_CELLS_TABLE` goes further (`trial_fix6.json`):
`openroad -python harden/odb_anchor_cells.py --dump
harden/placements/<good>_cells.json <good odb>` (inside the nix shell, with
LibreLane's `scripts/odbpy` on PYTHONPATH) dumps the run's whole logic graph
with its placement, and the step pins the combinational cells too, matched
by structure (18682 of 18698 cells against the second routed build), so a
good placement is replayed and only the flow's buffers are new. The recipe
comes from ihp-um-janestreet-prism, where it turned unroutable runs
routable.

The timing constraints are `src/lisa.sdc`: LibreLane's `base.sdc` (the
clock from `CLOCK_PERIOD`, 30 ns as the TT07 build was constrained - its
`impl.sdc` overrode the 20 ns of its config; the chip runs at 66 MHz) plus
the core's multi-cycle paths, the set TT07 closed with: what the PC, the
instruction cache line, the breakpoint latches and the debugger's registers
reach is written two or three clocks later. The registers are found through
their Q nets (the cells are numbered), so there is no netlist renaming step;
every STA log opens with `lisa.sdc: pc 15 cl_valid 1 cl_addr 15 brk 96 ...`,
the registers each group resolved to, and a group that resolves to nothing
is reported (Yosys names a flattened net after any of its aliases: the
debugger's data register came out as `core_inst_o`). `make -C harden status
RUN=runs/<tag>` shows a run's steps and the router's progress.

`src/no_synth.cells` is the synthesis exclusion list (`SYNTH_EXCLUDED_CELL_FILE`).
The PDK's own list keeps synthesis off nearly every `_1` logic cell and flop,
which maps the design to `_2` cells and makes it about a quarter larger than
TT07's build, which used the `_1` cells (229K against 178K um2 synthesized
here; the 2024 PDK had the same list, how TT07's OpenLane 2.0.4 run got past
it is not known). Upstream open_pdks dropped the combinational `_1` cells
from the list on 2026-05-28 (it is `libs.tech/librelane/.../synth_excluded.cells`
there now), but no LibreLane release pins such a PDK yet. The project list is
the PDK's without the `_1` combinational cells and plain flops; clock, delay,
scan and latch cells stay excluded. `make -C harden synth` runs synthesis alone to check the
area (`runs/synth-<tag>/*-yosys-synthesis/reports/stat.json`).

On GitHub, `synth.yaml` synthesizes the RTL with Yosys on every push and
runs its check pass (the structural problems the flow stops on); `gds.yaml`
(run by hand) is the standard flow on the runners; `test.yaml` runs the
chip-level testbench under icarus.

## Testing

```sh
cd test && make          # RTL, icarus + cocotb (2.1 in CI; 1.9 works too)
make GATES=yes           # gate level, with gate_level_netlist.v from the harden
```

The testbench (`test/tb.v`) wires `tt_um_lisa` to a SPI flash model loaded
from `firmware.hex`, a SPI RAM model on CE1 and a UART on the auto-detected
debug port; `test.py` checks the debugger answers. The program-level tests
(the SDCC suite through the flash model, the data cache through the RAM
model) are part of the work in RESPIN.md.

The board-side tools - the LISA Commander web app, `uartPass.py`, the
hardware test - stay in `tt07-um-lisa-ttlc/lisa-test`; the debugger protocol
is unchanged, so they serve this chip too.

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.
To learn more and get started, visit https://tinytapeout.com.

- [FAQ](https://tinytapeout.com/faq/)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)
- [Join the community](https://tinytapeout.com/discord)
