# The constraints of tt_um_lisa: LibreLane's defaults (the clock, I/O delays)
# plus the core's multi-cycle paths.  PC changes in the fetch state and what
# it reaches - the next PC, IX, RA, IA, the BF16 accumulator, the divider's
# operands - is registered only after the pre-decode and decode states, two
# or three clocks later; the TT07 build (OpenLane 2, impl.sdc) closed at
# 50 MHz with these.  The flops are found through their Q nets, which keep
# the RTL names (i_lisa_core.pc[*] ...) while the cells are numbered.
source $::env(SCRIPTS_DIR)/base.sdc

# the flops driving the nets, through any buffers synthesis or the resizer
# put between (ix is an alias of the divider's register, buffered)
proc lisa_regs {pattern} {
    set regs {}
    foreach net [get_nets $pattern] {
        set pins [get_pins -of_objects $net -filter {direction == output}]
        for {set hop 0} {$hop < 4 && [llength $pins] > 0} {incr hop} {
            set cell [get_cells -of_objects [lindex $pins 0]]
            if {[llength $cell] == 0} { break }
            if {[string match "*df*" [get_name [get_lib_cells -of_objects $cell]]]} {
                lappend regs $cell
                break
            }
            set in [get_pins -of_objects $cell -filter {direction == input}]
            if {[llength $in] == 0} { break }
            set pins [get_pins -of_objects [get_nets -of_objects [lindex $in 0]] -filter {direction == output}]
        }
    }
    return $regs
}

set pc_regs   [lisa_regs {i_lisa_core.pc[*]}]
set ix_regs   [lisa_regs {i_lisa_core.ix[*]}]
set ra_regs   [lisa_regs {i_lisa_core.ra[*]}]
set ia_regs   [lisa_regs {i_lisa_core.ia[*]}]
set facc_regs [lisa_regs {i_lisa_core.facc[*]}]
puts "lisa.sdc: pc [llength $pc_regs] ix [llength $ix_regs] ra [llength $ra_regs] ia [llength $ia_regs] facc [llength $facc_regs] registers"

# (the TT07 build also relaxed PC to the divider's operand registers; here
# the divider works in the IX and RA registers themselves)
foreach {to cycles} [list $pc_regs 3 $facc_regs 3 $ix_regs 3 $ra_regs 3 $ia_regs 3] {
    if {[llength $to] > 0} {
        set_multicycle_path $cycles -setup -from $pc_regs -to $to
        set_multicycle_path [expr {$cycles - 1}] -hold -from $pc_regs -to $to
    }
}
