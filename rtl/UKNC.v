module UKNC (
   input         clk_25,

   input         nbut,        // reset_n button
   output        sound,

   input         vsync,

   output [15:0] addr_cpu_o,
   output [15:0] data_cpu_o,
   output        read_cpu_o,
   output        wrte_cpu_o,
   output  [1:0] mask_cpu_o,
   input  [15:0] data_cpu_i,
   input         ackn_cpu_i,

   output [15:0] addr_ppu_o,
   output [31:0] data_ppu_o,
   output        read_ppu_o,
   output        wrte_ppu_o,
   output  [3:0] mask_ppu_o,
   input  [31:0] data_ppu_i,
   input         ackn_ppu_i,

   input  [10:0] ps2_key,

   output        uart_tx,
   input         uart_rx,

   output [10:0] sd_lba,
   output        sd_rd,
   output        sd_wr,
   input         sd_ack,
   input   [8:0] sd_buff_addr,
   input   [7:0] sd_buff_dout,
   output  [7:0] sd_buff_din,
   input         sd_buff_wr
);

reg ce_12_5, ce_12_5n, ce_6_25, ce_6_25n;
always @(negedge clk_25) begin
   reg [1:0] div;

   div <= div + 1'd1;
   ce_12_5  <= !div[0];
   ce_12_5n <=  div[0];
   ce_6_25  <= !div[1:0];
   ce_6_25n <= div[1] && !div[0];
end

wire cpuclk_p = ce_12_5  & clk_25;
wire cpuclk_n = ce_12_5n & clk_25;
wire ppuclk_p = ce_6_25  & clk_25;
wire ppuclk_n = ce_6_25n & clk_25;

//------------------------------------------------------------//
reg  [23:0]count_rst = 0;
wire n_all_rst = nbut;
wire sys_rst = count_rst[23];

always @(posedge clk_25 or negedge n_all_rst)
       count_rst <= !n_all_rst ? 24'd0 : count_rst + !count_rst[23];

//------------------------------------------------------------//
//  Wishbone PPU
//------------------------------------------------------------//
wire        ppu_vm_clk_p;

wire        ppu_vm_init_o;
wire        ppu_vm_dclo_o;
wire        ppu_vm_aclo_o;

wire        ppu_vm_virq_i;

wire [16:0] ppu_wbm_adr_o;
wire [15:0] ppu_wbm_dat_o;
wire [15:0] ppu_wbm_dat_i;
wire        ppu_wbm_cyc_o;
wire        ppu_wbm_wre_o;
wire  [1:0] ppu_wbm_sel_o;
wire        ppu_wbm_stb_o;
wire        ppu_wbm_ack_i;
wire [15:0] ppu_wbi_dat_i;
wire        ppu_wbi_ack_i;
wire        ppu_wbi_stb_o;


// vp1-120
wire        ppu_vm_virq_i_vp;

wire [15:0] ppu_wbm_dat_i_vp;

wire        ppu_wbm_ack_i_vp;
wire [15:0] ppu_wbi_dat_i_vp;
wire        ppu_wbi_ack_i_vp;

wire        pin_tmr_ena_o;
// vp1-128
wire [15:0] ppu_wbm_dat_i_128;
wire        ppu_wbm_ack_i_128;

//wire       wite_clk_128;
wire        motor_on_128;
//xm2-01
wire [15:0] ppu_wbm_dat_i_xm2;
wire        ppu_vm_virq_i_xm2;
wire        ppu_wbm_ack_i_xm2;

wire [15:0] ppu_wbi_dat_i_xm2;
wire        ppu_wbi_ack_i_xm2;
wire        ppu_wbi_stb_o_xm2;

assign ppu_vm_virq_i = ppu_vm_virq_i_xm2 | ppu_vm_virq_i_vp;

assign ppu_wbm_dat_i = ppu_wbm_ack_i_xm2 ? ppu_wbm_dat_i_xm2 :
                       ppu_wbm_ack_i_vp  ? ppu_wbm_dat_i_vp  :
                       ppu_wbm_ack_i_128 ? ppu_wbm_dat_i_128 : 16'o0;

assign ppu_wbm_ack_i = ppu_wbm_ack_i_xm2 | ppu_wbm_ack_i_vp|ppu_wbm_ack_i_128;

assign ppu_wbi_dat_i = ppu_wbi_ack_i_xm2 ? ppu_wbi_dat_i_xm2 :
                       ppu_wbi_ack_i_vp  ? ppu_wbi_dat_i_vp  : 16'o0;
