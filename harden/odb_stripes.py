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
#
# pdngen cuts its stripes around the macro (the straps it adds on the pin
# columns start above the halo, and so do two tile stripes that pass within
# its clearance of a macro pin), and each cut stripe is also a pin box of the
# tile's power port.  Magic writes those boxes into the LEF and Tiny
# Tapeout's precheck rejects a power port box that does not reach the bottom
# and top edges ("Port VGND is too far from bottom edge of module: 154.12 >
# 10 um", 6 of them on the first submission).  So every met4 power pin box
# shorter than the core is replaced by a full-height one and the stripe is
# completed over the macro (same net: it lies on the macro pin or passes it
# at the met4 spacing; a tile stripe's column stays where the template put
# it).
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

        # pdngen's cut stripes: complete them and make their pin boxes full height
        # - unless the completed stripe would touch a macro pin of the other
        # net (pdngen cut it for that reason): a macro whose power pins are
        # off the tile's stripe grid.  The tile template needs every stripe,
        # so such a macro has to move onto the grid (x a multiple of the pitch).
        other = block.findNet("VGND" if net_name == "VPWR" else "VPWR")
        other_pins = []
        for inst in block.getInsts():
            master = inst.getMaster()
            if not master.isBlock() or inst.getOrient() != "R0":
                continue
            mt = master.findMTerm(other.getName()) if other is not None else None
            if mt is None:
                continue
            ib = inst.getBBox()
            for mpin in mt.getMPins():
                for box in mpin.getGeometry():
                    if box.getTechLayer().getName() == layer:
                        other_pins.append((ib.xMin() + box.xMin(), ib.xMin() + box.xMax()))
        spacing = m.getSpacing() if m.getSpacing() else int(0.3 * dbu)
        full = set()
        for bterm in net.getBTerms():
            for pin in bterm.getBPins():
                for box in pin.getBoxes():
                    if box.getTechLayer() is not None and box.getTechLayer().getName() == layer \
                            and box.yMin() <= ylo and box.yMax() >= yhi:
                        full.add((box.xMin(), box.xMax()))
        completed = 0
        for bterm in net.getBTerms():
            for pin in bterm.getBPins():
                for box in list(pin.getBoxes()):
                    if box.getTechLayer() is None or box.getTechLayer().getName() != layer:
                        continue
                    if box.yMin() <= ylo and box.yMax() >= yhi:
                        continue
                    x1, x2 = box.xMin(), box.xMax()
                    clash = [(a, b) for a, b in other_pins if x1 - spacing < b and a < x2 + spacing]
                    if clash:
                        print(f"[WARNING] {net_name}: pin box at x={(x1 + x2) / 2 / dbu:.3f} um is cut around the macro and cannot be completed: it would come within {spacing / dbu:.2f} um of a macro {other.getName()} pin at x={(clash[0][0] + clash[0][1]) / 2 / dbu:.3f} um - move the macro onto the stripe grid")
                        continue
                    print(f"[INFO] {net_name}: pin box at x={(x1 + x2) / 2 / dbu:.3f} um spans y {box.yMin() / dbu:.2f}..{box.yMax() / dbu:.2f} um (cut around the macro): completed to the full height")
                    odb.dbSBox_create(swire, m, x1, ylo, x2, yhi, "STRIPE")
                    odb.dbBox_destroy(box)
                    if (x1, x2) not in full:
                        odb.dbBox_create(pin, m, x1, ylo, x2, yhi)
                        full.add((x1, x2))
                    completed += 1
        print(f"[INFO] {net_name}: {completed} cut pin boxes completed to full-height stripes")


if __name__ == "__main__":
    extend()
