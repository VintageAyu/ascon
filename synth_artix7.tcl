# ═══════════════════════════════════════════════════════════════════════════════
# Script: synth_artix7.tcl
# Purpose: Headless Vivado Batch Synthesis for NIST LWC ATHENa Benchmarking
# Target Part: xc7a12tcsg325-1 (Official GMU ATHENa Artix-7 Benchmark Silicon)
# Design: Ascon-128 2-Round Super-Round Accelerated Engine (ascon128_lwc_core)
# ═══════════════════════════════════════════════════════════════════════════════

set PART "xc7a12tcsg325-1"
set TOP  "ascon128_lwc_core"

puts "=========================================================================="
puts "  ATHENa NIST LWC BENCHMARK: ASCON-128 2-ROUND SUPER-ROUND CORE"
puts "  Target Silicon: AMD/Xilinx Artix-7 ($PART)"
puts "=========================================================================="

# Create in-memory project
create_project -in_memory -part $PART

# Read Verilog Sources
read_verilog "hardware/ascon/ascon_super_round_2r.v"
read_verilog "hardware/ascon/ascon128_lwc_core.v"

# Synthesize design Out-of-Context (preserves accurate core area without I/O pad distortion)
synth_design -top $TOP -part $PART -mode out_of_context

# Target 150 MHz (6.666 ns period)
create_clock -period 6.666 -name clk [get_ports clk]

# Physical Implementation
opt_design
place_design
route_design

# Generate Official Reports
report_utilization -file "hardware/ascon/artix7_utilization.rpt"
report_timing_summary -file "hardware/ascon/artix7_timing.rpt"

# Extract Key Performance Metrics
set luts [get_property STATS.LUT [get_designs]]
puts "\n--------------------------------------------------------------------------"
puts "  ATHENa BENCHMARK RESULTS:"
puts "  - Target: Artix-7 $PART"
puts "  - Architecture: 2-Round Fused Boundary Engine (3 cycles / 64-bit block)"
puts "  - Detailed reports saved to: hardware/ascon/artix7_*.rpt"
puts "--------------------------------------------------------------------------"

exit
