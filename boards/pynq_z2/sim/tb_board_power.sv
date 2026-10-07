`timescale 1ns/1ps
// The routed PL is intact. A BFM replaces only the PS7 boundary: GP0 MMIO,
// HP0 DDR transactions, FCLK0 and reset. DMA and both interconnects execute.
`include "ps7_binding.vh"
module tb_board_power #(parameter real CLK_PERIOD=10.0);
    logic clk=0, rst_n=0, finished=0;
    always #(CLK_PERIOD/2) clk=~clk;
    board_sim dut();
    integer pairs=256, pattern_select=0, seed_value=1, checked_words=0;
    integer cycle_count=0, job;
    logic [31:0] gp_awaddr=0, gp_wdata=0, gp_araddr=0;
    logic gp_awvalid=0, gp_wvalid=0, gp_arvalid=0;
    wire gp_awready=`PS.MAXIGP0AWREADY, gp_wready=`PS.MAXIGP0WREADY;
    wire gp_bvalid=`PS.MAXIGP0BVALID, gp_arready=`PS.MAXIGP0ARREADY;
    wire gp_rvalid=`PS.MAXIGP0RVALID;
    wire [31:0] gp_rdata=`PS.MAXIGP0RDATA;
    wire [1:0] gp_bresp=`PS.MAXIGP0BRESP, gp_rresp=`PS.MAXIGP0RRESP;

    // One outstanding burst per DDR direction, no artificial transfer gaps.
    logic rd_active=0, wr_active=0, hp_bvalid=0;
    logic [31:0] rd_addr=0, wr_addr=0;
    logic [3:0] rd_left=0, wr_left=0;
    logic [2:0] rd_size=0, wr_size=0;
    logic [5:0] rd_id=0, wr_id=0;
    wire hp_arvalid=`PS.SAXIHP0ARVALID, hp_awvalid=`PS.SAXIHP0AWVALID;
    wire hp_wvalid=`PS.SAXIHP0WVALID, hp_wlast=`PS.SAXIHP0WLAST;
    wire hp_rready=`PS.SAXIHP0RREADY, hp_bready=`PS.SAXIHP0BREADY;
    wire [31:0] hp_araddr=`PS.SAXIHP0ARADDR, hp_awaddr=`PS.SAXIHP0AWADDR;
    wire [3:0] hp_arlen=`PS.SAXIHP0ARLEN, hp_awlen=`PS.SAXIHP0AWLEN;
    wire [2:0] hp_arsize=`PS.SAXIHP0ARSIZE, hp_awsize=`PS.SAXIHP0AWSIZE;
    wire [5:0] hp_arid=`PS.SAXIHP0ARID, hp_awid=`PS.SAXIHP0AWID;
    wire [63:0] hp_wdata=`PS.SAXIHP0WDATA;
    wire [7:0] hp_wstrb=`PS.SAXIHP0WSTRB;
    wire hp_arready=rst_n&&!rd_active;
    wire hp_awready=rst_n&&!wr_active&&!hp_bvalid;
    wire hp_wready=rst_n&&wr_active;
    wire [63:0] hp_rdata={input_word((rd_addr&32'hfffffff8)+4), input_word(rd_addr&32'hfffffff8)};

    initial begin
        force `PS.FCLKCLK={3'b000,clk};
        force `PS.FCLKRESETN={4{rst_n}};
        force `PS.MAXIGP0AWADDR=gp_awaddr;
        force `PS.MAXIGP0AWVALID=gp_awvalid;
        force `PS.MAXIGP0AWID=12'd0;
        force `PS.MAXIGP0AWLEN=4'd0;
        force `PS.MAXIGP0AWSIZE=3'd2;
        force `PS.MAXIGP0AWBURST=2'd1;
        force `PS.MAXIGP0AWLOCK=2'd0;
        force `PS.MAXIGP0AWCACHE=4'd0;
        force `PS.MAXIGP0AWPROT=3'd0;
        force `PS.MAXIGP0AWQOS=4'd0;
        force `PS.MAXIGP0WDATA=gp_wdata;
        force `PS.MAXIGP0WVALID=gp_wvalid;
        force `PS.MAXIGP0WID=12'd0;
        force `PS.MAXIGP0WSTRB=4'hf;
        force `PS.MAXIGP0WLAST=1'b1;
        force `PS.MAXIGP0BREADY=1'b1;
        force `PS.MAXIGP0ARADDR=gp_araddr;
        force `PS.MAXIGP0ARVALID=gp_arvalid;
        force `PS.MAXIGP0ARID=12'd0;
        force `PS.MAXIGP0ARLEN=4'd0;
        force `PS.MAXIGP0ARSIZE=3'd2;
        force `PS.MAXIGP0ARBURST=2'd1;
        force `PS.MAXIGP0ARLOCK=2'd0;
        force `PS.MAXIGP0ARCACHE=4'd0;
        force `PS.MAXIGP0ARPROT=3'd0;
        force `PS.MAXIGP0ARQOS=4'd0;
        force `PS.MAXIGP0RREADY=1'b1;
        force `PS.SAXIHP0ARREADY=hp_arready;
        force `PS.SAXIHP0RVALID=rd_active;
        force `PS.SAXIHP0RDATA=hp_rdata;
        force `PS.SAXIHP0RLAST=(rd_left==0);
        force `PS.SAXIHP0RID=rd_id;
        force `PS.SAXIHP0RRESP=2'd0;
        force `PS.SAXIHP0AWREADY=hp_awready;
        force `PS.SAXIHP0WREADY=hp_wready;
        force `PS.SAXIHP0BVALID=hp_bvalid;
        force `PS.SAXIHP0BID=wr_id;
        force `PS.SAXIHP0BRESP=2'd0;
        force `PS.SAXIHP0RCOUNT=8'd0;
        force `PS.SAXIHP0WCOUNT=8'd0;
        force `PS.SAXIHP0RACOUNT=3'd0;
        force `PS.SAXIHP0WACOUNT=6'd0;
    end

    function automatic signed [7:0] operand(input integer e,r,c,j,which);
        reg [31:0] x;
        begin
            x=(j+seed_value)*32'h9e3779b9+(r*16+c)*32'h85ebca6b+e*7919+which*104729;
            x=(x^(x>>16))*32'h7feb352d;
            case(pattern_select)
                1: operand=-128;
                2: operand=127;
                3: operand=0;
                4: operand=((r+c+j+which)%2) ? -128:127;
                5: operand=which ? ((r%2) ? -127:127):127;
                default: operand=x[7:0];
            endcase
        end
    endfunction

    function automatic [31:0] input_word(input [31:0] addr);
        integer offset,j,section,pos,e,which,r,c,lane;
        begin
            input_word=0;
            if (addr>=32'h10000000 && addr<32'h10000000+pairs*1024) begin
                offset=addr-32'h10000000; j=offset/1024;
                section=(offset%1024)/256; e=section/2; which=section%2;
                for(lane=0;lane<4;lane=lane+1) begin
                    pos=(offset%256)+lane;
                    r=which ? pos%16:pos/16;
                    c=which ? pos/16:pos%16;
                    input_word[lane*8+:8]=operand(e,r,c,j,which);
                end
            end
        end
    endfunction

    task check_output(input [31:0] addr,input [31:0] data);
        integer offset,j,e,r,c,t,sum;
        reg signed [7:0] aa,bb;
        begin
            if (addr<32'h20000000 || addr>=32'h20000000+pairs*2048 || addr[1:0]!=0)
                $fatal(1,"Unexpected DDR write address %h",addr);
            offset=(addr-32'h20000000)/4;
            if (offset!=checked_words) $fatal(1,"DDR output ordering: %0d expected %0d",offset,checked_words);
            j=offset/512; e=(offset%512)/256; r=(offset%256)/16; c=offset%16;
            sum=0;
            for(t=0;t<16;t=t+1) begin
                aa=operand(e,r,t,j,0); bb=operand(e,t,c,j,1);
                sum=sum+$signed(aa)*$signed(bb);
            end
            if ($signed(data)!==sum) $fatal(1,"DDR mismatch word %0d got %0d expected %0d",offset,$signed(data),sum);
            checked_words=checked_words+1;
        end
    endtask

    // Model DDR slave responses on the PL clock observed at PS7 HP0. This
    // retains clock buffer delays between the BFM master and routed logic.
    always @(posedge `PS.SAXIHP0ACLK) begin
        if (!rst_n) begin
            rd_active<=0; wr_active<=0; hp_bvalid<=0;
        end else begin
            if(hp_arvalid&&hp_arready) begin
                if (`PS.SAXIHP0ARBURST!=1) $fatal(1,"Non-INCR DDR read");
                rd_active<=1; rd_addr<=hp_araddr; rd_left<=hp_arlen;
                rd_size<=hp_arsize; rd_id<=hp_arid;
            end
            if(rd_active&&hp_rready) begin
                if(rd_left==0) rd_active<=0;
                else begin rd_left<=rd_left-1; rd_addr<=rd_addr+(1<<rd_size); end
            end
            if(hp_awvalid&&hp_awready) begin
                if (`PS.SAXIHP0AWBURST!=1) $fatal(1,"Non-INCR DDR write");
                wr_active<=1; wr_addr<=hp_awaddr; wr_left<=hp_awlen;
                wr_size<=hp_awsize; wr_id<=hp_awid;
            end
            if(hp_wvalid&&hp_wready) begin
                if(hp_wlast!==(wr_left==0)) $fatal(1,"DDR WLAST mismatch");
                if(hp_wstrb[3:0]!=0) begin
                    if(hp_wstrb[3:0]!=4'hf) $fatal(1,"Partial result word");
                    check_output(wr_addr&32'hfffffff8,hp_wdata[31:0]);
                end
                if(hp_wstrb[7:4]!=0) begin
                    if(hp_wstrb[7:4]!=4'hf) $fatal(1,"Partial result word");
                    check_output((wr_addr&32'hfffffff8)+4,hp_wdata[63:32]);
                end
                if(wr_left==0) begin wr_active<=0; hp_bvalid<=1; end
                else begin wr_left<=wr_left-1; wr_addr<=wr_addr+(1<<wr_size); end
            end
            if(hp_bvalid&&hp_bready) hp_bvalid<=0;
        end
    end

    task mmio_write(input [31:0] addr,input [31:0] value);
        bit aw_done,w_done;
        begin
            @(negedge clk); gp_awaddr=addr; gp_wdata=value; gp_awvalid=1; gp_wvalid=1;
            aw_done=0; w_done=0;
            while(!aw_done||!w_done) begin
                @(posedge `PS.MAXIGP0ACLK);
                if(gp_awvalid&&gp_awready) aw_done=1;
                if(gp_wvalid&&gp_wready) w_done=1;
                @(negedge clk); if(aw_done) gp_awvalid=0; if(w_done) gp_wvalid=0;
            end
            while(!gp_bvalid) @(posedge `PS.MAXIGP0ACLK);
            if(gp_bresp!=0) $fatal(1,"MMIO BRESP at %h",addr);
            @(negedge clk);
        end
    endtask

    task mmio_read(input [31:0] addr,output [31:0] value);
        begin
            @(negedge clk); gp_araddr=addr; gp_arvalid=1;
            do @(posedge `PS.MAXIGP0ACLK); while(!gp_arready);
            @(negedge clk); gp_arvalid=0;
            while(!gp_rvalid) @(posedge `PS.MAXIGP0ACLK);
            if(gp_rresp!=0) $fatal(1,"MMIO RRESP at %h",addr);
            value=gp_rdata;
            @(negedge clk);
        end
    endtask

    always @(posedge clk) begin
        cycle_count=cycle_count+1;
        if(cycle_count>2000000) $fatal(1,"Board power watchdog, job %0d words %0d",job,checked_words);
    end
    logic [31:0] status;
    integer input_queued;
    initial begin
        if(!$value$plusargs("PAIRS=%d",pairs)) pairs=256;
        if(!$value$plusargs("PATTERN=%d",pattern_select)) pattern_select=0;
        if(!$value$plusargs("SEED=%d",seed_value)) seed_value=1;
        // The runner applies maximum SDF at /tb_board_power/dut with xelab.
        // Relative $sdf_annotate scopes lose the parent in XSim 2025.1.
        // Device primitives honour GSR for the first 100 ns.
        repeat(30) @(negedge clk); rst_n=1;
        repeat(40) @(negedge clk);
        mmio_write('h40000008,16); mmio_write('h4000000c,16);
        mmio_write('h40000010,16); mmio_write('h40000014,16); mmio_write('h40000018,16);
        mmio_write('h40400000,1); mmio_write('h40400030,1);
        // Prime both channels, then rearm MM2S independently of output drain.
        // The feeder's two banks and AXI backpressure bound the input queue.
        mmio_write('h40400048,32'h20000000); mmio_write('h40400058,2048);
        mmio_write('h40400018,32'h10000000); mmio_write('h40400028,1024);
        input_queued=1; job=0;
        while(job<pairs) begin
            mmio_read('h40400004,status);
            if(status&32'h70) $fatal(1,"MM2S DMA error %h",status);
            if((status&2)&&input_queued<pairs) begin
                mmio_write('h40400018,32'h10000000+input_queued*1024);
                mmio_write('h40400028,1024);
                input_queued=input_queued+1;
            end
            mmio_read('h40400034,status);
            if(status&32'h70) $fatal(1,"S2MM DMA error %h",status);
            if(status&2) begin
                if(checked_words!=(job+1)*512) $fatal(1,"Incomplete output packet");
                job=job+1;
                if(job<pairs) begin
                    mmio_write('h40400048,32'h20000000+job*2048);
                    mmio_write('h40400058,2048);
                end
            end
        end
        if(input_queued!=pairs) $fatal(1,"Incomplete input workload");
        $display("PASS: %0d full-board tile pairs, %0d DDR result words",pairs,checked_words);
        finished=1; $finish;
    end
endmodule
