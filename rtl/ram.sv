module ram
(
   input             clk,
   input             reset,

   output            ce_pix,
   output reg        hsync,
   output reg        vsync,
   output reg        hblank,
   output reg        vblank,
   output reg [ 2:0] red,
   output reg [ 2:0] green,
   output reg [ 2:0] blue,

   input      [15:0] cpu_addr,   // address 
   output reg [15:0] cpu_dout,   // data output to cpu
   input      [15:0] cpu_din,    // data input from cpu
   input      [ 1:0] cpu_dqm,    // dqm write only
   input             cpu_read,   // cpu requests read
   input             cpu_wrte,   // cpu requests write
   output reg        cpu_ack,    // dout is valid. Ready to accept new read/write.

   input      [15:0] ppu_addr,   // address 
   output reg [31:0] ppu_dout,   // data output to cpu
   input      [31:0] ppu_din,    // data input from cpu
   input      [ 3:0] ppu_dqm,    // dqm write only
   input             ppu_read,   // ppu requests read
   input             ppu_wrte,   // ppu requests write
   output reg        ppu_ack     // dout is valid. Ready to accept new read/write.
);

reg [10:0] horz;
reg [ 9:0] vert;
reg [15:0] vga_adst;  // address string in memory
reg [15:0] vga_adnx;  // address next string
reg        four_regs;
reg        types_reg;
reg        vga_curs;
reg        curs_set;
reg [31:0] vga_regi;  // vga register isobr
reg [31:0] vga_regc;  // vga register color

wire [9:0] x = horz[10:1];

wire new_scr   = x[9:3] == 0 && vert==0;
wire get_regs0 = x[9:3] == 3;
wire get_regs1 = x[9:3] == 4;
wire get_regs2 = x[9:3] == 5;
wire get_regs3 = x[9:3] == 6;
wire get_regs  = get_regs0|get_regs1|get_regs2|get_regs3;

// ---------------------------------------------------------------------
// --------------------- vga control signals ---------------------------
// ---------------------------------------------------------------------

wire visible_x = x > 159;
wire visible_y = vert > 19 && vert < 308;
wire hs        = x > 15 && x < 16 + 64;
wire vs        = vert > 309;

// ---------------------------------------------------------------------
reg  [ 2:0] indx_reg;
wire [15:0] addr_reg = four_regs ?  {vga_adnx[15:3],3'b000} + indx_reg : {vga_adnx[15:2],2'b00} + indx_reg;
reg  [15:0] addr_scr;

reg  [ 7:0] blue_data;
reg  [ 7:0] green_data;
reg  [ 7:0] red_data;

reg  [ 2:0] tripl;
reg         iscursor;
reg         curs_set_d;

wire [ 3:0] q = horz[3:0];
assign ce_pix = horz[0];

reg  [12:0] xs;
wire  [1:0] scale = vga_regi[21:20];
wire  [9:0] px = xs[scale +:10];

always @(posedge clk) begin

   curs_set_d <= curs_set;
   if(~curs_set_d & curs_set) vga_curs <= ~vga_curs;

   if(new_scr)begin
      vga_adnx  <= 16'o270;
      types_reg <= 0;
      four_regs <= 0;
      curs_set  <= 0;
      curs_set_d<= 0;
      indx_reg  <= 0;
      vga_curs  <= 0;
   end 

// ---------------------------------------------------------------------
// --------------------------- steps/video ---------------------------
// ---------------------------------------------------------------------
   horz <= horz + 1'b1;
   if(horz >= 1599)begin
      horz <= 0;
      vert <= vert + 1'b1;
      if(vert >= 311) vert <= 0;
   end

	xs <= visible_x ? (xs + horz[0]) : 13'd0;
	addr_scr <= vga_adst + px[9:3] + visible_x;

	tripl[0] <= blue_data [px[2:0]];
   tripl[1] <= green_data[px[2:0]];
   tripl[2] <= red_data  [px[2:0]];
   iscursor <= vga_curs && ((vga_regi[14:8]>>scale) == px[9:3]) && (~vga_regi[4] || (px[2:0] == vga_regi[7:5]));
	
   if(&q) begin
		if(get_regs)begin
			indx_reg <= indx_reg + 2'b10;
			case({four_regs,get_regs3,get_regs2,get_regs1})
			'b1_000: if(types_reg) vga_regc[15: 0] <= bram_data1;
						else          vga_regi[15: 0] <= bram_data1;
			'b1_001: if(types_reg) vga_regc[31:16] <= bram_data1;
						else          vga_regi[31:16] <= bram_data1;
			'b1_010: vga_adst     <= bram_data1;
			'b1_100: begin
							vga_adnx  <= bram_data1;
							curs_set  <= bram_data1[0];
							four_regs <= bram_data1[1];
							types_reg <= bram_data1[2];
						end

			'b0_000: vga_adst     <= bram_data1;
			'b0_001: vga_adnx     <= bram_data1;
			'b0_100: begin
							curs_set  <= vga_adnx[0];
							four_regs <= vga_adnx[1];
							types_reg <= vga_adnx[2];
						end
			endcase
		end else begin
			if(&px[2:0] || ~visible_x) begin
				blue_data  <= addr_scr[0] ? bram_data1[15:8]: bram_data1[7:0];
				green_data <= bram_data2[7:0];
				red_data   <= bram_data2[15:8];
			end
		end
	end
