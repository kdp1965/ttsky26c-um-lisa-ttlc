# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# The design, as info.yaml lists it (data_cache8.v is the 8-line cache the
# chip has; data_cache.v is the older 4-line one with the same module name,
# so only one of them can be compiled).
PROJECT_SOURCES  = tt_um_lisa.v RAM32.v
PROJECT_SOURCES += lisa_core.v lisa_dbg.v lisa_div.v lisa_periph.v lisa_io_mux.v
PROJECT_SOURCES += lisa_qqspi.v lisa_qspi_controller.v lisa_rx8n.v lisa_tx8n.v lisa_i2c.v
PROJECT_SOURCES += debug_ctrl.v debug_autobaud.v debug_brg.v debug_regs.v
PROJECT_SOURCES += data_cache8.v inst_cache.v
PROJECT_SOURCES += i2c_master_byte_ctrl.v i2c_master_bit_ctrl.v lisa_uart.v
PROJECT_SOURCES += fops.v lampFPU_div_top.sv lampFPU_div.sv lampFPU_fractDiv.sv lampFPU_utils.v
PROJECT_SOURCES += mc14500b.v ttlc_io.v ttlc_inst_cache.v shift_reg_io.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
# behavioural models of the sky130 cells debug_regs.v instantiates
VERILOG_SOURCES += $(PWD)/test_cells.v

else

# Gate level simulation:
SIM_BUILD        = sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
# a locally hardened build with the RAM32 DFFRAM macro needs its netlist too:
# make GATES=yes MACRO_NETLIST=../macros/RAM32.pnl.v
VERILOG_SOURCES += $(MACRO_NETLIST)

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS    += -I$(SRC_DIR)

# The testbench: the DUT with a SPI flash (firmware.hex) on CE0, a SPI RAM on
# CE1 and a UART on the debug port.
VERILOG_SOURCES += $(PWD)/tb.v $(PWD)/spiflash.v $(PWD)/psram.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test
MODULE = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
