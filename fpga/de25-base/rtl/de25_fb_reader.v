// SPDX-License-Identifier: GPL-3.0-or-later
// Scans a linear XRGB8888 framebuffer in HPS DDR out to 1080p over a 256-bit AXI4 read port.
// Whole-number scale (1-4x), centred, black border; design notes in docs/de25-base-image.md §6.
module de25_fb_reader #(
	parameter AW = 40,
	parameter [AW-1:0] WIN_LO = 40'h00_8000_0000,  // the region must lie in [WIN_LO, WIN_HI)
	parameter [AW-1:0] WIN_HI = 40'h00_C000_0000   // (HPS DDR on the DE25)
) (
	// --- system clock: registers and AXI ---
	input  wire          clk,
	input  wire          rst_n,          // synchronous to clk (de25_hdmi synchronises it)
	input  wire          cfg_enable,
	input  wire [AW-1:0] cfg_base,
	input  wire [11:0]   cfg_width,
	input  wire [10:0]   cfg_height,
	input  wire [15:0]   cfg_stride,
	output reg           underrun,       // pulse: a fetch was still running when the next was due
	output reg           rerror,         // pulse: a read response was not OKAY
	output reg           frame,          // pulse: a frame's settings were taken
	output reg  [2:0]    scale,
	output reg  [AW-1:0] m_araddr,
	output wire [7:0]    m_arlen,
	output wire [2:0]    m_arsize,
	output wire [1:0]    m_arburst,
	output wire [4:0]    m_arid,
	output wire [3:0]    m_arcache,
	output wire [2:0]    m_arprot,
	output reg           m_arvalid,
	input  wire          m_arready,
	input  wire [255:0]  m_rdata,
	input  wire [1:0]    m_rresp,
	input  wire          m_rlast,
	input  wire          m_rvalid,
	output wire          m_rready,
	// --- pixel clock: timing in (from de25_vtiming), pixels out three cycles later ---
	input  wire          pclk,
	input  wire          prst_n,         // synchronous to pclk
	input  wire          hs_in,
	input  wire          vs_in,
	input  wire          de_in,
	input  wire [11:0]   x_in,
	input  wire [10:0]   y_in,
	output reg           p_on,           // this frame shows the framebuffer (changes at vsync)
	output reg           active,         // this pixel comes from the framebuffer
	output reg  [23:0]   rgb
);
	localparam H_ACT = 1920, V_ACT = 1080, V_TOT = 1125;
	assign m_arlen = 8'd7;                // 8 beats x 32 B = 256 B: never crosses 4 KiB
	assign m_arsize = 3'd5;
	assign m_arburst = 2'b01;
	assign m_arid = 5'd0;
	assign m_arcache = 4'b0011;
	assign m_arprot = 3'b000;
	assign m_rready = 1'b1;

	// ---------------- frame handshake: pixel asks at vsync, system snapshots ----------------
	reg          f_en;
	reg [AW-1:0] f_base;
	reg [11:0]   f_w;
	reg [10:0]   f_h;
	reg [15:0]   f_stride;
	reg [11:0]   f_x0;
	reg [10:0]   f_y0;
	reg          p_freq;
	reg [2:0]    s_freq;
	reg          s_fack;
	reg [2:0]    p_fack;

	// Largest whole scale that fits, then the centring offsets.
	wire [AW-1:0] f_end = cfg_base + cfg_height * cfg_stride + 256;  // last burst may overrun a row
	wire       ok = cfg_enable && cfg_width != 0 && cfg_height != 0 &&
	                cfg_width <= H_ACT && cfg_height <= V_ACT && cfg_stride >= {cfg_width, 2'b00} &&
	                cfg_base[7:0] == 8'd0 && cfg_stride[7:0] == 8'd0 &&
	                cfg_base >= WIN_LO && f_end <= WIN_HI && f_end > cfg_base;
	wire [2:0] sc = (cfg_width * 4 <= H_ACT && cfg_height * 4 <= V_ACT) ? 3'd4 :
	                (cfg_width * 3 <= H_ACT && cfg_height * 3 <= V_ACT) ? 3'd3 :
	                (cfg_width * 2 <= H_ACT && cfg_height * 2 <= V_ACT) ? 3'd2 : 3'd1;

	always @(posedge clk) begin
		if (!rst_n) begin
			s_freq <= 3'd0; s_fack <= 1'b0; frame <= 1'b0; scale <= 3'd1;
			f_en <= 1'b0; f_base <= 0; f_w <= 0; f_h <= 0; f_stride <= 0; f_x0 <= 0; f_y0 <= 0;
		end else begin
			s_freq <= {s_freq[1:0], p_freq};
			frame <= 1'b0;
			if (s_freq[2] != s_freq[1]) begin
				f_en <= ok; f_base <= cfg_base; f_w <= cfg_width; f_h <= cfg_height;
				f_stride <= cfg_stride; scale <= sc;
				f_x0 <= (H_ACT - cfg_width * sc) >> 1;
				f_y0 <= (V_ACT - cfg_height * sc) >> 1;
				s_fack <= s_freq[1];
				frame <= 1'b1;
			end
		end
	end

	// ---------------- line requests: pixel asks for a row two lines ahead ----------------
	reg        p_lreq;                    // toggles once per request
	reg [10:0] p_lrow;                    // stable while a request is outstanding
	reg        p_lbuf;
	reg [2:0]  s_lreq;

	// ---------------- system side: fetch one row into one half of the line buffer ----------------
	reg        busy;
	reg [5:0]  bursts_left;               // addresses still to issue, of ceil(width / 64)
	reg [5:0]  rl_left;                   // bursts whose data has not finished
	reg [8:0]  beats_left;                // beats still to store, of ceil(width / 8)
	reg [7:0]  waddr;
	reg        wbuf;
	reg [255:0] lbuf [0:511];

	always @(posedge clk) begin
		if (!rst_n) begin
			s_lreq <= 3'd0; busy <= 1'b0; m_arvalid <= 1'b0; m_araddr <= 0;
			bursts_left <= 0; rl_left <= 0; beats_left <= 0; waddr <= 0; wbuf <= 0;
			underrun <= 1'b0; rerror <= 1'b0;
		end else begin
			s_lreq <= {s_lreq[1:0], p_lreq};
			underrun <= 1'b0;
			rerror <= 1'b0;
			// A request while a fetch runs is dropped, never restarted: the AR channel and the
			// fetch's own bookkeeping stay coherent, and the dropped line shows stale pixels.
			if (s_lreq[2] != s_lreq[1] && f_en && busy) underrun <= 1'b1;
			if (s_lreq[2] != s_lreq[1] && f_en && !busy) begin
				busy <= 1'b1;
				wbuf <= p_lbuf;
				waddr <= 8'd0;
				m_araddr <= f_base + p_lrow * f_stride;
				m_arvalid <= 1'b1;
				bursts_left <= (f_w + 12'd63) >> 6;
				rl_left <= (f_w + 12'd63) >> 6;
				beats_left <= (f_w + 12'd7) >> 3;
			end else if (busy) begin
				if (m_arvalid && m_arready) begin
					if (bursts_left == 6'd1) m_arvalid <= 1'b0;
					bursts_left <= bursts_left - 6'd1;
					m_araddr <= m_araddr + 256;
				end
				if (m_rvalid) begin
					if (m_rresp != 2'b00) rerror <= 1'b1;
					if (beats_left != 0) begin
						lbuf[{wbuf, waddr}] <= m_rdata;
						waddr <= waddr + 8'd1;
						beats_left <= beats_left - 9'd1;
					end
					// The last burst may fetch past the line's end; those beats are dropped.
					if (m_rlast) begin
						rl_left <= rl_left - 6'd1;
						if (rl_left == 6'd1) busy <= 1'b0;
					end
				end
			end
		end
	end

	// ---------------- pixel side ----------------
	reg        p_en;
	reg [11:0] p_w, p_x0;
	reg [10:0] p_h, p_y0;
	reg [2:0]  p_sc;
	reg        vs_d, hs_d;
	// row tracking for the line two ahead (n_*), and the line one ahead (c1_*)
	reg        n_in;
	reg [10:0] n_row;
	reg [2:0]  n_sub;
	reg        c1_in;                     // the next line shows the framebuffer
	reg        c_in;                      // the current line shows the framebuffer
	// column tracking (stage 1)
	reg        x_in1;
	reg [11:0] col;
	reg [2:0]  csub;
	reg        lb1;
	// stage 2
	reg [255:0] word2;
	reg [2:0]  lane2;
	reg        x_in2;

	// At the hsync after line y's pixels, line y+2 is requested into the half line y just freed.
	wire [10:0] y_ahead  = (y_in >= V_TOT - 2) ? y_in + 11'd2 - V_TOT : y_in + 11'd2;
	wire        nx_first = p_en && y_ahead == p_y0;
	wire        nx_wrap  = n_sub == p_sc - 3'd1;
	wire        nx_in    = nx_first || (p_en && n_in && !(nx_wrap && n_row == p_h - 11'd1));
	wire [10:0] nx_row   = nx_first ? 11'd0 : (nx_wrap ? n_row + 11'd1 : n_row);
	wire [2:0]  nx_sub   = (nx_first || nx_wrap) ? 3'd0 : n_sub + 3'd1;

	always @(posedge pclk) begin
		if (!prst_n) begin
			p_freq <= 1'b0; p_fack <= 3'd0; p_en <= 1'b0; p_on <= 1'b0;
			p_w <= 0; p_h <= 0; p_x0 <= 0; p_y0 <= 0;
			p_sc <= 3'd1; vs_d <= 1'b0; hs_d <= 1'b0; p_lreq <= 1'b0; p_lrow <= 0; p_lbuf <= 1'b0;
			n_in <= 1'b0; n_row <= 0; n_sub <= 0; c1_in <= 1'b0; c_in <= 1'b0;
			x_in1 <= 1'b0; col <= 0; csub <= 0; lb1 <= 1'b0;
			word2 <= 0; lane2 <= 0; x_in2 <= 1'b0; active <= 1'b0; rgb <= 24'd0;
		end else begin
			vs_d <= vs_in; hs_d <= hs_in;
			p_fack <= {p_fack[1:0], s_fack};
			if (vs_in && !vs_d) p_freq <= ~p_freq;                 // ask for this frame's settings
			if (p_fack[2] != p_fack[1]) begin                       // the system took them
				p_en <= f_en; p_on <= f_en;
				p_w <= f_w; p_h <= f_h; p_x0 <= f_x0; p_y0 <= f_y0; p_sc <= scale;
			end

			if (hs_in && !hs_d) begin
				n_in <= nx_in; n_row <= nx_row; n_sub <= nx_sub;
				c1_in <= nx_in;
				c_in <= c1_in;
				if (nx_in) begin p_lrow <= nx_row; p_lbuf <= y_ahead[0]; p_lreq <= ~p_lreq; end
			end

			// Stage 1: which framebuffer column this pixel shows.
			if (!de_in || !c_in) x_in1 <= 1'b0;
			else if (x_in == p_x0) begin x_in1 <= 1'b1; col <= 12'd0; csub <= 3'd0; end
			else if (x_in1) begin
				if (csub == p_sc - 3'd1) begin
					csub <= 3'd0;
					if (col == p_w - 12'd1) x_in1 <= 1'b0; else col <= col + 12'd1;
				end else csub <= csub + 3'd1;
			end
			lb1 <= y_in[0];

			// Stage 2: the 8-pixel word; stage 3: the pixel.
			word2 <= lbuf[{lb1, col[10:3]}];
			lane2 <= col[2:0];
			x_in2 <= x_in1;
			active <= x_in2;
			rgb <= x_in2 ? word2[lane2 * 32 +: 24] : 24'd0;
		end
	end
endmodule
