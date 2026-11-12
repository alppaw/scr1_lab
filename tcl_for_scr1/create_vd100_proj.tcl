
set script_dir [file dirname [file normalize [info script]]]

set part "xcve2302-sfva784-1LP-e-s"

set proj_name "vd100_scr1"

set proj_dir "./$proj_name"

create_project -name $proj_name -dir $proj_dir -part $part

source [file join $script_dir add_scr1_axi_files.tcl]
source [file join $script_dir vd100_tcl_ex.tcl]
source [file join $script_dir add_vd100_custom_files.tcl]
source [file join $script_dir init_vd100_boot_bram.tcl]

