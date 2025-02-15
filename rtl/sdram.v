module sdram(
   // interface to the MT48LC16M16 chip
   output reg [10:0] SDRAM_A,       // 13 bit multiplexed address bus
   inout  reg [15:0] SDRAM_DQ,
   output reg [ 1:0] SDRAM_BA,      // two banks
   output            SDRAM_nCS,     // a single chip select
   output            SDRAM_nWE,     // write enable
   output            SDRAM_nRAS,    // row address select
   output            SDRAM_nCAS,    // columns address select
   output reg        SDRAM_DQML,
   output reg        SDRAM_DQMH,
   output            SDRAM_CLK,
 
   // cpu/chipset interface
   input             clk_50,      // sdram is accessed at up to 50MHz
   input             clk_25,      // sdram is accessed at up to 25MHz
   input             lockclk,
   output            init,     // init signal after FPGA config to initialize RAM
   
   output            hsync,
   output            vsync,
   output            visible,
   output     [ 2:0] red,
   output     [ 2:0] green,
   output     [ 2:0] blue,

   input      [18:0] cpu_addr,   // 19 bit address 
   output reg [15:0] cpu_dout,   // data output to cpu
   input      [15:0] cpu_din,    // data input from cpu
   input      [ 1:0] cpu_dqm,    // dqm write only
   input             cpu_read,   // cpu requests read
   input             cpu_wrte,   // cpu requests write
   output reg        cpu_ack,   // dout is valid. Ready to accept new read/write.

   input      [18:0] ppu_addr,   // 19 bit address 
   output reg [31:0] ppu_dout,   // data output to cpu
   input      [31:0] ppu_din,    // data input from cpu
   input      [ 3:0] ppu_dqm,    // dqm write only
   input             ppu_read,   // ppu requests read
   input             ppu_wrte,   // ppu requests write
   output reg        ppu_ack    // dout is valid. Ready to accept new read/write.
);
// ---------------------------------------------------------------------
// no burst configured
// ---------------------------------------------------------------------
localparam RASCAS_DELAY   = 3'd2;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 1'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------
localparam STATE_LAST      = 3'd7;   // last state in cycle
// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

// drive control signals according to current command
assign SDRAM_nCS  = 1'b0;
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];
assign init = reset == 0;

reg  [ 4:0] reset;
reg  [ 2:0] sd_cmd;   // current command sent to sd ram
reg  [10:0] horz;
reg  [ 9:0] vert;
reg  [15:0] vga_adst;        // address string in memory
reg  [15:0] vga_adnx    = 16'o270;  // address next string
reg         qutro_reg;
reg         types_reg;
reg         vga_curs;
reg         ppu_ll;
reg         ppu_hl;
reg         cpu_vl;
reg         curs_set;
reg [31:0] vga_regi;        // vga register isobr
reg [31:0] vga_regc;        // vga register color

always @(posedge curs_set or posedge new_scr)vga_curs <= new_scr ? 1'b0 : ~vga_curs;

wire [ 9:0] x            = horz[10:1] /* synthesis keep */;
wire        new_scr      = x[9:3]  == 0 && vert==0 /* synthesis keep */;
wire        get_regs0    = x[9:3]  == 3;
wire        get_regs1    = x[9:3]  == 4;
wire        get_regs2    = x[9:3]  == 5;
wire        get_regs3    = x[9:3]  == 6;
wire        get_regs     = get_regs0|get_regs1|get_regs2|get_regs3/* synthesis keep */;
wire        get_regs_new = vert[0] == 1'b0/* synthesis keep */;
wire        refresh      = x[9:3]  == 0;
// ---------------------------------------------------------------------
// --------------------- vga control signals ---------------------------
// ---------------------------------------------------------------------
`define HSYNC 64
`define HBP   80
`define HACTV 640
`define HFP   16
`define HSTR  800

`define VSYNC 3
`define VBP   14
`define VACTV 600
`define VFP   1
`define VSTR  618

wire   startd    = x > 143;
wire   visible_x = x > 16 + 64 + 80;
wire   visible_y = vert < 600;
assign hsync     = x > 15 && x < 16 + 64;
assign vsync     = vert > 600 + 13 && vert < 600 + 14 + 3;
assign visible   = visible_x && visible_y;

