module aberrant(
   input         clk,

   input         vm_init_i,

   input  [16:0] wbm_adr_i,
   input  [15:0] wbm_dat_i,
   output [15:0] wbm_dat_o,
   input         wbm_cyc_i,
   input         wbm_wre_i,
   input   [1:0] wbm_sel_o,
   input         wbm_stb_i,
   output        wbm_ack_o,

   output [9:0] l_channel,
   output [9:0] r_channel
);
//---------------------------------------------------------------------------------
// Chipselect 177360/2
//---------------------------------------------------------------------------------
//wire ceppu = ~(|((wbm_adr_i[15:3] ^ 13'o17736) & 13'o17736));
wire ceppu = wbm_adr_i[15:3] == 13'o17736;
//---------------------------------------------------------------------------------
assign wbm_ack_o = (ceppu || ce_covox) && wbm_stb_i;

assign wbm_dat_o = ce0 ? {2{DO_0}} :
                   ce1 ? {2{DO_1}} : {2{DO_2}};

wire ce0 = ceppu && wbm_adr_i[2:1] == 2'b00 && wbm_stb_i;
wire ce1 = ceppu && wbm_adr_i[2:1] == 2'b01 && wbm_stb_i;
wire ce2 = ceppu && wbm_adr_i[2:1] == 2'b10 && wbm_stb_i;
//wire ce_midi = ceppu && wbm_adr_i[2:1] == 2'b11 && wbm_stb_i; // 177366
wire ce_covox = wbm_adr_i[15:1] == 15'o77575 && wbm_stb_i; //177372

wire nwtbt = &wbm_sel_o;

reg bdir1 = 0;
reg bc1   = 0;
reg bdir2 = 0;
reg bc2   = 0;
//reg bdir3 = 0;
//reg bc3   = 0;

always @(posedge clk)begin
        bdir1 <= ce0 && wbm_wre_i;
        bc1   <= ce0 && nwtbt;
        bdir2 <= ce1 && wbm_wre_i;
        bc2   <= ce1 && nwtbt;
//        bdir3 <= ce2 && wbm_wre_i;
//        bc3   <= ce2 && nwtbt;
    end

//---------------------------------------------------------------------------------
// COVOX
reg  [7:0] covox;

always @(posedge clk) begin
   if(ce_covox && wbm_wre_i) covox <= wbm_dat_i[7:0];
end

//---------------------------------------------------------------------------------
// AY Clock chips 25MHz / 14 = 1,7857MHz
reg  [3:0] psg_div;
reg  ce_psg;

