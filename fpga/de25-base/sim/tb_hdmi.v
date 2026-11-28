// SPDX-License-Identifier: GPL-3.0-or-later
// de25_hdmi top level: splash passes through untouched when disabled; framebuffer with black border when enabled.
`timescale 1ps/1ps
module tb_hdmi;
	reg clk = 0, pclk = 0, rst_n = 0;
	always #5000 clk = ~clk;
	always #3367 pclk = ~pclk;
	reg [3:0] addr = 0; reg rd = 0, wr = 0; reg [31:0] wdata = 0; wire [31:0] rdata;
	task wreg(input [3:0] a, input [31:0] d);
		begin @(posedge clk); addr <= a; wdata <= d; wr <= 1; @(posedge clk); wr <= 0; end
	endtask
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


	wire tclk, tde, ths, tvs; wire [23:0] td; wire scl, sda, idone, inack;
	pullup (scl); pullup (sda);
	de25_hdmi #(.CLK_HZ(100_000_000)) dut (.clk(clk), .rst_n(rst_n), .pclk(pclk), .pll_locked(1'b1),
		.s_address(addr), .s_read(rd), .s_write(wr), .s_byteenable(4'hF), .s_writedata(wdata), .s_readdata(rdata),
		.m_araddr(araddr), .m_arlen(arlen), .m_arsize(arsize), .m_arburst(arburst), .m_arid(arid),
		.m_arcache(arcache), .m_arprot(arprot), .m_arvalid(arvalid), .m_arready(arready),
		.m_rdata(rdata_m), .m_rresp(2'b00), .m_rlast(rlast), .m_rvalid(rvalid), .m_rready(rready),
		.HDMI_TX_CLK(tclk), .HDMI_TX_DE(tde), .HDMI_TX_HS(ths), .HDMI_TX_VS(tvs), .HDMI_TX_D(td),
		.HDMI_I2C_SCL(scl), .HDMI_I2C_SDA(sda), .init_done(idone), .init_nack(inack));

	// Reference: an independent timing + splash, delayed to the top level's 4-cycle latency.
	reg [1:0] prst = 0; always @(posedge pclk) prst <= {prst[0], rst_n};
	wire hs0, vs0, de0; wire [11:0] x; wire [10:0] y;
	de25_vtiming rt (.clk(pclk), .rst_n(prst[1]), .hs(hs0), .vs(vs0), .de(de0), .x(x), .y(y));
	wire hs1, vs1, de1; wire [23:0] s1;
	de25_splash rs (.clk(pclk), .hs_in(hs0), .vs_in(vs0), .de_in(de0), .x(x), .y(y), .hs(hs1), .vs(vs1), .de(de1), .rgb(s1));
	reg [26:0] d2, d3, d4; always @(posedge pclk) begin d2 <= {hs1, vs1, de1, s1}; d3 <= d2; d4 <= d3; end
	reg [11:0] xa, xb, xc, xd; reg [10:0] ya, yb, yc, yd;
	always @(posedge pclk) begin xa <= x; xb <= xa; xc <= xb; xd <= xc; ya <= y; yb <= ya; yc <= yb; yd <= yc; end

	integer mode = 0, bad_sync = 0, bad_splash = 0, bad_border = 0, bad_img = 0, nde = 0;
	reg in_img; reg [23:0] want;
	always @(posedge pclk) if (mode != 0) begin
		if ({ths, tvs, tde} !== d4[26:24]) bad_sync = bad_sync + 1;
		if (tde) nde = nde + 1;
		if (mode == 1 && tde && td !== d4[23:0]) bad_splash = bad_splash + 1;
		if (mode == 2 && tde) begin
			in_img = xd >= 320 && xd < 1600 && yd >= 60 && yd < 1020;
			want = pix(40'h00_A000_1000 + ((yd - 60) / 2) * 2560 + ((xd - 320) / 2) * 4);
			if (!in_img && td !== 0) bad_border = bad_border + 1;
			if (in_img && td !== want) bad_img = bad_img + 1;
		end
	end
	task frame_check(input integer m);
		begin
			@(posedge vs0); @(negedge vs0);
			while (!(y == 0 && x == 0 && de0)) @(posedge pclk);
			bad_sync = 0; bad_splash = 0; bad_border = 0; bad_img = 0; nde = 0; mode = m;
			@(posedge vs0); mode = 0;
		end
	endtask
	initial begin
		#20000 @(negedge clk) rst_n = 1;
		frame_check(1);
		$display("splash: de=%0d sync_mismatch=%0d splash_mismatch=%0d", nde, bad_sync, bad_splash);
		wreg(4'd2, 1);                       // reset defaults: 640x480 at 0xA0001000, stride 2560
		@(posedge vs0); @(posedge vs0);
		frame_check(2);
		$display("fb: de=%0d sync_mismatch=%0d border_nonblack=%0d image_mismatch=%0d", nde, bad_sync, bad_border, bad_img);
		$finish;
	end
endmodule
