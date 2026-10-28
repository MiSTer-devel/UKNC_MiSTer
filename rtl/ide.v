// ide.v - the drive behind the УКНЦ IDE cartridge (Oleg H.'s WD
// controller), as UKNCBTL emulates it (emubase/Hard.cpp), on hps_io's
// sector interface: the image is an ordinary MiSTer disk slot, so it
// works with the stock Main.  From tang-uknc's ide.v (MIT), by way of
// alfishe/UKNC_MiSTer.
//
// ppu.v decodes the cartridge's registers and passes them here as
// io_address/io_read/io_write, already turned back from the bus's
// inverted form - except the data register, whose words go through as
// they are.  ppu.v acknowledges the cycle itself, so io_readdata is
// combinational and what a read or a write does happens at the edges of
// io_read/io_write.
//
// Sector data is inverted once more when the image is stored in the
// "inverted" form (a raw dump of a real drive holds ~software data),
// detected from sector 0: the software always sees its own view of the
// disk, whichever way the image is stored.
//
// Addressing is CHS, as the WD driver does it: the image's sector is
// (cyl * heads + head) * spt + sector - 1, with spt and heads from sector
// 0 and overridable by the SET CONFIG command, as in the emulator - or
// LBA28 when bit 6 of the head register is set, {head[3:0], cyl, sector}
// taken as the sector number straight.  A multi-sector read is read
// ahead: the next sector is fetched into a second bank while the software
// drains the first.
//
// Everything is on clk_25, the clock of hps_io and of the PPU's gated
// clock.
//
module ide
(
    input             clk,          // clk_25
    input             rst_n,

    // the cartridge's registers, from ppu.v
    input      [ 2:0] io_address,   // register index
    input             io_read,      // high for a read cycle
    output reg [15:0] io_readdata,
    input             io_write,     // high for a write cycle
    input      [15:0] io_writedata,

    // hps_io, this drive's slot
    input             img_mounted,
    input             img_readonly,
    input      [63:0] img_size,
    output reg [31:0] sd_lba,
    output            sd_rd,
    output            sd_wr,
    input             sd_ack,
    input      [ 7:0] sd_buff_addr,
    input      [15:0] sd_buff_dout,
    output reg [15:0] sd_buff_din,
    input             sd_buff_wr
);

//------------------------------------------------------------------------
// Constants, from Hard.cpp
//------------------------------------------------------------------------
localparam [7:0] ST_ERROR = 8'h01, ST_DRQ = 8'h08, ST_SEEK = 8'h10,
                 ST_READY = 8'h40, ST_BUSY = 8'h80;
localparam [7:0] ER_NONE = 8'h00, ER_BADSECT = 8'h80;
localparam [7:0] CMD_READ = 8'h20, CMD_READ1 = 8'h21, CMD_WRITE = 8'h30,
                 CMD_WRITE1 = 8'h31, CMD_SETCFG = 8'h91, CMD_IDENT = 8'hEC;
localparam [2:0] REG_DATA = 3'd0, REG_ERROR = 3'd1, REG_COUNT = 3'd2,
                 REG_SECTOR = 3'd3, REG_CYL_LO = 3'd4, REG_CYL_HI = 3'd5,
                 REG_HEAD = 3'd6, REG_STATUS = 3'd7;
localparam       HEAD_LBA = 6;      // head register bit: LBA28 addressing
localparam [7:0] RESET_CLOCKS = 8'd64;
localparam [7:0] LAST_WORD = 8'd255;
localparam [8:0] MAX_COUNT = 9'd256; // a sector count of 0 means 256
localparam       SECTOR_SHIFT = 9;   // bytes to sectors
localparam [15:0] MAX_CYL = 16'hFFFF;
localparam [7:0] REG_HIGH = 8'hFF;   // the upper byte of a register, before ppu.v inverts it

//------------------------------------------------------------------------
// The bus cycles: what a read does happens when it ends, so the word
// read stays put while ppu.v takes it; a write is taken when it starts.
//------------------------------------------------------------------------
reg  io_read_d = 1'b0, io_write_d = 1'b0;
always @(posedge clk) begin
    io_read_d  <= io_read;
    io_write_d <= io_write;
