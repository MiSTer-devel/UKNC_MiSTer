module video
(
   input             clk,

   output            ce_pix,
   output reg        hsync,
   output reg        vsync,
   output reg        hblank,
   output reg        vblank,
   output reg [ 7:0] red,
   output reg [ 7:0] green,
   output reg [ 7:0] blue,

   output      [3:0] cycle,

   output reg [15:0] addr_scr,
   input      [15:0] data1,
   input      [15:0] data2
);

reg [10:0] horz;
reg [ 9:0] vert;

reg [15:0] addr_line;
reg        four_regs;
reg        type_regs;

reg        curs_ena;
reg [31:0] reg_img;
reg [31:0] reg_clr;

wire [9:0] x = horz[10:1];

wire new_scr   = x[9:3] == 0 && vert==0;
wire get_regs0 = x[9:3] == 3 && four_regs;
wire get_regs1 = x[9:3] == 4 && four_regs;
wire get_regs2 = x[9:3] == 5;
wire get_regs3 = x[9:3] == 6;
wire get_regs  = get_regs0|get_regs1|get_regs2|get_regs3;

wire visible_x = x >= 160;
wire visible_y = vert >= 19 && vert < 307;
wire hs        = x >= 16 && x < 80;
wire vs        = vert >= 310;

reg  [15:0] addr_reg;

reg  [ 7:0] blue_data;
reg  [ 7:0] green_data;
reg  [ 7:0] red_data;

reg  [ 2:0] tripl;
reg         cursor;

assign cycle  = horz[3:0];
assign ce_pix = horz[0];

reg  [12:0] xs;
wire  [1:0] scale = reg_img[21:20];
wire  [9:0] px = xs[scale +:10];

always @(posedge clk) begin

   if(new_scr) begin
      addr_reg  <= 16'o270;
      type_regs <= 0;
      four_regs <= 0;
      curs_ena  <= 0;
   end

   horz <= horz + 1'b1;
   if(horz >= 1599) begin
      horz <= 0;
      vert <= vert + 1'b1;
      if(vert >= 311) vert <= 0;
   end

	xs <= visible_x ? (xs + ce_pix) : 13'd0;
	addr_scr <= get_regs ? addr_reg : (addr_line + px[9:3] + visible_x);

	tripl[0] <= blue_data [px[2:0]];
   tripl[1] <= green_data[px[2:0]];
   tripl[2] <= red_data  [px[2:0]];
   cursor   <= curs_ena && ((reg_img[14:8]>>scale) == px[9:3]) && (~reg_img[4] || (px[2:0] == reg_img[7:5]));
	
   if(&cycle) begin
		if(get_regs)begin
			addr_reg <= addr_reg + 2'd2;
			case({get_regs3,get_regs2,get_regs1})

			  'b000: if(type_regs) reg_clr[15: 0] <= data1;
						else          reg_img[15: 0] <= data1;

			  'b001: if(type_regs) reg_clr[31:16] <= data1;
						else          reg_img[31:16] <= data1;

			  'b010: addr_line    <= data1;

			  'b100: begin
							addr_reg  <= {data1[15:3],~data1[1] & data1[2],2'b00};
							four_regs <= data1[1];
							type_regs <= data1[2];
							if(data1[0]) curs_ena <= ~curs_ena;
						end
			endcase
		end
		else if(&px[2:0] || ~visible_x) begin
			blue_data  <= addr_scr[0] ? data1[15:8]: data1[7:0];
			green_data <= data2[7:0];
			red_data   <= data2[15:8];
		end
	end
end

// ---------------------------------------------------------------------
// display out logic
// ---------------------------------------------------------------------
// Channel levels as in UKNCBTL: Y gives 80 or FF, a cleared intensity bit
// (reg_img[18:16], R G B) dims the channel to 60 or DF.  The cursor takes
// the place of the pixel, in its own YRGB at full intensity.
function [7:0] level(input on, input y, input intensity);
   level = !on ? 8'h00 : y ? (intensity ? 8'hFF : 8'hDF) : (intensity ? 8'h80 : 8'h60);
endfunction

wire [3:0] cvt  = reg_clr[tripl*4 +:4];
wire [3:0] yrgb = cursor ? reg_img[3:0] : cvt;
wire [2:0] ints = cursor ? 3'b111 : reg_img[18:16];

wire [7:0] r = level(yrgb[2], yrgb[3], ints[2]);
wire [7:0] g = level(yrgb[1], yrgb[3], ints[1]);
wire [7:0] b = level(yrgb[0], yrgb[3], ints[0]);

always @(posedge clk) begin
   red   <= r;
   green <= g;
   blue  <= b;
   hsync <= hs;
   vsync <= vs;
   hblank<= ~visible_x;
   vblank<= ~visible_y;
end

endmodule
