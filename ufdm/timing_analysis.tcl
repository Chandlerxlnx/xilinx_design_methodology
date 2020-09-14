##########################################################################################
#Author  : Lauren Gao
#Date    : 2017/11/13
#Company : Xilinx
#Description: Quickly position the potential risks in the design
##########################################################################################
#Version 2.0 -- Update logic level computing methods
#-------------- Add the option -fanout_greater_than for report_high_fanout_nets
#Version 3.0 -- Incorporate the logic level analysis for 7 series FPGAs
#---------------Optimize the scripts to reduce running time
##########################################################################################
#Setcion 01:| Check timing and create timing summary report
#Section 02:| Logic level analysis
#Section 03:| Paths start at ff and end at the control pins of blocks (BRAM/UREAM/DSP)
#Section 04:| Paths start at Blocks like BRAM, URAM and DSP48 and end at FFs
#Section 05:| Paths ends at shift register
#Section 06:| Paths with Dedicated Blocks and Macro Primitives
#Section 07:| Clock skew analysis
#Section 08:| CDC analysis
#Section 09:| Control Set analysis
#Section 10:| Congestion level analysis
#Section 11:| Complexity analysis
#Section 12:| DSP48 is used as multiplier without using MREG
#Section 13:| DSP48 is used as MAC or Adder without using PREG
#Section 14:| BRAM is used without opening output register
#Section 15:| SRLs with lower depth
#Section 16:| LUT6 (combined LUT) utilization analysis
#Section 17:| MUXF utilization analysis
#Section 18:| Latch analysis
#Section 19:| Paths crossing SLR analysis(only for post-route dcp based on SSI device)
#Section 20:| High fanout nets analysis (ug949 table 3-1)
#Section 21:| Gated clocks analysis
#Section 22:| Constraints analysis
#Section 23:| Report QoR suggestions
#Section 24:| Resource utilization analysis
##########################################################################################
#When operated at VCCINT = 0.85V, using -2LE devices,
#the speed specification for the L devices is the same as the -2I speed grade.
#When operated at VCCINT = 0.72V, the -2LE performance and static and dynamic power is reduced.
##########################################################################################
# Modify parameters below according to your requirements
##########################################################################################
set target_dcp [glob run23_routed.dcp -quiet]
set is_opt_design 0
set max_paths_neg_slack 100
set clk_skew_en 1
set max_paths_logic_level 100
set max_paths_ff2block 100
set ff2block_target_fanout 8
set ff2block_freq 300
set max_paths_bram2ff 100
set max_paths_uram2ff 100
set max_paths_dsp2ff 100
set max_paths_end_srl 100
set max_paths_block2block 100
set max_paths_mmcmi2o 100
set max_paths_mmcmo2i 100
set high_fanout_num 100
set fanout_greater_than 200
##########################################################################################
# Please DO NOT change the code below
##########################################################################################
##########################################################################################
#Sub procs
##########################################################################################
#The lowest power -1L and -2L devices, where VCCINT = 0.72V, are listed in the Vivado Design Suite as -1LV and -2LV
#respectively (DS922, page 17)
namespace eval timing_analysis {
  proc get_max_logic_level {family_end clk_freq} {
    set max_logic_level [list]
    switch -exact -- $family_end {
      "7" {if {$clk_freq <= 125} {
             set max_logic_level 15
           } elseif {$clk_freq > 125 && $clk_freq <= 250} {
             set max_logic_level 7
           } elseif {$clk_freq > 250 && $clk_freq <= 350} {
             set max_logic_level 5
           } elseif {$clk_freq > 350 && $clk_freq <= 400} {
             set max_logic_level 4
           } elseif {$clk_freq > 400 && $clk_freq <= 500} {
             set max_logic_level 3
           } else {
             set max_logic_level 2
           }
          }
      "u" {if {$clk_freq <= 125} {
             set max_logic_level 18
           } elseif {$clk_freq > 125 && $clk_freq <= 250} {
             set max_logic_level 9
           } elseif {$clk_freq > 250 && $clk_freq <= 350} {
             set max_logic_level 6
           } elseif {$clk_freq > 350 && $clk_freq <= 400} {
             set max_logic_level 5
           } elseif {$clk_freq > 400 && $clk_freq <= 500} {
             set max_logic_level 4
           } else {
             set max_logic_level 3
           }
          }
      "s" {if {$clk_freq <= 125} {
             set max_logic_level 25
           } elseif {$clk_freq > 125 && $clk_freq <= 250} {
             set max_logic_level 12
           } elseif {$clk_freq > 250 && $clk_freq <= 350} {
             set max_logic_level 8
           } elseif {$clk_freq > 350 && $clk_freq <= 400} {
             set max_logic_level 7
           } elseif {$clk_freq > 400 && $clk_freq <= 500} {
             set max_logic_level 5
           } else {
             set max_logic_level 4
           }
          }
      default {set max_logic_level "NaN"}
    }
    return $max_logic_level
  }

