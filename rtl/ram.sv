module ram
(
   input             clk,

	input       [3:0] cycle,

	input      [15:0] scr_addr,
	output     [15:0] scr_data1,
	output     [15:0] scr_data2,
	
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

   case (cycle[2:0])
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

wire [15:0] bramppu_data, bramcpu_data;
reg   [1:0] bramppu_we, bramcpu_we;

dpram #(15) bramppu_l
(
   .clock(clk),

   .address_a(ppu_addr_new[15:1]),
   .data_a(ppu_din_new[7:0]),
   .wren_a(bramppu_we[0]),
   .q_a(bramppu_data[7:0]),
	
   .address_b(scr_addr[15:1]),
   .q_b(scr_data1[7:0])
);

dpram #(15) bramppu_u
(
   .clock(clk),

   .address_a(ppu_addr_new[15:1]),
   .data_a(ppu_din_new[15:8]),
   .wren_a(bramppu_we[1]),
   .q_a(bramppu_data[15:8]),

   .address_b(scr_addr[15:1]),
   .q_b(scr_data1[15:8])
);

dpram #(16) bramcpu_l
(
	.clock(clk),

	.address_a(cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0]),
	.data_a(cpu_select ? cpu_din_new[7:0] : ppu_din_new[23:16] ),
	.wren_a(bramcpu_we[0]),
	.q_a(bramcpu_data[7:0]),

	.address_b(scr_addr[15:0]),
	.q_b(scr_data2[7:0])
);

dpram #(16) bramcpu_u
(
	.clock(clk),

	.address_a(cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0]),
	.data_a(cpu_select ? cpu_din_new[15:8] : ppu_din_new[31:24] ),
	.wren_a(bramcpu_we[1]),
	.q_a(bramcpu_data[15:8]),

	.address_b(scr_addr[15:0]),
	.q_b(scr_data2[15:8])
);

endmodule
