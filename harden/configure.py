#!/usr/bin/env python3
"""configure.py [--macro] - the LibreLane configuration for a local harden,
built the way tt-support-tools' --create-user-config does it: the sources,
die area and floorplan template from ../info.yaml's tile, merged over
../src/config.json; with --macro, macro.json on top (the RAM32 DFFRAM macro
in place of src/RAM32.v).  Writes config_merged.json."""
import json
import os
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TILE_SIZES = {                       # tt-support-tools tech/sky130A/tile_sizes.yaml
    "1x1": [0, 0, 161.00, 111.52], "1x2": [0, 0, 161.00, 225.76],
    "2x2": [0, 0, 334.88, 225.76], "3x2": [0, 0, 508.76, 225.76],
    "3x4": [0, 0, 508.76, 511.36], "4x2": [0, 0, 682.64, 225.76],
    "4x4": [0, 0, 682.64, 511.36], "5x4": [0, 0, 856.52, 511.36],
    "6x2": [0, 0, 1030.40, 225.76], "6x4": [0, 0, 1030.40, 511.36],
    "8x2": [0, 0, 1378.16, 225.76], "8x4": [0, 0, 1378.16, 511.36],
}


def load_json(path):
    with open(path, encoding="utf8") as f:
        return json.load(f)


def main():
    macro = "--macro" in sys.argv
    info = yaml.safe_load(open(os.path.join(ROOT, "info.yaml")))["project"]
    tiles = info["tiles"]
    sources = list(info["source_files"])
    cfg = load_json(os.path.join(ROOT, "src", "config.json"))
    if macro:
        over = load_json(os.path.join(HERE, "macro.json"))
        for s in over.pop("REMOVE_SOURCES", []):
            sources.remove(s)
        cfg.update(over)
    cfg.update({
        "DESIGN_NAME": info["top_module"],
        "VERILOG_FILES": ["dir::../src/" + s for s in sources],
        "DIE_AREA": TILE_SIZES[tiles],
        "FP_DEF_TEMPLATE": "dir::tt_block_%s_pg.def" % tiles,
        "VDD_PIN": "VPWR",
        "GND_PIN": "VGND",
        "RT_MAX_LAYER": "met4",
    })
    if not os.path.exists(os.path.join(HERE, "tt_block_%s_pg.def" % tiles)):
        sys.exit("harden/tt_block_%s_pg.def is missing: fetch it from tt-support-tools tech/sky130A/def" % tiles)
    cfg = {k: v for k, v in cfg.items() if k != "//"}
    out = os.path.join(HERE, "config_merged.json")
    with open(out, "w", encoding="utf8") as f:
        json.dump(cfg, f, indent=2)
    print("%s: %s tile %s, %d sources%s" % (out, info["top_module"], tiles, len(sources),
                                             ", the RAM32 macro" if macro else ""))


if __name__ == "__main__":
    main()