  proc get_max_min {listin} {
    if {[lsearch -regexp $listin {\D}] == 1} {
      puts "The list contains non-numbers"
      return -code 1
    } elseif {[lsearch -exact -real $listin] == -1} {
      set list_sort [lsort -integer -decreasing $listin]
      set list_max [lindex $list_sort 0]
      set list_min [lindex $list_sort end]
    } else {
      set list_sort [lsort -real -decreasing $listin]
      set list_max [lindex $list_sort 0]
      set list_min [lindex $list_sort end]
    }
    return [concat $list_max $list_min]
  }

  proc get_ff2block_paths {clk target_fanout used_ffs used_blocks max_paths} {
    set ff2block_ctrl_path_LL_0 [list]
    set ff2block_ctrl_path_LL_g_0 [list]
    set ff2block_ctrl_path [get_timing_paths -from $used_ffs -to $used_blocks -max $max_paths\
                           -nworst 1 -unique_pins \
                           -filter "GROUP == $clk" -quiet]
    if {[llength $ff2block_ctrl_path] > 0} {
      foreach ff2block_ctrl_path_i $ff2block_ctrl_path {
        set end_pin [get_property ENDPOINT_PIN $ff2block_ctrl_path_i]
        set end_pin_hier [split $end_pin /]
        set end_pin_last_part [lindex $end_pin_hier end]
        if {[regexp {^CE|[ABEOWR]|CA} $end_pin_last_part]} {
          set logic_level [get_property LOGIC_LEVELS $ff2block_ctrl_path_i]
          if {$logic_level == 0} {
            set net_of_path [get_nets -of $ff2block_ctrl_path_i]
            set net_fanout [get_property PIN_COUNT $net_of_path]
            set net_fanout_max [lindex [timing_analysis::get_max_min $net_fanout] 0]
            if {$net_fanout > $target_fanout} {
              lappend ff2block_ctrl_path_LL_0 $ff2block_ctrl_path_i
            }
          } else {
            lappend ff2block_ctrl_path_LL_g_0 $ff2block_ctrl_path_i
          }
        }
      }
    }
    return [list $ff2block_ctrl_path_LL_0 $ff2block_ctrl_path_LL_g_0]
  }

  proc report_critical_path {file_name critical_path} {
    set fid [open ${file_name}.csv w]
    puts $fid "#\n# File created on [clock format [clock seconds]] \n#\n"
    puts $fid "Startpoint, Endpoint, Slack, LogicLevel, #Lut, Requirement, PathDelay, LogicDelay, NetDelay, Skew, StartClk, EndClk"
    set myf "%.2f"
    foreach critical_path_i $critical_path {
      set start_point [get_property STARTPOINT_PIN $critical_path_i]
      set end_point [get_property ENDPOINT_PIN $critical_path_i]
      set req [get_property REQUIREMENT $critical_path_i]
      if {[llength $req] == 0} {
        set req inf
        set slack inf
      } else {
        set req [format $myf $req]
        set slack [get_property SLACK $critical_path_i]
        if {[llength $slack] > 0} {
          set slack [format $myf $slack]
        }
      }
      set logic_level [get_property LOGIC_LEVELS $critical_path_i]
      set num_luts [llength [get_cells -filter {REF_NAME =~ LUT*} -of $critical_path_i -quiet]]
      set path_delay [format $myf [get_property DATAPATH_DELAY $critical_path_i]]
      set logic_delay [format $myf [get_property DATAPATH_LOGIC_DELAY $critical_path_i]]
      set net_delay [format $myf [get_property DATAPATH_NET_DELAY $critical_path_i]]
      set logic_delay_percent [expr round($logic_delay/$path_delay*100)]%
      set net_delay_percent [expr round($net_delay/$path_delay*100)]%
      set logic_delay $logic_delay\($logic_delay_percent\)
      set net_delay $net_delay\($net_delay_percent\)
      set skew [get_property SKEW $critical_path_i]
      if {[llength $skew] == 0} {
        set skew inf
      } else {
        set skew [format $myf $skew]
      }
      set start_clk [get_property STARTPOINT_CLOCK $critical_path_i]
      if {[llength $start_clk] == 0} {
        set start_clk No
      }
      set end_clk [get_property ENDPOINT_CLOCK $critical_path_i]
      if {[llength $end_clk] == 0} {
        set end_clk No
      }
      puts $fid "$start_point, $end_point, $slack, $logic_level, $num_luts, $req, $path_delay,\
      $logic_delay, $net_delay, $skew, $start_clk, $end_clk"
    }
    close $fid
    puts "CSV file $file_name has been created."
  }