wire [ 9:0] xs = startd ?
                 vga_regi[21:20] == 2'b00 ? x - 10'd144 :
                 vga_regi[21:20] == 2'b01 ? x - 10'd144 :
                 vga_regi[21:20] == 2'b10 ? x - 10'd128 :
                                            x - 10'd96 : 10'd0;
// ---------------------------------------------------------------------
reg  [ 2:0] indx_reg = 0;
wire [15:0] addr_reg = qutro_reg ?  {vga_adnx[15:3],3'b000} + indx_reg : {vga_adnx[15:2],2'b00} + indx_reg /* synthesis keep */;
reg  [15:0] addr_scr = 0;

wire [10:0] reset_addr = (reset == 13)?11'b10000000000:MODE;
wire [ 3:0] q = horz[3:0] /* synthesis keep */;
wire cpu_select = &ppu_dqm_new[3:2];

reg  [21:0] cpu_addr_new = 0;
reg  [15:0] cpu_din_new  = 0;
reg  [ 1:0] cpu_dqm_new  = 0;
reg         cpu_read_new = 0;
reg         cpu_wrte_new = 0;


reg  [21:0] ppu_addr_new = 0;
reg  [31:0] ppu_din_new  = 0;
reg  [ 3:0] ppu_dqm_new  = 0;
reg         ppu_read_new = 0;
reg         ppu_wrte_new = 0;

reg  [ 7:0] ppu_emul = 8'b0000_0001;

reg  [ 7:0] pr_blue_data  = 0;
reg  [ 7:0] pr_green_data = 0;
reg  [ 7:0] pr_red_data   = 0;

reg  [ 7:0] blue_data     = 0;
reg  [ 7:0] green_data    = 0;
reg  [ 7:0] red_data      = 0;

reg  [15:0] RAM_DATA      = 0;

reg  [ 2:0] tripl         = 0;
reg         iscursor      = 0;

always @(posedge clk_50)begin
   RAM_DATA <= SDRAM_DQ;

   ppu_ll <= 1'b0;
   ppu_hl <= 1'b0;
   cpu_vl <= 1'b0;
//----------------------------------------------------------------------
// 
//----------------------------------------------------------------------
   if(new_scr)begin
      vga_adnx  <= 16'o270;
      types_reg <= 0;
      qutro_reg <= 0;
      curs_set  <= 0;
      indx_reg  <= 0;
   end 
// ---------------------------------------------------------------------
// --------------------------- steps/video ---------------------------
// ---------------------------------------------------------------------
   if(horz==1599)begin
      if(vert == 617)vert <= 10'd0;
      else vert <= vert + 1'b1;
      horz <= 11'd0;
   end else horz <= horz + 1'b1;
   
   // ---------------------------------------------------------------------