assign ppu_wbi_ack_i = ppu_wbi_ack_i_xm2 | ppu_wbi_ack_i_vp;

//------------------------------------------------------------//
//  Wishbone CPU
//------------------------------------------------------------//
wire [15:0] vp65_wbm_dat_i;
wire [15:0] vp65_wbi_dat_i;
wire        vp65_vm_virq_i;
wire        vp65_wbm_ack_i;
wire        vp65_wbi_ack_i;
wire        vp65_wbi_stb_i;
//--------------------------------------------
wire        cpu_vm_init_o;
wire        cpu_vm_dclo_i;
wire        cpu_vm_aclo_i;
wire        pin_vm_halt_i;

wire        cpu_vm_virq_i = cpu_vm_virq_i_vp | vp65_vm_virq_i;

wire [16:0] cpu_wbm_adr_o;
wire [15:0] cpu_wbm_dat_o;
wire [15:0] cpu_wbm_dat_i = cpu_wbm_ack_i_vp ? cpu_wbm_dat_i_vp : 
                            vp65_wbm_ack_i   ? vp65_wbm_dat_i   : 16'o0;
wire        cpu_wbm_cyc_o;
wire        cpu_wbm_wre_o;
wire [ 1:0] cpu_wbm_sel_o;
wire        cpu_wbm_stb_o;
wire        cpu_wbm_ack_i = cpu_wbm_ack_i_vp | vp65_wbm_ack_i;

wire [15:0] cpu_wbi_dat_i = cpu_wbi_ack_i_vp ? cpu_wbi_dat_i_vp : 
                            vp65_wbi_ack_i   ? vp65_wbi_dat_i   : 16'o0;

wire        cpu_wbi_ack_i = cpu_wbi_ack_i_vp | vp65_wbi_ack_i;
wire        cpu_wbi_stb_o;

// vp1-120
wire        cpu_vm_virq_i_vp;

wire [15:0] cpu_wbm_dat_i_vp;

wire        cpu_wbm_ack_i_vp;
wire [15:0] cpu_wbi_dat_i_vp;
wire        cpu_wbi_ack_i_vp;
//------------------------------------------------------------//
ppu_wb ppu1(
   .vm_clk_p    (ppuclk_p),
   .vm_clk_n    (ppuclk_n),
   .rst         (~sys_rst),
   .clk50hz     (vsync),

   .addr_ram    (addr_ppu_o),
   .duot_ram    (data_ppu_o),
   .dinp_ram    (data_ppu_i),
   .mask_ram    (mask_ppu_o),
   .read_ram    (read_ppu_o),
   .wrte_ram    (wrte_ppu_o),
   .ackn_ram    (ackn_ppu_i),

   .vm_init     (ppu_vm_init_o),
   .vm_dclo     (ppu_vm_dclo_o),
   .vm_aclo     (ppu_vm_aclo_o),

   .vm_virq     (ppu_vm_virq_i),

   .pin_wbm_adr_o   (ppu_wbm_adr_o),
   .pin_wbm_dat_o   (ppu_wbm_dat_o),
   .pin_wbm_dat_i   (ppu_wbm_dat_i),
   .pin_wbm_cyc_o   (ppu_wbm_cyc_o),
   .pin_wbm_wre_o   (ppu_wbm_wre_o),
   .pin_wbm_sel_o   (ppu_wbm_sel_o),
   .pin_wbm_stb_o   (ppu_wbm_stb_o),
   .pin_wbm_ack_i   (ppu_wbm_ack_i),
   .pin_wbi_dat_i   (ppu_wbi_dat_i),
   .pin_wbi_ack_i   (ppu_wbi_ack_i),
   .pin_wbi_stb_o   (ppu_wbi_stb_o),

   .pin_tmr_ena_o   (pin_tmr_ena_o)
);
//------------------------------------------------------------//
wire  [7:0] keycode;

