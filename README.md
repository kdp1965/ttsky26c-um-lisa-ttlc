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
commit `librelane/open_pdks_rev` names), as the DFFRAM.librelane work does:

```sh
make -C harden            # the standard Tiny Tapeout flow: the RAM synthesized from src/RAM32.v
make -C harden macro      # with the RAM32 DFFRAM macro (macros/): harden/macro.json places it,
                          # flow.py runs the tile's power stripes over its met4 pins after the PDN
make -C harden shell      # the nix shell itself
```

`configure.py` builds `config_merged.json` the way tt-support-tools'
`--create-user-config` does (the sources, the tile's die area and floorplan
template from `info.yaml`, over `src/config.json`); results land in
`harden/runs/<tag>/final/`. For a submission, copy the macro build's GDS,
LEF and netlist to `gds/`, `lef/` and `pnl/` and run `gds_custom.yaml`.

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
