# The tile's PDN (LibreLane's default pdn_cfg.tcl) plus one more met4 stripe
# on each power pin column of every hard macro that does not already lie on a
# tile stripe (PDN_VOFFSET / PDN_VPITCH / PDN_VSPACING, the offset being the
# centre of the first stripe).  pdngen gives these stripes its via arrays down
# to the rails like the tile's own and trims them around the macro, as it does
# the others; Tile.ExtendPowerStripes (odb_stripes.py) then draws each column
# full height over the macro, which is what joins the macro pin to the stripe.
# Without this the two VGND columns of the RAM32 macro were an island with the
# macro pin (the IR-drop step's check_power_grid failed) and VPWR hung on a
# 0.57 um overlap of one column with a tile stripe.
source $::env(SCRIPTS_DIR)/openroad/common/pdn_cfg.tcl

set block [ord::get_db_block]
set core [$block getCoreArea]
set dbu [$block getDbUnitsPerMicron]
set layer $::env(PDN_VERTICAL_LAYER)
set width $::env(PDN_VWIDTH)
set pitch $::env(PDN_VPITCH)
set core_x [expr {[$core xMin] / double($dbu)}]
set first_vdd [expr {$core_x + $::env(PDN_VOFFSET)}]
set first_gnd [expr {$first_vdd + $width + $::env(PDN_VSPACING)}]
set extra_args [list]
append_if_equals extra_args PDN_EXTEND_TO "core_ring" -extend_to_core_ring
append_if_equals extra_args PDN_EXTEND_TO "boundary" -extend_to_boundary

foreach inst [$block getInsts] {
    set master [$inst getMaster]
    if { ![$master isBlock] } { continue }
    if { [$inst getOrient] ne "R0" } {
        puts "\[WARNING\] pdn_macro: [$inst getName] is not placed R0, its pin columns are not computed"
        continue
    }
    set bbox [$inst getBBox]
    foreach net [list $::env(VDD_NET) $::env(GND_NET)] first [list $first_vdd $first_gnd] {
        set mterm [$master findMTerm $net]
        if { $mterm == "NULL" } { continue }
        foreach mpin [$mterm getMPins] {
            foreach box [$mpin getGeometry] {
                if { [[$box getTechLayer] getName] ne $layer } { continue }
                set cx [expr {([$bbox xMin] + ([$box xMin] + [$box xMax]) / 2.0) / double($dbu)}]
                set k [expr {round(($cx - $first) / $pitch)}]
                set off [expr {abs($cx - ($first + $k * $pitch))}]
                if { $off < $width } {
                    puts "\[INFO\] pdn_macro: [$inst getName] $net column at [format %.3f $cx] um lies on a tile stripe ([format %.3f $off] um off), nothing added"
                    continue
                }
                # pdngen silently drops a strap that comes closer than about 1 um
                # to a tile stripe of the other net (met4 spacing is 0.3; straps
                # 0.37 and 0.6 um away were dropped, 1.0 um was kept; a RAM32 VGND
                # column sits 0.37 um from a VPWR stripe): move it away, up to half
                # its width, so it still overlaps the full-height stripe the
                # extension step draws over the pin column
                set sx $cx
                set other_first [expr {$net eq $::env(VDD_NET) ? $first_gnd : $first_vdd}]
                set ko [expr {round(($cx - $other_first) / $pitch)}]
                set other [expr {$other_first + $ko * $pitch}]
                set want [expr {$width + 1.0}]
                if { abs($cx - $other) < $want } {
                    set shift [expr {$want - abs($cx - $other)}]
                    if { $shift > $width / 2.0 } { set shift [expr {$width / 2.0}] }
                    set sx [expr {$cx > $other ? $cx + $shift : $cx - $shift}]
                    puts "\[INFO\] pdn_macro: column at [format %.3f $cx] um is [format %.3f [expr {abs($cx - $other) - $width}]] um from a tile stripe of the other net, stripe moved to [format %.3f $sx] um"
                }
                set offset [format %.3f [expr {$sx - $core_x}]]
                puts "\[INFO\] pdn_macro: [$inst getName] $net column at [format %.3f $cx] um ([format %.3f $off] um off the nearest tile stripe): stripe at offset $offset"
                add_pdn_stripe -grid stdcell_grid -layer $layer -width $width -pitch $pitch \
                    -offset $offset -number_of_straps 1 -nets $net {*}$extra_args
            }
        }
    }
}
