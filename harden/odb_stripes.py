# Extend the tile's vertical power stripes across every hard macro.
#
# (From the CFGMEM tile trial in DFFRAM.librelane.)  A Tiny Tapeout tile has
# a single-layer PDN (vertical stripes on the top routing layer, no
# horizontal straps), so a macro's Metal4 power pins can only be reached by a
# tile stripe running straight over them. pdngen trims its stripes around
# macros; this step draws each macro's VPWR/VGND pin columns from the bottom
# to the top of the core as tile stripes (and tile power pins), which bridges
# the gap and lands exactly on the macro pins. It warns if a macro pin column
# is not aligned with an existing tile stripe.
#
# A column that is not on a tile stripe would be an island with the macro
# pin (the IR-drop step's check_power_grid failed on VGND; VPWR only passed
# through a 0.57 um overlap with a tile stripe): pdn_macro.tcl (PDN_CFG) has
# pdngen put a stripe with its via arrays on every such column first, and the
# full-height stripe drawn here lies on it.  (Via stacks drawn here from
# single M1M2_PR/M2M3_PR/M3M4_PR vias were 2175 Magic DRC errors: met3 minimum
# area and via spacing to the neighbouring tile stripe's arrays.)
import click
import odb
from reader import click_odb


@click.command()
@click.option("--layer", default="met4", help="Vertical PDN layer")
@click_odb
def extend(reader, layer):
    block = reader.block
    tech = reader.tech
    m = tech.findLayer(layer)
    core = block.getCoreArea()
    ylo, yhi = core.yMin(), core.yMax()
    dbu = block.getDefUnits()

    for net_name in ("VPWR", "VGND"):
        net = block.findNet(net_name)
        if net is None:
            raise click.ClickException(f"net {net_name} not found")
        swires = net.getSWires()
        swire = swires[0] if swires else odb.dbSWire_create(net, "ROUTED")
        existing = [
            b for b in swire.getWires()
            if b.getTechLayer() is not None  # via boxes carry no layer
            and b.getTechLayer().getName() == layer
            and (b.yMax() - b.yMin()) > (b.xMax() - b.xMin())
        ]
        bpin = None
        for bterm in net.getBTerms():
            pins = bterm.getBPins()
            if pins:
                bpin = pins[0]
                break

        added = 0
        for inst in block.getInsts():
            master = inst.getMaster()
            if not master.isBlock():
                continue
            mterm = master.findMTerm(net_name)
            if mterm is None:
                print(f"[WARNING] macro {inst.getName()} has no pin {net_name}")
                continue
            if inst.getOrient() != "R0":
                raise click.ClickException(
                    f"{inst.getName()} is placed with orientation {inst.getOrient()}; "
                    "only R0 (N) is supported by this step"
                )
            ib = inst.getBBox()
            ox, oy = ib.xMin(), ib.yMin()  # macro origin in tile coordinates (R0)
            for mpin in mterm.getMPins():
                for box in mpin.getGeometry():
                    if box.getTechLayer().getName() != layer:
                        continue
                    r = odb.Rect(ox + box.xMin(), oy + box.yMin(), ox + box.xMax(), oy + box.yMax())
                    cx = (r.xMin() + r.xMax()) / 2
                    nearest = min(
                        (abs((e.xMin() + e.xMax()) / 2 - cx) for e in existing), default=None
                    )
                    if nearest is None or nearest > 0.85 * dbu:  # pdn_macro.tcl may move a stripe by up to width/2
                        print(
                            f"[WARNING] {inst.getName()} {net_name} pin column at x={cx/dbu:.3f} um is "
                            f"{'not near any' if nearest is None else f'{nearest/dbu:.3f} um off the nearest'} tile stripe"
                        )
                    odb.dbSBox_create(swire, m, r.xMin(), ylo, r.xMax(), yhi, "STRIPE")
                    if bpin is not None:
                        odb.dbBox_create(bpin, m, r.xMin(), ylo, r.xMax(), yhi)
                    added += 1
        print(f"[INFO] {net_name}: {len(existing)} tile stripes found, {added} full-height stripes added over macro pin columns")


if __name__ == "__main__":
    extend()
