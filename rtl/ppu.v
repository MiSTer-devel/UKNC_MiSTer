module ppu_wb(
    input         vm_clk_p,
    input         vm_clk_n,
    input         vm_clk_slow,
    input         rst,
    input         clk50hz,

    output reg[15:0] addr_ram,
    output [31:0] duot_ram,
    input  [31:0] dinp_ram,
    output  [3:0] mask_ram,
    output        read_ram,
    output        wrte_ram,
    input         ackn_ram,

    output        vm_init,
    output        vm_dclo,
    output        vm_aclo,

    input         vm_virq,

    output [16:0] wbm_adr_o,
    output [15:0] wbm_dat_o,
    input  [15:0] wbm_dat_i,
    output        wbm_cyc_o,
    output        wbm_we_o,
    output  [1:0] wbm_sel_o,
    output        wbm_stb_o,
    input         wbm_ack_i,
    input  [15:0] wbi_dat_i,
    input         wbi_ack_i,
    output        wbi_stb_o,

    output        tmr_ena_o,
    input  [15:0] mouse,

    output  [2:0] ide_addr,
    output        ide_read,
    output        ide_write,
    input  [15:0] ide_readdata,
    output [15:0] ide_writedata
);
//========================================================================================
//  Wishbone PPU
//========================================================================================

wire        vm_halt = 1'b0;
wire        vm_evnt;

wire        wbm_gnt_i = 1'b1;
wire        wbm_ios_o;
reg  [15:0] wbm_dat_loc;
wire        wbm_ack_loc;

wire [15:0] wbi_dat_loc;
wire        wbi_ack_loc;
wire        wbi_stb_loc;
wire        wbi_una_o;

reg         rom;
reg         ram_wr;
reg         ram_rd;
reg         rio;
reg         rio_ram_wr;
reg         rio_ram_rd;
wire [15:0] prom;
reg         ack;

reg  [15:0] data_rio;
reg  [31:0] ramd_rio;
reg   [3:0] mask_rio;


reg  [15:0] R177010;
reg  [15:0] R177012;
reg  [15:0] R177014;

reg  [15:0] R177016;
reg  [15:0] R177020;
reg  [15:0] R177022;
reg  [15:0] R177024;
reg  [15:0] R177026;

reg   [9:0] R177054 = 10'o1401;

wire [31:0] data_reg_out_plan_out;
wire  [3:0] io_dqm_out;
wire [15:0] o177020_out;
wire [15:0] o177022_out;
//========================================================================================
//  Wishbone out
//========================================================================================
assign wbi_stb_o = wbi_una_o ? 1'b0 : wbi_stb_loc;
assign tmr_ena_o = R177054[9];
//========================================================================================
// VIRQ
//========================================================================================
assign wbi_dat_loc = wbi_una_o ? 16'o160000 : wbi_stb_loc ? wbi_dat_i : 16'o0;
assign wbi_ack_loc = wbi_una_o | wbi_ack_i;
//========================================================================================

always @(*)
    casex({wbm_we_o, wbm_ack_i, rio, ram_rd, ide_read, romcart, rom})
    'b0xx_xxx1: wbm_dat_loc <= prom;
    'b0xx_xx10: wbm_dat_loc <= cart_dat;
    'b0xx_x100: wbm_dat_loc <= (ide_addr == 3'd0) ? ide_readdata : ~ide_readdata;
    'b0xx_1000: wbm_dat_loc <= dinp_ram[15:0];
    'b0x1_0000: wbm_dat_loc <= data_rio;
    'b010_0000: wbm_dat_loc <= wbm_dat_i;
    default:  wbm_dat_loc <= 16'o0;
    endcase

assign wbm_ack_loc = (ack | ackn_ram | wbm_ack_i) & wbm_stb_o;
assign duot_ram = rio_ram_wr ? ramd_rio : {wbm_dat_o,wbm_dat_o};
assign mask_ram = (rio_ram_wr | rio_ram_rd) ? mask_rio : {2'b11,~wbm_sel_o};
assign read_ram = (ram_rd | rio_ram_rd) & wbm_stb_o;
assign wrte_ram = (ram_wr | rio_ram_wr) & wbm_stb_o;
//========================================================================================
spram #(14,16,"rtl/rom/uknc_rom.mif","MIF") rom208 (
   .clock   (vm_clk_p),
   .address (wbm_adr_o[14:1]),
//   .data    (),
//   .wren    (),
   .q       (prom)
);

//========================================================================================
// Cartridge
wire [15:0] cart_dat;
reg         romcart;

spram #(11,16,"rtl/rom/ide_wdromv0200.mif","MIF") rom_cart (
//spram #(11,16,"rtl/rom/ide_wdromv0110.mif","MIF") rom_cart (
//spram #(11,16,"../rom/wddbg2.mif","MIF") rom_cart (
   .clock   (vm_clk_p),
   .address (wbm_adr_o[11:1]),
   .q       (cart_dat)
);
//========================================================================================
// IDE HDD - 110000-110016  CS0 - address revesed (inverted)!

