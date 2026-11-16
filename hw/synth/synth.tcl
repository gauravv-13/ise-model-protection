# Genus synthesis of one block at TSMC 65 nm LP, typical corner.
# Called by scripts/synth.sh, which sets these environment variables:
#   SYN_LIB      Liberty file          SYN_TOP     top module
#   SYN_FILES    file with one source per line (packages first)
#   SYN_INCDIRS  space-separated include folders
#   SYN_DEFINES  space-separated defines (SYNTHESIS is always set)
#   SYN_PERIOD   clock period in ns    SYN_OUT     output folder
set out    $env(SYN_OUT)
set top    $env(SYN_TOP)
set period $env(SYN_PERIOD)                       ;# ns, the library time unit

set_db max_cpus_per_server 4
set_db information_level 1
set_db init_hdl_search_path $env(SYN_INCDIRS)
# Memory macros (CVA6 cache SRAMs) are left out of the file list on purpose:
# they stay black boxes and are not part of the logic area.
set_db hdl_error_on_blackbox false
read_libs $env(SYN_LIB)

set fh [open $env(SYN_FILES)]
set files [split [string trim [read $fh]] "\n"]
close $fh
read_hdl -sv -define [concat SYNTHESIS $env(SYN_DEFINES)] $files
elaborate $top
check_design -unresolved > $out/check_design.rpt

# One clock; inputs and outputs get 20% of the period each (registered on both
# sides in the real design).
create_clock -name clk -period $period [get_ports clk_i]
set ins [remove_from_collection [all_inputs] [get_ports {clk_i clk_edn_i}]]
set_input_delay  [expr {0.2 * $period}] -clock clk $ins
set_output_delay [expr {0.2 * $period}] -clock clk [all_outputs]
if {[llength [get_ports -quiet clk_edn_i]]} {
    create_clock -name clk_edn -period $period [get_ports clk_edn_i]
}

syn_generic
syn_map
syn_opt

report_area -depth 4 > $out/area.rpt
report_gates  > $out/gates.rpt
report_timing > $out/timing.rpt
report_qor    > $out/qor.rpt
exit
