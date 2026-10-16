#!/usr/bin/env python3
"""flow.py [--macro] [run-tag] - harden tt_um_lisa locally with LibreLane's
Classic flow on config_merged.json (configure.py).  With --macro the RAM32
DFFRAM macro is in the design and one extra step runs the tile's vertical
power stripes across its pin columns after the PDN is generated (the
single-layer tile PDN does not reach a macro's pins by itself).

    python3 flow.py [--macro] [tag]        inside the LibreLane nix shell, PDK_ROOT set
"""
import json
import os
import sys

from librelane.flows.classic import Classic
from librelane.steps import OpenROAD
from librelane.steps.odb import OdbpyStep

HERE = os.path.dirname(os.path.abspath(__file__))


class ExtendPowerStripes(OdbpyStep):
    id = "Tile.ExtendPowerStripes"
    name = "Extend Power Stripes Over Macros"

    def get_script_path(self):
        return os.path.join(HERE, "odb_stripes.py")


class MacroFlow(Classic):
    Steps = list(Classic.Steps)
    Steps.insert(Steps.index(OpenROAD.GeneratePDN) + 1, ExtendPowerStripes)


def main():
    macro = "--macro" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cfg = json.load(open(os.path.join(HERE, "config_merged.json"), encoding="utf8"))
    cfg["PDK"] = "sky130A"
    flow_class = MacroFlow if macro else Classic
    flow = flow_class(cfg, design_dir=HERE, pdk_root=os.environ["PDK_ROOT"])
    flow.start(tag=args[0] if args else None)


if __name__ == "__main__":
    main()