//wire ide_stb = wbm_stb_o & (wbm_adr_o[15:4] == (16'o110000 >> 4));  // IDE HDD
//reg ide_stb;
//assign  ide_read      = ~wbm_we_o & ide_stb;
//assign  ide_write     = wbm_we_o & ide_stb;

assign  ide_addr      = ~wbm_adr_o[3:1];
assign ide_writedata = (ide_addr == 3'd0) ? wbm_dat_o : ~wbm_dat_o;
reg  ide_rd;
reg  ide_wr;
assign ide_read  = ide_rd & wbm_stb_o;
assign ide_write = ide_wr & wbm_stb_o;

//========================================================================================
vm_reset r1
(
   .clk   (vm_clk_p),
   .reset (rst),
   .dclo  (vm_dclo),
   .aclo  (vm_aclo)
);
//========================================================================================
assign vm_evnt = R177054[8] | clk50hz;
//========================================================================================
reg [2:0] cpudelay;

always @ (posedge vm_clk_p) begin
   if (cpudelay != 3'd2) cpudelay <= cpudelay + 1'b1;  // считаем от 0 до 3
   else cpudelay <= 3'd0;
end
wire vm_clk_ena = cpudelay == 3'd2;

//========================================================================================
vm2_wb #(.VM2_CORE_FIX_PREFETCH(0)) ppu
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
    .wbm_stb_o  (wbm_stb_o),    // master wishbone strobe
    .wbm_ack_i  (wbm_ack_loc),  // master wishbone acknowledgement
                                //
    .wbi_dat_i  (wbi_dat_loc),  // interrupt vector input
    .wbi_ack_i  (wbi_ack_loc),  // interrupt vector acknowledgement
    .wbi_stb_o  (wbi_stb_loc),  // interrupt vector strobe
    .wbi_una_o  (wbi_una_o)     // unaddressed read access
);

reg wbm_stb_o_old = 0;
reg read_177124 = 0;

always @(posedge vm_clk_p)
    if(vm_init)begin
        rom <= 1'b0;
        romcart <= 1'b0;
        ide_rd <= 1'b0;
        ide_wr <= 1'b0;
        ram_wr <= 1'b0;
        ram_rd <= 1'b0;
        rio <= 1'b0;
        ack <= 1'b0;
        wbm_stb_o_old <= 1'b0;
        rio_ram_wr    <= 1'b0;
        rio_ram_rd    <= 1'b0;
        mask_rio      <= 4'b1100;
        R177054       <= 10'o1401;
    end else begin
        if(ackn_ram & rio_ram_rd & !read_177124){R177014,R177012} <= dinp_ram;
        if(ackn_ram & rio_ram_rd &  read_177124){R177022,R177020} <= {o177022_out,o177020_out};
        wbm_stb_o_old <= wbm_stb_o;
        if(!wbm_stb_o)begin
            rom <= 1'b0;
            romcart <= 1'b0;
            ide_rd <= 1'b0;
            ide_wr <= 1'b0;
            ram_wr <= 1'b0;
            ram_rd <= 1'b0;
            rio <= 1'b0;
            data_rio <= 16'o0;
            rio_ram_wr <= 1'b0;
            rio_ram_rd <= 1'b0;
            read_177124 <= 1'b0;
            ack <= 1'b0;
        end else
        if(~wbm_stb_o_old & wbm_stb_o)begin
            if(wbm_adr_o[15:9] < 'o100)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b0;
                romcart <= 1'b0;
                ide_rd  <= 1'b0;
                ide_wr  <= 1'b0;
                rio      <= 1'b0;
                ack      <= 1'b0;
                ram_wr   <= wbm_we_o;
                ram_rd   <=~wbm_we_o;
            end else
            if(wbm_adr_o[15:9] < 'o120)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= R177054[0];
                if (R177054[3:0] == 4'h2) begin
//                   romcart <= 1'b1;
                   romcart <= ~wbm_adr_o[12];
                   ide_rd <= ~wbm_we_o & (wbm_adr_o[12:4] == 9'b1_0000_0000);
                   ide_wr <=  wbm_we_o & (wbm_adr_o[12:4] == 9'b1_0000_0000);
                   ack <= 1'b1;
                end
                else begin
                   ram_wr   <= wbm_we_o;
                   ram_rd   <=~(R177054[0]|wbm_we_o) & R177054[4];
                   ack      <=~wbm_we_o & R177054[0];
                end
                rio      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o140)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b1;
                ram_wr   <= wbm_we_o;
                ram_rd   <= 1'b0;
                ack      <=~wbm_we_o;
                rio      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o160)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b1;
                ram_wr   <= wbm_we_o;
                ram_rd   <= 1'b0;
                ack      <=~wbm_we_o;
                rio      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o177)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b1;
                ram_wr   <= wbm_we_o;
                ram_rd   <= 1'b0;
                ack      <=~wbm_we_o;
                rio      <= 1'b0;
            end else begin
                rom <= 1'b0;
                romcart <= 1'b0;
                ide_rd <= 1'b0;
                ide_wr <= 1'b0;
                ram_wr <= 1'b0;
                ram_rd <= 1'b0;
                if(wbm_we_o)begin
                    if(wbm_adr_o[8:1] == 'o4)begin
                        addr_ram[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        addr_ram[7:0]  <= wbm_sel_o[0] ? wbm_dat_o[7:0]  : 8'o0;
                        R177010[15:8]  <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R177010[ 7:0]  <= wbm_sel_o[0] ? wbm_dat_o[7:0]  : 8'o0;
                        rio_ram_rd     <= 1'b1;
                        mask_rio       <= 4'b0000;
                        ack            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o5)begin 
                        ramd_rio       <= wbm_sel_o[0] ? {2{wbm_dat_o[7:0]}} : 16'o0;
                        R177012        <= wbm_sel_o[0] ? {2{wbm_dat_o[7:0]}} : 16'o0;
                        addr_ram       <= R177010;
                        mask_rio       <= {2'b11,~R177010[0],R177010[0]};
                        rio_ram_wr     <= 1'b1;
                        ack            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o6)begin
                        ramd_rio[31:24]<= wbm_sel_o[1] ? wbm_dat_o[15:8] : R177014[15:8];
                        ramd_rio[23:16]<= wbm_sel_o[0] ? wbm_dat_o[7:0]  : R177014[7:0];
                        R177014[15:8]  <= wbm_sel_o[1] ? wbm_dat_o[15:8] : R177014[15:8];
                        R177014[7:0]   <= wbm_sel_o[0] ? wbm_dat_o[7:0]  : R177014[7:0];
                        addr_ram       <= R177010;
                        mask_rio       <= 4'b0011;
                        rio_ram_wr     <= 1'b1;
                        ack            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o7)begin
                        R177016       <= {13'o0,wbm_dat_o[2:0]};
                        ack           <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o10)begin
                        R177020[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R177020[7:0]  <= wbm_sel_o[0] ? wbm_dat_o[7:0]  : 8'o0;
                        ack <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o11)begin
                        R177022[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R177022[7:0]  <= wbm_sel_o[0] ? wbm_dat_o[7:0]  : 8'o0;
                        ack <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o12)begin // 0177024
                        addr_ram      <= R177010;
                        ramd_rio      <= data_reg_out_plan_out;
                        mask_rio      <= io_dqm_out;
                        rio_ram_wr    <= 1'b1;
                        ack           <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o13)begin
                        R177026       <= {13'o0,wbm_dat_o[2:0]};
                        ack           <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o26)begin
                        R177054       <= wbm_dat_o[9:0];
                        ack           <= 1'b1;
                    end else 
                    if(wbm_adr_o[8:1] >= 'o14 && wbm_adr_o[8:1] <'o26)begin
                        ack           <= 1'b1;
                    end else
                    /*if(wbm_adr_o[8:1] >= 'o54 && wbm_adr_o[8:1] <'o56)begin
                        ack           <= 1'b1;
                    end else*/
                    begin
                        //ack           <= 1'b1;
                    end

                end else begin
// read
                    if(wbm_adr_o[8:1] == 'o4)begin
                        data_rio   <= R177010;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o5)begin
                        data_rio   <= R177010[0] ? R177012[15:8] : R177012[7:0];
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o6)begin
                        data_rio   <= R177014;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o7)begin
                        data_rio   <= {13'd0,R177016[2:0]};
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o10)begin
                        data_rio   <= R177020;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o11)begin
                        data_rio   <= R177022;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o12)begin //  0177024
                        data_rio       <= 16'd0;
                        rio            <= 1'b1;
                        read_177124    <= 1'b1;
                        addr_ram       <= R177010;
                        mask_rio       <= 4'b0000;
                        rio_ram_rd     <= 1'b1;
                        ack            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o13)begin
                        data_rio   <= {13'd0,R177026[2:0]};
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o26)begin
                        data_rio   <= {6'd0,R177054};
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] >= 'o14 && wbm_adr_o[8:1] <'o26)begin
                        data_rio   <= 16'o000000;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    /*if(wbm_adr_o[8:1] >= 'o54 && wbm_adr_o[8:1] <'o56)begin
                        data_rio   <= 16'o000000;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else*/
                    if(wbm_adr_o[8:1] == 'o200)begin   // 177400
                        data_rio   <= mouse;
                        ack        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    begin
                        //ack       <= 1'b1;
                    end

                end
            end
        end
    end
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Registers color/pixel/fon
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//wire [7:0]mkdat = wbm_dat_o[7:0];//wbm_sel_o[0] ? wbm_dat_o[7:0]: wbm_dat_o[15:8];

mkcolorg mc1(
    .addr      (R177010[0]),
    .o177016   (R177016[2:0]),
    .o177020   (R177020),
    .o177022   (R177022),
    .o177026   (R177026[2:0]),
    .ADB       (wbm_dat_o[7:0]),

    .data_reg_out_plan_out  (data_reg_out_plan_out),
    .io_dqm_out             (io_dqm_out)
);

rd_plan mc2(
   .dinp_ram    (dinp_ram),
   .addr        (R177010[0]),
   .o177020_out (o177020_out),
   .o177022_out (o177022_out)
);

endmodule
