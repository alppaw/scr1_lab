
set script_dir [file dirname [file normalize [info script]]]


# SCR1 repository is located elsewhere:
#   set ::SCR1_ROOT C:/path/to/scr1
if {![info exists ::SCR1_ROOT]} {
    set ::SCR1_ROOT [file normalize [file join $script_dir .. scr1_lab]]
}

proc scr1_require_file {path} {
    if {![file isfile $path]} {
        error "SCR1 source file was not found: $path"
    }
}

proc scr1_add_file_if_missing {fileset path} {
    set normalized_path [file normalize $path]
    
    set existing_file [get_files -quiet -of_objects $fileset $normalized_path]

    
    if {[llength $existing_file] == 0} {
        set same_name [get_files -quiet -of_objects $fileset *[file tail $normalized_path]]
        if {[llength $same_name] > 1} {
            error "Several project sources have the same basename as $normalized_path: $same_name"
        }
        if {[llength $same_name] == 1} {
            set existing_file $same_name
        }
    }

    if {[llength $existing_file] > 0} {
        puts "INFO: file is already in $fileset, skipping: $normalized_path"
        return $existing_file
    }

    add_files -norecurse -fileset $fileset $normalized_path
    return [get_files -quiet -of_objects $fileset $normalized_path]
}

proc scr1_add_axi_files {scr1_root} {
    if {[llength [get_projects -quiet]] == 0} {
        error "No Vivado project is open"
    }

    set scr1_root [file normalize $scr1_root]
    set src_root  [file join $scr1_root src]
    set inc_dir   [file join $src_root includes]

    if {![file isdirectory $inc_dir]} {
        error "SCR1 include directory was not found: $inc_dir"
    }

    set relative_files {
        core/pipeline/scr1_pipe_mprf.sv
        core/pipeline/scr1_pipe_lsu.sv
        core/pipeline/scr1_pipe_ifu.sv
        core/pipeline/scr1_pipe_idu.sv
        core/pipeline/scr1_pipe_ialu.sv
        core/pipeline/scr1_pipe_exu.sv
        core/pipeline/scr1_pipe_hdu.sv
        core/pipeline/scr1_pipe_csr.sv
        core/pipeline/scr1_ipic.sv
        core/pipeline/scr1_pipe_tdu.sv
        core/pipeline/scr1_pipe_top.sv
        core/primitives/scr1_cg.sv
        core/primitives/scr1_reset_cells.sv
        core/scr1_dm.sv
        core/scr1_dmi.sv
        core/scr1_scu.sv
        core/scr1_clk_ctrl.sv
        core/scr1_tapc_synchronizer.sv
        core/scr1_tapc_shift_reg.sv
        core/scr1_tapc.sv
        core/scr1_core_top.sv
        top/scr1_dp_memory.sv
        top/scr1_tcm.sv
        top/scr1_imem_router.sv
        top/scr1_dmem_router.sv
        top/scr1_mem_axi.sv
        top/scr1_timer.sv
        top/i_cache.sv
        top/d_cache.sv
        top/scr1_top_axi.sv
    }

    set rtl_files [list]
    foreach relative_file $relative_files {
        set full_path [file normalize [file join $src_root $relative_file]]
        scr1_require_file $full_path
        lappend rtl_files $full_path
    }

    set header_files [glob -nocomplain -directory $inc_dir *.svh]
    if {[llength $header_files] == 0} {
        error "No SCR1 headers were found in: $inc_dir"
    }

    set sources [get_filesets sources_1]

    foreach header_file $header_files {
        set header_obj [scr1_add_file_if_missing $sources $header_file]
        if {[llength $header_obj] > 0} {
            set_property file_type "Verilog Header" $header_obj
        }
    }

    foreach rtl_file $rtl_files {
        set rtl_obj [scr1_add_file_if_missing $sources $rtl_file]
        if {[llength $rtl_obj] > 0} {
            set_property file_type SystemVerilog $rtl_obj
            set_property used_in_synthesis true $rtl_obj
        }
    }

    set include_dirs [get_property include_dirs $sources]
    if {[lsearch -exact $include_dirs $inc_dir] < 0} {
        lappend include_dirs $inc_dir
    }
    set_property include_dirs $include_dirs $sources

    update_compile_order -fileset sources_1

   
    set synthesis_files [get_files -compile_order sources -used_in synthesis]
    foreach required_module_file {
        core/primitives/scr1_cg.sv
        core/primitives/scr1_reset_cells.sv
        core/scr1_clk_ctrl.sv
        top/scr1_top_axi.sv
    } {
        set required_path [file normalize [file join $src_root $required_module_file]]
        set found 0
        foreach synth_file $synthesis_files {
            if {[file tail $synth_file] eq [file tail $required_path]} {
                set found 1
                break
            }
        }
        if {!$found} {
            error "SCR1 file is not in the synthesis compile order: $required_path (or its imported copy)"
        }
    }

    puts "INFO: SCR1 AXI files added successfully"
    puts "INFO: SCR1 root: $scr1_root"
    puts "INFO: RTL files: [llength $rtl_files]"
    puts "INFO: Header files: [llength $header_files]"
}

scr1_add_axi_files $::SCR1_ROOT
