# ============================================================
#  vivado_synth.tcl
#  Vivado synthesis comparison: baseline vs operand-isolated
#
#  Target : Genesys-2  (Kintex-7  xc7k325tffg900-2)
#  Usage  : vivado -mode batch -source vivado_synth.tcl
# ============================================================

# NOTE: Genesys-2 uses xc7k325tffg900-2. That device is not in
# every Vivado install. xc7k160tffg676-2 is the same Kintex-7
# family with identical primitives (LUT6, FDCE, CARRY4), so the
# LUT/FF/CARRY comparison below transfers directly to the 325T.
set PART   "xc7k160tffg676-2"
set RTLDIR [file normalize [file join [file dirname [info script]] .. rtl]]
set OUTDIR [file normalize [file dirname [info script]]]

proc run_synth {name srcfile topmod part outdir} {
    puts "\n============================================"
    puts "  SYNTHESIZING: $name  (top = $topmod)"
    puts "============================================"

    read_verilog $srcfile
    synth_design -top $topmod -part $part -flatten_hierarchy none

    report_utilization -file [file join $outdir "util_$name.rpt"]

    set luts [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]]
    set ffs  [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]
    set crn  [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == CARRY}]]
    set mux  [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == MUXF}]]

    puts "RESULT|$name|LUT=$luts|FF=$ffs|CARRY=$crn|MUXF=$mux"

    report_timing_summary -file [file join $outdir "timing_$name.rpt"]

    close_design
    return [list $luts $ffs $crn $mux]
}

set r1 [run_synth "baseline" \
    [file join $RTLDIR clock_gated_alu.v] \
    "clock_gated_alu_top" $PART $OUTDIR]

set r2 [run_synth "isolated" \
    [file join $RTLDIR clock_gated_alu_isolated.v] \
    "alu_isolated" $PART $OUTDIR]

puts "\n============================================"
puts "  VIVADO SYNTHESIS COMPARISON"
puts "  Part: $PART (Genesys-2 / Kintex-7)"
puts "============================================"
puts [format "%-10s %8s %8s %8s %8s" "Design" "LUT" "FF" "CARRY" "MUXF"]
puts [format "%-10s %8d %8d %8d %8d" "Baseline" \
     [lindex $r1 0] [lindex $r1 1] [lindex $r1 2] [lindex $r1 3]]
puts [format "%-10s %8d %8d %8d %8d" "Isolated" \
     [lindex $r2 0] [lindex $r2 1] [lindex $r2 2] [lindex $r2 3]]
puts [format "%-10s %+8d %+8d %+8d %+8d" "Delta" \
     [expr {[lindex $r2 0]-[lindex $r1 0]}] \
     [expr {[lindex $r2 1]-[lindex $r1 1]}] \
     [expr {[lindex $r2 2]-[lindex $r1 2]}] \
     [expr {[lindex $r2 3]-[lindex $r1 3]}]]
puts "============================================"

exit
