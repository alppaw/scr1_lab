proc vd100_require_file {path description} {
    if {![file isfile $path]} {
        error "$description was not found: $path"
    }
}

proc vd100_add_file_if_missing {fileset_name path} {
    set normalized_path [file normalize $path]
    set existing_file [get_files -quiet -all $normalized_path]

    if {[llength $existing_file] > 0} {
        puts "INFO: file is already in the project, skipping: $normalized_path"
        return $existing_file
    }

    set fileset [get_filesets $fileset_name]
    add_files -norecurse -fileset $fileset $normalized_path
    return [get_files -quiet -all $normalized_path]
}

proc vd100_add_board_sources {board_dir} {
    set sources [get_filesets sources_1]

    set top_file    [file normalize [file join $board_dir src vd100_scr1.sv]]
    set custom_file [file normalize [file join $board_dir src scr1_arch_custom.svh]]
    set base_xdc    [file normalize [file join $board_dir constraints vd100_base.xdc]]
    set ddr4_xdc    [file normalize [file join $board_dir constraints ddr4.xdc]]
    set uart_xdc    [file normalize [file join $board_dir constraints uart.xdc]]
    set bootloader  [file normalize [file join $board_dir sc_loader scbl_init32.mem]]

    vd100_require_file $top_file    "VD100 top-level source"
    vd100_require_file $custom_file "VD100 SCR1 architecture file"
    vd100_require_file $base_xdc    "VD100 button/LED constraints"
    vd100_require_file $ddr4_xdc    "Original ALINX VD100 DDR4 constraints"
    vd100_require_file $uart_xdc    "Constraints for UART"
    vd100_require_file $bootloader  "SCR1 bootloader memory image"

    set custom_obj [vd100_add_file_if_missing sources_1 $custom_file]
    set top_obj    [vd100_add_file_if_missing sources_1 $top_file]
    set_property file_type "Verilog Header" $custom_obj
    set_property file_type SystemVerilog     $top_obj
    
    set board_inc_dir [file dirname $custom_file]
    foreach fileset_name {sources_1 sim_1} {
        set fileset [get_filesets -quiet $fileset_name]
        if {[llength $fileset] == 0} {
            continue
        }

        set include_dirs [get_property include_dirs $fileset]
        set old_index [lsearch -exact $include_dirs $board_inc_dir]
        if {$old_index >= 0} {
            set include_dirs [lreplace $include_dirs $old_index $old_index]
        }
        set include_dirs [linsert $include_dirs 0 $board_inc_dir]
        set_property include_dirs $include_dirs $fileset

        set defines [get_property verilog_define $fileset]
        if {[lsearch -regexp $defines {^SCR1_ARCH_CUSTOM(=.*)?$}] < 0} {
            lappend defines SCR1_ARCH_CUSTOM=1
        }
        set_property verilog_define $defines $fileset
    }

    vd100_add_file_if_missing constrs_1 $base_xdc
    vd100_add_file_if_missing constrs_1 $ddr4_xdc
    vd100_add_file_if_missing constrs_1 $uart_xdc
    set bootloader_obj [vd100_add_file_if_missing sources_1 $bootloader]
    set_property used_in_synthesis  true $bootloader_obj
    set_property used_in_simulation true $bootloader_obj

    puts "INFO: board top: $top_file"
    puts "INFO: custom architecture: $custom_file"
    puts "INFO: bootloader memory image: $bootloader"
    puts "INFO: DDR4 pinout reused from ALINX: $ddr4_xdc"
}

set vd100_script_dir [file dirname [file normalize [info script]]]
set vd100_board_dir  [file join $vd100_script_dir boards vd100]

if {[llength [get_projects -quiet]] == 0} {
    error "No Vivado project is open"
}

set expected_part "xcve2302-sfva784-1LP-e-s"
set actual_part [get_property PART [current_project]]
if {![string equal -nocase $actual_part $expected_part]} {
    error "The open project uses '$actual_part', but the VD100 requires '$expected_part'"
}

if {[llength [get_files -quiet -all *scr1_top_axi.sv]] == 0} {
    error "scr1_top_axi.sv is not in the project. Run add_scr1_axi_files.tcl first"
}

vd100_add_board_sources $vd100_board_dir

set bd_files [get_files -quiet -all *vd100_scr1_subsystem.bd]
if {[llength $bd_files] == 0} {
    error "vd100_scr1_subsystem.bd is not in the project. Run vd100_tcl_ex.tcl first"
}
if {[llength $bd_files] > 1} {
    error "Several vd100_scr1_subsystem.bd files were found: $bd_files"
}
set bd_file [lindex $bd_files 0]

set wrapper_files [make_wrapper -files $bd_file -top]
if {[llength $wrapper_files] == 0} {
    error "make_wrapper did not return an HDL wrapper for $bd_file"
}
foreach wrapper_file $wrapper_files {
    vd100_add_file_if_missing sources_1 $wrapper_file
}

set_property top vd100_scr1 [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "INFO: block-design HDL wrapper added: $wrapper_files"
puts "INFO: synthesis top set to vd100_scr1"
