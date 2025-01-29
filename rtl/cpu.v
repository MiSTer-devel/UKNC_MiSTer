module cpu_wb(
    input         vm_clk_p,
    input         vm_clk_n,
    input         clk50hz,

    output reg [15:0] addr_ram,
    output [15:0] dout_ram,
    input  [15:0] dinp_ram,
    output  [3:0] mask_ram,
    output        read_ram,
    output        wrte_ram,
    input         ackn_ram,

    output        vm_init,
    input         vm_dclo,
    input         vm_aclo,
    input         vm_halt,

    input         vm_virq,

    output [16:0] wbm_adr_o,
    output [15:0] wbm_dat_o,
    input  [15:0] wbm_dat_i,
    output        wbm_cyc_o,
    output        wbm_we_o,
    output [ 1:0] wbm_sel_o,
    output        wbm_stb_o,
    input         wbm_ack_i,
    input  [15:0] wbi_dat_i,
    input         wbi_ack_i,
    output        wbi_stb_o,

    input         tmr_ena_i,

    output        traps_o
);
//========================================================================================
//  Wishbone CPU
//========================================================================================
wire        vm_clk_ena  = 1'b0;
wire        vm_clk_slow = 1'b0;

wire        vm_evnt;

wire        wbm_gnt_i = 1'b1;
wire        wbm_ios_o;

wire        wbi_una_o;

reg         ram_rd;
reg         ram_wr;
reg         rio;
reg         rio_ram_wr;
reg         rio_ram_rd;
reg         ack;

reg  [15:0] wbm_dat_loc;
reg  [15:0] data_rio;
reg  [15:0] ramd_rio;
reg   [3:0] mask_rio;

reg  [15:0] R176640;
reg  [15:0] R176642;
//========================================================================================
//  Wishbone out
//========================================================================================
wire  wbi_stb_loc;
assign wbi_stb_o = wbi_una_o ? 1'b0 : wbi_stb_loc;

assign traps_o = wbm_adr_o[16:0] == 17'o200170;
//========================================================================================
// VIRQ
//========================================================================================
wire [15:0] wbi_dat_loc = wbi_una_o ? 16'o160000 : (wbi_stb_o ? wbi_dat_i : 16'o000);
wire  wbi_ack_loc = wbi_una_o | wbi_ack_i;
//========================================================================================
always @(*)
    casex({wbm_we_o, wbm_ack_i, rio, read_ram})
    'b0_xx1: wbm_dat_loc <= dinp_ram;
    'b0_x10: wbm_dat_loc <= data_rio;
    'b0_100: wbm_dat_loc <= wbm_dat_i;
    default: wbm_dat_loc <= 16'o0;
    endcase

wire  wbm_ack_loc = (ack | ackn_ram | wbm_ack_i) & wbm_stb_o;

assign dout_ram = rio_ram_wr ? ramd_rio : wbm_dat_o;
assign mask_ram = rio_ram_wr ? {mask_rio[3:2],2'b11} : {~wbm_sel_o,2'b11};
assign read_ram = (ram_rd | rio_ram_rd) & wbm_stb_o;
assign wrte_ram = (ram_wr | rio_ram_wr) & wbm_stb_o;
//========================================================================================
assign vm_evnt = tmr_ena_i | clk50hz;
//========================================================================================
vm2_wb #(.VM2_CORE_FIX_PREFETCH(0)) cpu
(
   //
   // Processor core clock section:
   //    - vm_clk_p     - processor core positive clock, also feeds the wishbone buses
   //    - vm_clk_n     - processor core negative clock, should be vm_clk_p 180 degree phase shifted
   //    - vm_clk_ena   - slow clock simulation strobe, enables clock at vm_clk_p
   //    - vm_clk_slow  - clock mode selector, enables clock slowdown simulation,
   //                     the external I/O cycles is launched with rate of vm_clk_ena
   //
    .vm_clk_p   (vm_clk_p),     // positive edge clock
    .vm_clk_n   (vm_clk_n),     // negative edge clock
    .vm_clk_ena (vm_clk_ena),   // slow clock enable
    .vm_clk_slow(vm_clk_slow),  // slow clock sim mode
                                //
    .vm_init    (vm_init),      // peripheral reset output
    .vm_dclo    (vm_dclo),      // processor reset
    .vm_aclo    (vm_aclo),      // power fail notificaton
    .vm_halt    (vm_halt),      // halt mode interrupt
    .vm_evnt    (vm_evnt),      // timer interrupt requests
    .vm_virq    (vm_virq),      // vectored interrupt request
                                //
                                // adr MSB is halt mode flag
    .wbm_gnt_i  (wbm_gnt_i),    // master wishbone granted
    .wbm_ios_o  (wbm_ios_o),    // master wishbone I/O select
    .wbm_adr_o  (wbm_adr_o),    // master wishbone address
    .wbm_dat_o  (wbm_dat_o),    // master wishbone data output
    .wbm_dat_i  (wbm_dat_loc),  // master wishbone data input
    .wbm_cyc_o  (wbm_cyc_o),    // master wishbone cycle
    .wbm_we_o   (wbm_we_o),     // master wishbone direction
    .wbm_sel_o  (wbm_sel_o),    // master wishbone byte selection
    .wbm_stb_o  (wbm_stb_o),  // master wishbone strobe
    .wbm_ack_i  (wbm_ack_loc),  // master wishbone acknowledgement
                                //
    .wbi_dat_i  (wbi_dat_loc),  // interrupt vector input
    .wbi_ack_i  (wbi_ack_loc),  // interrupt vector acknowledgement
    .wbi_stb_o  (wbi_stb_loc),  // interrupt vector strobe
    .wbi_una_o  (wbi_una_o)     // unaddressed read access
);

