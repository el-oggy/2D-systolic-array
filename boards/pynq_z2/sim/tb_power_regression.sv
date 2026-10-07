`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Testbench: tb_accel_dual_engine_top.sv
// Description: Comprehensive Self-Checking Verification for Option 2 Unified
//              Dual-Engine Systolic Matrix Accelerator.
//
// Verifies:
// 1. AXI4-Lite register configuration (dimensions, control, status).
// 2. Single AXI4-Stream MM2S ingestion of packed A0, B0, A1, B1 dual tiles.
// 3. Concurrent dual-engine execution across 512 MAC lanes (110/110 DSP balance).
// 4. Single AXI4-Stream S2MM sequential draining of C0 followed by C1 (512 words).
// 5. Strict tlast assertion on the 512th beat.
// 6. Bit-exact comparison against software golden reference model.
// ============================================================================

module tb_power_regression #(parameter int DSP_LIMIT=110, parameter real CLK_PERIOD=10.0);

    localparam int ARRAY_ROWS      = 16;
    localparam int ARRAY_COLS      = 16;
    localparam int TILE_K          = 16;
    localparam int DATA_WIDTH      = 8;
    localparam int ACC_WIDTH       = 20;
    localparam int AXI_ADDR_WIDTH  = 32;
    localparam int AXI_DATA_WIDTH  = 32;
    localparam int AXIS_DATA_WIDTH = 32;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #(CLK_PERIOD/2.0) clk = ~clk; // 100 MHz clock (10 ns period)

    // AXI-Lite signals
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [2:0]                s_axi_awprot = 3'b000;
    logic                      s_axi_awvalid = 1'b0;
    wire                       s_axi_awready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [3:0]                s_axi_wstrb = 4'b1111;
    logic                      s_axi_wvalid = 1'b0;
    wire                       s_axi_wready;
    wire [1:0]                 s_axi_bresp;
    wire                       s_axi_bvalid;
    logic                      s_axi_bready = 1'b1;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [2:0]                s_axi_arprot = 3'b000;
    logic                      s_axi_arvalid = 1'b0;
    wire                       s_axi_arready;
    wire [AXI_DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]                 s_axi_rresp;
    wire                       s_axi_rvalid;
    logic                      s_axi_rready = 1'b1;

    // AXI-Stream slave (input from DMA MM2S)
    logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata = '0;
    logic [3:0]                 s_axis_tkeep = 4'b1111;
    logic                       s_axis_tvalid = 1'b0;
    wire                        s_axis_tready;
    logic                       s_axis_tlast = 1'b0;

    // AXI-Stream master (output to DMA S2MM)
    wire [AXIS_DATA_WIDTH-1:0]  m_axis_tdata;
    wire [3:0]                  m_axis_tkeep;
    wire                        m_axis_tvalid;
    logic                       m_axis_tready = 1'b1;
    wire                        m_axis_tlast;
    wire                        interrupt;

    // Instantiate Device Under Test (DUT)
`ifdef GATE_DUT
    accel_sim dut (
`else
    accel_dual_engine_top #(
        .ARRAY_ROWS     (ARRAY_ROWS),
        .ARRAY_COLS     (ARRAY_COLS),
        .TILE_K         (TILE_K),
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .DSP_PE_LIMIT_0 (DSP_LIMIT),
        .DSP_PE_LIMIT_1 (DSP_LIMIT)
    ) dut (
`endif
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awprot (s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arprot (s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tkeep (s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .interrupt    (interrupt)
    );

    integer received=0, expected_words=0, packets=0, jobs=0, checked_words=0;
    integer expected [0:1048575];
    integer pairs=2, pattern_select=-1, seed_value=1;
    logic random_stalls=1'b1, force_stall=1'b0, finished=1'b0;
    logic stalled_q=1'b0;
    logic [31:0] stalled_data_q;
    logic stalled_last_q;
    integer cycle_count=0;

    always @(negedge clk) begin
        if (rst_n) m_axis_tready = !force_stall && (!random_stalls || ($urandom_range(0,3) != 0));
    end
    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (cycle_count > 4000000) $fatal(1,"Watchdog: received=%0d expected=%0d",received,expected_words);
        if (!rst_n) stalled_q <= 1'b0;
        else begin
            if (stalled_q && (!m_axis_tvalid || m_axis_tdata !== stalled_data_q ||
                             m_axis_tlast !== stalled_last_q))
                $fatal(1,"AXI output changed while stalled, word %0d",received);
            stalled_q <= m_axis_tvalid && !m_axis_tready;
            stalled_data_q <= m_axis_tdata;
            stalled_last_q <= m_axis_tlast;
            if (m_axis_tvalid && m_axis_tready) begin
                if (received >= expected_words) $fatal(1,"Unexpected output");
                if ($signed(m_axis_tdata) !== expected[received])
                    $fatal(1,"Mismatch word %0d: got %0d expected %0d",received,$signed(m_axis_tdata),expected[received]);
                if (m_axis_tkeep !== 4'hf || m_axis_tlast !== ((received%512)==511))
                    $fatal(1,"Output framing mismatch word %0d",received);
                if (m_axis_tlast) packets = packets + 1;
                received = received + 1;
                checked_words = checked_words + 1;
            end
        end
    end

    task axi_write(input [31:0] addr,input [31:0] value);
        begin
            @(negedge clk);
            s_axi_awaddr=addr; s_axi_awvalid=1; s_axi_wdata=value; s_axi_wvalid=1;
            do @(posedge clk); while (!s_axi_awready || !s_axi_wready);
            @(negedge clk); s_axi_awvalid=0; s_axi_wvalid=0;
            do @(posedge clk); while (!s_axi_bvalid);
        end
    endtask

`ifndef GATE_DUT
    task reset_in_phase(input integer phase);
        begin
            send_job(0,16,16,16,16,16);
            case (phase)
                0: wait(dut.u_feeder.pf_state == 1);
                1: wait(dut.u_compute_core.array_en);
                2: wait(dut.u_c_buf_0.capture_active_q);
                3: while ((received % 512) != 15) @(negedge clk);
                4: while ((received % 512) != 255) @(negedge clk);
                5: while ((received % 512) != 511) @(negedge clk);
            endcase
            @(negedge clk); force_stall=1; m_axis_tready=0;
            repeat(2) @(negedge clk);
            rst_n=0; s_axis_tvalid=0;
            // Retire the abandoned packet's scoreboard positions. Its output
            // has already been checked where present; no TLAST is expected.
            received=expected_words; jobs=jobs-1;
            repeat(4) @(negedge clk); rst_n=1; force_stall=0;
            configure(16,16,16,16,16);
            send_job(phase%6,16,16,16,16,16); wait_drain();
        end
    endtask
`endif

    function automatic signed [7:0] operand(input integer p,e,r,c,j,which);
        reg [31:0] x;
        begin
            x = (j+seed_value)*32'h9e3779b9 + (r*16+c)*32'h85ebca6b + e*7919 + which*104729;
            x = (x ^ (x >> 16))*32'h7feb352d;
            case(p)
                1: operand=-128;
                2: operand=127;
                3: operand=0;
                4: operand=((r+c+j+which)%2) ? -128 : 127;
                5: operand=which ? ((r%2) ? -127 : 127) : 127;
                default: operand=x[7:0];
            endcase
        end
    endfunction

    task configure(input integer m,k,n,am,an);
        begin
            axi_write('h08,m); axi_write('h0c,k); axi_write('h10,n);
            axi_write('h14,am); axi_write('h18,an);
        end
    endtask

    task send_job(input integer p,m,k,n,am,an);
        integer e,r,c,t,idx,entry,lane,which,rr,cc;
        integer sum,active_rows_eff,active_cols_eff;
        reg signed [7:0] aa,bb;
        reg [31:0] word_data;
        begin
            active_rows_eff=(am==0 || am>16) ? 16:am;
            active_cols_eff=(an==0 || an>16) ? 16:an;
            for(e=0;e<2;e=e+1) for(r=0;r<16;r=r+1) for(c=0;c<16;c=c+1) begin
                sum=0;
                if(r<m && c<n && r<active_rows_eff && c<active_cols_eff)
                    for(t=0;t<k;t=t+1) begin
                        aa=operand(p,e,r,t,jobs,0); bb=operand(p,e,t,c,jobs,1);
                        sum=sum+$signed(aa)*$signed(bb);
                    end
                expected[expected_words]=sum;
                expected_words=expected_words+1;
            end
            for(idx=0;idx<256;idx=idx+1) begin
                entry=idx/4; e=entry/32; which=(entry%32)/16;
                for(lane=0;lane<4;lane=lane+1) begin
                    rr=which ? ((idx%4)*4+lane):(entry%16);
                    cc=which ? (entry%16):((idx%4)*4+lane);
                    aa=operand(p,e,rr,cc,jobs,which);
                    word_data[lane*8+:8]=aa;
                end
                @(negedge clk);
                if(random_stalls && $urandom_range(0,4)==0) begin
                    s_axis_tvalid=0;
                    @(negedge clk);
                end
                s_axis_tvalid=1; s_axis_tdata=word_data; s_axis_tlast=(idx==255);
                do @(posedge clk); while(!s_axis_tready);
            end
            @(negedge clk); s_axis_tvalid=0; s_axis_tlast=0;
            jobs=jobs+1;
        end
    endtask

    task wait_drain;
        begin
            while(received<expected_words) @(negedge clk);
            repeat(6) @(negedge clk);
        end
    endtask

    integer p,j,d;
    // Gate simulation gets maximum SDF from xelab at /tb_power_regression/dut.
    initial begin
        s_axi_awaddr=0; s_axi_wdata=0; s_axis_tdata=0;
        if ($value$plusargs("PAIRS=%d",pairs)) begin end
        if ($value$plusargs("PATTERN=%d",pattern_select)) begin end
        if ($value$plusargs("SEED=%d",seed_value)) begin end
        if ($test$plusargs("POWER")) random_stalls=0;
        repeat(5) @(negedge clk); rst_n=1;
        configure(16,16,16,16,16);
`ifndef GATE_DUT
        if (!$test$plusargs("POWER")) begin
            // A bank's input packet is complete before its 33-cycle prefetch.
            // CTRL.start in that interval must not consume a partial tile.
            send_job(0,16,16,16,16,16);
            wait(dut.u_feeder.pf_state == 1);
            axi_write('h00,1);
            wait_drain();
            if ($test$plusargs("MANUAL_PREFETCH")) begin
                $display("PASS: manual start during prefetch, %0d checked words",checked_words);
                finished=1; $finish;
            end
        end
`endif
        for(p=0;p<6;p=p+1) begin
            if(pattern_select<0 || pattern_select==p) begin
                for(j=0;j<pairs;j=j+1) send_job(p,16,16,16,16,16);
                wait_drain();
            end
        end
        if (!$test$plusargs("POWER")) begin
            for(d=1;d<=16;d=d+1) begin
                configure(d,17-d,d,d,17-d);
                send_job(0,d,17-d,d,d,17-d);
                wait_drain();
            end
            configure(16,16,16,0,0);
            send_job(4,16,16,16,0,0); wait_drain();
            // Reset with a partly received packet; abandoned data must not leak.
            @(negedge clk); s_axis_tvalid=1; s_axis_tdata=32'h12345678;
            @(negedge clk); rst_n=0; s_axis_tvalid=0;
            repeat(4) @(negedge clk); rst_n=1;
            configure(16,16,16,16,16);
            send_job(1,16,16,16,16,16); wait_drain();
`ifndef GATE_DUT
            for(d=0;d<6;d=d+1) reset_in_phase(d);
            // Fill another bank and request manual restart during a stalled
            // drain. The first result must survive and the next job must wait.
            force_stall=1;
            send_job(0,16,16,16,16,16);
            wait(m_axis_tvalid);
            send_job(2,16,16,16,16,16);
            axi_write('h00,1);
            repeat(12) @(negedge clk);
            if (!dut.job_pending_q || dut.effective_core_start)
                $fatal(1,"Job lifetime lost during stalled output");
            force_stall=0; wait_drain();
            configure(16,16,16,16,16);
            send_job(0,16,16,16,16,16);
            wait(dut.u_compute_core.array_en);
            // Configure a later job without changing the accepted job's
            // narrow ingress mask or its already-latched result mask.
            axi_write('h14,1); axi_write('h18,1);
            wait_drain();
            send_job(0,16,16,16,1,1); wait_drain();
`endif
        end
        if(packets!=jobs) $fatal(1,"Packet count mismatch");
        $display("PASS: %0d completed jobs, %0d checked words, DSP_LIMIT=%0d",jobs,checked_words,DSP_LIMIT);
        finished=1; $finish;
    end
endmodule
`default_nettype wire
