# The BF16 adder / multiplier against an exact reference: make
# Verilator when it is installed (cocotb needs 5.036 or later), else icarus:
# make SIM=icarus.  On this Mac cocotb's libraries are x86_64 builds.
SIM ?= $(if $(shell which verilator),verilator,icarus)
ifeq ($(SIM),verilator)
EXTRA_ARGS += -Wno-fatal -Wno-lint -Wno-style --timing
ifeq ($(shell uname),Darwin)
ifeq ($(shell $(shell cocotb-config --python-bin) -c "import platform; print(platform.machine())"),x86_64)
EXTRA_ARGS += -CFLAGS "-arch x86_64" -LDFLAGS "-arch x86_64"
endif
endif
endif
.DEFAULT_GOAL := sim
export COCOTB_RESOLVE_X = ZEROS
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
SIM_BUILD = sim_build
VERILOG_SOURCES += $(SRC_DIR)/fops.v $(SRC_DIR)/lampFPU_div_top.sv $(SRC_DIR)/lampFPU_div.sv $(SRC_DIR)/lampFPU_fractDiv.sv $(SRC_DIR)/lampFPU_utils.v $(PWD)/tb_fops.v
COMPILE_ARGS += -I$(SRC_DIR)
TOPLEVEL = tb_fops
COCOTB_TEST_MODULES = test_fops
MODULE = test_fops
include $(shell cocotb-config --makefiles)/Makefile.sim