// Read data screen x > 79 && x < 640 + 80;
// ---------------------------------------------------------------------
   case(vga_regi[21:20])
   'b00: begin
           if(&q)begin
               addr_scr <=  vga_adst + xs[9:3];
           end
           if(vga_regi[14: 8] + 2'b10 == xs[9:3] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[2:0]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;
           //iscursor <= (vga_regi[14: 8] == x[9:3]) && (x[2:0]==vga_regi[7:5] || !vga_regi[4]) && vga_curs;
           tripl[0] <= blue_data [x[2:0]];
           tripl[1] <= green_data[x[2:0]];
           tripl[2] <= red_data  [x[2:0]];
         end
   'b01: begin
           if(&q)begin
               addr_scr   <=  vga_adst + xs[9:4];
           end
           if(vga_regi[14: 9] + 1'b1 == xs[9:4] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[3:1]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;
           //iscursor <= (vga_regi[14: 9] == x[9:4]) && (x[3:1]==vga_regi[7:5] || !vga_regi[4]) && vga_curs;
           tripl[0] <= blue_data [x[3:1]];
           tripl[1] <= green_data[x[3:1]];
           tripl[2] <= red_data  [x[3:1]];
         end
   'b10: begin
           if(&q && &xs[4:0])begin
               addr_scr <=  vga_adst + xs[9:5];
           end
           if(vga_regi[14: 10] + 1'b1 == xs[9:5] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[4:2]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;
           //iscursor <= (vga_regi[14:10] == x[9:5]) && (x[4:2]==vga_regi[7:5] || !vga_regi[4]) && vga_curs;
           tripl[0] <= pr_blue_data [x[4:2]];
           tripl[1] <= pr_green_data[x[4:2]];
           tripl[2] <= pr_red_data  [x[4:2]];
         end
   'b11: begin
           if(&q && &xs[5:0])begin
               addr_scr <=  vga_adst + xs[9:6];
           end
           if(vga_regi[14: 11] + 1'b1 == xs[9:6] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[5:3]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;
           //iscursor <= (vga_regi[14:11] == x[9:6]) && (x[5:3]==vga_regi[7:5] || !vga_regi[4]) && vga_curs;
           tripl[0] <= blue_data [xs[5:3]];
           tripl[1] <= green_data[xs[5:3]];
           tripl[2] <= red_data  [xs[5:3]];
         end
   endcase
// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
   if(!lockclk)begin
      reset <= 5'h1f;
      horz <= 0;
      vert <= 0;
   end else if((q == STATE_LAST) && (reset != 0))reset <= reset - 5'd1;
   
   if(reset != 0) begin
   end else
   if(refresh)begin
   end else begin
      case (q)
      4'd4 : begin
               if(get_regs)begin
                  if(get_regs_new)begin
                     indx_reg <= indx_reg + 2'b10;
                     case({qutro_reg,get_regs3,get_regs2,get_regs1})
                     'b1_000: if(types_reg) vga_regc[15: 0] <= RAM_DATA;
                              else          vga_regi[15: 0] <= RAM_DATA;
                     'b1_001: if(types_reg) vga_regc[31:16] <= RAM_DATA;
                              else          vga_regi[31:16] <= RAM_DATA;
                     'b1_010: vga_adst     <= RAM_DATA;
                     'b1_100: begin
                                 vga_adnx  <= RAM_DATA;
                                 curs_set  <= RAM_DATA[0];
                                 qutro_reg <= RAM_DATA[1];
                                 types_reg <= RAM_DATA[2];
                              end

                     'b0_000: vga_adst     <= RAM_DATA;
                     'b0_001: vga_adnx     <= RAM_DATA;
                     'b0_100: begin
                                 curs_set  <= vga_adnx[0];
                                 qutro_reg <= vga_adnx[1];
                                 types_reg <= vga_adnx[2];
                              end
                     endcase
                  end
               end else begin
                  pr_blue_data <= addr_scr[0] ? RAM_DATA[15:8]: RAM_DATA[7:0];
               end
             end
      4'd6 : begin
               cpu_addr_new <= cpu_addr;
               cpu_din_new  <= cpu_din;
               cpu_dqm_new  <= cpu_dqm;
               cpu_read_new <= cpu_read;
               cpu_wrte_new <= cpu_wrte;


               ppu_addr_new <= ppu_addr;
               ppu_din_new  <= ppu_din;
               ppu_dqm_new  <= ppu_dqm;

               ppu_read_new <= ppu_read & ppu_emul[0];
               ppu_wrte_new <= ppu_wrte & ppu_emul[0];

               ppu_emul <= {ppu_emul[2:0],ppu_emul[3]};
             end
      4'd7 : begin
               if(!get_regs)begin
                  pr_green_data  <= RAM_DATA[ 7:0];
                  pr_red_data    <= RAM_DATA[15:8];
               end
             end
      4'd9: begin
               if(ppu_wrte_new)begin
                  ppu_ll     <= cpu_select;
               end
             end
      4'd12: begin
               if(ppu_read_new)begin 
                  ppu_dout[15: 0] <= RAM_DATA;
                  ppu_ll          <= cpu_select;
               end
               if(cpu_select)begin
                  if(cpu_wrte_new) cpu_vl <= 1'b1;
               end else begin
                  if(ppu_wrte_new) ppu_hl <= 1'b1;
               end
             end
      4'd15: begin
               blue_data  <= pr_blue_data  ;
               green_data <= pr_green_data ;
               red_data   <= pr_red_data   ;
// ---------------------------------------------------------------------
// --------------------------- Get data CPU or high PPU-----------------
// ---------------------------------------------------------------------
               if(cpu_select)begin
                  cpu_vl <= cpu_read_new;
                  cpu_dout <= RAM_DATA;
               end else begin
                  ppu_hl <= ppu_read_new;
                  ppu_dout[31:16] <= RAM_DATA;
               end
             end
      endcase
      end
   end

always @(*)begin
   if(reset != 0) begin
      if(q == 0) begin
         SDRAM_A    <= reset_addr;
         SDRAM_DQ   <= 16'hZZZZ;
         SDRAM_BA   <= 2'b00;
         SDRAM_DQML <= 1;
         SDRAM_DQMH <= 1;
         if(reset == 13)  sd_cmd <= CMD_PRECHARGE;
         else if(reset ==  2)  sd_cmd <= CMD_LOAD_MODE;
         else  sd_cmd <= CMD_NOP;
      end else begin
         SDRAM_A    <= reset_addr;
         SDRAM_DQ   <= 16'hZZZZ;
         SDRAM_BA   <= 2'b00;
         SDRAM_DQML <= 1;
         SDRAM_DQMH <= 1;
         sd_cmd     <= CMD_NOP;
      end
   end else
   if(refresh)begin
         SDRAM_A      <= 0;
         SDRAM_DQ     <= 16'hZZZZ;
         SDRAM_BA     <= 2'b00;
         SDRAM_DQML   <= 1;
         SDRAM_DQMH   <= 1;
         if(q==7)sd_cmd <= CMD_AUTO_REFRESH;
         else  sd_cmd <= CMD_NOP;
   end else begin
      case (q)
      4'd0 : begin
// ---------------------------------------------------------------------
// --------------------------- control/adress regs ---------------------
// ---------------------------------------------------------------------
               if(get_regs)begin   // Get control register
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= {4'd0, addr_reg[15:9]}; //ppu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin      // Get adress reg
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= {4'd0, addr_scr[15:9]}; //ppu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd1 : begin
// ---------------------------------------------------------------------
// --------------------------- NOP operation ---------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
             end
      4'd2 : begin
// ---------------------------------------------------------------------
// --------------------------- READ CMD --------------------------------
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 3'b100, addr_reg[8:1]}; //Zone ppu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 3'b100, addr_scr[8:1]}; // Zone ppu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end
             end
      4'd3 : begin
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get scr data----------
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= {3'd0, addr_scr[15:8]}; //Zone cpu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd4 : begin
// First word data from sdram
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get scr data----------
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
             end
      4'd5 : begin
// Second word data from sdram
// ---------------------------------------------------------------------
// -------if get register then NOP operation else CMD scr CPU data -----
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 3'b100, addr_scr[7:0]};//cpu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end

             end
      4'd6 : begin
// Third word data from sdram
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get addr str scr -----
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd7 : begin
// Fourth word data from sdram or first data str scr
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get addr str scr -----
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
             end
      4'd8 : begin
// ---------------------------------------------------------------------
// ----------------Start get PPU data -------------------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= ppu_addr_new[18:9]; //ppu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
             end
      4'd9 : begin
// ---------------------------------------------------------------------
// --------------------------- NOP operation ---------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd10: begin
// ---------------------------------------------------------------------
// --------------------------- R/W operation ---------------------------
// ---------------------------------------------------------------------
               if(ppu_wrte_new)begin
                  sd_cmd     <= CMD_WRITE;
                  SDRAM_A    <= {3'b100, ppu_addr_new[8:1]};//ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQ   <= ppu_din_new[15:0];
                  SDRAM_DQML <= ppu_dqm_new[0];
                  SDRAM_DQMH <= ppu_dqm_new[1];
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 3'b100, ppu_addr_new[8:1]};//ppu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end

             end
      4'd11: begin
// ---------------------------------------------------------------------
// -----if ppu_dqm[3:2]!=0 then r/w oper CPU else r/w oper PPU----------
// ---------------------------------------------------------------------
               if(cpu_select)begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= cpu_addr_new[18:8]; //Zone cpu
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= ppu_addr_new[18:8]; //Zone cpu (from register ppu)
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd12: begin
               begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
             end
      4'd13: begin
// ---------------------------------------------------------------------
// -------------R/W operation to zone cpu (PPU  regs or CPU)------------
// ---------------------------------------------------------------------
               if(cpu_select)begin
// ---------------------------------------------------------------------
                  if(cpu_wrte_new)begin
                     sd_cmd     <= CMD_WRITE;
                     SDRAM_A    <= { 3'b100, cpu_addr_new[7:0]}; //cpu
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQ   <= cpu_din_new;
                     SDRAM_DQML <= cpu_dqm_new[0];
                     SDRAM_DQMH <= cpu_dqm_new[1];
                  end else begin
                     sd_cmd     <= CMD_READ;
                     SDRAM_A    <= { 3'b100, cpu_addr_new[7:0]}; //cpu
                     SDRAM_DQ   <= 16'hZZZZ;
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQML <= 0;
                     SDRAM_DQMH <= 0;
                  end
               end else begin
                  if(ppu_wrte_new)begin
                     sd_cmd     <= CMD_WRITE;
                     SDRAM_A    <= { 3'b100, ppu_addr_new[7:0]}; //cpu (from register ppu)
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQ   <= ppu_din_new[31:16];
                     SDRAM_DQML <= ppu_dqm_new[2];
                     SDRAM_DQMH <= ppu_dqm_new[3];
                  end else begin
                     sd_cmd     <= CMD_READ;
                     SDRAM_A    <= { 3'b100, ppu_addr_new[7:0]}; //cpu (from register ppu)
                     SDRAM_DQ   <= 16'hZZZZ;
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQML <= 0;
                     SDRAM_DQMH <= 0;
                  end
               end
             end
      4'd14: begin
               begin
                  sd_cmd     <= CMD_NOP;
                  SDRAM_A    <= 0;
                  SDRAM_DQ   <= 16'hZZZZ;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
             end
      4'd15: begin
               sd_cmd     <= CMD_NOP;
               SDRAM_A    <= 0;
               SDRAM_DQ   <= 16'hZZZZ;
               SDRAM_BA   <= 2'b01;
               SDRAM_DQML <= 1;
               SDRAM_DQMH <= 1;
             end
      endcase
      end
   end
//-------------------------------------------------------------------
//-------------PPU/CPU busy/asck signals-----------------------------
//-------------------------------------------------------------------
always @(posedge clk_50)begin
      if(init)begin
//-------------------------------------------------------------------
           if(!(ppu_read|ppu_wrte))ppu_ack <= 1'b0;
           if(ppu_hl||ppu_ll)ppu_ack <= 1'b1;
//-------------------------------------------------------------------
           if(!(cpu_read|cpu_wrte))cpu_ack <= 1'b0;
           if(cpu_vl)cpu_ack <= 1'b1;
//-------------------------------------------------------------------
      end else begin
         ppu_ack <= 1'b0;
         cpu_ack <= 1'b0;
      end
   end
//---------------------------------------------------------------------------------------------------------//
//          VGA generator
//---------------------------------------------------------------------------------------------------------//
// 640x576 @ 50.00 Hz (GTF) hsync: 29.65 kHz; pclk: 23.72 MHz
// Modeline "640x600_50.00" 25.00 640 656 710 800 600 601 604 618 -HSync +Vsync
//  _____|^^^^^|_______|^^^^^^^^^^^^^^^^^^^^^^^^^^^^|______
//   FP   HSYNC   BP         ACTIVE                    FP
//---------------------------------------------------------------------------------------------------------//
`define HSYNC 64
`define HBP   80
`define HACTV 640
`define HFP   16
`define HSTR  800

`define VSYNC 3
`define VBP   14
`define VACTV 600
`define VFP   1
`define VSTR  618

`define HVS   `HFP + `HSYNC + `HBP
`define VVS   `VFP + `VSYNC + `VBP

// ---------------------------------------------------------------------
// display out logic
// ---------------------------------------------------------------------
reg  [ 3:0]cvt;

always @(*)
    case(tripl)
    3'b000: cvt <= vga_regc[ 3: 0];
    3'b001: cvt <= vga_regc[ 7: 4];
    3'b010: cvt <= vga_regc[11: 8];
    3'b011: cvt <= vga_regc[15:12];
    3'b100: cvt <= vga_regc[19:16];
    3'b101: cvt <= vga_regc[23:20];
    3'b110: cvt <= vga_regc[27:24];
    3'b111: cvt <= vga_regc[31:28];
    endcase

wire [ 2:0]curR = vga_regi[2] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curG = vga_regi[1] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curB = vga_regi[0] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;

assign red   = (cvt[2] & visible ? vga_regi[18] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible & iscursor ? curR : 3'd0);
assign green = (cvt[1] & visible ? vga_regi[17] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible & iscursor ? curG : 3'd0);
assign blue  = (cvt[0] & visible ? vga_regi[16] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible & iscursor ? curB : 3'd0);
//---------------------------------------------------------------------------------------------------------//
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_50),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
