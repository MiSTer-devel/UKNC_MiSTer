module sdram(
   // interface to the MT48LC16M16 chip
   output reg [12:0] SDRAM_A,       // 13 bit multiplexed address bus
   inout  reg [15:0] SDRAM_DQ,
   output reg [ 1:0] SDRAM_BA,      // two banks
   output            SDRAM_nCS,     // a single chip select
   output            SDRAM_nWE,     // write enable
   output            SDRAM_nRAS,    // row address select
   output            SDRAM_nCAS,    // columns address select
   output            SDRAM_DQML,
   output            SDRAM_DQMH,
   output            SDRAM_CLK,

   // cpu/chipset interface
   input             clk_50,      // sdram is accessed at up to 128MHz
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
   input      [ 3:0] cpu_dqm,    // dqm write only
   input             cpu_read,   // cpu requests read
   input             cpu_wrte,   // cpu requests write
   output reg        cpu_ack ,   // dout is valid. Ready to accept new read/write.

   input      [18:0] ppu_addr,   // 19 bit address 
   output reg [31:0] ppu_dout,   // data output to cpu
   input      [31:0] ppu_din,    // data input from cpu
   input      [ 3:0] ppu_dqm,    // dqm write only
   input             ppu_read,   // ppu requests read
   input             ppu_wrte,   // ppu requests write
   output reg        ppu_ack     // dout is valid. Ready to accept new read/write.
);
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
// no burst configured
// ---------------------------------------------------------------------
localparam RASCAS_DELAY   = 3'd2;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

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

reg  [ 4:0] reset;
wire [12:0] reset_addr = (reset == 13) ? 13'b0010000000000 : MODE;
reg  [ 2:0] sd_cmd;   // current command sent to sd ram
// drive control signals according to current command
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];
assign SDRAM_nCS  = 1'b0;
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];
assign init       = reset == 0;

reg  [15:0] RAM_DATA;
reg  [10:0] horz;
reg  [ 9:0] vert;
wire        refresh  = horz[10:4] == 81;
wire [ 3:0] state    = horz[3:0];

// ---------------------------------------------------------------------
// UKNC Screen
// ---------------------------------------------------------------------
reg  [18:0] addr_blu;
reg  [18:0] addr_gr;
reg  [15:0] vga_adst;        // address string in memory
reg  [15:0] vga_adnx   = 16'o270;  // address next string
reg  [31:0] vga_regi;        // vga register isobr
reg  [31:0] vga_regc;        // vga register color

reg         qutro_reg;
reg         types_reg;
reg         vga_curs;

reg  [ 7:0] blue_data;
reg  [ 7:0] green_data;
reg  [ 7:0] red_data;
reg  [ 7:0] blue_;
reg  [ 7:0] green_;
reg  [ 7:0] red_;


wire [15:0] addr_reg = qutro_reg ? {vga_adnx[15:3],2'b00} : {vga_adnx[15:2],1'b0};
// ---------------------------------------------------------------------
// PPU / CPU
// ---------------------------------------------------------------------
reg  [18:0] addr_uknc_lo = 0;     //PPU zone
reg  [15:0] din_uknc_lo  = 0;
reg  [ 1:0] dqm_uknc_lo  = 0;
reg         read_uknc_lo = 0;
reg         wrte_uknc_lo = 0;

reg  [18:0] addr_uknc_hi = 0;     //CPU zone
reg  [15:0] din_uknc_hi  = 0;
reg  [ 1:0] dqm_uknc_hi  = 0;
reg         read_uknc_hi = 0;
reg         wrte_uknc_hi = 0;

reg         cpu_select   = 0;
// ---------------------------------------------------------------------

always @(posedge clk_50) begin
   SDRAM_DQ <= 16'hZZZZ;
   RAM_DATA <= SDRAM_DQ;
   
   if (!(cpu_read | cpu_wrte)) cpu_ack <= 0;
   if (!(ppu_read | ppu_wrte)) ppu_ack <= 0;

