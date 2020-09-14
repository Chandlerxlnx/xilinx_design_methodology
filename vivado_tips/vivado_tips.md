# vivado tips

Content

[TOC]

# vivado enable Engineering sample in vivado #
  * creat file `vivado_init.tcl` in folder \<PATH TO VIVADO\>\scripts.
  * the file include enable_beta_devices command, example script as below
  ```TCL
  # file: vivado_init.tcl
  enable_beta_devices xc*
  ```
# Implementation # 
## ==opt_design tips== ##
- merging control set
  >opt_design -control_set_merge followed by opt_design -hier_fanout_limit 512.
- replication
  > opt_design -
  
## ==place_design tips== ##

## ==post place phys_opt_design tips== ##

## ==route_design== ##

#Timing#


## overtemp protect ##

* cmd: set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN ENABLE [current_design]