reg wbm_stb_o_old = 0;

always @(posedge vm_clk_p)
    if(vm_init) begin
        ram_rd <= 1'b0;
        ram_wr <= 1'b0;
        rio <= 1'b0;
        ack <= 1'b0;
        wbm_stb_o_old <= 1'b0;
        rio_ram_wr <= 1'b0;
        rio_ram_rd <= 1'b0;
        mask_rio <= 4'b0000;
        ramd_rio[15:0] <= 16'h0000;
    end else begin
        if(ackn_ram & rio_ram_rd) R176642 <= dinp_ram;
        wbm_stb_o_old <= wbm_stb_o;
        if(!wbm_stb_o)begin
            ram_rd <= 1'b0;
            ram_wr <= 1'b0;
            rio <= 1'b0;
            data_rio <= 16'o0;
            rio_ram_wr <= 1'b0;
            rio_ram_rd <= 1'b0;
            ack <= 1'b0;
        end else
        if(~wbm_stb_o_old & wbm_stb_o) begin
            if(wbm_adr_o[16])begin
                addr_ram <= wbm_adr_o[15:1];
                ram_rd <=~wbm_we_o;
                ram_wr <= wbm_we_o;
                rio    <= 1'b0;
                ack    <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o160) begin
                addr_ram <= wbm_adr_o[15:1];
                ram_rd <=~wbm_we_o;
                ram_wr <= wbm_we_o;
                rio    <= 1'b0;
                ack    <= 1'b0;
            end else begin
                ram_rd <= 1'b0;
                ram_wr <= 1'b0;
                if(wbm_we_o) begin
                    if(wbm_adr_o[12:1] == 'o7270) begin
                        ack <= 1'b0;
                    end else
                    if(wbm_adr_o[12:1] == 'o7271) begin
                        ack <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7272) begin
                        ack <= 1'b0;
                    end else
                    if(wbm_adr_o[12:1] == 'o7273) begin
                        ack <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7320) begin
                        R176640[15:8]  <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R176640[ 7:0]  <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : 8'o0;
                        ack            <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7321) begin
                        ramd_rio[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : R176642[15:8];
                        ramd_rio[7:0]  <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : R176642[ 7:0];
                        R176642[15:8]   <= wbm_sel_o[1] ? wbm_dat_o[15:8] : R176642[15:8];
                        R176642[ 7:0]   <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : R176642[ 7:0];
                        addr_ram        <= R176640;
                        mask_rio        <= 4'b0011;
                        rio_ram_wr      <= 1'b1;
                        ack             <= 1'b0;
                    end else begin
                        ram_rd          <= 1'b0;
                        ram_wr          <= 1'b0;
                        rio             <= 1'b0;
                        data_rio        <= 16'o0;
                        rio_ram_wr      <= 1'b0;
                        rio_ram_rd      <= 1'b0;
                        ack             <= 1'b0;
                    end

                end else begin

                    if(wbm_adr_o[12:1] == 'o7270) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7271) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7272) begin
                        ack <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7273) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7274) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7275) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7276) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7277) begin
                        data_rio     <= 16'o0;
                        ack          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7320) begin
                        data_rio     <= R176640;
                        rio          <= 1'b1;
                        ack          <= 1'b1;
                    end else
                    if(wbm_adr_o[12:1] == 'o7321) begin
                        addr_ram     <= R176640;
                        mask_rio     <= 4'b0000;
                        rio_ram_rd   <= 1'b1;
                        ack          <= 1'b0;
                    end else begin
                        ram_rd       <= 1'b0;
                        ram_wr       <= 1'b0;
                        rio          <= 1'b0;
                        data_rio     <= 16'o0;
                        rio_ram_wr   <= 1'b0;
                        rio_ram_rd   <= 1'b0;
                        ack          <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
