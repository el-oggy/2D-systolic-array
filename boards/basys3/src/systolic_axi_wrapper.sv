`timescale 1ns / 1ps
// ============================================================================
// Module: systolic_axi_wrapper.sv
// Description: AXI4-Lite Slave Wrapper for 16x16 2D Systolic Array Accelerator
//              Enables standard plug-and-play integration into Vivado IP Integrator
//              Block Designs (.bd) with Zynq, MicroBlaze, or PCIe host processors.
//
// Register Memory Map (4KB Address Space):
//   0x000: Control Register (RW)
//          bit [0]: start (1 = initiate matrix multiply; auto-cleared on completion)
//          bit [1]: soft_reset (1 = reset systolic array core)
//   0x004: Status Register (RO)
//          bit [0]: done (1 = computation finished, result matrix valid)
//          bit [1]: busy (1 = systolic array currently computing)
//   0x008: Config Register (RO)
//          bits [15:0]  : Array Dimension N = 16
//          bits [23:16] : Input Data Width = 8 (INT8)
//          bits [31:24] : Output Data Width = 16 (INT16)
//   0x100 - 0x1FF: Matrix A Memory Space (64 words x 4 bytes = 256 INT8 values)
//   0x200 - 0x2FF: Matrix B Memory Space (64 words x 4 bytes = 256 INT8 values)
//   0x300 - 0x4FF: Matrix C Result Space (128 words x 2 INT16 = 256 INT16 values)
// ============================================================================

module systolic_axi_wrapper #(
    parameter int N               = 16,
    parameter int DATA_WIDTH      = 8,
    parameter int AXI_ADDR_WIDTH  = 12,
    parameter int AXI_DATA_WIDTH  = 32
)(
    // AXI4-Lite Clock and Active-Low Reset
    input  wire                          s_axi_aclk,
    input  wire                          s_axi_aresetn,

    // Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                    s_axi_awprot,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    // Write Response Channel
    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    // Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    // Read Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // Interrupt / Hardware Done Flag
    output wire                          irq_done
);

    // ------------------------------------------------------------------------
    // Internal Storage Registers
    // ------------------------------------------------------------------------
    reg        reg_ctrl_start;
    reg        reg_ctrl_reset;
    reg        reg_status_done;
    reg        reg_status_busy;

    // Matrix Storage Banks (packed into 32-bit registers)
    reg [AXI_DATA_WIDTH-1:0] ram_a [0:63];  // 64 words x 4 INT8 = 256 elements
    reg [AXI_DATA_WIDTH-1:0] ram_b [0:63];  // 64 words x 4 INT8 = 256 elements

    // Unpacked matrix wires to feed systolic core
    logic signed [DATA_WIDTH-1:0]   core_matrix_a [0:N-1][0:N-1];
    logic signed [DATA_WIDTH-1:0]   core_matrix_b [0:N-1][0:N-1];
    wire  signed [2*DATA_WIDTH-1:0] core_result   [0:N-1][0:N-1];
    wire                            core_done;
    reg                             core_start_pulse;

    // Unpack 32-bit words into N x N 8-bit inputs
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : gen_unpack_r
            for (c = 0; c < N; c = c + 1) begin : gen_unpack_c
                localparam int elem_idx = (r * N) + c;
                localparam int word_idx = elem_idx / 4;
                localparam int byte_idx = elem_idx % 4;

                always_comb begin
                    core_matrix_a[r][c] = ram_a[word_idx][byte_idx*8 +: 8];
                    core_matrix_b[r][c] = ram_b[word_idx][byte_idx*8 +: 8];
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Systolic Core Instantiation
    // ------------------------------------------------------------------------
    wire core_rst = (!s_axi_aresetn) || reg_ctrl_reset;

    systolic_top #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_systolic_core (
        .clk     (s_axi_aclk),
        .rst     (core_rst),
        .start   (core_start_pulse),
        .matrix_a(core_matrix_a),
        .matrix_b(core_matrix_b),
        .result  (core_result),
        .done    (core_done)
    );

    assign irq_done = reg_status_done;

    // ------------------------------------------------------------------------
    // AXI-Lite Write FSM & Logic
    // ------------------------------------------------------------------------
    reg [AXI_ADDR_WIDTH-1:0] awaddr_latched;
    reg                      aw_en;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            aw_en           <= 1'b1;
            reg_ctrl_start  <= 1'b0;
            reg_ctrl_reset  <= 1'b0;
        end else begin
            // Write Address Handshake
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready  <= 1'b1;
                awaddr_latched <= s_axi_awaddr;
                aw_en          <= 1'b0;
            end else begin
                s_axi_awready  <= 1'b0;
            end

            // Write Data Handshake
            if (~s_axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en) begin
                s_axi_wready <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            // Write Execution
            if (s_axi_wready && s_axi_wvalid && s_axi_awready && s_axi_awvalid) begin
                // Register Decode
                if (awaddr_latched[11:8] == 4'h0) begin
                    if (awaddr_latched[7:0] == 8'h00) begin
                        reg_ctrl_start <= s_axi_wdata[0];
                        reg_ctrl_reset <= s_axi_wdata[1];
                    end
                end else if (awaddr_latched[11:8] == 4'h1) begin
                    // Matrix A Space: 0x100 - 0x1FF
                    ram_a[awaddr_latched[7:2]] <= s_axi_wdata;
                end else if (awaddr_latched[11:8] == 4'h2) begin
                    // Matrix B Space: 0x200 - 0x2FF
                    ram_b[awaddr_latched[7:2]] <= s_axi_wdata;
                end
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
                aw_en        <= 1'b1;
            end

            // Auto-clear start pulse after launching
            if (core_start_pulse) begin
                reg_ctrl_start <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Accelerator Control & Status Handshake
    // ------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || reg_ctrl_reset) begin
            core_start_pulse <= 1'b0;
            reg_status_done  <= 1'b0;
            reg_status_busy  <= 1'b0;
        end else begin
            if (reg_ctrl_start && !reg_status_busy) begin
                core_start_pulse <= 1'b1;
                reg_status_busy  <= 1'b1;
                reg_status_done  <= 1'b0;
            end else begin
                core_start_pulse <= 1'b0;
            end

            if (core_done) begin
                reg_status_busy <= 1'b0;
                reg_status_done <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // AXI-Lite Read FSM & Logic
    // ------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'b0;
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;

                // Read Decode
                case (s_axi_araddr[11:8])
                    4'h0: begin
                        case (s_axi_araddr[7:0])
                            8'h00: s_axi_rdata <= {30'b0, reg_ctrl_reset, reg_ctrl_start};
                            8'h04: s_axi_rdata <= {30'b0, reg_status_busy, reg_status_done};
                            8'h08: s_axi_rdata <= {8'd16, 8'd8, 16'd16}; // [31:24]=ACC, [23:16]=DW, [15:0]=N
                            default: s_axi_rdata <= 32'b0;
                        endcase
                    end
                    4'h1: begin
                        // Read Matrix A RAM
                        s_axi_rdata <= ram_a[s_axi_araddr[7:2]];
                    end
                    4'h2: begin
                        // Read Matrix B RAM
                        s_axi_rdata <= ram_b[s_axi_araddr[7:2]];
                    end
                    4'h3, 4'h4: begin
                        // Read Matrix C Result Space: 0x300 - 0x4FF
                        // Each 32-bit word contains two 16-bit elements:
                        // word_idx = s_axi_araddr[8:2] (128 words total)
                        // elem_low = 2 * word_idx, elem_high = 2 * word_idx + 1
                        int w_idx, r_low, c_low, r_high, c_high;
                        w_idx  = s_axi_araddr[8:2];
                        r_low  = (2 * w_idx) / N;
                        c_low  = (2 * w_idx) % N;
                        r_high = (2 * w_idx + 1) / N;
                        c_high = (2 * w_idx + 1) % N;

                        s_axi_rdata <= {core_result[r_high][c_high], core_result[r_low][c_low]};
                    end
                    default: s_axi_rdata <= 32'hDEADBEEF;
                endcase
            end else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b0;
            end
        end
    end

endmodule
