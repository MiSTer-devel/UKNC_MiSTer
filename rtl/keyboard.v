module keybrd(
   input            clk,
   input            rst,

   output reg       press_btn,
   output reg [7:0] keycode,
   input            read,

   input     [10:0] ps2_key
);
//--------------------------------------------------------
//
//--------------------------------------------------------
wire  [7:0] code = ps2_key[7:0];
//assign code[7:0] = ps2_key[7:0];
wire  extend = ps2_key[8];
wire  press  = ps2_key[9];

always @(posedge clk) begin
   reg old_stb;
   old_stb <= ps2_key[10];

   if(old_stb != ps2_key[10]) begin

      if (extend)  // extended keys
        case(code)
           8'h75: keycode <= press ? 8'o154 & 8'o177 : (8'o154 & 8'o17)|8'o200; // row up
           8'h72: keycode <= press ? 8'o134 & 8'o177 : (8'o134 & 8'o17)|8'o200; // row down
           8'h6B: keycode <= press ? 8'o116 & 8'o177 : (8'o116 & 8'o17)|8'o200; // row left
           8'h74: keycode <= press ? 8'o133 & 8'o177 : (8'o133 & 8'o17)|8'o200; // row right
           8'h1F: keycode <= press ? 8'o66  & 8'o177 : (8'o66  & 8'o17)|8'o200; // GRAF - Win
           8'h5A: keycode <= press ? 8'o166 & 8'o177 : (8'o166 & 8'o17)|8'o200; // num Enter
         default: keycode <= 0;
        endcase
      else case (code)
              8'h5A: keycode <= press ? 8'o153 & 8'o177 : (8'o153 & 8'o17)|8'o200; // Enter
              8'h1C: keycode <= press ? 8'o72  & 8'o177 : (8'o72  & 8'o17)|8'o200; // A
              8'h32: keycode <= press ? 8'o76  & 8'o177 : (8'o76  & 8'o17)|8'o200; // B
              8'h21: keycode <= press ? 8'o50  & 8'o177 : (8'o50  & 8'o17)|8'o200; // C
              8'h23: keycode <= press ? 8'o57  & 8'o177 : (8'o57  & 8'o17)|8'o200; // D
              8'h24: keycode <= press ? 8'o33  & 8'o177 : (8'o33  & 8'o17)|8'o200; // E
              8'h2B: keycode <= press ? 8'o47  & 8'o177 : (8'o47  & 8'o17)|8'o200; // F
              8'h34: keycode <= press ? 8'o55  & 8'o177 : (8'o55  & 8'o17)|8'o200; // G
              8'h33: keycode <= press ? 8'o156 & 8'o177 : (8'o156 & 8'o17)|8'o200; // H
              8'h43: keycode <= press ? 8'o73  & 8'o177 : (8'o73  & 8'o17)|8'o200; // I
              8'h3B: keycode <= press ? 8'o27  & 8'o177 : (8'o27  & 8'o17)|8'o200; // J
              8'h42: keycode <= press ? 8'o52  & 8'o177 : (8'o52  & 8'o17)|8'o200; // K
              8'h4B: keycode <= press ? 8'o56  & 8'o177 : (8'o56  & 8'o17)|8'o200; // L
              8'h3A: keycode <= press ? 8'o112 & 8'o177 : (8'o112 & 8'o17)|8'o200; // M
              8'h31: keycode <= press ? 8'o54  & 8'o177 : (8'o54  & 8'o17)|8'o200; // N
              8'h44: keycode <= press ? 8'o75  & 8'o177 : (8'o75  & 8'o17)|8'o200; // O
              8'h4D: keycode <= press ? 8'o53  & 8'o177 : (8'o53  & 8'o17)|8'o200; // P
              8'h15: keycode <= press ? 8'o67  & 8'o177 : (8'o67  & 8'o17)|8'o200; // Q
              8'h2D: keycode <= press ? 8'o74  & 8'o177 : (8'o74  & 8'o17)|8'o200; // R
              8'h1B: keycode <= press ? 8'o111 & 8'o177 : (8'o111 & 8'o17)|8'o200; // S
              8'h2C: keycode <= press ? 8'o114 & 8'o177 : (8'o114 & 8'o17)|8'o200; // T
              8'h3C: keycode <= press ? 8'o51  & 8'o177 : (8'o51  & 8'o17)|8'o200; // U
              8'h2A: keycode <= press ? 8'o137 & 8'o177 : (8'o137 & 8'o17)|8'o200; // V
              8'h1D: keycode <= press ? 8'o71  & 8'o177 : (8'o71  & 8'o17)|8'o200; // W
              8'h22: keycode <= press ? 8'o115 & 8'o177 : (8'o115 & 8'o17)|8'o200; // X
              8'h35: keycode <= press ? 8'o70  & 8'o177 : (8'o70  & 8'o17)|8'o200; // Y
              8'h1A: keycode <= press ? 8'o157 & 8'o177 : (8'o157 & 8'o17)|8'o200; // Z
              8'h45: keycode <= press ? 8'o176 & 8'o177 : (8'o176 & 8'o17)|8'o200; // 0
              8'h16: keycode <= press ? 8'o30  & 8'o177 : (8'o30  & 8'o17)|8'o200; // 1
              8'h1E: keycode <= press ? 8'o31  & 8'o177 : (8'o31  & 8'o17)|8'o200; // 2
              8'h26: keycode <= press ? 8'o32  & 8'o177 : (8'o32  & 8'o17)|8'o200; // 3
              8'h25: keycode <= press ? 8'o13  & 8'o177 : (8'o13  & 8'o17)|8'o200; // 4
              8'h2E: keycode <= press ? 8'o34  & 8'o177 : (8'o34  & 8'o17)|8'o200; // 5
              8'h36: keycode <= press ? 8'o35  & 8'o177 : (8'o35  & 8'o17)|8'o200; // 6
              8'h3D: keycode <= press ? 8'o16  & 8'o177 : (8'o16  & 8'o17)|8'o200; // 7
              8'h3E: keycode <= press ? 8'o17  & 8'o177 : (8'o17  & 8'o17)|8'o200; // 8
              8'h46: keycode <= press ? 8'o177 & 8'o177 : (8'o177 & 8'o17)|8'o200; // 9
              8'h0E: keycode <= press ? 8'o77  & 8'o177 : (8'o77  & 8'o17)|8'o200; // ~ - Р®/@
              8'h55: keycode <= press ? 8'o175 & 8'o177 : (8'o175 & 8'o17)|8'o200; // -/=
              8'h5D: keycode <= press ? 8'o136 & 8'o177 : (8'o136 & 8'o17)|8'o200; // Р­/\
              8'h54: keycode <= press ? 8'o36  & 8'o177 : (8'o36  & 8'o17)|8'o200; // РЁ/[
              8'h5B: keycode <= press ? 8'o37  & 8'o177 : (8'o37  & 8'o17)|8'o200; // Р©/]
              8'h4C: keycode <= press ? 8'o7   & 8'o177 : (8'o7   & 8'o17)|8'o200; // ;/+
              8'h41: keycode <= press ? 8'o117 & 8'o177 : (8'o117 & 8'o17)|8'o200; // ,/<
              8'h49: keycode <= press ? 8'o135 & 8'o177 : (8'o135 & 8'o17)|8'o200; // ./>
              8'h4A: keycode <= press ? 8'o173 & 8'o177 : (8'o173 & 8'o17)|8'o200; // / ?
              8'h66: keycode <= press ? 8'o132 & 8'o177 : (8'o132 & 8'o17)|8'o200; // BRACKE SPACE
              8'h76: keycode <= press ? 8'o6   & 8'o177 : (8'o6   & 8'o17)|8'o200; // ESC - AP2
              8'h0D: keycode <= press ? 8'o26  & 8'o177 : (8'o26  & 8'o17)|8'o200; // TAB
              8'h14: keycode <= press ? 8'o46  & 8'o177 : (8'o46  & 8'o17)|8'o200; // Ctrl - UPR
              8'h29: keycode <= press ? 8'o113 & 8'o177 : (8'o113 & 8'o17)|8'o200; // Space
              8'h83: keycode <= press ? 8'o4   & 8'o177 : (8'o4   & 8'o17)|8'o200; // F7  - STOP
              8'h78: keycode <= press ? 8'o171 & 8'o177 : (8'o171 & 8'o17)|8'o200; // F11 - RST
              8'h09: keycode <= press ? 8'o151 & 8'o177 : (8'o151 & 8'o17)|8'o200; // F10 - ISP
              8'h01: keycode <= press ? 8'o152 & 8'o177 : (8'o152 & 8'o17)|8'o200; // F9  - UST
              8'h0A: keycode <= press ? 8'o172 & 8'o177 : (8'o172 & 8'o17)|8'o200; // F8  - POM
              8'h12: keycode <= press ? 8'o105 & 8'o177 : (8'o105 & 8'o17)|8'o200; // Shift
              8'h58: keycode <= press ? 8'o107 & 8'o177 : (8'o107 & 8'o17)|8'o200; // Caps - Fix
              8'h11: keycode <= press ? 8'o106 & 8'o177 : (8'o106 & 8'o17)|8'o200; // Alt - Alf
              8'h05: keycode <= press ? 8'o10  & 8'o177 : (8'o10  & 8'o17)|8'o200; // F1 - K1
              8'h06: keycode <= press ? 8'o11  & 8'o177 : (8'o11  & 8'o17)|8'o200; // F2 - K2
              8'h04: keycode <= press ? 8'o12  & 8'o177 : (8'o12  & 8'o17)|8'o200; // F3 - K3
              8'h0C: keycode <= press ? 8'o14  & 8'o177 : (8'o14  & 8'o17)|8'o200; // F4 - K4
              8'h03: keycode <= press ? 8'o15  & 8'o177 : (8'o15  & 8'o17)|8'o200; // F5 - K5
              8'h7C: keycode <= press ? 8'o174 & 8'o177 : (8'o174 & 8'o17)|8'o200; // *
              8'h52: keycode <= press ? 8'o5   & 8'o177 : (8'o5   & 8'o17)|8'o200; // Num '
              8'h4E: keycode <= press ? 8'o25  & 8'o177 : (8'o25  & 8'o17)|8'o200; // Num -   
              8'h70: keycode <= press ? 8'o126 & 8'o177 : (8'o126 & 8'o17)|8'o200; // Num 0
              8'h69: keycode <= press ? 8'o127 & 8'o177 : (8'o127 & 8'o17)|8'o200; // Num 1
              8'h72: keycode <= press ? 8'o147 & 8'o177 : (8'o147 & 8'o17)|8'o200; // Num 2
              8'h7A: keycode <= press ? 8'o167 & 8'o177 : (8'o167 & 8'o17)|8'o200; // Num 3
              8'h6B: keycode <= press ? 8'o130 & 8'o177 : (8'o130 & 8'o17)|8'o200; // Num 4
              8'h73: keycode <= press ? 8'o150 & 8'o177 : (8'o150 & 8'o17)|8'o200; // Num 5
              8'h74: keycode <= press ? 8'o170 & 8'o177 : (8'o170 & 8'o17)|8'o200; // Num 6
              8'h6C: keycode <= press ? 8'o125 & 8'o177 : (8'o125 & 8'o17)|8'o200; // Num 7
              8'h75: keycode <= press ? 8'o145 & 8'o177 : (8'o145 & 8'o17)|8'o200; // Num 8
              8'h7D: keycode <= press ? 8'o165 & 8'o177 : (8'o156 & 8'o17)|8'o200; // Num 9
            default: keycode <= 0;
         endcase
   end
end

reg [7:0]keycode_old = 0;
always @(posedge clk)
   if(keycode_old!=keycode && |keycode) begin
      press_btn <= 1'b1; 
      keycode_old <= keycode;
   end
   else if(read) begin press_btn <= 1'b0; end

endmodule