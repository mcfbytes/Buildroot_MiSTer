// SPDX-License-Identifier: GPL-3.0-or-later
// One full 1080p frame through de25_vtiming + de25_splash: timing counts and lit-pixel count.
`timescale 1ns/1ps
module tb_video;
	reg clk = 0, rst_n = 0;
	always #1 clk = ~clk;
	wire hs0, vs0, de0, hs, vs, de;
	wire [11:0] x; wire [10:0] y; wire [23:0] rgb;
	de25_vtiming t (.clk(clk), .rst_n(rst_n), .hs(hs0), .vs(vs0), .de(de0), .x(x), .y(y));
	de25_splash #(.LOGO_HEX("../rtl/de25_splash_logo.hex")) s (.clk(clk), .hs_in(hs0), .vs_in(vs0), .de_in(de0),
		.x(x), .y(y), .hs(hs), .vs(vs), .de(de), .rgb(rgb));

	integer de_n = 0, hs_edges = 0, vs_cy = 0, lit = 0, bar = 0, bad = 0, cy = 0;
	reg hs_d = 0;
	initial begin
		#10 rst_n = 1;
		// Skip the reset/pipeline edge, then measure exactly one frame (2200 * 1125 clocks).
		repeat (4) @(posedge clk);
		repeat (2200 * 1125) begin
			@(posedge clk);
			if (de) de_n = de_n + 1;
			if (hs && !hs_d) hs_edges = hs_edges + 1;
			hs_d = hs;
			if (vs) vs_cy = vs_cy + 1;
			if (de && rgb == 24'hF0F0F0) lit = lit + 1;
			if (de && rgb == 24'hE05A1E) bar = bar + 1;
			if (!de && rgb != 0) bad = bad + 1;
		end
		$display("de=%0d hs_edges=%0d vs_cycles=%0d lit=%0d bar=%0d blank_nonzero=%0d", de_n, hs_edges, vs_cy, lit, bar, bad);
		$finish;
	end
endmodule
