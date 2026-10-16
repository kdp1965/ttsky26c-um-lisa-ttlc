#!/usr/bin/env python3
"""flow.py [--macro] [run-tag] - harden tt_um_lisa locally with LibreLane's
Classic flow on config_merged.json (configure.py; config_merged_macro.json
with --macro).  With --macro the RAM32
DFFRAM macro is in the design and one extra step runs the tile's vertical
power stripes across its pin columns after the PDN is generated (the
single-layer tile PDN does not reach a macro's pins by itself).  Both flows
can pin the registers to a reference placement (ANCHOR_SEQ_TABLE, a
seq_placement.py table; Project.AnchorSequential before global placement,
Project.ReleaseAnchors after it).

    python3 flow.py [--macro] [--to=Step.Id] [tag]   inside the LibreLane nix shell, PDK_ROOT set
                                           (--to=Yosys.Synthesis: synthesis only, `make synth`)
"""
import json
import os
import sys
from typing import List, Optional

from librelane.common import Path
from librelane.config import Variable
from librelane.flows.classic import Classic
from librelane.steps import Odb, OpenROAD
from librelane.steps.odb import OdbpyStep

HERE = os.path.dirname(os.path.abspath(__file__))


class ExtendPowerStripes(OdbpyStep):
    id = "Tile.ExtendPowerStripes"
    name = "Extend Power Stripes Over Macros"

    def get_script_path(self):
        return os.path.join(HERE, "odb_stripes.py")


class AnchorSequential(OdbpyStep):
    """Pins the flops and latches where an earlier run had them (a
    seq_placement.py table keyed by RTL name, odb_anchor_seq.py) right before
    global placement, after the rows are cut and the taps and the PDN are in:
    a good run's register skeleton is reused and the placer arranges the
    logic around it (the placement is not deterministic run to run, and a
    run near the routability threshold is a lottery otherwise).  Registers
    the table does not know place freely.  With ANCHOR_CELLS_TABLE (an
    odb_anchor_cells.py --dump of the reference) the combinational cells are
    pinned too, matched by structure.  No table: nothing happens."""
    id = "Project.AnchorSequential"
    name = "Anchor the Registers to a Reference Placement"
    config_vars = [
        Variable("ANCHOR_SEQ_TABLE", Optional[Path], "seq_placement.py JSON of the run whose register placement is reused; unset = nothing pinned.", default=None),
        Variable("ANCHOR_SEQ_STATUS", str, "Placement status of the pinned registers: FIRM (DEF FIXED, the placers leave them) or PLACED (a starting point only).", default="FIRM"),
        Variable("ANCHOR_CELLS_TABLE", Optional[Path], "odb_anchor_cells.py --dump graph of the run whose placement is reused: the registers by name AND the combinational cells by structure; takes precedence over ANCHOR_SEQ_TABLE.", default=None),
        Variable("ANCHOR_CELLS_ROUNDS", int, "Neighbourhood radius (hops) of the structural matching's local pass.", default=3),
    ]

    def anchoring(self):
        return self.config["ANCHOR_SEQ_TABLE"] is not None or self.config["ANCHOR_CELLS_TABLE"] is not None

    def get_script_path(self):
        if self.config["ANCHOR_CELLS_TABLE"] is not None:
            return os.path.join(HERE, "odb_anchor_cells.py")
        return os.path.join(HERE, "odb_anchor_seq.py")

    def get_command(self) -> List[str]:
        if self.config["ANCHOR_CELLS_TABLE"] is not None:
            return super().get_command() + [
                "--table", str(self.config["ANCHOR_CELLS_TABLE"]),
                "--status", self.config["ANCHOR_SEQ_STATUS"],
                "--rounds", str(self.config["ANCHOR_CELLS_ROUNDS"]),
                "--report", os.path.join(self.step_dir, "anchor_pairs.json"),
            ]
        return super().get_command() + ["--table", str(self.config["ANCHOR_SEQ_TABLE"]), "--status", self.config["ANCHOR_SEQ_STATUS"]]

    def run(self, state_in, **kwargs):
        if not self.anchoring():
            return {}, {}
        return super().run(state_in, **kwargs)


class ReleaseAnchors(OdbpyStep):
    """Sets the registers Project.AnchorSequential pinned back to PLACED right
    after global placement (odb_anchor_release.py): FIRM only has to steer
    the global placer, and left on it breaks the resizers' in-place
    upsizing."""
    id = "Project.ReleaseAnchors"
    name = "Release the Anchored Registers"
    config_vars = AnchorSequential.config_vars

    def get_script_path(self):
        return os.path.join(HERE, "odb_anchor_release.py")

    def run(self, state_in, **kwargs):
        if not AnchorSequential.anchoring(self):
            return {}, {}
        return super().run(state_in, **kwargs)


def with_anchors(steps):
    steps = list(steps)
    steps.insert(steps.index(Odb.AddRoutingObstructions) + 1, AnchorSequential)
    steps.insert(steps.index(OpenROAD.GlobalPlacement) + 1, ReleaseAnchors)
    return steps


class StandardFlow(Classic):
    Steps = with_anchors(Classic.Steps)


class MacroFlow(Classic):
    Steps = with_anchors(Classic.Steps)
    Steps.insert(Steps.index(OpenROAD.GeneratePDN) + 1, ExtendPowerStripes)


def main():
    macro = "--macro" in sys.argv
    to = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--to=")), None)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    merged = "config_merged_macro.json" if macro else "config_merged.json"
    cfg = json.load(open(os.path.join(HERE, merged), encoding="utf8"))
    cfg["PDK"] = "sky130A"
    flow_class = MacroFlow if macro else StandardFlow
    flow = flow_class(cfg, design_dir=HERE, pdk_root=os.environ["PDK_ROOT"])
    flow.start(tag=args[0] if args else None, **({"to": to} if to else {}))


if __name__ == "__main__":
    main()