  proc report_target_cell {file_name target_cell} {
    set fid [open ${file_name}.csv w]
    puts $fid "#\n# File created on [clock format [clock seconds]] \n#\n"
    puts $fid "ClkName, ClkFreq, Cell"
    foreach target_cell_i $target_cell {
      set clk_pin [get_pins -of $target_cell_i -filter "NAME =~ *CLK"]
      set clk_name [get_clocks -of $clk_pin]
      set clk_period [get_property PERIOD $clk_name]
      set clk_freq [format %.2f [expr 1 / $clk_period * 1000]]
      puts $fid "$clk_name, $clk_freq, $target_cell_i"
    }
    close $fid
  }
}

##########################################################################################
namespace import timing_analysis::get_max_logic_level
namespace import timing_analysis::get_max_min
namespace import timing_analysis::get_ff2block_paths
namespace import timing_analysis::report_critical_path
namespace import timing_analysis::report_target_cell
##########################################################################################
#Open DCP
##########################################################################################
set start_open_dcp [clock format [clock seconds] -format "%s"]
open_checkpoint $target_dcp
set end_open_dcp [clock format [clock seconds] -format "%s"]
set open_dcp_elapse [clock format [expr $end_open_dcp - $start_open_dcp] -format "%H:%M:%S" -gmt true]
##########################################################################################
#Basic information about target part
##########################################################################################

set part   [get_property PART [current_design]]
set family [get_property FAMILY [get_parts $part]]
set speed  [get_property SPEED [get_parts $part]]
set slrs   [get_property SLRS [get_parts $part]]
set brams  [get_property BLOCK_RAMS [get_parts $part]]
set dsps   [get_property DSP [get_parts $part]]
set ffs    [get_property FLIPFLOPS [get_parts $part]]
set luts   [get_property LUT_ELEMENTS [get_parts $part]]
set slices [get_property SLICES [get_parts $part]]

