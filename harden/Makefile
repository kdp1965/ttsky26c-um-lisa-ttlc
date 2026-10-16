# Harden tt_um_lisa on this machine with LibreLane (the GitHub runners take
# an hour for what the Mac does in minutes).
#
#   make            # the standard Tiny Tapeout flow: the RAM synthesized from src/RAM32.v
#   make macro      # with the RAM32 DFFRAM macro (macro.json, the stripe step of flow.py)
#   make clean
#
# LibreLane and the tools come from the dev shell of a LibreLane checkout
# (LIBRELANE), the PDK from PDK_ROOT (ciel enable --pdk-family sky130 <the
# open_pdks commit librelane/open_pdks_rev names>).  Run outside the shell,
# each recipe re-runs itself inside it.  Results: runs/<tag>/final/.
LIBRELANE ?= $(HOME)/projects/tiny_tapeout/librelane
export PDK_ROOT ?= $(HOME)/projects/fossi
TAG ?= $(shell date +%Y%m%d-%H%M%S)

ifeq ($(IN_NIX_SHELL),)
NIX_RUN = nix-shell $(LIBRELANE)/shell.nix --run
else
NIX_RUN = sh -c
endif

standard:
	$(NIX_RUN) "python3 configure.py && python3 flow.py standard-$(TAG)"

macro:
	$(NIX_RUN) "python3 configure.py --macro && python3 flow.py --macro macro-$(TAG)"

shell:
	nix-shell $(LIBRELANE)/shell.nix

clean:
	rm -rf runs config_merged.json

.PHONY: standard macro shell clean
