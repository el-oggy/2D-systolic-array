// ============================================================================
// Header: systolic_constants.vh
// Description: Global Preprocessor Constants & Parameter Defaults for 
//              the 2D Systolic Array Hardware Accelerator.
// ============================================================================

`ifndef SYSTOLIC_CONSTANTS_VH
`define SYSTOLIC_CONSTANTS_VH

// Matrix & Grid Defaults (Scaled to 16x16)
`define DEFAULT_N            16
`define DEFAULT_DATA_WIDTH   8
`define DEFAULT_ACC_WIDTH    16

// 16x16 Timing Constants
`define COMPUTE_CYCLES_16X16 47   // 3 * 16 - 1
`define SKEW_DEPTH_16X16     31   // 2 * 16 - 1
`define TOTAL_PES_16X16      256  // 16 * 16

// 8x8 Timing Constants
`define COMPUTE_CYCLES_8X8   23   // 3 * 8 - 1
`define SKEW_DEPTH_8X8       15   // 2 * 8 - 1
`define TOTAL_PES_8X8        64   // 8 * 8

// 4x4 Timing Constants
`define COMPUTE_CYCLES_4X4   11   // 3 * 4 - 1
`define SKEW_DEPTH_4X4       7    // 2 * 4 - 1
`define TOTAL_PES_4X4        16   // 4 * 4

// 2x2 Timing Constants
`define COMPUTE_CYCLES_2X2   5    // 3 * 2 - 1
`define SKEW_DEPTH_2X2       3    // 2 * 2 - 1
`define TOTAL_PES_2X2        4    // 2 * 2

// FSM State Encodings
`define STATE_IDLE           2'b00
`define STATE_LOAD           2'b01
`define STATE_COMPUTE        2'b10
`define STATE_DONE           2'b11

`endif // SYSTOLIC_CONSTANTS_VH