file mkdir rpt
cd ./rpt
##########################################################################################
#Resources used in current design
##########################################################################################
set used_brams [get_cells -hier -filter "PRIMITIVE_SUBGROUP == BRAM" -quiet]
set used_dsps [get_cells -hier -filter "PRIMITIVE_SUBGROUP == DSP" -quiet]
set used_gts [get_cells -hier -filter "PRIMITIVE_SUBGROUP == GT" -quiet]
set used_ffs [get_cells -hier -filter "PRIMITIVE_SUBGROUP == SDR" -quiet]
##########################################################################################
#Section 01: Check timing and create timing summary report
##########################################################################################
report_clock_networks -name clk_networks -file clk_networks.rpt
report_timing_summary -name timing_summary -file timing_summary.rpt
set neg_slack_paths [get_timing_paths -max $max_paths_neg_slack -slack_lesser_than 0 -unique_pins]
timing_analysis::report_critical_path neg_slack_paths $neg_slack_paths
##########################################################################################
#Section 02: Logic level analysis
##########################################################################################
if {[regexp {es} $family]} {
  set family [string range $family 0 end-3]
}
set part_3_letter [string index $part 2]
set speed_len [string length $speed]
if {[string equal $part_3_letter 7] == 1} {
  if {$speed_len == 3} {
    set speed [string range $speed 0 1]
  }
  set family 7
}
if {[string index $speed end] == "L"} {
  set speed [string range $speed 0 end-1]
}
set family_end [string index $family end]
set current_clk [get_clocks]
foreach current_clk_i $current_clk {
  set period [get_property PERIOD [get_clocks $current_clk_i]]
  set freq [format "%.3f" [expr 1.0/$period*1000]]
  set max_logic_level [timing_analysis::get_max_logic_level $family_end $freq]
  if {[string equal $max_logic_level "NaN"] != 1} {
    set paths [get_timing_paths -max_paths $max_paths_logic_level \
               -filter "LOGIC_LEVELS > $max_logic_level && GROUP == $current_clk_i" -quiet]
    if {[llength $paths] > 0} {
      set timing_rpt_name ${current_clk_i}_${freq}MHz_LL_g_${max_logic_level}
      report_timing -of $paths -name $timing_rpt_name
      timing_analysis::report_critical_path $timing_rpt_name $paths
    }
  }
}
##########################################################################################
#Section 03: Paths start at ff and end at the control pins of blocks (BRAM/UREAM/DSP)
#Control pins: addr, ce, en, byte_enable, rst, cas
##########################################################################################
set ff2block_ctrl_path         [list]
set ff2block_ctrl_path_LL_0    [list]
set ff2block_ctrl_path_LL_g_0  [list]
if {$family_end == "s"} {
  set used_urams [get_cells -hier -filter "PRIMITIVE_SUBGROUP == URAM" -quiet]
  set used_urams_num [llength $used_urams]
} else {
  set used_urams [list]
  set used_urams_num 0
}
set used_blocks [list]
set used_brams_num [llength $used_brams]
set used_dsps_num [llength $used_dsps]
set block_type [list]
if {$used_brams_num > 0} {
  lappend used_blocks $used_brams
  lappend block_type bram
} elseif {$used_dsps_num > 0} {
  lappend used_blocks $used_dsps
  lappend block_type dsp
} elseif {$used_urams_num > 0} {
  lappend used_blocks $used_urams
  lappend block_type uram
}

if {[llength $used_blocks] > 0} {
  foreach current_clk_i $current_clk {
    set period [get_property PERIOD [get_clocks $current_clk_i]]
    set freq [format "%.2f" [expr 1.0/$period*1000]]
    if {$freq >= $ff2block_freq} {
      foreach used_blocks_i $used_blocks block_type_i $block_type {
        set ff2block_ctrl_path \
        [timing_analysis::get_ff2block_paths $current_clk_i $ff2block_target_fanout $used_ffs $used_blocks_i $max_paths_ff2block]
        set ff2block_ctrl_path_LL_0   [lindex $ff2block_ctrl_path 0]
        set ff2block_ctrl_path_LL_g_0 [lindex $ff2block_ctrl_path 1]
        if {[llength $ff2block_ctrl_path_LL_0] > 0} {
          set ff2block_ctrl_path_name ${current_clk_i}_${freq}MHz_ff2${block_type_i}_ctrl_path_LL_0
          report_design_analysis -of_timing_paths $ff2block_ctrl_path_LL_0 -name $ff2block_ctrl_path_name
          timing_analysis::report_critical_path $ff2block_ctrl_path_name $ff2block_ctrl_path_LL_0
        }
        if {[llength $ff2block_ctrl_path_LL_g_0] > 0} {
          set ff2block_ctrl_path_LL_g_name ${current_clk_i}_${freq}MHz_ff2${block_type_i}_ctrl_path_LL_g_0
          report_design_analysis -of_timing_paths $ff2block_ctrl_path_LL_g_0 -name $ff2block_ctrl_path_LL_g_name
          timing_analysis::report_critical_path $ff2block_ctrl_path_LL_g_name $ff2block_ctrl_path_LL_g_0
        }
      }
    }
  }
}
##########################################################################################
#Section 04: Paths start at Blocks like BRAM, URAM and DSP48 and end at FFs
##########################################################################################
if {[llength $used_brams] > 0} {
  set bram2ff_path [get_timing_paths -from $used_brams -max $max_paths_bram2ff -nworst 1 -unique_pins -quiet]
  if {[llength $bram2ff_path] > 0} {
    report_design_analysis -of_timing_paths $bram2ff_path
    timing_analysis::report_critical_path bram2ff $bram2ff_path
  }
}
if {$family_end == "s"} {
  if {$used_urams_num > 0} {
    set uram2ff_path [get_timing_paths -from $used_urams -max $max_paths_uram2ff -nworst 1 -unique_pins -quiet]
    if {[llength $uram2ff_path] > 0} {
      report_design_analysis -of_timing_paths $uram2ff_path
      timing_analysis::report_critical_path uram2ff $uram2ff_path
    }
  }
}
if {[llength $used_dsps] > 0} {
  set dsp2ff_path [get_timing_paths -from $used_dsps -max $max_paths_dsp2ff -nworst 1 -unique_pins -quiet]
  if {[llength $dsp2ff_path] > 0} {
    report_design_analysis -of_timing_paths $dsp2ff_path
    timing_analysis::report_critical_path dsp2ff $dsp2ff_path
  }
}
##########################################################################################
#Section 05: Paths ends at shift register
#ug949 -> C5 -> Analyzing and Resolving -> Reducing logic delay | page 207
##########################################################################################
set srl [get_cells -hier -filter {IS_PRIMITIVE && REF_NAME =~ SRL*} -quiet]
if {[llength $srl] > 0} {
  set paths_end_srl [get_timing_paths -to $srl -max_paths $max_paths_end_srl -quiet]
} else {
  set paths_end_srl [list]
}