xm2_01 dd1(
   .pin_vm_clk25    (clk_25),

//   .pin_vm_clk_p    (ppuclk_n),
   .pin_vm_clk_p    (ppuclk_p),
   .pin_vm_init_i   (ppu_vm_init_o),
   .pin_vm_virq_o   (ppu_vm_virq_i_xm2),

   .pin_wbm_adr_i   (ppu_wbm_adr_o),
   .pin_wbm_dat_i   (ppu_wbm_dat_o),
   .pin_wbm_dat_o   (ppu_wbm_dat_i_xm2),

   .pin_wbm_wre_i   (ppu_wbm_wre_o),

   .pin_wbm_stb_i   (ppu_wbm_stb_o),
   .pin_wbm_ack_o   (ppu_wbm_ack_i_xm2),

   .pin_wbi_dat_o   (ppu_wbi_dat_i_xm2),
   .pin_wbi_ack_o   (ppu_wbi_ack_i_xm2),
   .pin_wbi_stb_i   (ppu_wbi_stb_o),

   .pin_vm_dclo_o   (cpu_vm_dclo_i),
   .pin_vm_aclo_o   (cpu_vm_aclo_i),
   .pin_vm_halt_o   (pin_vm_halt_i),

   .pin_wbi_stb_o   (ppu_wbi_stb_o_xm2),

   .but_data        (keycode),

   .sound           (sound)
);

keybrd kbrd(
   .clk         (clk_25),
   .rst         (~sys_rst),

   .keycode     (keycode),
   .ps2_key     (ps2_key)
);

//--------------------------------------------
wire [15:0] disk_data_out;
wire [15:0] disk_data_in ;
wire [ 1:0] disk_drive   ;
wire        disk_valid   ;
wire        disk_sync    ;
wire        disk_crc_ok  ;
wire        disk_rdy     ;
wire        disk_tr0     ;
wire        disk_ind     ;
wire        disk_motor   ;
wire        disk_step    ;
wire        disk_dir     ;
wire        disk_head    ;
wire        disk_write   ;

