module keyboard
(
   input            clk,
   input            rst,

   output reg [7:0] keycode,
   output reg       keytgl,  // toggles with every new keycode
   input     [10:0] ps2_key
);
//--------------------------------------------------------
//
//--------------------------------------------------------
wire  [7:0] code = ps2_key[7:0];
wire  extend = ps2_key[8];
wire  press  = ps2_key[9];

reg [7:0] ukey;
always begin
	if (extend)  // extended keys
		case(code)
			  8'h75: ukey = 8'o154; // row up
			  8'h72: ukey = 8'o134; // row down
			  8'h6B: ukey = 8'o116; // row left
			  8'h74: ukey = 8'o133; // row right
			  8'h1F: ukey = 8'o066; // GRAF - Win
			  8'h5A: ukey = 8'o166; // Num Enter
			  8'h4A: ukey = 8'o131; // Num / - +
			default: ukey = 0;
		endcase
	else 
		case (code)
			  8'h1C: ukey = 8'o072; // A
			  8'h32: ukey = 8'o076; // B
			  8'h21: ukey = 8'o050; // C
			  8'h23: ukey = 8'o057; // D
			  8'h24: ukey = 8'o033; // E
			  8'h2B: ukey = 8'o047; // F
			  8'h34: ukey = 8'o055; // G
			  8'h33: ukey = 8'o156; // H
			  8'h43: ukey = 8'o073; // I
			  8'h3B: ukey = 8'o027; // J
			  8'h42: ukey = 8'o052; // K
			  8'h4B: ukey = 8'o056; // L
			  8'h3A: ukey = 8'o112; // M
			  8'h31: ukey = 8'o054; // N
			  8'h44: ukey = 8'o075; // O
			  8'h4D: ukey = 8'o053; // P
			  8'h15: ukey = 8'o067; // Q
			  8'h2D: ukey = 8'o074; // R
			  8'h1B: ukey = 8'o111; // S
			  8'h2C: ukey = 8'o114; // T
			  8'h3C: ukey = 8'o051; // U
			  8'h2A: ukey = 8'o137; // V
			  8'h1D: ukey = 8'o071; // W
			  8'h22: ukey = 8'o115; // X
			  8'h35: ukey = 8'o070; // Y
			  8'h1A: ukey = 8'o157; // Z
			  8'h45: ukey = 8'o176; // 0
			  8'h16: ukey = 8'o030; // 1
			  8'h1E: ukey = 8'o031; // 2
			  8'h26: ukey = 8'o032; // 3
			  8'h25: ukey = 8'o013; // 4
			  8'h2E: ukey = 8'o034; // 5
			  8'h36: ukey = 8'o035; // 6
			  8'h3D: ukey = 8'o016; // 7
			  8'h3E: ukey = 8'o017; // 8
			  8'h46: ukey = 8'o177; // 9
			  8'h0E: ukey = 8'o007; // ~ / ; +
			  8'h52: ukey = 8'o077; // ' / @ Ю
			  8'h4E: ukey = 8'o175; // - / - =
			  8'h55: ukey = 8'o110; // = /   Ч
			  8'h5D: ukey = 8'o136; // ­\ / \ Э
			  8'h54: ukey = 8'o036; // [ / [ Ш
			  8'h5B: ukey = 8'o037; // ] / ] Щ
			  8'h41: ukey = 8'o117; // , / <
			  8'h49: ukey = 8'o135; // . / >
			  8'h4A: ukey = 8'o173; // / / / ?
			  8'h4C: ukey = 8'o174; // : / : *
			  8'h5A: ukey = 8'o153; // Enter
			  8'h66: ukey = 8'o132; // Back Space
			  8'h76: ukey = 8'o006; // ESC - AP2
			  8'h0D: ukey = 8'o026; // TAB
			  8'h29: ukey = 8'o113; // Space
			  8'h83: ukey = 8'o004; // F7  - STOP
			  8'h78: ukey = 8'o171; // F11 - RST
			  8'h09: ukey = 8'o151; // F10 - ISP
			  8'h01: ukey = 8'o152; // F9  - UST
			  8'h0A: ukey = 8'o172; // F8  - POM
			  8'h14: ukey = 8'o046; // Ctrl - UPR
			  8'h12,
			  8'h59: ukey = 8'o105; // Shift - HP
			  8'h58: ukey = 8'o107; // Caps - Fix
			  8'h11: ukey = 8'o106; // Alt - Alf
			  8'h05: ukey = 8'o010; // F1 - K1
			  8'h06: ukey = 8'o011; // F2 - K2
			  8'h04: ukey = 8'o012; // F3 - K3
			  8'h0C: ukey = 8'o014; // F4 - K4
			  8'h03: ukey = 8'o015; // F5 - K5
			  8'h70: ukey = 8'o126; // Num 0
			  8'h69: ukey = 8'o127; // Num 1
			  8'h72: ukey = 8'o147; // Num 2
			  8'h7A: ukey = 8'o167; // Num 3
			  8'h6B: ukey = 8'o130; // Num 4
			  8'h73: ukey = 8'o150; // Num 5
			  8'h74: ukey = 8'o170; // Num 6
			  8'h6C: ukey = 8'o125; // Num 7
			  8'h75: ukey = 8'o145; // Num 8
			  8'h7D: ukey = 8'o165; // Num 9
			  8'h7C: ukey = 8'o025; // Num * / -
			  8'h7B: ukey = 8'o005; // Num - / ,
			  8'h79: ukey = 8'o155; // Num + / Ъ
			  8'h71: ukey = 8'o146; // Num .
			default: ukey = 0;
		endcase
end

// A press sends the key's code; a release sends 0200 | row, but only once
// every key of that row is up, as the UKNC keyboard does.  held[] keeps
// PS/2 typematic repeats and releases of keys never pressed out of the
// per-row count.
wire [3:0] row = ukey[3:0];
reg  [2:0] row_keys[0:15];
reg  [511:0] held;
reg        old_stb;

always @(posedge clk) begin
   integer i;
   old_stb <= ps2_key[10];
   if(rst) begin
      held <= 0;
      for(i = 0; i < 16; i = i + 1) row_keys[i] <= 0;
   end
   else if(old_stb != ps2_key[10] && ukey) begin
      if(press) begin
         if(!held[ps2_key[8:0]]) begin
            held[ps2_key[8:0]] <= 1'b1;
            row_keys[row] <= row_keys[row] + 1'd1;
            keycode <= ukey;
            keytgl  <= ~keytgl;
         end
      end
      else if(held[ps2_key[8:0]]) begin
         held[ps2_key[8:0]] <= 1'b0;
         row_keys[row] <= row_keys[row] - 1'd1;
         if(row_keys[row] == 1) begin
            keycode <= {4'b1000, row};
            keytgl  <= ~keytgl;
         end
      end
   end
end

endmodule
