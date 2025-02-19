module ram
(
   // cpu/chipset interface
   input             clk_50,      // sdram is accessed at up to 128MHz
   input             reset,

   output reg        hsync,
   output reg        vsync,
   output reg        de,
   output reg [ 2:0] red,
   output reg [ 2:0] green,
   output reg [ 2:0] blue,

   input      [15:0] cpu_addr,   // 19 bit address 
   output reg [15:0] cpu_dout,   // data output to cpu
   input      [15:0] cpu_din,    // data input from cpu
   input      [ 1:0] cpu_dqm,    // dqm write only
   input             cpu_read,   // cpu requests read
   input             cpu_wrte,   // cpu requests write
   output reg        cpu_ack,   // dout is valid. Ready to accept new read/write.

   input      [15:0] ppu_addr,   // 19 bit address 
   output reg [31:0] ppu_dout,   // data output to cpu
   input      [31:0] ppu_din,    // data input from cpu
   input      [ 3:0] ppu_dqm,    // dqm write only
   input             ppu_read,   // ppu requests read
   input             ppu_wrte,   // ppu requests write
   output reg        ppu_ack    // dout is valid. Ready to accept new read/write.
);

reg [10:0] horz;
reg [ 9:0] vert;
reg [15:0] vga_adst;        // address string in memory
reg [15:0] vga_adnx = 16'o270;  // address next string
reg        qutro_reg;
reg        types_reg;
reg        vga_curs;
reg        ppu_vl;
reg        cpu_vl;
reg        curs_set;
reg [31:0] vga_regi;        // vga register isobr
reg [31:0] vga_regc;        // vga register color

wire [ 9:0] x            = horz[10:1] /* synthesis keep */;
wire        new_scr      = x[9:3]  == 0 && vert==0 /* synthesis keep */;
wire        get_regs0    = x[9:3]  == 3;
wire        get_regs1    = x[9:3]  == 4;
wire        get_regs2    = x[9:3]  == 5;
wire        get_regs3    = x[9:3]  == 6;
wire        get_regs     = get_regs0|get_regs1|get_regs2|get_regs3/* synthesis keep */;
wire        get_regs_new = vert[0] == 1'b0/* synthesis keep */;
// ---------------------------------------------------------------------
// --------------------- vga control signals ---------------------------
// ---------------------------------------------------------------------

wire startd    = x > 143;
wire visible_x = x > 16 + 64 + 80 - 1;
//wire visible_y = vert < 600;
wire visible_y = vert > 39 && vert < 616;
wire hs        = x > 15 && x < 16 + 64;
//wire vs        = vert > 600 + 13 && vert < 600 + 14 + 3;
wire vs        = vert > 600 + 20 && vert < 600 + 20 + 3;
wire visible   = visible_x && visible_y;

wire [ 9:0] xs = startd ?
                 vga_regi[21:20] == 2'b00 ? x - 10'd144 :
                 vga_regi[21:20] == 2'b01 ? x - 10'd144 :
                 vga_regi[21:20] == 2'b10 ? x - 10'd128 :
                                            x - 10'd96 : 10'd0;
// ---------------------------------------------------------------------
reg  [ 2:0] indx_reg;
wire [15:0] addr_reg = qutro_reg ?  {vga_adnx[15:3],3'b000} + indx_reg : {vga_adnx[15:2],2'b00} + indx_reg /* synthesis keep */;
reg  [15:0] addr_scr;

wire [ 3:0] q = horz[3:0] /* synthesis keep */;
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

reg  [ 7:0] pr_blue_data;
reg  [ 7:0] pr_green_data;
reg  [ 7:0] pr_red_data;

reg  [ 7:0] blue_data;
reg  [ 7:0] green_data;
reg  [ 7:0] red_data;

reg  [ 2:0] tripl;
reg         iscursor;
reg         curs_set_d;