fdd fdd(
   .clk_25       (       clk_25),
   .ppu_vm_init_i(ppu_vm_init_o),

   .data_in      ( disk_data_in),
   .data_out     (disk_data_out),
   .write        (   disk_write),

   .drive        (   disk_drive),
   .motor        (   disk_motor),
   .step         (    disk_step),
   .dir          (     disk_dir),
   .head         (    disk_head),
   .valid        (   disk_valid),
   .sync         (    disk_sync),
   .crc_ok       (  disk_crc_ok),
   .rdy          (     disk_rdy),
   .tr0          (     disk_tr0),
   .ind          (     disk_ind),

//   .led_init     (      leds[5]),
   
   .rstart       ( sd_rd ),
   .wstart       ( sd_wr),
   .rsector      ( sd_lba ),
   .rbusy        (      sd_busy),
//   .rdone        (      sd_done),

   .outen        ( sd_buff_wr ),
   .outaddr      ( sd_buff_addr ),
   .inbyte       ( sd_buff_dout ),
   .outbyte      ( sd_buff_din ),
//   .mount_dsk    ( mount_dsk )
   .mount_dsk    ( 4'b0001 )
);

vp1_128fdd vp128(
//    .ppu_vm_clk_p (         ppuclk_n),
    .ppu_vm_clk_p (         ppuclk_p),
    
    .ppu_vm_init_i(    ppu_vm_init_o),

    .ppu_wbm_adr_i(    ppu_wbm_adr_o),
    .ppu_wbm_dat_i(    ppu_wbm_dat_o),
    .ppu_wbm_dat_o(ppu_wbm_dat_i_128),
    .ppu_wbm_cyc_i(    ppu_wbm_cyc_o),
    .ppu_wbm_wre_i(    ppu_wbm_wre_o),
    .ppu_wbm_stb_i(    ppu_wbm_stb_o),
    .ppu_wbm_ack_o(ppu_wbm_ack_i_128),

    .data_in      (    disk_data_out),
    .data_out     (     disk_data_in),
    .write        (       disk_write),

    .drive        (   disk_drive),
    .motor        (   disk_motor),
    .step         (    disk_step),
    .dir          (     disk_dir),
    .head         (    disk_head),
    .valid        (   disk_valid),
    .sync         (    disk_sync),
    .crc_ok       (  disk_crc_ok),
    .rdy          (     disk_rdy),
    .tr0          (     disk_tr0),
    .ind          (     disk_ind),
    .wrprt_dsk    (system_floppy_wprot)
); 

//------------------------------------------------------------//
cpu_wb cpu1(
   .vm_clk_p    (cpuclk_p),
   .vm_clk_n    (cpuclk_n),
   .clk50hz     (vsync),

   .addr_ram    (addr_cpu_o),
   .dout_ram    (data_cpu_o),
   .dinp_ram    (data_cpu_i),
   .mask_ram    (mask_cpu_o),
   .read_ram    (read_cpu_o),
   .wrte_ram    (wrte_cpu_o),
   .ackn_ram    (ackn_cpu_i),

   .vm_init     (cpu_vm_init_o),
   .vm_dclo     (cpu_vm_dclo_i),
   .vm_aclo     (cpu_vm_aclo_i),
   .vm_halt     (pin_vm_halt_i),

   .vm_virq     (cpu_vm_virq_i),

   .wbm_adr_o   (cpu_wbm_adr_o),
   .wbm_dat_o   (cpu_wbm_dat_o),
   .wbm_dat_i   (cpu_wbm_dat_i),
   .wbm_cyc_o   (cpu_wbm_cyc_o),
   .wbm_we_o    (cpu_wbm_wre_o),
   .wbm_sel_o   (cpu_wbm_sel_o),
   .wbm_stb_o   (cpu_wbm_stb_o),
   .wbm_ack_i   (cpu_wbm_ack_i),
   .wbi_dat_i   (cpu_wbi_dat_i),
   .wbi_ack_i   (cpu_wbi_ack_i),
   .wbi_stb_o   (cpu_wbi_stb_o),

   .tmr_ena_i   (pin_tmr_ena_o)
);
//------------------------------------------------------------//
wire cpu_wbi_stb_o_vp1; // not use

vp1_120 vp1
(
   .clk             (clk_25),
   .cpu_vm_init_i   (cpu_vm_init_o),
   .cpu_vm_virq_o   (cpu_vm_virq_i_vp),

   .cpu_wbm_adr_i   (cpu_wbm_adr_o),
   .cpu_wbm_dat_i   (cpu_wbm_dat_o),
   .cpu_wbm_dat_o   (cpu_wbm_dat_i_vp),
   .cpu_wbm_cyc_i   (cpu_wbm_cyc_o),
   .cpu_wbm_wre_i   (cpu_wbm_wre_o),
   .cpu_wbm_sel_i   (cpu_wbm_sel_o),
   .cpu_wbm_stb_i   (cpu_wbm_stb_o),
   .cpu_wbm_ack_o   (cpu_wbm_ack_i_vp),
   .cpu_wbi_dat_o   (cpu_wbi_dat_i_vp),
   .cpu_wbi_ack_o   (cpu_wbi_ack_i_vp),
   .cpu_wbi_stb_i   (cpu_wbi_stb_o),

   .cpu_wbi_stb_o   (cpu_wbi_stb_o_vp1),
//--------------------------------------------
   .ppu_vm_init_i   (ppu_vm_init_o),
   .ppu_vm_virq_o   (ppu_vm_virq_i_vp),

   .ppu_wbm_adr_i   (ppu_wbm_adr_o),
   .ppu_wbm_dat_i   (ppu_wbm_dat_o),
   .ppu_wbm_dat_o   (ppu_wbm_dat_i_vp),
   .ppu_wbm_cyc_i   (ppu_wbm_cyc_o),
   .ppu_wbm_wre_i   (ppu_wbm_wre_o),
   .ppu_wbm_sel_i   (ppu_wbm_sel_o),
   .ppu_wbm_stb_i   (ppu_wbm_stb_o),
   .ppu_wbm_ack_o   (ppu_wbm_ack_i_vp),
   .ppu_wbi_dat_o   (ppu_wbi_dat_i_vp),
   .ppu_wbi_ack_o   (ppu_wbi_ack_i_vp),
   .ppu_wbi_stb_i   (ppu_wbi_stb_o_xm2),

   .ppu_wbi_stb_o()
);

//------------------------------------------------------------//
vp065 dd2(
   .pin_clk         (clk_25),
   .pin_vm_clk_p    (cpuclk_n),

   .pin_vm_init_i   (cpu_vm_init_o),

   .pin_vm_virq_o   (vp65_vm_virq_i),

   .pin_wbm_adr_i   (cpu_wbm_adr_o),
   .pin_wbm_dat_i   (cpu_wbm_dat_o),
   .pin_wbm_dat_o   (vp65_wbm_dat_i),
   .pin_wbm_wre_i   (cpu_wbm_wre_o),
   .pin_wbm_stb_i   (cpu_wbm_stb_o),
   .pin_wbm_ack_o   (vp65_wbm_ack_i),
   .pin_wbi_dat_o   (vp65_wbi_dat_i),
   .pin_wbi_ack_o   (vp65_wbi_ack_i),
   .pin_wbi_stb_i   (cpu_wbi_stb_o_vp1),

   .pin_wbi_stb_o   (vp65_wbi_stb_i),

   .pin_tx_o        (uart_tx),
   .pin_rx_i        (uart_rx)
);
//------------------------------------------------------------//
endmodule
