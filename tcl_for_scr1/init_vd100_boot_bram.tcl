# Prepare the VD100 Boot BRAM initialization before synthesis.
#
# Run this script after:
#   1. add_scr1_axi_files.tcl
#   2. vd100_tcl_ex.tcl
#   3. add_vd100_custom_files.tcl
#
# The Embedded Memory Generator resets MEMORY_INIT_FILE to NONE in the Block
# Design.  Therefore this script generates the IP output products and patches
# the C_MEMORY_INIT_FILE parameter in the generated synthesis HDL.  It does not
# launch synthesis, implementation or device-image generation.

proc vd100_read_file {path} {
    set channel [open $path r]
    set contents [read $channel]
    close $channel
    return $contents
}

proc vd100_write_file {path contents} {
    set channel [open $path w]
    puts -nonewline $channel $contents
    close $channel
}

proc vd100_check_bootloader_mem {mem_file expected_words reset_word_index} {
    if {![file isfile $mem_file]} {
        error "Bootloader memory file was not found: $mem_file"
    }

    set contents [vd100_read_file $mem_file]
    set words [list]
    set line_number 0

    foreach line [split $contents "\n"] {
        incr line_number
        set word [string trim $line]
        if {$word eq ""} {
            continue
        }
        if {![regexp {^[0-9a-fA-F]{8}$} $word]} {
            error "Invalid 32-bit hexadecimal word in $mem_file at line $line_number: '$word'"
        }
        lappend words $word
    }

    if {[llength $words] != $expected_words} {
        error "Bootloader image has [llength $words] words; expected $expected_words: $mem_file"
    }

    set reset_word [lindex $words $reset_word_index]
    if {$reset_word eq "00000000"} {
        error "Bootloader reset-vector word is zero at index 0x[format %X $reset_word_index]"
    }

    puts "INFO: bootloader image checked: $mem_file"
    puts "INFO: bootloader words: [llength $words]"
    puts "INFO: reset-vector word at 0x[format %X $reset_word_index]: $reset_word"
}

proc vd100_patch_init_parameter {hdl_file mem_file required} {
    if {![file isfile $hdl_file]} {
        if {$required} {
            error "Generated Boot BRAM synthesis HDL was not found: $hdl_file"
        }
        puts "INFO: optional generated Boot BRAM HDL is absent, skipping: $hdl_file"
        return
    }

    set contents [vd100_read_file $hdl_file]
    set pattern {\.C_MEMORY_INIT_FILE[ \t]*\([ \t]*"[^"]*"[ \t]*\)}
    set mem_file [string map {\\ /} [file normalize $mem_file]]
    set replacement ".C_MEMORY_INIT_FILE(\"$mem_file\")"
    set replacements [regsub -all $pattern $contents $replacement patched_contents]

    if {$replacements != 1} {
        error "Expected one C_MEMORY_INIT_FILE parameter in $hdl_file, found $replacements"
    }

    vd100_write_file $hdl_file $patched_contents

    set verification [vd100_read_file $hdl_file]
    if {[string first $replacement $verification] < 0} {
        error "Boot BRAM initialization parameter verification failed: $hdl_file"
    }

    puts "INFO: Boot BRAM initialization patched: $hdl_file"
}

if {[llength [get_projects -quiet]] == 0} {
    error "No Vivado project is open"
}

set expected_part "xcve2302-sfva784-1LP-e-s"
set actual_part [get_property PART [current_project]]
if {![string equal -nocase $actual_part $expected_part]} {
    error "The open project uses '$actual_part', but the VD100 requires '$expected_part'"
}

set script_dir [file dirname [file normalize [info script]]]
set mem_file [file normalize [file join $script_dir boards vd100 sc_loader scbl_init32.mem]]
set bd_name "vd100_scr1_subsystem"
set boot_ip_name "${bd_name}_boot_bram_0"

# 64 KiB / 4 bytes = 16384 words.  SCR1 starts at 0xFFFFFF00 inside the
# 0xFFFF0000..0xFFFFFFFF Boot BRAM, hence local word index 0xFF00 / 4 = 0x3FC0.
vd100_check_bootloader_mem $mem_file 16384 0x3FC0

set mem_objects [get_files -quiet -all *scbl_init32.mem]
if {[llength $mem_objects] == 0} {
    error "scbl_init32.mem is not in the project. Run add_vd100_custom_files.tcl first"
}

set bd_files [get_files -quiet -all *${bd_name}.bd]
if {[llength $bd_files] != 1} {
    error "Expected one ${bd_name}.bd in the project, found [llength $bd_files]: $bd_files"
}
set bd_file [lindex $bd_files 0]

set wrapper_files [get_files -quiet -all *${bd_name}_wrapper.v]
if {[llength $wrapper_files] != 1} {
    error "Expected one ${bd_name}_wrapper.v in the project. Run add_vd100_custom_files.tcl first"
}
set bd_wrapper [file normalize [lindex $wrapper_files 0]]

# Refresh generated IP HDL. This may restore C_MEMORY_INIT_FILE to NONE, which
# is why the patch is deliberately applied after generate_target.
generate_target all $bd_file

set bd_gen_dir [file dirname [file dirname $bd_wrapper]]
set synth_hdl [file join $bd_gen_dir ip $boot_ip_name synth ${boot_ip_name}.v]
set sim_hdl   [file join $bd_gen_dir ip $boot_ip_name sim   ${boot_ip_name}.sv]

vd100_patch_init_parameter $synth_hdl $mem_file 1
vd100_patch_init_parameter $sim_hdl   $mem_file 0

# A previously completed OOC run contains the old memory contents. Reset only
# this IP run so the next top-level synthesis rebuilds it from the patched HDL.
set boot_ooc_runs [get_runs -quiet ${boot_ip_name}_synth_1]
if {[llength $boot_ooc_runs] > 0} {
    reset_run $boot_ooc_runs
    puts "INFO: reset stale Boot BRAM OOC run: $boot_ooc_runs"
}

puts "INFO: VD100 Boot BRAM preparation completed"
puts "INFO: you may now run synthesis, implementation and write_device_image"