/*   if (horz < `HSTR * 2) begin
       horz <= horz + 1'b1;
   end else begin
         horz <= 0;
         if (vert < `VSTR) vert <= vert + 1'b1;
         else vert <= 0;
   end */
   if (horz==1599) begin
      if (vert == 617) vert <= 10'd0;
      else vert <= vert + 1'b1;
      horz <= 11'd0;
   end else horz <= horz + 1'b1;
// ---------------------------------------------------------------------
// new screen / screen str
// ---------------------------------------------------------------------
   if (horz == 1310 && vert == 617) begin
      vga_adnx <= 16'o270;
      types_reg <= 0;
      qutro_reg <= 0;
      vga_curs  <= 0;
   end

   if (horz == 1311) begin
      addr_blu <= addr_reg;
   end
   if (horz == 1311 + 16) begin
      addr_blu <= addr_reg + 2'b01;
   end
   if (horz == 1311 + 32) begin
      addr_blu <= addr_reg + 2'b10;
   end
   if (horz == 1311 + 48) begin
      addr_blu <= addr_reg + 2'b11;
   end

// ---------------------------------------------------------------------
// new string
// ---------------------------------------------------------------------
  if (horz == 1583) begin
      addr_blu <= vga_adst>>1;
      addr_gr  <= vga_adst;
   end
   if (horz < 1264 && state[3]) begin
      addr_blu <= (vga_adst + adtx + 1'b1)>>1;
      addr_gr  <=  vga_adst + adtx + 1'b1;
   end
//=======================================================================
// Initial SDRAM
//=======================================================================
   if (!lockclk) begin
      reset <= 5'h1f;
   end else if((state == STATE_LAST) && (reset != 0))reset <= reset - 5'd1;

   if(reset != 0) begin
      if(state == 0) begin
         SDRAM_A    <= reset_addr;
         SDRAM_BA   <= 2'b00;
         if (reset == 13)     sd_cmd <= CMD_PRECHARGE;
         else if (reset == 2) sd_cmd <= CMD_LOAD_MODE;
         else                 sd_cmd <= CMD_NOP;
      end else begin
         SDRAM_A    <= reset_addr;
         SDRAM_BA   <= 2'b00;
         sd_cmd     <= CMD_NOP;

         cpu_ack <= 0;
         ppu_ack <= 0;
         read_uknc_lo <= 0;
         wrte_uknc_lo <= 0;
         read_uknc_hi <= 0;
         wrte_uknc_hi <= 0;
      end
   end else
   if (refresh) begin
         SDRAM_A      <= 13'h0000;
         SDRAM_BA     <= 2'b00;
         if (state == STATE_LAST) sd_cmd <= CMD_AUTO_REFRESH;
         else               sd_cmd <= CMD_NOP;
   end else begin
//=======================================================================
// Get data screen/cpu/ppu
//=======================================================================
// ---------------------------------------------------------------------
// new screen regs
// ---------------------------------------------------------------------
      if (state == 5) begin

         if (horz[10:4] == 82 && vert[0]) begin
            if (qutro_reg) begin
               if (types_reg) vga_regc[15:0] <= RAM_DATA;
               else           vga_regi[15:0] <= RAM_DATA;
            end else          vga_adst       <= RAM_DATA;
         end

         if (horz[10:4] == 83 && vert[0]) begin
            if (qutro_reg) begin
               if (types_reg) vga_regc[31:16] <= RAM_DATA;
               else           vga_regi[31:16] <= RAM_DATA;
            end else          vga_adnx        <= RAM_DATA;
         end

         if (horz[10:4] == 84 && vert[0]) begin
            if (qutro_reg) vga_adst  <= RAM_DATA;
            else           types_reg <= vga_adnx[2];
         end

         if (horz[10:4] == 85 && vert[0]) begin
            if (qutro_reg) begin
               vga_adnx  <= RAM_DATA;
               vga_curs  <= RAM_DATA[0] ? ~vga_curs : vga_curs;
               qutro_reg <= RAM_DATA[1];
               types_reg <= RAM_DATA[2];
            end else begin
               qutro_reg <= vga_adnx[1];
               vga_curs  <= vga_adnx[0] ? ~vga_curs : vga_curs;
            end
         end
         blue_data <= addr_gr[0] ? RAM_DATA[15:8] : RAM_DATA[7:0];
      end
      if (state == 6) begin
         {green_data,red_data} <= RAM_DATA;
      end
      if (vga_regi[21:20] == 2 && state ==  7) begin
         blue_  <= blue_data;
         green_ <= green_data;
         red_   <= red_data;
      end
// ---------------------------------------------------------------------
// cpu/ppu 
// ---------------------------------------------------------------------
      if (state == 6) cpu_select <= &ppu_dqm[3:2];
      if (state == 7) begin
         addr_uknc_lo <= ppu_addr[18:1];
         din_uknc_lo  <= ppu_din[15:0];
         dqm_uknc_lo  <= ppu_dqm[1:0];
         read_uknc_lo <= ppu_read;
         wrte_uknc_lo <= ppu_wrte;

         if (cpu_select) begin
            addr_uknc_hi <= cpu_addr[18:0];
            din_uknc_hi  <= cpu_din;
            dqm_uknc_hi  <= cpu_dqm[3:2];
            wrte_uknc_hi <= cpu_wrte;
            read_uknc_hi <= cpu_read;
         end else begin
            addr_uknc_hi <= ppu_addr[18:0];
            din_uknc_hi  <= ppu_din[31:16];
            dqm_uknc_hi  <= ppu_dqm[3:2];
            wrte_uknc_hi <= ppu_wrte;
            read_uknc_hi <= ppu_read;
         end
      end
      if (state == 13)  ppu_dout[15:0]  <= RAM_DATA;
      if (state == 14)
         if(cpu_select) cpu_dout        <= RAM_DATA;
         else           ppu_dout[31:16] <= RAM_DATA;
      if (state == 15) begin
         if (cpu_select) cpu_ack <= read_uknc_hi|wrte_uknc_hi;
         ppu_ack <= read_uknc_lo|wrte_uknc_lo;

         read_uknc_lo <= 0;
         read_uknc_hi <= 0;
         wrte_uknc_lo <= 0;
         wrte_uknc_hi <= 0;
         if (vga_regi[21:20] != 2) begin
            blue_  <= blue_data;
            green_ <= green_data;
            red_   <= red_data;
         end
      end
//=======================================================================
// sdram state m
//=======================================================================
      case (state)
      'd0 : begin
// ---------------------------------------------------------------------
// blue CMD_ACTIVE
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_ACTIVE;
               SDRAM_A    <= {2'b00, addr_blu[18:8]};
               SDRAM_BA   <= 2'b00;
            end
      'd1 : begin
// ---------------------------------------------------------------------
// green/red CMD_ACTIVE
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_ACTIVE;
               SDRAM_A    <= {2'b00, addr_gr[18:8]};
               SDRAM_BA   <= 2'b01;
            end
      'd2 : begin
// ---------------------------------------------------------------------
// blue CMD_READ
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_READ;
               SDRAM_A    <= { 5'b00100,addr_blu[7:0]};
               SDRAM_BA   <= 2'b00;
            end
      'd3 : begin
// ---------------------------------------------------------------------
// green/red CMD_READ
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_READ;
               SDRAM_A    <= { 5'b00100,addr_gr[7:0]};
               SDRAM_BA   <= 2'b01;
            end
      'd8 : begin
// ---------------------------------------------------------------------
// ppu CMD_ACTIVE
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_ACTIVE;
               SDRAM_A    <= {2'b00, addr_uknc_lo[18:8]};
               SDRAM_BA   <= 2'b00;
            end
      'd9 : begin
// ---------------------------------------------------------------------
// cpu CMD_ACTIVE
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_ACTIVE;
               SDRAM_A    <= {2'b00, addr_uknc_hi[18:8]};
               SDRAM_BA   <= 2'b01;
            end
      'd10: begin
// ---------------------------------------------------------------------
// ppu CMD_READ
// ---------------------------------------------------------------------
               if(wrte_uknc_lo)begin
                  sd_cmd     <= CMD_WRITE;
                  SDRAM_A    <= {dqm_uknc_lo, 3'b100,addr_uknc_lo[7:0]};
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQ   <= din_uknc_lo;
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 5'b00100,addr_uknc_lo[7:0]};
                  SDRAM_BA   <= 2'b00;
               end
            end
      'd11: begin
// ---------------------------------------------------------------------
// cpu CMD_READ
// ---------------------------------------------------------------------
               if(wrte_uknc_hi)begin
                  sd_cmd     <= CMD_WRITE;
                  SDRAM_A    <= { dqm_uknc_hi, 3'b100,addr_uknc_hi[7:0]};
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQ   <= din_uknc_hi;
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 5'b00100,addr_uknc_hi[7:0]};
                  SDRAM_BA   <= 2'b01;
               end
            end
      default: begin
               sd_cmd     <= CMD_NOP;
               SDRAM_A    <= 13'h0000;
               SDRAM_BA   <= 2'b00;
            end
      endcase
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
wire   visible_x = horz <  1280;
wire   visible_y = vert < (`VACTV + `VFP);
assign hsync   = horz >= 1312 && horz < 1408 ;
assign vsync   = vert >=  601 && vert < 604;
assign visible = visible_x && visible_y;
//---------------------------------------------------------------------------------------------------------//
//---------------------------------------------------------------------------------------------------------//
// adtx - адрес байта в строке, начинается с х=0
// indx - начало видимой части, начинается с х=8
// tx   - смещение битов в байте, для сдвига
//---------------------------------------------------------------------------------------------------------//
wire [ 9:0]x  = horz[10:1];

wire [ 9:0]xs = horz[10:1] + 4;

wire [ 9:0]adtx= vga_regi[21:20] == 0 ?  x[9:3] :
                 vga_regi[21:20] == 1 ?  x[9:4] :
                 vga_regi[21:20] == 2 ?  xs[9:5] : x[9:6];

wire [ 9:0]indx= vga_regi[21:20] == 0 ? x[9:3] :
                 vga_regi[21:20] == 1 ? x[9:4] :
                 vga_regi[21:20] == 2 ? xs[9:5] : x[9:6];

wire [ 2:0]tx  = vga_regi[21:20] == 0 ? x[2:0] :
                 vga_regi[21:20] == 1 ? x[3:1] :
                 vga_regi[21:20] == 2 ? x[4:2] : x[5:3];

reg  [ 2:0]tripl = 0;

always @(posedge clk_50)begin
        tripl[0] = blue_ [tx];
        tripl[1] = green_[tx];
        tripl[2] = red_  [tx];
    end

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

always @(*)
   case(vga_regi[21:20])
   'b00: xcursor <= vga_regi[14: 8];
   'b01: xcursor <= vga_regi[14: 9];
   'b10: xcursor <= vga_regi[14:10];
   'b11: xcursor <= vga_regi[14:11];
   endcase

wire [ 2:0]curR = vga_regi[2] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curG = vga_regi[1] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curB = vga_regi[0] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;

reg  [ 6:0] xcursor = 0;
wire        cursor_pos = xcursor + 1'b1 == indx;
wire        cursor_pos_byte = tx==vga_regi[7:5] || !vga_regi[4];
wire        iscursor   = cursor_pos & vga_curs & cursor_pos_byte;

assign red   = (cvt[2] & visible ? vga_regi[18] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible&iscursor ? curR : 3'd0);
assign green = (cvt[1] & visible ? vga_regi[17] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible&iscursor ? curG : 3'd0);
assign blue  = (cvt[0] & visible ? vga_regi[16] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible&iscursor ? curB : 3'd0);

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