`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: axi_lite_regs
// Description: AXI4-Lite Slave Register Interface for Systolic Array Accelerator.
//
// Register Map:
// 0x00: CTRL     - [0] Start (W1P), [1] Soft Reset, [2] Int Enable
// 0x04: STATUS   - [0] Busy (RO), [1] Done (RO/W1C), [2] Overflow (RO/W1C)
// 0x08: M_DIM    - [15:0] Matrix M dimension
// 0x0C: K_DIM    - [15:0] Matrix K dimension
// 0x10: N_DIM    - [15:0] Matrix N dimension
// 0x14: ACTIVE_M - [7:0]  Active rows in PE mesh
// 0x18: ACTIVE_N - [7:0]  Active cols in PE mesh
// 0x1C: CYCLES   - [31:0] Real hardware measured cycle count (RO)
// 0x20: TILES    - [31:0] Real hardware measured tile count (RO)
// 0x24: CACHE    - [0] Cached MVM mode, [1] manual stream target, [2] B target
// ============================================================================

module axi_lite_regs #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32
)(
    input  wire                      s_axi_aclk,
    input  wire                      s_axi_aresetn,

    // AXI4-Lite Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]                s_axi_awprot,
    input  wire                      s_axi_awvalid,
    output logic                     s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output logic                     s_axi_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  wire                      s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                s_axi_arprot,
    input  wire                      s_axi_arvalid,
    output logic                     s_axi_arready,

    // AXI4-Lite Read Data Channel
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rvalid,
    input  wire                      s_axi_rready,

    // Accelerator Control & Status Interface
    output logic                     ctrl_start,
    output logic                     ctrl_soft_reset,
    output logic [15:0]              cfg_m_dim,
    output logic [15:0]              cfg_k_dim,
    output logic [15:0]              cfg_n_dim,
    output logic [7:0]               cfg_active_m,
    output logic [7:0]               cfg_active_n,
    output logic                     cfg_cache_mvm,
    output logic                     cfg_stream_target_manual,
    output logic                     cfg_stream_target,

    input  wire                      status_busy,
    input  wire                      status_done,
    input  wire                      status_overflow,
    input  wire                      status_invalid,
    input  wire                      status_a_loaded,
    input  wire                      status_b_loaded,
    input  wire [31:0]               hw_cycles,
    input  wire [31:0]               hw_tiles
);

    // Register address offsets
    localparam [7:0] ADDR_CTRL     = 8'h00;
    localparam [7:0] ADDR_STATUS   = 8'h04;
    localparam [7:0] ADDR_M_DIM    = 8'h08;
    localparam [7:0] ADDR_K_DIM    = 8'h0C;
    localparam [7:0] ADDR_N_DIM    = 8'h10;
    localparam [7:0] ADDR_ACTIVE_M = 8'h14;
    localparam [7:0] ADDR_ACTIVE_N = 8'h18;
    localparam [7:0] ADDR_CYCLES   = 8'h1C;
    localparam [7:0] ADDR_TILES    = 8'h20;
    localparam [7:0] ADDR_CACHE    = 8'h24;

    // Internal registers
    logic [15:0] reg_m;
    logic [15:0] reg_k;
    logic [15:0] reg_n;
    logic [7:0]  reg_act_m;
    logic [7:0]  reg_act_n;
    logic        reg_cache_mvm;
    logic        reg_stream_manual;
    logic        reg_stream_target;
    logic        reg_soft_reset;
    logic        start_pulse;
    logic        done_sticky;
    logic        overflow_sticky;
    logic        aw_captured;
    logic        w_captured;
    logic [AXI_ADDR_WIDTH-1:0] awaddr_hold;
    logic [AXI_DATA_WIDTH-1:0] wdata_hold;
    logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_hold;
    wire         aw_handshake = s_axi_awvalid && s_axi_awready;
    wire         w_handshake  = s_axi_wvalid && s_axi_wready;
    wire         write_commit = !s_axi_bvalid &&
                                (aw_captured || aw_handshake) &&
                                (w_captured || w_handshake);
    wire [AXI_ADDR_WIDTH-1:0] write_addr = aw_captured ? awaddr_hold : s_axi_awaddr;
    wire [AXI_DATA_WIDTH-1:0] write_data = w_captured ? wdata_hold : s_axi_wdata;
    wire [(AXI_DATA_WIDTH/8)-1:0] write_strb = w_captured ? wstrb_hold : s_axi_wstrb;
    wire status_write = write_commit && (write_addr[7:0] == ADDR_STATUS) && write_strb[0];

    always_comb begin
        s_axi_awready = !aw_captured && !s_axi_bvalid;
        s_axi_wready  = !w_captured && !s_axi_bvalid;
    end

    // Latch sticky flags
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || reg_soft_reset) begin
            done_sticky     <= 1'b0;
            overflow_sticky <= 1'b0;
        end else begin
            if (status_write && write_data[1]) begin
                done_sticky <= 1'b0;
            end else if (start_pulse) begin
                done_sticky <= 1'b0;
            end else if (status_done) begin
                done_sticky <= 1'b1;
            end

            if (status_write && write_data[2]) begin
                overflow_sticky <= 1'b0;
            end else if (status_overflow) begin
                overflow_sticky <= 1'b1;
            end
        end
    end

    // AXI4-Lite write address and data channels are accepted independently.
    // Commit a write only after both halves have arrived, then hold BVALID
    // until the master accepts the response.
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            aw_captured    <= 1'b0;
            w_captured     <= 1'b0;
            awaddr_hold    <= '0;
            wdata_hold     <= '0;
            wstrb_hold     <= '0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            start_pulse    <= 1'b0;
            reg_m          <= 16'd16;
            reg_k          <= 16'd16;
            reg_n          <= 16'd16;
            reg_act_m      <= 8'd16;
            reg_act_n      <= 8'd16;
            reg_cache_mvm  <= 1'b0;
            reg_stream_manual <= 1'b0;
            reg_stream_target <= 1'b0;
            reg_soft_reset <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            if (aw_handshake) begin
                aw_captured <= 1'b1;
                awaddr_hold <= s_axi_awaddr;
            end
            if (w_handshake) begin
                w_captured <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (write_commit) begin
                aw_captured  <= 1'b0;
                w_captured   <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;

                case (write_addr[7:0])
                    ADDR_CTRL: begin
                        if (write_strb[0]) begin
                            reg_soft_reset <= write_data[1];
                            if (write_data[0]) start_pulse <= 1'b1;
                        end
                    end
                    ADDR_STATUS: ; // W1C handled in the sticky flag block.
                    ADDR_M_DIM: begin
                        if (write_strb[0]) reg_m[7:0]  <= write_data[7:0];
                        if (write_strb[1]) reg_m[15:8] <= write_data[15:8];
                    end
                    ADDR_K_DIM: begin
                        if (write_strb[0]) reg_k[7:0]  <= write_data[7:0];
                        if (write_strb[1]) reg_k[15:8] <= write_data[15:8];
                    end
                    ADDR_N_DIM: begin
                        if (write_strb[0]) reg_n[7:0]  <= write_data[7:0];
                        if (write_strb[1]) reg_n[15:8] <= write_data[15:8];
                    end
                    ADDR_ACTIVE_M: if (write_strb[0]) reg_act_m <= write_data[7:0];
                    ADDR_ACTIVE_N: if (write_strb[0]) reg_act_n <= write_data[7:0];
                    ADDR_CACHE: begin
                        if (write_strb[0]) begin
                            reg_cache_mvm <= write_data[0];
                            reg_stream_manual <= write_data[1];
                            reg_stream_target <= write_data[2];
                        end
                    end
                    default: ;
                endcase
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite Read Handshake
    logic [AXI_ADDR_WIDTH-1:0] axi_araddr_latched;
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready      <= 1'b0;
            s_axi_rvalid       <= 1'b0;
            s_axi_rresp        <= 2'b00;
            s_axi_rdata        <= '0;
            axi_araddr_latched <= '0;
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready      <= 1'b1;
                axi_araddr_latched <= s_axi_araddr;
            end else begin
                s_axi_arready      <= 1'b0;
            end

            if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY

                case (axi_araddr_latched[7:0])
                    ADDR_CTRL:     s_axi_rdata <= {29'd0, 1'b0, reg_soft_reset, 1'b0};
                    ADDR_STATUS:   s_axi_rdata <= {26'd0, status_b_loaded, status_a_loaded, status_invalid, overflow_sticky, done_sticky, status_busy};
                    ADDR_M_DIM:    s_axi_rdata <= {16'd0, reg_m};
                    ADDR_K_DIM:    s_axi_rdata <= {16'd0, reg_k};
                    ADDR_N_DIM:    s_axi_rdata <= {16'd0, reg_n};
                    ADDR_ACTIVE_M: s_axi_rdata <= {24'd0, reg_act_m};
                    ADDR_ACTIVE_N: s_axi_rdata <= {24'd0, reg_act_n};
                    ADDR_CACHE:    s_axi_rdata <= {29'd0, reg_stream_target, reg_stream_manual, reg_cache_mvm};
                    ADDR_CYCLES:   s_axi_rdata <= hw_cycles;
                    ADDR_TILES:    s_axi_rdata <= hw_tiles;
                    default:       s_axi_rdata <= 32'hdeadbeef;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // Continuous outputs
    assign ctrl_start      = start_pulse;
    assign ctrl_soft_reset = reg_soft_reset;
    assign cfg_m_dim       = reg_m;
    assign cfg_k_dim       = reg_k;
    assign cfg_n_dim       = reg_n;
    assign cfg_active_m    = reg_act_m;
    assign cfg_active_n    = reg_act_n;
    assign cfg_cache_mvm   = reg_cache_mvm;
    assign cfg_stream_target_manual = reg_stream_manual;
    assign cfg_stream_target = reg_stream_target;

endmodule

`default_nettype wire