end
wire rd_done  = io_read_d & ~io_read;
wire wr_start = io_write & ~io_write_d;
reg  [2:0] rd_reg = REG_DATA;        // the register of the read in progress
always @(posedge clk) if(io_read) rd_reg <= io_address;

//------------------------------------------------------------------------
// The sector buffers.  Reads: two banks of 256 words; the bus drains bank
// `cur` while hps_io fills `fbank` with the next sector of a multi-sector
// read.  Writes: one sector, which the bus fills and hps_io takes.
//------------------------------------------------------------------------
reg  [7:0]  bufoff  = 8'd0;          // word index 0..255
reg         bwr     = 1'b0;
reg  [7:0]  bwaddr  = 8'd0;
reg  [15:0] bwdata  = 16'd0;
reg         cur     = 1'b0;          // the bank the bus reads
reg         fbank   = 1'b0;          // the bank a read fills
reg  [15:0] bdout;

reg  [15:0] rbuf[0:511];
reg  [15:0] wbuf[0:255];

// The word the bus will read next is always addressed, so it is there
// when the cycle comes.
always @(posedge clk) if(sd_buff_wr && sd_ack) rbuf[{fbank, sd_buff_addr}] <= sd_buff_dout;
always @(posedge clk) bdout <= rbuf[{cur, bufoff}];

always @(posedge clk) if(bwr) wbuf[bwaddr] <= bwdata;
always @(posedge clk) sd_buff_din <= wbuf[sd_buff_addr];

//------------------------------------------------------------------------
// The image, as hps_io mounts it
//------------------------------------------------------------------------
reg         mnt_new  = 1'b0;
reg         mnt_has  = 1'b0;         // non-empty
reg         mnt_ro   = 1'b0;
reg  [31:0] mnt_secs = 32'd0;

always @(posedge clk) begin
    mnt_new <= img_mounted;
    if(img_mounted) begin
        mnt_has  <= |img_size;
        mnt_ro   <= img_readonly;
        mnt_secs <= |img_size[63:32+SECTOR_SHIFT] ? 32'hFFFFFFFF : img_size[32+SECTOR_SHIFT-1:SECTOR_SHIFT];
    end
end

reg  ack_d = 1'b0;
always @(posedge clk) ack_d <= sd_ack;
wire acked = ack_d;

//------------------------------------------------------------------------
// The geometry, from sector 0, the way UKNCBTL's CHardDrive::AttachImage
// works it out: an "HD type" image announces itself with a signature in
// words 0-2 and carries spt in word 4 and spt * heads in word 5; an
// "ID/WD type" image carries spt and heads in bytes 0 and 1, and is
// inverted when bytes 0x1f0-0x1fb are all ones.  A geometry of zero leaves
// the controller unable to seek - visible, rather than silently wrong.
// The words are picked off hps_io's stream while sector 0 is read.
//------------------------------------------------------------------------
localparam [15:0] HD_SIG0 = 16'h54A9, HD_SIG1 = 16'hFFEF, HD_SIG2 = 16'hFEFF;
localparam [7:0]  W_SIG0 = 8'd0, W_SIG1 = 8'd1, W_SIG2 = 8'd2, W_SPT = 8'd4, W_HS = 8'd5;
localparam [7:0]  W_TEST_FIRST = 8'hF8, W_TEST_LAST = 8'hFD;   // bytes 0x1f0-0x1fb

reg         probing = 1'b0;
reg  [15:0] p_w0, p_w1, p_w2, p_w4, p_w5;
reg  [15:0] p_test;

always @(posedge clk) if(probing && sd_buff_wr && sd_ack) begin
    case(sd_buff_addr)
    W_SIG0: p_w0 <= sd_buff_dout;
    W_SIG1: p_w1 <= sd_buff_dout;
    W_SIG2: p_w2 <= sd_buff_dout;
    W_SPT:  p_w4 <= sd_buff_dout;
    W_HS:   p_w5 <= sd_buff_dout;
    default: ;
    endcase
    if(sd_buff_addr == W_SIG0) p_test <= 16'hFFFF;
    else if(sd_buff_addr >= W_TEST_FIRST && sd_buff_addr <= W_TEST_LAST) p_test <= p_test & sd_buff_dout;