always @(posedge clk_50) begin

   curs_set_d <= curs_set;
   if(~curs_set_d & curs_set) vga_curs <= ~vga_curs;

   if(new_scr)begin
      vga_adnx  <= 16'o270;
      types_reg <= 0;
      qutro_reg <= 0;
      curs_set  <= 0;
      curs_set_d<= 0;
      indx_reg  <= 0;
      vga_curs  <= 0;
   end 
// ---------------------------------------------------------------------
// --------------------------- steps/video ---------------------------
// ---------------------------------------------------------------------
   if(horz==1599)begin
      if(vert == 623)vert <= 10'd0;
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

           tripl[0] <= blue_data [xs[2:0]];
           tripl[1] <= green_data[xs[2:0]];
           tripl[2] <= red_data  [xs[2:0]];
         end
   'b01: begin
           if(&q)begin
               addr_scr   <=  vga_adst + xs[9:4];
           end
           if(vga_regi[14: 9] + 1'b1 == xs[9:4] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[3:1]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;

           tripl[0] <= blue_data [xs[3:1]];
           tripl[1] <= green_data[xs[3:1]];
           tripl[2] <= red_data  [xs[3:1]];
         end
   'b10: begin
           if(&q && &xs[4:0])begin
               addr_scr <=  vga_adst + xs[9:5];
           end
           if(vga_regi[14: 10] + 1'b1 == xs[9:5] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[4:2]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;

           tripl[0] <= pr_blue_data [xs[4:2] + 7];
           tripl[1] <= pr_green_data[xs[4:2] + 7];
           tripl[2] <= pr_red_data  [xs[4:2] + 7];
         end
   'b11: begin
           if(&q && &xs[5:0])begin
               addr_scr <=  vga_adst + xs[9:6];
           end
           if(vga_regi[14: 11] + 1'b1 == xs[9:6] && vga_curs)begin
               if(!vga_regi[4]) iscursor <= 1'b1;
               else iscursor <= x[5:3]==vga_regi[7:5] ? 1'b1 : 1'b0;
           end else iscursor <= 1'b0;

           tripl[0] <= blue_data [xs[5:3]];
           tripl[1] <= green_data[xs[5:3]];
           tripl[2] <= red_data  [xs[5:3]];
         end
   endcase

   ppu_vl <= 0;
   cpu_vl <= 0;
   bramppu_we <= 0;
   bramcpu_we <= 0;

   case (q)
   4'd2 : begin
            if(get_regs)begin
               if(get_regs_new)begin
                  indx_reg <= indx_reg + 2'b10;
                  case({qutro_reg,get_regs3,get_regs2,get_regs1})
                  'b1_000: if(types_reg) vga_regc[15: 0] <= bramppu_data;
                           else          vga_regi[15: 0] <= bramppu_data;
                  'b1_001: if(types_reg) vga_regc[31:16] <= bramppu_data;
                           else          vga_regi[31:16] <= bramppu_data;
                  'b1_010: vga_adst     <= bramppu_data;
                  'b1_100: begin
                              vga_adnx  <= bramppu_data;
                              curs_set  <= bramppu_data[0];
                              qutro_reg <= bramppu_data[1];
                              types_reg <= bramppu_data[2];
                           end

                  'b0_000: vga_adst     <= bramppu_data[15:0];
                  'b0_001: vga_adnx     <= bramppu_data[15:0];
                  'b0_100: begin
                              curs_set  <= vga_adnx[0];
                              qutro_reg <= vga_adnx[1];
                              types_reg <= vga_adnx[2];
                           end
                  endcase
               end
            end else begin
               pr_blue_data <= addr_scr[0] ? bramppu_data[15:8]: bramppu_data[7:0];
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
               pr_green_data  <= bramcpu_data[7:0];
               pr_red_data    <= bramcpu_data[15:8];
            end
          end

   4'd9 : begin
            //ppu memory
            if(ppu_wrte_new)begin
               bramppu_we <= ~ppu_dqm_new[1:0];
               ppu_vl     <= 1'b1;
            end

            //cpu memory
            if(cpu_select)begin
               if(cpu_wrte_new) begin 
                  bramcpu_we <= ~cpu_dqm_new[1:0];
                  cpu_vl <= 1'b1;
               end
            end else begin
               if(ppu_wrte_new) begin 
                  bramcpu_we <= ~ppu_dqm_new[3:2];
                  ppu_vl <= 1'b1;
               end
            end
          end

   4'd10: begin
            //ppu memory
            if(ppu_read_new)begin 
               ppu_dout[15:0] <= bramppu_data;
               ppu_vl         <= 1'b1;
            end

            //cpu memory
            if(cpu_select) begin
               if(cpu_read_new) begin
                  cpu_dout <= bramcpu_data;
                  cpu_vl <= 1'b1;
               end
            end else begin
               if(ppu_read_new) begin
                  ppu_dout[31:16] <= bramcpu_data;
                  ppu_vl <= 1'b1;
               end
            end
          end

   4'd15: begin
            blue_data  <= pr_blue_data  ;
            green_data <= pr_green_data ;
            red_data   <= pr_red_data   ;
          end
   endcase
end

//-------------------------------------------------------------------
//-------------PPU/CPU busy/asck signals-----------------------------
//-------------------------------------------------------------------
always @(posedge clk_50) begin
      if(~reset)begin
//-------------------------------------------------------------------
        if(!(ppu_read|ppu_wrte)) ppu_ack <= 1'b0;
        if(ppu_vl)               ppu_ack <= 1'b1;
//-------------------------------------------------------------------
        if(!(cpu_read|cpu_wrte)) cpu_ack <= 1'b0;
        if(cpu_vl)               cpu_ack <= 1'b1;
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

// ---------------------------------------------------------------------
// display out logic
// ---------------------------------------------------------------------
wire [ 2:0]curR = vga_regi[2] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curG = vga_regi[1] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curB = vga_regi[0] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;

wire [3:0] cvt = vga_regc[tripl*4 +:4];

wire [2:0] r = (cvt[2] & visible ? vga_regi[18] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible & iscursor ? curR : 3'd0);
wire [2:0] g = (cvt[1] & visible ? vga_regi[17] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible & iscursor ? curG : 3'd0);
wire [2:0] b = (cvt[0] & visible ? vga_regi[16] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) | (visible & iscursor ? curB : 3'd0);

always @(posedge clk_50) begin
   red   <= r;
   green <= g;
   blue  <= b;
   hsync <= hs;
   vsync <= vs;
   de    <= visible;
end

//---------------------------------------------------------------------------------------------------------//

wire [15:0] bramppu_data, bramcpu_data;
reg   [1:0] bramppu_we, bramcpu_we;

spram #(15) bramppu_l
(
   .clock(clk_50),
   .address(q[3] ? ppu_addr_new[15:1] : get_regs ? addr_reg[15:1] : addr_scr[15:1]),
   .data(ppu_din_new[7:0]),
   .wren(bramppu_we[0]),
   .q(bramppu_data[7:0])
);

spram #(15) bramppu_u
(
   .clock(clk_50),
   .address(q[3] ? ppu_addr_new[15:1] : get_regs ? addr_reg[15:1] : addr_scr[15:1]),
   .data(ppu_din_new[15:8]),
   .wren(bramppu_we[1]),
   .q(bramppu_data[15:8])
);

spram #(16) bramcpu_l
(
	.clock(clk_50),
	.address(q[3] ? (cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0]) : addr_scr[15:0]),
	.data(cpu_select ? cpu_din_new[7:0] : ppu_din_new[23:16] ),
	.wren(bramcpu_we[0]),
	.q(bramcpu_data[7:0])
);

spram #(16) bramcpu_u
(
	.clock(clk_50),
	.address(q[3] ? (cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0]) : addr_scr[15:0]),
	.data(cpu_select ? cpu_din_new[15:8] : ppu_din_new[31:24] ),
	.wren(bramcpu_we[1]),
	.q(bramcpu_data[15:8])
);

endmodule
