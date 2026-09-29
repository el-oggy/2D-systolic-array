`timescale 1ns / 1ps
// ============================================================================
// Package: systolic_pkg.sv
// Description: Global Parameters, Constants, and Type Definitions for 
//              the 2D Systolic Array Hardware Accelerator.
//
// Scalable Configuration:
//   - Default array dimension: N = 16 (16x16 Grid = 256 Processing Elements)
//   - Operand precision: DATA_WIDTH = 8 bits (Signed INT8)
//   - Accumulator precision: ACC_WIDTH = 16 bits (Signed INT16)
// ============================================================================

package systolic_pkg;

    // ------------------------------------------------------------------------
    // Architectural Constants
    // ------------------------------------------------------------------------
    localparam int N_DEFAULT          = 16;       // 16x16 Systolic Grid
    localparam int DATA_WIDTH_DEFAULT = 8;        // 8-bit signed operands
    localparam int ACC_WIDTH_DEFAULT  = 16;       // 16-bit accumulation width
    
    // Derived Timing Parameters for N = 16
    localparam int COMPUTE_CYCLES_16X16 = (3 * 16) - 1; // 47 clock cycles
    localparam int SKEW_DEPTH_16X16     = (2 * 16) - 1; // 31 stages
    localparam int TOTAL_PES_16X16      = 16 * 16;      // 256 PEs

    // Derived Timing Parameters for N = 8
    localparam int COMPUTE_CYCLES_8X8   = (3 * 8) - 1;  // 23 clock cycles
    localparam int SKEW_DEPTH_8X8       = (2 * 8) - 1;  // 15 stages
    localparam int TOTAL_PES_8X8        = 8 * 8;        // 64 PEs

    // Derived Timing Parameters for N = 4
    localparam int COMPUTE_CYCLES_4X4   = (3 * 4) - 1;  // 11 clock cycles
    localparam int SKEW_DEPTH_4X4       = (2 * 4) - 1;  // 7 stages
    localparam int TOTAL_PES_4X4        = 4 * 4;        // 16 PEs

    // Derived Timing Parameters for N = 2
    localparam int COMPUTE_CYCLES_2X2   = (3 * 2) - 1;  // 5 clock cycles
    localparam int SKEW_DEPTH_2X2       = (2 * 2) - 1;  // 3 stages
    localparam int TOTAL_PES_2X2        = 2 * 2;        // 4 PEs

    // ------------------------------------------------------------------------
    // Controller FSM State Type & Encodings
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] {
        STATE_IDLE    = 2'b00, // Waits for start pulse; array held in reset
        STATE_LOAD    = 2'b01, // 1 cycle: parallel loads matrices into skew buffers
        STATE_COMPUTE = 2'b10, // (3N-1) cycles: shift buffers & clock systolic mesh
        STATE_DONE    = 2'b11  // 1 cycle / holds until next start: result valid
    } fsm_state_t;

    // ------------------------------------------------------------------------
    // Helper Calculation Functions
    // ------------------------------------------------------------------------
    function automatic int get_compute_cycles(int array_size);
        return (3 * array_size) - 1;
    endfunction

    function automatic int get_skew_depth(int array_size);
        return (2 * array_size) - 1;
    endfunction

    function automatic int get_total_pes(int array_size);
        return array_size * array_size;
    endfunction

endpackage: systolic_pkg
