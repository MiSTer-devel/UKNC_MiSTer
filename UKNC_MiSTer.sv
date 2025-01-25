// FPGA Electronika MS-0511 - UKNC
//
// Copyright (c) 2025 Alexander Kholodov
//
// All rights reserved
// MISTER version
//================================================================================
//

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign UART_RTS = UART_CTS;
assign UART_DTR = UART_DSR;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SCALER  = 0;
assign VGA_F1 = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

assign AUDIO_S   = 0;
assign AUDIO_MIX = 0;

//assign LED_USER  = vsd_sel & sd_act;
//assign LED_DISK  = {1'b1, ~vsd_sel & sd_act};
//assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

assign VGA_SL = scale ? scale[1:0] - 1'd1 : 2'd0;

wire [2:0] scale = status[10:8];

`include "build_id.v" 
localparam CONF_STR = {
	"UKNC;UART19200;",
	"-;",
	"S0,DSK,Mount Drive 1;",
	"S1,DSK,Mount Drive 2;",
	"S2,DSK,Mount Drive 3;",
	"S3,DSK,Mount Drive 4;",
//	"S2,VHD,Mount Drive;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[10:8],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"-;",
	"R[0],Reset and close OSD;",
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire [64:0] rtc;

wire [31:0] sd_lba_sd;
wire [31:0] sd_lba[4] = '{sd_lba_sd,sd_lba_sd,sd_lba_sd,sd_lba_sd};
wire  [3:0] sd_rd;
wire  [3:0] sd_wr;
wire  [3:0] sd_ack;
wire        sd_ack_conf;
wire  [8:0] sd_buff_addr;   // [7:0] for 16bit BUS WIDE, [8:0] for 8bit BUS WIDE
wire  [7:0] sd_buff_dout;   // [15:0] for 16bit BUS WIDE, [7:0] for 8bit BUS WIDE
wire  [7:0] sd_buff_din_sd; // [15:0] for 16bit BUS WIDE, [7:0] for 8bit BUS WIDE
wire  [7:0] sd_buff_din[4] = '{sd_buff_din_sd,sd_buff_din_sd,sd_buff_din_sd,sd_buff_din_sd}; // [15:0] for 16bit BUS WIDE, [7:0] for 8bit BUS WIDE
wire        sd_buff_wr;

wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire  [7:0] uart_mode;

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(14'd2000), .VDNUM(4), .WIDE(0)) hps_io   //50MHz // .PS2DIV(3200)   //100MHz
(
	.clk_sys      (CLK_50M),
	.HPS_BUS      (HPS_BUS),
//	.EXT_BUS      (EXT_BUS),
	.gamma_bus    (),

	.forced_scandoubler (forced_scandoubler),

	.buttons      (buttons),
	.status       (status),
	.status_menumask ({status[5]}),

	.ps2_key      (ps2_key),
	.ps2_mouse    (ps2_mouse),

	.RTC          (rtc),

	.sd_lba       (sd_lba),
	.sd_rd        (sd_rd),
	.sd_wr        (sd_wr),
	.sd_ack       (sd_ack),
	.sd_buff_addr (sd_buff_addr),
	.sd_buff_din  (sd_buff_din),
	.sd_buff_dout (sd_buff_dout),
	.sd_buff_wr   (sd_buff_wr),
	.img_mounted  (img_mounted),
	.img_readonly (img_readonly),
	.img_size     (img_size),

	.uart_mode    (uart_mode)
);
/*
   wire [15:0] mgmt_din;
   wire [15:0] mgmt_dout;
   wire [15:0] mgmt_addr;
   wire        mgmt_rd;
   wire        mgmt_wr;
   wire  [2:0] mgmt_req;

   wire [35:0] EXT_BUS;
   hps_ext hps_ext  
(
	.clk_sys      (CLK_50M),
	.EXT_BUS      (EXT_BUS),

	.ext_din      (mgmt_din),
	.ext_dout     (mgmt_dout),
	.ext_addr     (mgmt_addr),
	.ext_rd       (mgmt_rd),
	.ext_wr       (mgmt_wr),

	.ext_req      (mgmt_req),
	.ext_hotswap  (2'b00)
);
*/
/*
video_mixer #(.LINE_LENGTH(832), .GAMMA(1)) video_mixer
(
	.*,
	.ce_pix       (ce_5m3),

	.scandoubler  (scale || forced_scandoubler),
	.hq2x         (scale==1),

	.VGA_DE       (vga_de),

	// Positive pulses.
	.HSync        (hs_o),
	.VSync        (vs_o),
	.HBlank       (hblank),
	.VBlank       (vblank)
);

	input            CLK_VIDEO, // should be multiple by (ce_pix*4)
	output reg       CE_PIXEL,  // output pixel clock enable
	input            ce_pix,    // input pixel clock or clock_enable
	input            scandoubler,
	input            hq2x,      // high quality 2x scaling
	inout     [21:0] gamma_bus,
	// color
	input [DWIDTH:0] R,
	input [DWIDTH:0] G,
	input [DWIDTH:0] B,
	// Freeze engine
	// HDMI: displays last frame 
	// VGA:  black screen with HSync and VSync
	input            HDMI_FREEZE,
	output           freeze_sync,
*/

//************************************************
//* PLL Clocks
//************************************************
wire        clk_50;
wire        clk_25;
wire        clk_12_5;
wire        clk_6_25;
wire        sys_init;     // Reset
wire        sys_plock;    // PLL Ready

pll pll (
   .refclk   (CLK_50M),
   .rst      (0),
   .outclk_0 (clk_50),    // 50MHz
   .outclk_1 (clk_25),    // 24MHz
   .outclk_2 (clk_12_5),  // 12,5MHz
   .outclk_3 (clk_6_25),  // 6,25MHz
   .outclk_4 (SDRAM_CLK), // 50MHz 90 shift
   .locked   (sys_plock)    // флаг готовности PLL
);

///////////
wire  [2:0] vgarn;
wire  [2:0] vgagn;
wire  [2:0] vgabn;
//wire        hblank;
//wire        vblank;
wire  [9:0] audio;
wire  [6:0] mouse;
assign AUDIO_R = {audio, 6'd0};
assign AUDIO_L = AUDIO_R;

UKNC UKNC (
    .clk_50   (clk_50),
    .clk_25   (clk_25),
    .cpuclk_p (clk_12_5),
    .ppuclk_p (clk_6_25),
    .locked   (sys_plock),
    .red      (vgarn),
    .green    (vgagn),
    .blue     (vgabn),
    .vsync    (VGA_VS),
    .hsync    (VGA_HS),
    .visible  (VGA_DE),
    .ps2_key  (ps2_key),
    .nbut     (~reset_key),
    .uart_rx  (UART_RXD),
    .uart_tx  (UART_TXD),
    .sound    (audio),
//    .rtc      (rtc),
//    .msxmouse (msxmouse),
//    .msxstb   (msxstb),

//   .img_mounted   (img_mounted),   //[2:1]),
//   .img_size      (img_size),
//   .img_wp        (0),
   .sd_lba        (sd_lba_sd),
   .sd_rd         (sd_rd),
//   .sd_wr         (sd_wr),
   .sd_ack        (sd_ack),
   .sd_buff_addr  (sd_buff_addr),
   .sd_buff_dout  (sd_buff_dout),
   .sd_buff_din   (sd_buff_din_sd),
   .sd_buff_wr    (sd_buff_wr),
/*
   .ide_addr      (ide_addr),
   .ide_writedata (ide_writedata),
   .ide_readdata  (ide_readdata),
   .ide_read      (ide_read),
   .ide_write     (ide_write),
*/
   .SDRAM_A       (SDRAM_A),        // SDRAM Address bus 12 Bits
   .SDRAM_DQ      (SDRAM_DQ),       // SDRAM Data bus 16 Bits
   .SDRAM_DQML    (SDRAM_DQML),     // SDRAM Low-byte Data Mask 
   .SDRAM_DQMH    (SDRAM_DQMH),     // SDRAM High-byte Data Mask
   .SDRAM_nWE     (SDRAM_nWE),      // SDRAM Write Enable
   .SDRAM_nCAS    (SDRAM_nCAS),     // SDRAM Column Address Strobe
   .SDRAM_nRAS    (SDRAM_nRAS),     // SDRAM Row Address Strobe
   .SDRAM_nCS     (SDRAM_nCS),      // SDRAM Chip Select
   .SDRAM_BA      (SDRAM_BA),       // SDRAM Bank Address 0,1
//   .SDRAM_CLK     (SDRAM_CLK),      // SDRAM Clock
   .SDRAM_CKE     (SDRAM_CKE) 
);

assign CLK_VIDEO = clk_25;

//reg  clk16;
//always @ (posedge clk32p) clk16 <= ~clk16;

assign CE_PIXEL  = 1'b1;  // (forced_scandoubler ? 1'b1 : clk16);

//assign VGA_DE = ~(hblank | vblank);
assign VGA_R[7:5] = vgarn ;
assign VGA_G[7:5] = vgagn ;
assign VGA_B[7:5] = vgabn ;

//-----------------------
wire        reset_key;      // кнопка сброса
assign      reset_key = RESET | buttons[1] | status[0];    // кнопка сброса

//wire        video   = status[3];  // Пункт меню Video  Терминал или Неон
//wire        cpuslow = status[5];  // Пункт меню Turbo
//wire        int_sel = status[6];  // Пункт меню INT

//-----------------------------------------------------
//
// IDE
//
    logic           mgmt_ide0_cs;
/*    logic [15:0]    mgmt_ide0_readdata;
    logic           ide0_command_cs;
    logic           ide0_control_cs;
    logic           ide0_comd_ctrl_select;
    logic           ide0_io_read;
    logic           ide0_io_read_1;
    logic           ide0_io_write;
    logic           prev_ide0_io_read;
    logic           prev_ide0_io_write;
    logic [3:0]     ide0_address_1;
    logic [15:0]    ide0_writedata;
*/ 
    logic [2:0]     ide_addr;
    logic [15:0]    ide_writedata;
    logic [15:0]    ide_readdata;
    logic           ide_read;
    logic           ide_write;

//    assign mgmt_ide0_cs     = (mgmt_addr[15:8] == 8'hF0);
/*    assign ide0_command_cs  = ~ide0_cs1fx;
    assign ide0_control_cs  = ~ide0_cs3fx & &ide0_address[2:1];
    assign ide0_io_read     = ~ide0_io_read_n  & (ide0_command_cs | ide0_control_cs);
    assign ide0_io_write    = ~ide0_io_write_n & (ide0_command_cs | ide0_control_cs);

    always_ff @(posedge clk32p)
    begin
        ide0_io_read_1          <= ide0_io_read;
        prev_ide0_io_read       <= ide0_io_read_1;
        prev_ide0_io_write      <= ide0_io_write;
        ide0_address_1          <= {1'b0, ide_address};
        ide0_writedata          <= ide0_data_bus_out;
    end */
/*  ao486
assign mgmt_ide0_cs  = (mgmt_address[15:8] == 8'hF0);
assign mgmt_ide1_cs  = (mgmt_address[15:8] == 8'hF1);
assign mgmt_fdd_cs   = (mgmt_address[15:8] == 8'hF2);
assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);
assign mgmt_readdata = mgmt_ide0_cs ? mgmt_ide0_readdata : mgmt_ide1_cs ? mgmt_ide1_readdata : mgmt_fdd_readdata;
*/

/*
ide ide (
   .clk           (clk32p),
   .rst_n         (~reset_key),

// .irq           (),
// .drq           (),

   .use_fast      (0),
// .no_data       (),

// .drive_en      (),

   .io_address    ({1'b0,ide_addr}),
   .io_read       (ide_read),
   .io_readdata   (ide_readdata),
// .io_readdata   ({ide_readdata[7:0], ide_readdata[15:8]}),
   .io_write      (ide_write),
   .io_writedata  (ide_writedata),
// .io_writedata  ({ide_writedata[7:0], ide_writedata[15:8]}),
   .io_32         (0),

// .io_wait       (),

   .request       (mgmt_req),
   .mgmt_address  (mgmt_addr[3:0]),
   .mgmt_writedata (mgmt_dout),
   .mgmt_readdata (mgmt_din),
   .mgmt_write    (mgmt_wr & mgmt_ide0_cs),
   .mgmt_read     (mgmt_rd & mgmt_ide0_cs)
);
*/
//--- Mouse --------------
/*wire  [5:0] msxmouse;
wire        msxstb;

ps2mouse msx_mouse (
   .clk          (clk_50),
   .reset        (reset_key),
   .strobe       (msxstb),
   .data         (msxmouse),
   .ps2_mouse    (ps2_mouse)
);
*/
endmodule
