# Convenience entry point for the actual PS/DMA-based PYNQ-Z2 implementation.
# This runs the full synthesis, implementation, and bitstream flow.
set script_dir [file dirname [info script]]
source [file join $script_dir create_system.tcl]

