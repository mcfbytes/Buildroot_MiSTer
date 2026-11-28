// SPDX-License-Identifier: GPL-3.0-or-later
// de25_fb_reader + de25_fb_regs against a stalling AXI memory model; checks whole 1080p frames.
`timescale 1ps/1ps
module tb_fb;
	reg clk = 0, pclk = 0, rst_n = 0;
	always #5000 clk = ~clk;                 // 100 MHz
	always #3367 pclk = ~pclk;               // ~148.5 MHz

	// --- registers ---
	reg [3:0] addr = 0; reg rd = 0, wr = 0; reg [31:0] wdata = 0; wire [31:0] rdata;
	wire en; wire [39:0] base; wire [11:0] w; wire [10:0] h; wire [15:0] stride;
	wire underrun, rerror, frame; wire [2:0] scale;
	de25_fb_regs u_r (.clk(clk), .rst_n(rst_n), .address(addr), .read(rd), .write(wr),
		.byteenable(4'hF), .writedata(wdata), .readdata(rdata), .enable(en), .base(base), .width(w),
		.height(h), .stride(stride), .underrun(underrun), .rerror(rerror), .frame(frame),
		.scale(scale), .init_done(1'b1), .init_nack(1'b0));
	task wreg(input [3:0] a, input [31:0] d);
		begin @(posedge clk); addr <= a; wdata <= d; wr <= 1; @(posedge clk); wr <= 0; end
	endtask
	task rreg(input [3:0] a, output [31:0] d);
		begin @(posedge clk); addr <= a; rd <= 1; @(posedge clk); rd <= 0; @(negedge clk); d = rdata; end
	endtask

	// --- timing ---
	wire hs, vs, de; wire [11:0] x; wire [10:0] y;
	de25_vtiming u_t (.clk(pclk), .rst_n(rst_n), .hs(hs), .vs(vs), .de(de), .x(x), .y(y));

	// --- AXI memory model: random stalls, 8-beat bursts, in order ---
	wire [39:0] araddr; wire [7:0] arlen; wire arvalid, rready;
	wire [2:0] arsize; wire [1:0] arburst; wire [4:0] arid; wire [3:0] arcache; wire [2:0] arprot;
	reg arready = 0, rvalid = 0, rlast = 0; reg [255:0] rdata_m = 0;
	integer stall_pct = 30;
	function [31:0] pix(input [39:0] a);     // the value stored at byte address a
		pix = (a[33:2] * 32'h9E3779B1) ^ (a[33:2] >> 7);
	endfunction
	reg [39:0] q [0:63]; integer qh = 0, qt = 0, nb = 0, k;
	integer hold = 0, proto_bad = 0, inject_err = 0; reg [1:0] rresp = 0;
	reg ar_was_waiting = 0; reg [39:0] ar_last = 0;
	always @(posedge clk) begin
		// AXI checks: payload stable while waiting; fixed burst shape; 256-byte aligned.
		if (arvalid && ar_was_waiting && araddr !== ar_last) proto_bad = proto_bad + 1;
		if (arvalid && (arlen !== 8'd7 || arsize !== 3'd5 || arburst !== 2'b01 || araddr[7:0] !== 0))
			proto_bad = proto_bad + 1;
		ar_was_waiting <= arvalid && !arready; ar_last <= araddr;
		if (hold > 0) hold <= hold - 1;
		arready <= hold == 0 && ($urandom % 100) >= stall_pct;
		if (arvalid && arready) begin q[qt % 64] <= araddr; qt <= qt + 1; end
		if (rvalid && rready) rvalid <= 0;
		// Present the next beat whenever the channel is free, after a random stall.
		if ((!rvalid || rready) && qh != qt && hold == 0 && ($urandom % 100) >= stall_pct) begin
			rresp <= (inject_err > 0 && nb == 0) ? 2'b10 : 2'b00;
			if (inject_err > 0 && nb == 0) inject_err = inject_err - 1;
			for (k = 0; k < 8; k = k + 1)
				rdata_m[k*32 +: 32] <= pix(q[qh % 64] + nb * 32 + k * 4);
			rvalid <= 1;
			rlast <= nb == 7;
			if (nb == 7) begin nb <= 0; qh <= qh + 1; end else nb <= nb + 1;
		end
	end

	wire active, p_on; wire [23:0] rgb;
	reg prst_n = 0; always @(posedge pclk) prst_n <= rst_n;
	de25_fb_reader u_f (.clk(clk), .rst_n(rst_n), .cfg_enable(en), .cfg_base(base), .cfg_width(w),
		.cfg_height(h), .cfg_stride(stride), .underrun(underrun), .rerror(rerror), .frame(frame), .scale(scale),
		.m_araddr(araddr), .m_arlen(arlen), .m_arsize(arsize), .m_arburst(arburst), .m_arid(arid),
		.m_arcache(arcache), .m_arprot(arprot), .m_arvalid(arvalid), .m_arready(arready),
		.m_rdata(rdata_m), .m_rresp(rresp), .m_rlast(rlast), .m_rvalid(rvalid), .m_rready(rready),
		.pclk(pclk), .prst_n(prst_n), .hs_in(hs), .vs_in(vs), .de_in(de), .x_in(x), .y_in(y),
		.p_on(p_on), .active(active), .rgb(rgb));

	// --- checker: compare each output pixel with the expected image, 3 cycles after timing ---
	reg [11:0] x1, x2, x3; reg [10:0] y1, y2, y3; reg de1, de2, de3;
	always @(posedge pclk) begin x1 <= x; x2 <= x1; x3 <= x2; y1 <= y; y2 <= y1; y3 <= y2;
		de1 <= de; de2 <= de1; de3 <= de2; end
	reg checking = 0; integer bad = 0, n_img = 0, cw, ch, cs, cx0, cy0; reg [39:0] cbase; integer cstride;
	reg in_img; reg [23:0] want;
	always @(posedge pclk) if (checking && de3) begin
		in_img = x3 >= cx0 && x3 < cx0 + cw * cs && y3 >= cy0 && y3 < cy0 + ch * cs;
		want = in_img ? pix(cbase + ((y3 - cy0) / cs) * cstride + ((x3 - cx0) / cs) * 4) : 24'd0;
		if (in_img) n_img = n_img + 1;
		if (active !== in_img || rgb !== want) begin
			if (bad < 5) $display("  mismatch at (%0d,%0d): active=%b rgb=%h want %b %h", x3, y3, active, rgb, in_img, want);
			bad = bad + 1;
		end
	end

	integer fails = 0;
	// kind 0: the image must be exact; 1: must be black (invalid settings); 2: forced underrun;
	// 3: one read error. ss = expected scale (0 for black).
	task run_case(input [255:0] name, input integer ww, input integer hh, input integer ss,
	              input integer st, input [39:0] b, input integer stall, input integer kind);
		reg [31:0] status; reg ok;
		begin
			stall_pct = stall; proto_bad = 0;
			wreg(4'd2, 0); wreg(4'd3, b[31:0]); wreg(4'd4, b[39:32]);
			wreg(4'd5, ww); wreg(4'd6, hh); wreg(4'd7, st); wreg(4'd9, 3); wreg(4'd2, 1);
			cw = (kind == 1) ? 0 : ww; ch = hh; cs = (ss == 0) ? 1 : ss; cstride = st; cbase = b;
			cx0 = (1920 - ww * cs) / 2; cy0 = (1080 - hh * cs) / 2;
			@(posedge vs); @(posedge vs); @(negedge vs);
			while (!(y == 0 && x == 0 && de)) @(posedge pclk);
			if (kind == 2) begin wreg(4'd9, 3); repeat (600000) @(posedge clk); hold = 3500; end
			if (kind == 3) begin wreg(4'd9, 3); repeat (50000) @(posedge clk); inject_err = 1; end
			while (!(y == 0 && x == 0 && de)) @(posedge pclk);
			if (kind == 0 || kind == 1) begin
				bad = 0; n_img = 0; checking = 1;
				@(posedge vs); checking = 0;
			end else @(posedge vs);
			rreg(4'd9, status);
			case (kind)
				0: ok = bad == 0 && n_img == ww * hh * ss * ss && status[6:4] == ss && status[1:0] == 0;
				1: ok = bad == 0 && n_img == 0 && status[1:0] == 0;
				2: ok = status[0] == 1;
				3: ok = status[1] == 1 && status[0] == 0;
			endcase
			ok = ok && proto_bad == 0;
			if (!ok) fails = fails + 1;
			$display("%s %0s: %0dx%0d stride=%0d base=%h stall=%0d%% scale=%0d image_px=%0d mismatches=%0d status=%h axi_violations=%0d",
				ok ? "PASS" : "FAIL", name, ww, hh, st, b, stall, status[6:4], n_img, bad, status[15:0], proto_bad);
		end
	endtask

	reg [31:0] magic, version;
	initial begin
		#20000 @(negedge clk) rst_n = 1;
		rreg(4'd0, magic); rreg(4'd1, version);
		if (magic !== 32'hDE25FB5A || version !== 2) fails = fails + 1;
		$display("%s magic=%h version=%0d", (magic === 32'hDE25FB5A && version === 2) ? "PASS" : "FAIL", magic, version);
		run_case("2x",            640,  480, 2, 2560, 40'h00_A000_1000, 30, 0);
		run_case("1x",           1280,  720, 1, 5120, 40'h00_A000_1000, 30, 0);
		run_case("full",         1920, 1080, 1, 7680, 40'h00_A000_1000, 50, 0);
		run_case("4x-odd",        333,  200, 4, 1536, 40'h00_A000_1000, 30, 0);
		run_case("3x",            600,  300, 3, 2560, 40'h00_A100_0000, 30, 0);
		run_case("short-stride",  640,  480, 0, 2304, 40'h00_A000_1000, 30, 1);
		run_case("outside-ddr",   640,  480, 0, 2560, 40'h00_0000_1000, 30, 1);
		run_case("underrun",     1280,  720, 1, 5120, 40'h00_A000_1000, 10, 2);
		run_case("recovered",    1280,  720, 1, 5120, 40'h00_A000_1000, 30, 0);
		run_case("read-error",    640,  480, 2, 2560, 40'h00_A000_1000, 30, 3);
		$display("tb_fb: %0d failure(s)", fails);
		$finish;
	end
endmodule