if {[llength $paths_end_srl] > 0} {
  report_timing -of $paths_end_srl -name paths_end_srl
  timing_analysis::report_critical_path paths_end_srl $paths_end_srl
}
##########################################################################################
#Section 06: Paths with Dedicated Blocks and Macro Primitives
#ug949 -> C5 -> Analyzing and Resolving -> Reducing logic delay | page 208
##########################################################################################
set used_gts_num [llength $used_gts]
if {$used_gts_num > 0} {lappend used_blocks $used_gts}
set paths_block2block [get_timing_paths -from $used_blocks -to $used_blocks -max_paths $max_paths_block2block -quiet]
if {[llength $paths_block2block] > 0} {
  report_timing -of $paths_block2block -name paths_block2block
  timing_analysis::report_critical_path paths_block2block $paths_block2block
}

##########################################################################################
#Section 07: Clock skew analysis
#Ug949 -> C5 -> Analyzing and Resolving -> Reducing Clock Skew | page 218
#Scenario 1:
#Synchronous CDC Paths with Common Nodes on Input and Output of a MMCM
#clkin ---> BUFGCE --Disable LUT Combining and MUXF Inference--------> FF | Synchronous Elements
#                   |                                          ^   .
#                   |                                          |   |
#                   |                                          .   ^
#                   |-> CLKIN1 --> MMCM --> BUFGCE --> FF | Synchronous Elements
#Solution:
#(1) Xilinx recommends limiting the number of synchronous clock domain crossing paths even
#    when clock skew is acceptable
#(2) Also, when skew is abnormally high and cannot be reduced, Xilinx recommends treating
#    these paths as asynchronous by implementing asynchronous clock domain crossing
#    circuitry and adding timing exceptions
##########################################################################################
set used_clk_module [get_cells -hier -filter "PRIMITIVE_SUBGROUP == PLL" -quiet]
if {[llength $used_clk_module] > 0} {
  foreach used_clk_module_i $used_clk_module {
    set clkin_pin [get_pins -of $used_clk_module_i -filter "REF_PIN_NAME == CLKIN1"]
    set clkin [get_clocks -of $clkin_pin]
    set clkout_pin [get_pins -of $used_clk_module_i -filter "IS_CONNECTED == 1 && REF_PIN_NAME =~ CLKOUT*"]
    foreach clkout_pin_i $clkout_pin {
      set clkout [get_clocks -of $clkout_pin_i]
      set path_mmcmi2o [get_timing_paths -from $clkin -to $clkout -max_paths $max_paths_mmcmi2o -quiet]
      set path_mmcmo2i [get_timing_paths -from $clkout -to $clkin -max_paths $max_paths_mmcmo2i -quiet]
      set path_mmcmio [concat $path_mmcmi2o $path_mmcmo2i]
      if {[llength $path_mmcmio] > 0} {
        report_timing -of $path_mmcmio -name paths_${clkin}_Between_${clkout}
        timing_analysis::report_critical_path paths_${clkin}_Between_${clkout} $path_mmcmio
      }
    }
  }
}
##########################################################################################
#Section 08: CDC analysis
##########################################################################################
report_clock_interaction -name clk_inter -file clk_inter.rpt
report_cdc -name cdc -file cdc.rpt
##########################################################################################
#Section 09: Control Set analysis
#Guidelines: ug949 Table 5-9
#Solution:
#(1) Remove the MAX_FANOUT attributes that are set on control signals in the HDL sources
#or constraint files. Replication on control signals will dramatically increase the number
#of unique control sets. Xilinx recommends manual replication based on hierarchy in the
#RTL, where replicated drivers are preserved with a KEEP attribute.
#(2) Increase the control set threshold of Vivado synthesis (or other FPGA synthesis tool).
#For example: synth_design -control_set_opt_threshold 16
#(3) Avoid low fanout asynchronous set/reset (preset/clear), as they can only be connected
#to dedicated asynchronous pins and cannot be moved to the datapath by synthesis. For
#this reason, the synthesis control set threshold option does not apply to asynchronous
#set/reset.
#(4) Avoid using both active high and low of a control signal for different sequential cells.
#(5) Only use clock enable and set/reset when necessary.
##########################################################################################
set ctrl_set_rpt [report_control_sets -return_string]
puts $ctrl_set_rpt
set ctrl_set_rpt_new  [split $ctrl_set_rpt \n]
set target [lsearch -all -regexp $ctrl_set_rpt_new {Number of unique control sets}]
puts [lindex $ctrl_set_rpt_new $target]
set target_line [lindex $ctrl_set_rpt_new $target]
set uni_ctrl_sets [regexp -inline -all {[0-9]+} $target_line]
set uni_percentage [expr double($uni_ctrl_sets) / double($slices)]
set uni_pf [format "%.3f" $uni_percentage]
set uni_ph [format "%.1f" [expr $uni_pf*100]]%
if {$uni_pf <= 0.075} {
  puts "Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Acceptable"
} elseif {$uni_pf > 0.075 && $uni_pf < 0.15} {
  set ctrl_set_fid [open ./ctrl_set.rpt w]
  puts $ctrl_set_fid \
  "Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Noted"
  close $ctrl_set_fid
} elseif {$uni_pf >= 0.15 && $uni_pf < 0.25} {
  set ctrl_set_fid [open ./ctrl_set.rpt w]
  puts $ctrl_set_fid \
  "Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Analysis Required"
  close $ctrl_set_fid
} else {
  puts "Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Recommended Design Change"
  set ctrl_set_fid [open ./ctrl_set.rpt w]
  puts $ctrl_set_fid "Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Recommended Design Change"
  close $ctrl_set_fid
}
##########################################################################################
#Section 10: Congestion level analysis
#ug949 -> C5 -> Analyzing and Resolving -> Reducing Net delay | page 209
##########################################################################################
report_design_analysis -congestion -name cong_level -file cong_level.rpt
##########################################################################################
#Section 11: Complexity analysis
#ug949 -> C5 -> Analyzing and Resolving -> Reducing Net delay | page 214
#The Complexity Report shows the Rent Exponent, Average Fanout, and distribution per type
#of leaf cells for the top-level and/or for hierarchical cells. The Rent exponent is the
#relationship between the number of ports and the number of cells of a netlist partition
#when recursively partitioning the design with a min-cut algorithm
#Use the -hierarchical_depth option to refine the analysis to include the lower-level modules
##########################################################################################
report_design_analysis -complexity -name complexity_rpt
##########################################################################################
#Section 12: DSP48 is used as multiplier without using MREG
##########################################################################################
set dsp48_no_mreg [get_cells -hier -filter \
{REF_NAME =~ DSP48E* && USE_MULT != NONE && MREG == 0}]
set dsp48_no_mreg_num [llength $dsp48_no_mreg]
if {$dsp48_no_mreg_num > 0} {
  show_objects -name dsp48_mreg_0 -object $dsp48_no_mreg
  timing_analysis::report_target_cell dsp48_no_mreg $dsp48_no_mreg
}
##########################################################################################
#Section 13: DSP48 is used as MAC or Adder without using PREG
##########################################################################################
set dsp48_no_preg [get_cells -hier -filter \
{REF_NAME =~ DSP48E* && PREG == 0}]
set dsp48_no_preg_num [llength $dsp48_no_preg]
if {$dsp48_no_preg_num > 0} {
  show_objects -name dsp48_preg_0 -object $dsp48_no_preg
  timing_analysis::report_target_cell dsp48_no_preg $dsp48_no_preg
}
##########################################################################################
#Section 14: BRAM is used without opening output register
##########################################################################################
set bram_no_reg [list]
set fid [open bram_no_reg.csv w]
puts $fid "#\n# File created on [clock format [clock seconds]] \n#\n"
puts $fid "BRAM, CLKA, CLKA_FREQ, CLKB, CLKB_FREQ, DOA_REG, DOA_CONNECTED, DOB_REG, DOB_CONNECTED"
foreach used_bram_i $used_brams {
  set douta_pin [get_pins -of $used_bram_i -filter "NAME =~ *DOUTADOUT* || NAME =~ *DOADO*"]
  set doutb_pin [get_pins -of $used_bram_i -filter "NAME =~ *DOUTBDOUT* || NAME =~ *DOBDO*"]
  set clka_pin  [get_pins -of $used_bram_i -filter "NAME =~ *CLKARDCLK*"]
  set clkb_pin  [get_pins -of $used_bram_i -filter "NAME =~ *CLKBWRCLK*"]
  set clka_net  [get_nets -of $clka_pin]
  set clkb_net  [get_nets -of $clkb_pin]
  if {[get_property TYPE $clka_net] == "GLOBAL_CLOCK"} {
    set clka [get_clocks -of $clka_pin]
    set clka_period [get_property PERIOD $clka]
    set clka_freq [format "%.2f" [expr 1.0/$clka_period*1000]]
  } else {
    set clka_freq 0
  }
  if {[get_property TYPE $clkb_net] == "GLOBAL_CLOCK"} {
    set clkb [get_clocks -of $clkb_pin]
    set clkb_period [get_property PERIOD $clkb]
    set clkb_freq [format "%.2f" [expr 1.0/$clkb_period*1000]]
  } else {
    set clkb_freq 0
  }
  set doa_reg [get_property DOA_REG $used_bram_i]
  set dob_reg [get_property DOB_REG $used_bram_i]
  set douta_pin_status [timing_analysis::get_max_min [get_property IS_CONNECTED $douta_pin]]
  set douta_pin_connect [lindex $douta_pin_status 0]
  set doutb_pin_status [timing_analysis::get_max_min [get_property IS_CONNECTED $doutb_pin]]
  set doutb_pin_connect [lindex $doutb_pin_status 0]
  if {($douta_pin_connect == 1 && $doa_reg == 0) || ($doutb_pin_connect == 1 && $dob_reg == 0)} {
    puts $fid "$used_bram_i, $clka, $clka_freq, $clkb, $clkb_freq, $doa_reg, $douta_pin_connect, \
    $dob_reg, $doutb_pin_connect"
    lappend bram_no_reg $used_bram_i
  }
}
close $fid
show_objects -name bram_no_reg -object $bram_no_reg
##########################################################################################
#Section 15: SRLs with lower depth
##########################################################################################
set srl1 [get_cells -hier -filter {IS_PRIMITIVE && REF_NAME =~ SRL* && (NAME =~ *_srl1)}]
set srl2 [get_cells -hier -filter {IS_PRIMITIVE && REF_NAME =~ SRL* && (NAME =~ *_srl2)}]
set srl3 [get_cells -hier -filter {IS_PRIMITIVE && REF_NAME =~ SRL* && (NAME =~ *_srl3)}]
set srl1_len [llength $srl1]
set srl2_len [llength $srl2]
set srl3_len [llength $srl3]
if {$srl1_len > 1} {
  show_objects -name SRL1_${srl1_len} -object $srl1
}
if {$srl2_len > 1} {
  show_objects -name SRL2_${srl2_len} -object $srl2
}
if {$srl3_len > 1} {
  show_objects -name SRL3_${srl3_len} -object $srl3
}
##########################################################################################
#Section 16: LUT6 (combined LUT) utilization analysis
#Disable LUT Combining and MUXF Inference: page 233 ug949
##########################################################################################
set lut6 [get_cells -hier -filter {REF_NAME =~ LUT* && SOFT_HLUTNM != ""}]
set used_lut6 [llength $lut6]
if {$used_lut6 > 0} {
  set used_lut6_percent [expr double($used_lut6)/double($luts)]
  if {$used_lut6_percent > 0.15} {
    show_objects -name lut6_${used_lut6}
    close $lut6_fid
  }
  set used_lut6_percent [expr round($used_lut6_percent*100)]%
}