end

wire        hd_plain = p_w0 == HD_SIG0 && p_w1 == HD_SIG1 && p_w2 == HD_SIG2;
wire        hd_inv   = p_w0 == ~HD_SIG0 && p_w1 == ~HD_SIG1 && p_w2 == ~HD_SIG2;
wire        wd_inv   = &p_test;

// A divider for heads = (spt * heads) / spt and cyl = sectors / (spt * heads)
reg  [31:0] dv_n = 32'd0;            // the dividend, shifting into the quotient
reg  [16:0] dv_r = 17'd0;
reg  [15:0] dv_d = 16'd0;
reg  [5:0]  dv_cnt = 6'd0;
wire [16:0] dv_sh = {dv_r[15:0], dv_n[31]};
wire        dv_ge = dv_sh >= {1'b0, dv_d};
localparam [5:0] DIV_STEPS = 6'd32;

reg  [7:0]  geo_spt = 8'd0, geo_heads = 8'd0;
reg  [15:0] geo_cyl = 16'd0;
reg         geo_inv = 1'b0;
reg  [15:0] geo_hs = 16'd0;          // spt * heads, set in P_HS

localparam [2:0] P_IDLE = 3'd0, P_REQ = 3'd1, P_WAIT = 3'd2, P_GEO = 3'd3,
                 P_HEADS = 3'd4, P_CYL = 3'd5, P_DIV = 3'd6, P_HS = 3'd7;
reg  [2:0]  pst = P_IDLE;
reg  [2:0]  p_after = P_IDLE;        // where P_DIV returns
reg         p_rd = 1'b0;
reg         present = 1'b0;          // mounted and probed, with a geometry

always @(posedge clk) begin
    if(dv_cnt != 6'd0) begin
        dv_cnt <= dv_cnt - 6'd1;
        dv_r   <= dv_ge ? dv_sh - {1'b0, dv_d} : dv_sh;
        dv_n   <= {dv_n[30:0], dv_ge};
    end

    case(pst)
    P_IDLE: ;
    // a request goes up only once a transfer still running from before
    // the mount is over, so its ack is not taken for this one's
    P_REQ: begin
        if(!acked) begin p_rd <= 1'b1; probing <= 1'b1; end
        if(p_rd && acked) begin p_rd <= 1'b0; pst <= P_WAIT; end
    end
    P_WAIT: if(!acked) begin probing <= 1'b0; pst <= P_GEO; end
    P_GEO: begin
        if(hd_plain || hd_inv) begin
            geo_inv   <= hd_inv;
            geo_spt   <= hd_inv ? ~p_w4[7:0] : p_w4[7:0];
            dv_n      <= {16'd0, hd_inv ? ~p_w5 : p_w5};
            dv_d      <= {8'd0, hd_inv ? ~p_w4[7:0] : p_w4[7:0]};
            dv_r      <= 17'd0;
            dv_cnt    <= DIV_STEPS;
            p_after   <= P_HEADS;
            pst       <= P_DIV;
        end else begin
            geo_inv   <= wd_inv;
            geo_spt   <= wd_inv ? ~p_w0[7:0] : p_w0[7:0];
            geo_heads <= wd_inv ? ~p_w0[15:8] : p_w0[15:8];
            pst       <= P_HS;
        end
    end
    P_DIV: if(dv_cnt == 6'd0) pst <= p_after;
    P_HEADS: begin
        geo_heads <= geo_spt == 8'd0 ? 8'd0 : dv_n[7:0];
        pst       <= P_HS;
    end
    P_HS: begin
        geo_hs <= geo_spt * geo_heads;
        pst    <= P_CYL;
    end
    P_CYL: begin
        // cylinders, for IDENTIFY: the WD ROM reads the drive's geometry
        // back and wants it to agree with the home block's
        if(p_after == P_CYL) begin
            geo_cyl <= |dv_n[31:16] ? MAX_CYL : dv_n[15:0];
            present <= 1'b1;
            pst     <= P_IDLE;
        end else if(geo_hs == 16'd0) begin
            geo_cyl <= 16'd0;
            present <= 1'b1;
            pst     <= P_IDLE;
        end else begin
            dv_n    <= mnt_secs;
            dv_d    <= geo_hs;
            dv_r    <= 17'd0;
            dv_cnt  <= DIV_STEPS;
            p_after <= P_CYL;
            pst     <= P_DIV;
        end
    end
    default: pst <= P_IDLE;
    endcase

    // a new image: drop the drive and probe it
    if(mnt_new) begin
        present <= 1'b0;
        p_rd    <= 1'b0;
        p_after <= P_IDLE;
        probing <= 1'b0;
        pst     <= mnt_has ? P_REQ : P_IDLE;
    end
end

//------------------------------------------------------------------------
// Drive state
//------------------------------------------------------------------------
reg  [7:0]  status = ST_BUSY, error = ER_NONE;
reg  [8:0]  sectorcount = 9'd0;      // 1..256
reg  [7:0]  cursector = 8'd0, curheadreg = 8'd0;
reg  [3:0]  curhead = 4'd0;
reg  [15:0] curcyl = 16'd0;
reg  [7:0]  spt_r = 8'd0, heads_r = 8'd0;
reg  [7:0]  resetcnt = 8'd0;

// Transfer engine states
localparam [3:0] S_IDLE = 4'd0, S_RD_LBA1 = 4'd1, S_RD_LBA2 = 4'd2, S_RD_REQ = 4'd3,
                 S_RD_WAIT = 4'd4, S_WR_LBA1 = 4'd5, S_WR_LBA2 = 4'd6, S_WR_REQ = 4'd7,
                 S_WR_WAIT = 4'd8;
reg  [3:0]  st = S_IDLE;
reg         id_mode = 1'b0;      // the data register reads the IDENTIFY sector
reg  [31:0] lba_c = 32'd0;           // cyl * heads * spt
reg  [12:0] lba_h = 13'd0;           // head * spt + sector
reg  [31:0] eng_lba = 32'd0;
reg         eng_rd = 1'b0, eng_wr = 1'b0;
// read ahead: the bus wants the next sector (drained its own, or the
// command just came) / the other bank already holds it / a READ came
// while a fetch was in flight, so its result is thrown away / a WRITE's
// buffer filled while a fetch was in flight
reg         rd_pending = 1'b0, pf_valid = 1'b0, restart = 1'b0, wr_pending = 1'b0;
reg         pf_bank = 1'b0;      // the bank the fetched sector sits in

always @(posedge clk) sd_lba <= probing ? 32'd0 : eng_lba;
assign sd_rd = eng_rd | p_rd;
assign sd_wr = eng_wr;

// heads * spt and the drive's size in sectors, for the transfer engine
// and IDENTIFY, worked out once into registers instead of on the bus's
// and the engine's paths.  spt_r and heads_r change only on a reset and
// on SET CONFIG, and the two clocks these take to follow are over long
// before the next command.
reg  [15:0] hs_r    = 16'd0;
reg  [31:0] total_r = 32'd0;
always @(posedge clk) begin
    hs_r    <= spt_r * heads_r;
    total_r <= geo_cyl * hs_r;
end

// The IDENTIFY sector, word by word, as Hard.cpp builds it.  Strings are
// stored with the first character in the high byte of each word.
function [15:0] ident;
    input [7:0] w;
    input [15:0] cyl; input [7:0] hd; input [7:0] sp;
    input [15:0] hs; input [31:0] total;
    begin
        case (w)
        8'd0:  ident = 16'h045a;
        8'd1:  ident = cyl;
        8'd3:  ident = {8'd0, hd};
        8'd6:  ident = {8'd0, sp};
        8'd10, 8'd11, 8'd12, 8'd13, 8'd14, 8'd15, 8'd16, 8'd17, 8'd18, 8'd19:
               ident = "00";                     // serial "0000000000"
        8'd23: ident = "1.";                     // firmware "1.0 "
        8'd24: ident = "0 ";
        8'd25, 8'd26: ident = "  ";
        8'd27: ident = "UK";                     // model "UKNC MiSTer Hard Disk"
        8'd28: ident = "NC";
        8'd29: ident = " M";
        8'd30: ident = "iS";
        8'd31: ident = "Te";
        8'd32: ident = "r ";
        8'd33: ident = "Ha";
        8'd34: ident = "rd";
        8'd35: ident = " D";
        8'd36: ident = "is";
        8'd37: ident = "k ";
        8'd38, 8'd39, 8'd40, 8'd41, 8'd42, 8'd43, 8'd44, 8'd45, 8'd46:
               ident = "  ";
        8'd47: ident = 16'h8001;
        8'd49: ident = 16'h2f00;
        8'd53: ident = 16'd1;
        8'd54: ident = cyl;
        8'd55: ident = {8'd0, hd};
        8'd56: ident = {8'd0, sp};
        8'd57: ident = hs;                       // heads*spt, low word
        8'd58: ident = 16'd0;
        8'd60: ident = total[15:0];
        8'd61: ident = total[31:16];
        8'd100: ident = total[15:0];
        8'd101: ident = total[31:16];
        default: ident = 16'd0;
        endcase
    end
endfunction

// The IDENTIFY word the bus will read next, addressed ahead as bdout is
reg  [15:0] id_dout = 16'd0;
always @(posedge clk) id_dout <= ident(bufoff, geo_cyl, heads_r, spt_r, hs_r, total_r);

// IDENTIFY reaches the software COMPLEMENTED, whatever form the image is
// in: that is what the bus does to the drive's identify words on real
// hardware, and WDINIT's identify loop complements every word it reads.
wire [15:0] inv_mask = {16{geo_inv}};
wire        wprot    = mnt_ro;

// LBA28 mode: the sector number is the register bytes themselves
wire        lba_mode = curheadreg[HEAD_LBA];
wire [27:0] lba_cur  = {curheadreg[3:0], curcyl, cursector};
wire [27:0] lba_nxt  = lba_cur + 28'd1;

// next sector, Hard.cpp NextSector(): CHS, or the LBA counted up
task next_sector;
    begin
      if (lba_mode) begin
        cursector       <= lba_nxt[7:0];
        curcyl          <= lba_nxt[23:8];
        curheadreg[3:0] <= lba_nxt[27:24];
        curhead         <= lba_nxt[27:24];
      end else begin
        // sectors are 1-based, heads compared in full width
        if ({1'b0, cursector} + 9'd1 > {1'b0, spt_r}) begin
            cursector <= 8'd1;
            if ({4'd0, curhead} + 8'd1 >= heads_r) begin
                curhead <= 4'd0;
                curcyl  <= curcyl + 16'd1;
            end else
                curhead <= curhead + 4'd1;
        end else
            cursector <= cursector + 8'd1;
      end
    end
endtask

// what a read gives: data words as they are, the rest as ppu.v inverts them
always @(*) begin
    case (io_address)
    REG_DATA:   io_readdata = id_mode ? ~id_dout : bdout ^ inv_mask;
    REG_ERROR:  io_readdata = {REG_HIGH, error};
    REG_COUNT:  io_readdata = {REG_HIGH, sectorcount[7:0]};
    REG_SECTOR: io_readdata = {REG_HIGH, cursector};
    REG_CYL_LO: io_readdata = {REG_HIGH, curcyl[7:0]};
    REG_CYL_HI: io_readdata = {REG_HIGH, curcyl[15:8]};
    REG_HEAD:   io_readdata = {REG_HIGH, curheadreg};
    default:    io_readdata = {REG_HIGH, status};
    endcase
end

wire [7:0] wr_byte = io_writedata[7:0];

always @(posedge clk) begin
    bwr <= 1'b0;

    if (!rst_n || !present) begin
        status      <= ST_BUSY;
        error       <= ER_NONE;
        resetcnt    <= RESET_CLOCKS;       // Reset(): BUSY, then READY|SEEK
        st          <= S_IDLE;
        eng_rd      <= 1'b0;
        eng_wr      <= 1'b0;
        bufoff      <= 8'd0;
        sectorcount <= 9'd0;
        cur         <= 1'b0;
        fbank       <= 1'b0;
        rd_pending  <= 1'b0;
        pf_valid    <= 1'b0;
        restart     <= 1'b0;
        wr_pending  <= 1'b0;
        pf_bank     <= 1'b0;
        id_mode     <= 1'b0;
        spt_r       <= geo_spt;
        heads_r     <= geo_heads;
    end else begin
        // power-on / reset timing
        if (resetcnt != 8'd0) begin
            resetcnt <= resetcnt - 8'd1;
            if (resetcnt == 8'd1)
                status <= (status & ~ST_BUSY) | ST_READY | ST_SEEK;
        end

        // handing a fetched sector to the bus: it is in a bank and the bus
        // wants it.  Then the bank just freed is filled with the next sector
        // of the command while this one drains.
        if (rd_pending && pf_valid) begin
            rd_pending <= 1'b0;
            pf_valid   <= 1'b0;
            id_mode    <= 1'b0;
            cur        <= pf_bank;
            bufoff     <= 8'd0;
            status     <= (status & ~ST_BUSY & ~ST_ERROR) | ST_DRQ | ST_SEEK;
            if (sectorcount != 9'd0 && st == S_IDLE) begin
                fbank <= ~pf_bank;
                st    <= S_RD_LBA1;
            end
        end

        //----------------------------------------------------------------
        // The bus: a data read moves on to the next word when it ends
        //----------------------------------------------------------------
        if (rd_done && rd_reg == REG_DATA && (status & ST_DRQ)) begin
            if (bufoff == LAST_WORD) begin               // sector consumed: ContinueRead
                bufoff <= 8'd0;
                status <= status & ~ST_DRQ & ~ST_BUSY;
                if (pf_valid || sectorcount != 9'd0 || st != S_IDLE) begin
                    rd_pending <= 1'b1;              // the next one: in the other bank, or on its way
                    status     <= (status & ~ST_DRQ) | ST_BUSY;
                    if (!pf_valid && st == S_IDLE) begin fbank <= ~cur; st <= S_RD_LBA1; end
                end
            end else
                bufoff <= bufoff + 8'd1;
        end

        if (wr_start) begin
            case (io_address)
            REG_DATA: if (status & ST_DRQ) begin            // DATA write
                bwr    <= 1'b1;
                bwaddr <= bufoff;
                bwdata <= io_writedata ^ inv_mask;
                if (bufoff == LAST_WORD) begin               // ContinueWrite
                    bufoff <= 8'd0;
                    status <= (status & ~ST_DRQ) | ST_BUSY;
                    if (st == S_IDLE) st <= S_WR_LBA1;
                    else              wr_pending <= 1'b1;    // a read-ahead is still in flight
                end else
                    bufoff <= bufoff + 8'd1;
            end
            REG_ERROR: ;                                     // precompensation, ignored
            REG_COUNT:  sectorcount <= (wr_byte == 8'd0) ? MAX_COUNT : {1'b0, wr_byte};
            REG_SECTOR: cursector   <= wr_byte;
            REG_CYL_LO: curcyl[7:0] <= wr_byte;
            REG_CYL_HI: curcyl[15:8]<= wr_byte;
            REG_HEAD:   begin curheadreg <= wr_byte; curhead <= wr_byte[3:0]; end
            REG_STATUS: begin                                // COMMAND
                case (wr_byte)
                CMD_READ, CMD_READ1: begin
                    status     <= (status | ST_BUSY) & ~ST_DRQ & ~ST_ERROR;
                    rd_pending <= 1'b1;
                    pf_valid   <= 1'b0;
                    id_mode    <= 1'b0;
                    fbank      <= cur;
                    if (st == S_IDLE) st <= S_RD_LBA1;
                    else              restart <= 1'b1;       // a read-ahead of the last command is in flight
                end
                CMD_SETCFG: begin
                    spt_r   <= sectorcount[7:0];
                    heads_r <= {4'd0, curhead} + 8'd1;
                end
                CMD_WRITE, CMD_WRITE1: begin
                    bufoff   <= 8'd0;
                    pf_valid <= 1'b0;
                    id_mode  <= 1'b0;
                    status   <= (status | ST_DRQ) & ~ST_ERROR;   // a new command clears ERR, as on a drive
                end
                CMD_IDENT: begin                                 // (drops a read-ahead; none is in flight at boot)
                    id_mode     <= 1'b1;
                    bufoff      <= 8'd0;
                    pf_valid    <= 1'b0;
                    sectorcount <= 9'd1;
                    status      <= (status | ST_DRQ | ST_SEEK | ST_READY) & ~ST_BUSY & ~ST_ERROR;
                end
                default: ;
                endcase
            end
            endcase
        end

        //----------------------------------------------------------------
        // The transfer engine
        //----------------------------------------------------------------
        case (st)
        S_IDLE: ;
        // the sector number, cyl * heads * spt + head * spt + sector - 1:
        // the two products, then their sum, then the request
        S_RD_LBA1, S_WR_LBA1: begin
            if (lba_mode) begin
                eng_lba <= {4'd0, lba_cur};
                st      <= (st == S_RD_LBA1) ? S_RD_REQ : S_WR_REQ;
            end else begin
                lba_c <= curcyl * hs_r;
                lba_h <= curhead * spt_r + {5'd0, cursector};
                st    <= (st == S_RD_LBA1) ? S_RD_LBA2 : S_WR_LBA2;
            end
        end
        S_RD_LBA2, S_WR_LBA2: begin
            eng_lba <= lba_c + {19'd0, lba_h} - 32'd1;
            st      <= (st == S_RD_LBA2) ? S_RD_REQ : S_WR_REQ;
        end
        // hps_io takes the request, raises sd_ack for the transfer and
        // drops it after; a request goes up only with no ack left over
        // from a transfer the reset cut short
        S_RD_REQ: begin
            if (!acked) eng_rd <= 1'b1;
            if (eng_rd && acked) begin eng_rd <= 1'b0; st <= S_RD_WAIT; end
        end
        S_RD_WAIT: if (!acked) begin                              // ReadSectorDone
            if (restart) begin                                    // a newer READ: fetch its sector instead
                restart <= 1'b0;
                fbank   <= cur;
                st      <= S_RD_LBA1;
            end else begin
                error <= ER_NONE;
                if (sectorcount != 9'd0) sectorcount <= sectorcount - 9'd1;
                if (sectorcount > 9'd1) next_sector;
                // the sector is in fbank; the hand-over above gives it to
                // the bus when it asks, and starts the read ahead of the
                // next one into the bank that frees
                pf_valid <= 1'b1;
                pf_bank  <= fbank;
                if (wr_pending) begin wr_pending <= 1'b0; st <= S_WR_LBA1; end
                else            st <= S_IDLE;
            end
        end
        S_WR_REQ: begin
            if (wprot) begin
                // Hard.cpp WriteSectorDone() on a read-only image: no write,
                // ERROR with BAD_SECTOR, the buffer left as it is.
                status <= (status & ~ST_BUSY) | ST_ERROR | ST_DRQ | ST_SEEK;
                error  <= ER_BADSECT;
                bufoff <= 8'd0;
                st     <= S_IDLE;
            end else begin
                if (!acked) eng_wr <= 1'b1;
                if (eng_wr && acked) begin eng_wr <= 1'b0; st <= S_WR_WAIT; end
            end
        end
        S_WR_WAIT: if (!acked) begin                              // WriteSectorDone
            status <= (status & ~ST_BUSY & ~ST_ERROR) | ST_DRQ | ST_SEEK;
            error  <= ER_NONE;
            bufoff <= 8'd0;
            if (sectorcount != 9'd0) sectorcount <= sectorcount - 9'd1;
            if (sectorcount > 9'd1) next_sector;
            st <= S_IDLE;
        end
        default: st <= S_IDLE;
        endcase
    end
end

endmodule
