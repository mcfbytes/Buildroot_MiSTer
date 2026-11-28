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
	wire underrun, frame; wire [2:0] scale;
	de25_fb_regs u_r (.clk(clk), .rst_n(rst_n), .address(addr), .read(rd), .write(wr),
		.writedata(wdata), .readdata(rdata), .enable(en), .base(base), .width(w), .height(h),
		.stride(stride), .underrun(underrun), .frame(frame), .scale(scale));
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
	always @(posedge clk) begin
		arready <= ($urandom % 100) >= stall_pct;
		if (arvalid && arready) begin q[qt % 64] <= araddr; qt <= qt + 1; end
		if (rvalid && rready) rvalid <= 0;
		// Present the next beat whenever the channel is free, after a random stall.
		if ((!rvalid || rready) && qh != qt && ($urandom % 100) >= stall_pct) begin
			for (k = 0; k < 8; k = k + 1)
				rdata_m[k*32 +: 32] <= pix(q[qh % 64] + nb * 32 + k * 4);
			rvalid <= 1;
			rlast <= nb == 7;
			if (nb == 7) begin nb <= 0; qh <= qh + 1; end else nb <= nb + 1;
		end
	end

	wire active; wire [23:0] rgb;
	de25_fb_reader u_f (.clk(clk), .rst_n(rst_n), .cfg_enable(en), .cfg_base(base), .cfg_width(w),
		.cfg_height(h), .cfg_stride(stride), .underrun(underrun), .frame(frame), .scale(scale),
		.m_araddr(araddr), .m_arlen(arlen), .m_arsize(arsize), .m_arburst(arburst), .m_arid(arid),
		.m_arcache(arcache), .m_arprot(arprot), .m_arvalid(arvalid), .m_arready(arready),
		.m_rdata(rdata_m), .m_rlast(rlast), .m_rvalid(rvalid), .m_rready(rready),
		.pclk(pclk), .prst_n(rst_n), .hs_in(hs), .vs_in(vs), .de_in(de), .x_in(x), .y_in(y),
		.active(active), .rgb(rgb));

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

	task run_case(input integer ww, input integer hh, input integer ss, input integer st, input integer stall);
		reg [31:0] status; integer exp_s;
		begin
			stall_pct = stall;
			wreg(4'd2, 0); wreg(4'd3, 32'hA000_1000); wreg(4'd4, 0);
			wreg(4'd5, ww); wreg(4'd6, hh); wreg(4'd7, st); wreg(4'd9, 1); wreg(4'd2, 1);
			exp_s = ss;
			cw = ww; ch = hh; cs = exp_s; cstride = st; cbase = 40'h00_A000_1000;
			cx0 = (1920 - ww * exp_s) / 2; cy0 = (1080 - hh * exp_s) / 2;
			// Settings are taken at the next vsync; check the frame after that, start to end.
			@(posedge vs); @(posedge vs); @(negedge vs);
			while (!(y == 0 && x == 0 && de)) @(posedge pclk);
			bad = 0; n_img = 0; checking = 1;
			@(posedge vs); checking = 0;
			rreg(4'd9, status);
			$display("case %0dx%0d stride=%0d stall=%0d%%: scale=%0d inside=%0d mismatches=%0d underrun=%0d",
				ww, hh, st, stall, status[6:4], n_img, bad, status[0]);
		end
	endtask

	reg [31:0] magic;
	initial begin
		#20000 rst_n = 1;
		rreg(4'd0, magic); $display("magic=%h", magic);
		run_case(640, 480, 2, 2560, 30);
		run_case(1280, 720, 1, 5120, 30);
		run_case(1920, 1080, 1, 7680, 50);
		run_case(333, 200, 4, 1536, 30);
		$finish;
	end
endmodule
