module fdd (
   input         clk_25,
   input         ppu_vm_init_i,

   input  [15:0] data_in,
   output reg [15:0] data_out,
   input         write,

   input  [ 1:0] drive,
   input         motor,
   input         step,
   input         dir,
   input         head,
   output        valid,
   output        sync,
   output        crc_ok,
   output        rdy,
   output        tr0,
   output        ind,

   output        led_init,

   output [ 3:0] rstart, // up to four different sources can request data 
   output [ 3:0] wstart,
   output [31:0] rsector,
   input         rbusy,
   input         sd_ack,

   output [ 7:0] outbyte,
   input         outen,   // when outen=1, a byte of sector content
   input  [ 8:0] outaddr, // outaddr from 0 to 511, because the sector size is 512
   input  [ 7:0] inbyte,   // a byte of sector content 
   input  [ 3:0] img_mounted,
   input  [19:0] img_size
);
//---------------------------------------------------------------------------------
// Size dsk image in sectors
//---------------------------------------------------------------------------------
// 1600 = 819200 / 512
//---------------------------------------------------------------------------------
// Spin disk emulation
//---------------------------------------------------------------------------------
// 25MHz input clk, 3125 16-bit word per one spin, result clk = 25000000/5/3125 = 1600
// 1 word in 64mkS
//---------------------------------------------------------------------------------
reg  [10:0] count_clk  =      0;
reg  [ 8:0] word_sectr =      0;
reg  [ 3:0] no_sec     =   4'd8;
reg  [ 7:0] no_trk     =   8'd5;
reg         clk_dsk    =      0;
reg         clk_dsk_n  =      0;

//---------------------------------------------------------------------------------
assign valid    = count_clk>10 && count_clk<900 && motor;///clk_dsk_n2 & motor;
assign led_init = ~motor;
assign sync     = (word_sectr == 9'h18 || word_sectr == 9'h2F ) && motor;
assign crc_ok   = (word_sectr == 9'h1C || word_sectr == 9'h131) && motor;
//assign crc_ok   = ((word_sectr >= 9'h18 && word_sectr <= 9'h1C ) || (word_sectr >= 9'h2F && word_sectr <= 9'h131)) && motor;
assign ind      = (word_sectr >= 9'h01 || word_sectr <= 9'h4) && motor;
assign tr0      = !no_trk && motor;

wire disk_insert = mount_dsk[drive];
reg  [3:0] mount_dsk;
reg  [3:0] old_img_mounted;

always @(posedge clk_25) begin
   integer i;
   old_img_mounted <= img_mounted;

   for(i = 0; i < 4; i = i+1'd1) begin
      if (~old_img_mounted[i] && img_mounted[i]) begin
         mount_dsk[i] <= |img_size;
      end
   end
end

//---------------------------------------------------------------------------------
// raw sectr, emul raw trk
// kolesiko krutit'sa - lave mutit'sa
//---------------------------------------------------------------------------------

always @(posedge clk_25) begin
   if (disk_insert) begin
      if  (_data) data_out <= {data_sec[7:0],data_sec[15:8]};
      else
      case (word_sectr)
         9'h01A:   data_out <= {no_trk,7'd0,head};
         9'h01B:   data_out <= {4'd0,no_sec+1'b1,8'd2};  // data_out <= 16'h0102;
         9'h012,
         9'h029:   data_out <= 16'h0000;
         9'h018,
         9'h02F:   data_out <= 16'hA1A1;
         9'h019:   data_out <= 16'hA1FE;
         9'h01C,
         9'h131:   data_out <= 16'h9315;
         9'h030:   data_out <= 16'hA1FB;
      default:  data_out <= 16'h4E4E;
   endcase
   end else data_out <= 16'h4E4E;
end 
//---------------------------------------------------------------------------------
reg         step_old;
reg         head_old = 1'b1;
reg  [ 1:0] drive_old= 1'b0;

always @(posedge clk_25) begin
   step_old <= step;
   if (~step_old && step) no_trk <= dir ? no_trk + 1'b1 : (no_trk ? no_trk - 1'b1 : 8'd0);
end

always @(posedge clk_25)
    if(!motor || step || head_old!=head || drive_old!=drive)begin
        word_sectr <=  9'h0;
        clk_dsk    <=  1'b0;
        clk_dsk_n  <=  1'b0;
        count_clk  <= 11'd0;
        head_old   <=  head;
        drive_old  <= drive;
    end else begin
//------ disk rotate immitation ---------------------------------------------------
        clk_dsk    <=       1'b0;
        clk_dsk_n  <=    clk_dsk;

        count_clk <= count_clk==1599 ? 11'd0 : count_clk + 1'b1;
        if(!count_clk)begin
            clk_dsk <= 1'b1;
            if(word_sectr==9'h168)begin no_sec <= 4'h0; word_sectr <= 9'h0; end
            else
                if(word_sectr==9'h132 && no_sec < 9)begin no_sec <= no_sec + 1'b1; word_sectr <= 9'h0; end
                else word_sectr <= word_sectr + 1'b1;
        end
//---------------------------------------------------------------------------------
    end
//---------------------------------------------------------------------------------
// SD-Card controller
//---------------------------------------------------------------------------------
wire [31:0] sd_sec = {no_trk,head,3'b000}+{no_trk,head,1'b0} + no_sec;
//---------------------------------------------------------------------------------
reg  sd_rd = 1'b0;
reg  _data = 1'b0;

always @(posedge clk_dsk_n or negedge motor)
    if(!motor)begin
        sd_rd <= 1'b0;
        _data <= 1'b0;
    end else begin
        sd_rd      <= word_sectr == 9'h1C ? 1'b1 : 1'b0;
        _data      <= word_sectr >= 9'h31 && word_sectr <= 9'h130 ? 1'b1 : 1'b0;
    end

reg  read_sd  = 1'b0;
reg  write_sd = 1'b0;

assign rsector = sd_sec;
assign rdy     = ~ppu_vm_init_i;
assign rstart  = {3'b000, read_sd}<<drive;
assign wstart  = {3'b000,write_sd}<<drive;

wire is_clean = ~motor|rbusy;

reg  old_sd_rd;
reg  old_is_clean;

always @(posedge clk_25)
   begin
      old_sd_rd <= sd_rd;
      old_is_clean <= is_clean;
      if ((~old_sd_rd & sd_rd) | (~old_is_clean & is_clean)) read_sd <= is_clean ? 1'b0 : disk_insert;
   end
//always @(posedge sd_rd or posedge is_clean)  read_sd <= is_clean ? 1'b0 : disk_insert;
//always @(posedge write or posedge is_clean)write_sd <= is_clean ? 1'b0 : _data ? disk_insert : write_sd;
//---------------------------------------------------------------------------------

wire [15:0] data_sec;
reg  [ 7:0] count_word = 8'd0;

always @(posedge clk_25) begin
   if (~clk_dsk_n && clk_dsk) count_word <= _data ? count_word + 1'b1 : 8'd0;
end

dpram_dif #(9,8,8,16) fdd_fifo
(
   .clock     (clk_25),
   .address_a (outaddr),
   .data_a    (inbyte),
   .wren_a    (outen & sd_ack),
   .q_a       (outbyte),
   .address_b (count_word),
   .data_b    (data_in),
   .wren_b    (write),
   .q_b       (data_sec)
);

endmodule