end

wire cpu_select = &ppu_dqm_new[3:2];

reg  [15:0] cpu_addr_new;
reg  [15:0] cpu_din_new;
reg  [ 1:0] cpu_dqm_new;
reg         cpu_read_new;
reg         cpu_wrte_new;

reg  [15:0] ppu_addr_new;
reg  [31:0] ppu_din_new;
reg  [ 3:0] ppu_dqm_new;
reg         ppu_read_new;
reg         ppu_wrte_new;

reg  [ 7:0] ppu_emul = 8'b0000_0001;

always @(posedge clk) begin
   bramppu_we <= 0;
   bramcpu_we <= 0;
   if(!(ppu_read|ppu_wrte)) ppu_ack <= 0;
   if(!(cpu_read|cpu_wrte)) cpu_ack <= 0;

   case (q[2:0])
      0: begin
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

      1: begin
            //ppu memory
            if(ppu_wrte_new)begin
               bramppu_we <= ~ppu_dqm_new[1:0];
               ppu_ack     <= 1'b1;
            end

            //cpu memory
            if(cpu_select)begin
               if(cpu_wrte_new) begin 
                  bramcpu_we <= ~cpu_dqm_new[1:0];
                  cpu_ack <= 1'b1;
               end
            end else begin
               if(ppu_wrte_new) begin 
                  bramcpu_we <= ~ppu_dqm_new[3:2];
                  ppu_ack <= 1'b1;
               end
            end
         end

      2: begin
            //ppu memory
            if(ppu_read_new)begin 
               ppu_dout[15:0] <= bramppu_data;
               ppu_ack        <= 1'b1;
            end

            //cpu memory
            if(cpu_select) begin
               if(cpu_read_new) begin
                  cpu_dout <= bramcpu_data;
                  cpu_ack <= 1'b1;
               end
            end else begin
               if(ppu_read_new) begin
                  ppu_dout[31:16] <= bramcpu_data;
                  ppu_ack <= 1'b1;
               end
            end
         end
   endcase
end

//---------------------------------------------------------------------------------------------------------//
//          VGA generator
//---------------------------------------------------------------------------------------------------------//
// 640x576 @ 50.00 Hz (GTF) hsync: 29.65 kHz; pclk: 23.72 MHz
// Modeline "640x600_50.00" 25.00 640 656 710 800 600 601 604 618 -HSync +Vsync
//  _____|^^^^^|_______|^^^^^^^^^^^^^^^^^^^^^^^^^^^^|______
//   FP   HSYNC   BP         ACTIVE                    FP
//---------------------------------------------------------------------------------------------------------//

// ---------------------------------------------------------------------
// display out logic
// ---------------------------------------------------------------------
wire [ 2:0]curR = vga_regi[2] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curG = vga_regi[1] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curB = vga_regi[0] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;

wire [3:0] cvt = vga_regc[tripl*4 +:4];

wire [2:0] r = (cvt[2] ? vga_regi[18] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (iscursor ? curR : 3'd0);
wire [2:0] g = (cvt[1] ? vga_regi[17] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (iscursor ? curG : 3'd0);
wire [2:0] b = (cvt[0] ? vga_regi[16] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (iscursor ? curB : 3'd0);

always @(posedge clk) begin
   red   <= r;
   green <= g;
   blue  <= b;
   hsync <= hs;
   vsync <= vs;
   hblank<= ~visible_x;
   vblank<= ~visible_y;
end

//---------------------------------------------------------------------------------------------------------//

wire [15:0] bramppu_data, bramcpu_data;
wire [15:0] bram_data1, bram_data2;
reg   [1:0] bramppu_we, bramcpu_we;

dpram #(15) bramppu_l
(
   .clock(clk),

   .address_a(ppu_addr_new[15:1]),
   .data_a(ppu_din_new[7:0]),
   .wren_a(bramppu_we[0]),
   .q_a(bramppu_data[7:0]),
	
   .address_b(get_regs ? addr_reg[15:1] : addr_scr[15:1]),
   .q_b(bram_data1[7:0])
);

dpram #(15) bramppu_u
(
   .clock(clk),

   .address_a(ppu_addr_new[15:1]),
   .data_a(ppu_din_new[15:8]),
   .wren_a(bramppu_we[1]),
   .q_a(bramppu_data[15:8]),

   .address_b(get_regs ? addr_reg[15:1] : addr_scr[15:1]),
   .q_b(bram_data1[15:8])
);

dpram #(16) bramcpu_l
(
	.clock(clk),

	.address_a(cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0]),
	.data_a(cpu_select ? cpu_din_new[7:0] : ppu_din_new[23:16] ),
	.wren_a(bramcpu_we[0]),
	.q_a(bramcpu_data[7:0]),

	.address_b(addr_scr[15:0]),
	.q_b(bram_data2[7:0])
);

dpram #(16) bramcpu_u
(
	.clock(clk),

	.address_a(cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0]),
	.data_a(cpu_select ? cpu_din_new[15:8] : ppu_din_new[31:24] ),
	.wren_a(bramcpu_we[1]),
	.q_a(bramcpu_data[15:8]),

	.address_b(addr_scr[15:0]),
	.q_b(bram_data2[15:8])
);

endmodule