##########################################################################################
#Section 17: MUXF utilization analysis
##########################################################################################
set used_muxfs [get_cells -hier -filter "PRIMITIVE_SUBGROUP == MUXF" -quiet]
set num_used_muxfs [llength $used_muxfs]
set num_muxfs [expr $slices * 7]
if {$num_used_muxfs > 0} {
  set used_muxfs_percent [expr round(double($num_used_muxfs)/double($num_muxfs)*100)]%
  show_objects $used_muxfs -name used_muxf_${num_used_muxfs}_${used_muxfs_percent}
} else {
  set used_muxfs_percent 0.0%
}
##########################################################################################
#Section 18: Latch analysis
##########################################################################################
set used_latch [get_cells -hierarchical -filter { PRIMITIVE_TYPE =~ FLOP_LATCH.latch.* } -quiet]
set used_latch_num [llength $used_latch]
if {$used_latch_num > 1} {
  show_objects -name latch_${used_latch_num}
}
##########################################################################################
#Section 19: Paths crossing SLR analysis
##########################################################################################
set slr_num [llength $slrs]
if {$is_opt_design == 0 && $slr_num > 1} {
  set slr_list [get_timing_paths -max 100 -slack_lesser_than 0 -filter \
  {INTER_SLR_COMPENSATION != ""}]
} else {
  set slr_list [list]
}
if {[llength $slr_list] > 0} {
  report_timing -of $slr_list -name failing_slrs -file failing_slr_timing_paths.rpt
  timing_analysis::report_critical_path failing_slr $slr_list
}
##########################################################################################
#Section 20: High fanout nets analysis (ug949 table 3-1)
##########################################################################################
report_high_fanout_nets -max 100 -name fanout_nets \
-fanout_greater_than $fanout_greater_than -file high_fanout_nets.rpt
##########################################################################################
#Section 21: Gated clocks analysis
##########################################################################################
report_drc -check PLHOLDVIO-2 -name gated_clk -file gated_clk.rpt
##########################################################################################
#Section 22: Constraints analysis
##########################################################################################
write_xdc -force -constraints invalid ./invalid_constraints.xdc
report_exceptions -ignored -file ./ignored_exceptions.xdc
report_exceptions -ignored_objects -file ./ignored_objects_exceptions.xdc
report_exceptions -write_merged_exceptions -file ./merged_exceptions.xdc
##########################################################################################
#Section 23: Report QoR suggestions
##########################################################################################
file mkdir qor
report_qor_suggestions -output_dir ./qor
report_methodology -name ufdm -file ufdm.rpt
##########################################################################################
#Section 24: Resource utilization analysis
##########################################################################################
report_utilization -name util -file utilization.rpt
##########################################################################################
#Final report
##########################################################################################
set end_analysis [clock format [clock seconds] -format "%s"]
set analysis_elapse [clock format [expr $end_analysis - $end_open_dcp] -format "%H:%M:%S" -gmt true]
set total_elapse [clock format [expr $end_analysis - $start_open_dcp] -format "%H:%M:%S" -gmt true]
array set Summary {}
set Summary(0.) "##################################################################################"
if {$uni_pf <= 0.075} {
  set Summary(1.) " Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Acceptable"
} elseif {$uni_pf > 0.075 && $uni_pf < 0.15} {
  set Summary(1.) " Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Noted"
} elseif {$uni_pf >= 0.15 && $uni_pf < 0.25} {
  set Summary(1.) " Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Analysis Required"
} else {
  set Summary(1.) " Number of unique control sets: $uni_ctrl_sets --> $uni_ph --> Recommended Design Change"
}
set Summary(2.) " LUT6 utilization: $used_lut6_percent"
set Summary(3.) " MUXF utilization: $used_muxfs_percent"
set Summary(4.) " Time duration for opening DCP: $open_dcp_elapse"
set Summary(5.) " Time duration for analysis: $analysis_elapse"
set Summary(6.) " Time duration for entire process: $total_elapse"
set Summary(7.) "##################################################################################"
set file_name Summary
set fid [open $file_name.rpt w]
set array_length [array size Summary]
for {set i 0} {$i < $array_length} {incr i} {
  puts -nonewline $fid ${i}.
  puts $fid "$Summary($i.)"
}
close $fid
parray Summary
cd ..