always @(posedge clk) begin
psg_div <= (psg_div == 4'd13) ? 4'd0 : psg_div + 4'd1;
ce_psg  <= (psg_div == 4'd13);
end

//---------------------------------------------------------------------------------
// Data outputs for each AY chips
wire [7:0] DO_0;
wire [7:0] DO_1;
wire [7:0] DO_2 = 8'd0;
//---------------------------------------------------------------------------------
wire [7:0] psg_ch_a_1;
wire [7:0] psg_ch_b_1;
wire [7:0] psg_ch_c_1;

YM2149 dd1(
    .CLK       ( clk ),            // Global clock
    .CE        ( ce_psg ),         // PSG Clock enable
    .RESET     ( vm_init_i ),      // Chip RESET (set all Registers to '0', active hi)
    .BDIR      ( bdir1 ),          // Bus Direction (0 - read , 1 - write)
    .BC        ( bc1 ),            // Bus control
    .DI        ( wbm_dat_i[7:0] ), // Data In
    .DO        ( DO_0 ),           // Data Out
    .CHANNEL_A ( psg_ch_a_1 ),     // PSG Output channel A
    .CHANNEL_B ( psg_ch_b_1 ),     // PSG Output channel B
    .CHANNEL_C ( psg_ch_c_1 ),     // PSG Output channel C

    .SEL       ( 1'b0 ),
    .MODE      ( 1'b0 ),

    .ACTIVE    ( ),

    .IOA_in    ( 8'd0 ),
    .IOA_out   ( ),

    .IOB_in    ( 8'd0 ),
    .IOB_out   ( )
);

wire [7:0] psg_ch_a_2;
wire [7:0] psg_ch_b_2;
wire [7:0] psg_ch_c_2;

YM2149 dd2(
    .CLK       ( clk ),            // Global clock
    .CE        ( ce_psg ),         // PSG Clock enable
    .RESET     ( vm_init_i),       // Chip RESET (set all Registers to '0', active hi)
    .BDIR      ( bdir2 ),          // Bus Direction (0 - read , 1 - write)
    .BC        ( bc2 ),            // Bus control
    .DI        ( wbm_dat_i[7:0] ), // Data In
    .DO        ( DO_1 ),           // Data Out
    .CHANNEL_A ( psg_ch_a_2 ),     // PSG Output channel A
    .CHANNEL_B ( psg_ch_b_2 ),     // PSG Output channel B
    .CHANNEL_C ( psg_ch_c_2 ),     // PSG Output channel C

    .SEL       ( 1'b0 ),
    .MODE      ( 1'b0 ),

    .ACTIVE   ( ),

    .IOA_in   ( 8'd0 ),
    .IOA_out  ( ),

    .IOB_in   ( 8'd0 ),
    .IOB_out  ( )
);

/*
wire [7:0] psg_ch_a_3;
wire [7:0] psg_ch_b_3;
wire [7:0] psg_ch_c_3;

YM2149 dd3(
    .CLK       ( clk ),            // Global clock
    .CE        ( 1'b1 ),           // PSG Clock enable
    .RESET     ( vm_init_i ),      // Chip RESET (set all Registers to '0', active hi)
    .BDIR      ( bdir3 ),          // Bus Direction (0 - read , 1 - write)
    .BC        ( bc3 ),            // Bus control
    .DI        ( wbm_dat_i[7:0] ), // Data In
    .DO        ( DO_2 ),           // Data Out
    .CHANNEL_A ( psg_ch_a_3 ),     // PSG Output channel A
    .CHANNEL_B ( psg_ch_b_3 ),     // PSG Output channel B
    .CHANNEL_C ( psg_ch_c_3 ),     // PSG Output channel C

    .SEL       ( 1'b1),
    .MODE      ( 1'b1),

    .ACTIVE    ( ),

    .IOA_in    ( 8'd0 ),
    .IOA_out   ( ),

    .IOB_in    ( 8'd0 ),
    .IOB_out   ( )
);*/
//---------------------------------------------------------------------------------
// mixer
//---------------------------------------------------------------------------------
assign l_channel = psg_l;
assign r_channel = psg_r;

reg  [8:0] sum_ch_a, sum_ch_b, sum_ch_c;
reg  [7:0] psg_a, psg_b, psg_c;
reg  [9:0] psg_l, psg_r; //, opn_s;
//reg [11:0] ch_l, ch_r;

always @(posedge clk)begin
   sum_ch_a <= { 1'b0, psg_ch_a_1 } + { 1'b0, psg_ch_a_2 };
   sum_ch_b <= { 1'b0, psg_ch_b_1 } + { 1'b0, psg_ch_b_2 };
   sum_ch_c <= { 1'b0, psg_ch_c_1 } + { 1'b0, psg_ch_c_2 };

   psg_a <= sum_ch_a[8] ? 8'hFF : sum_ch_a[7:0];
   psg_b <= sum_ch_b[8] ? 8'hFF : sum_ch_b[7:0];
   psg_c <= sum_ch_c[8] ? 8'hFF : sum_ch_c[7:0];

   psg_l <= {1'b0, psg_a, 1'd0} + {2'b00, psg_b} + {1'b0, covox, 1'd0};
   psg_r <= {1'b0, psg_c, 1'd0} + {2'b00, psg_b} + {1'b0, covox, 1'd0};
//   psg_l <= {3'b000,                   psg_a, 1'd0} + {4'b0000, PSG_MIX ? psg_c : psg_b};
//   psg_r <= {3'b000, PSG_MIX ? psg_b : psg_c, 1'd0} + {4'b0000, PSG_MIX ? psg_c : psg_b};
//	opn_s <= {{2{opn_0[15]}}, opn_0[15:6]} + {{2{opn_1[15]}}, opn_1[15:6]};

//	ch_l <= ~ENABLE ? 12'd0 : fm_ena ? $signed(opn_s) + $signed(psg_l) : $signed(psg_l);
//	ch_r <= ~ENABLE ? 12'd0 : fm_ena ? $signed(opn_s) + $signed(psg_r) : $signed(psg_r);
end


//---------------------------------------------------------------------------------
endmodule
