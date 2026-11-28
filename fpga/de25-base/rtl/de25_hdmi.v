// SPDX-License-Identifier: GPL-3.0-or-later
// DE25-Nano HDMI: 1080p60 out of the ADV7513, showing the framebuffer when enabled, else the splash.
// clk is the system clock of the LW bridge and F2SDRAM ports; pclk is 148.5 MHz.
module de25_hdmi #(
	parameter CLK_HZ = 100_000_000
) (
	input  wire         clk,
	input  wire         rst_n,
	input  wire         pclk,
	// LW bridge slave (Avalon-MM, 32-bit, read latency 1)
	input  wire [3:0]   s_address,
	input  wire         s_read,
	input  wire         s_write,
	input  wire [31:0]  s_writedata,
	output wire [31:0]  s_readdata,
	// F2SDRAM master (AXI4 read only; the write channels are tied off)
	output wire [39:0]  m_araddr,
	output wire [7:0]   m_arlen,
	output wire [2:0]   m_arsize,
	output wire [1:0]   m_arburst,
	output wire [4:0]   m_arid,
	output wire [3:0]   m_arcache,
	output wire [2:0]   m_arprot,
	output wire         m_arvalid,
	input  wire         m_arready,
	input  wire [255:0] m_rdata,
	input  wire         m_rlast,
	input  wire         m_rvalid,
	output wire         m_rready,
	// board pins
	output wire         HDMI_TX_CLK,
	output reg          HDMI_TX_DE,
	output reg          HDMI_TX_HS,
	output reg          HDMI_TX_VS,
	output reg  [23:0]  HDMI_TX_D,
	inout  wire         HDMI_I2C_SCL,
	inout  wire         HDMI_I2C_SDA,
	output wire         init_done,
	output wire         init_nack
);
	reg [1:0] prst = 2'b00;              // rst_n into the pixel domain
	always @(posedge pclk or negedge rst_n) prst <= !rst_n ? 2'b00 : {prst[0], 1'b1};

	wire en, underrun, frame; wire [39:0] base; wire [11:0] w; wire [10:0] h; wire [15:0] stride;
	wire [2:0] scale;
	de25_fb_regs u_regs (.clk(clk), .rst_n(rst_n), .address(s_address), .read(s_read),
		.write(s_write), .writedata(s_writedata), .readdata(s_readdata), .enable(en), .base(base),
		.width(w), .height(h), .stride(stride), .underrun(underrun), .frame(frame), .scale(scale));

	wire hs0, vs0, de0; wire [11:0] x; wire [10:0] y;
	de25_vtiming u_t (.clk(pclk), .rst_n(prst[1]), .hs(hs0), .vs(vs0), .de(de0), .x(x), .y(y));

	// Splash: one stage. Framebuffer: three. Delay the splash two more so both line up.
	wire hs1, vs1, de1; wire [23:0] srgb1;
	de25_splash u_s (.clk(pclk), .hs_in(hs0), .vs_in(vs0), .de_in(de0), .x(x), .y(y),
		.hs(hs1), .vs(vs1), .de(de1), .rgb(srgb1));
	reg hs2, vs2, de2, hs3, vs3, de3; reg [23:0] srgb2, srgb3;
	always @(posedge pclk) begin
		{hs2, vs2, de2, srgb2} <= {hs1, vs1, de1, srgb1};
		{hs3, vs3, de3, srgb3} <= {hs2, vs2, de2, srgb2};
	end

	wire fb_active; wire [23:0] frgb3;
	de25_fb_reader u_f (.clk(clk), .rst_n(rst_n), .cfg_enable(en), .cfg_base(base), .cfg_width(w),
		.cfg_height(h), .cfg_stride(stride), .underrun(underrun), .frame(frame), .scale(scale),
		.m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst),
		.m_arid(m_arid), .m_arcache(m_arcache), .m_arprot(m_arprot), .m_arvalid(m_arvalid),
		.m_arready(m_arready), .m_rdata(m_rdata), .m_rlast(m_rlast), .m_rvalid(m_rvalid),
		.m_rready(m_rready), .pclk(pclk), .prst_n(prst[1]), .hs_in(hs0), .vs_in(vs0),
		.de_in(de0), .x_in(x), .y_in(y), .active(fb_active), .rgb(frgb3));

	// Once enabled, the framebuffer owns the screen; its border is black, not splash.
	reg en_p1, en_p2;
	always @(posedge pclk) begin
		{en_p2, en_p1} <= {en_p1, en};
		HDMI_TX_HS <= hs3; HDMI_TX_VS <= vs3; HDMI_TX_DE <= de3;
		HDMI_TX_D <= !de3 ? 24'd0 : en_p2 ? frgb3 : srgb3;
	end
	// Data changes on the rising edge; the ADV7513 samples on the inverted clock's rising edge.
	assign HDMI_TX_CLK = ~pclk;

	wire scl_oe, sda_oe;
	de25_adv7513_init #(.CLK_HZ(CLK_HZ)) u_i (.clk(clk), .rst_n(rst_n), .scl_oe(scl_oe),
		.sda_oe(sda_oe), .sda_in(HDMI_I2C_SDA), .done(init_done), .nack(init_nack));
	assign HDMI_I2C_SCL = scl_oe ? 1'b0 : 1'bz;
	assign HDMI_I2C_SDA = sda_oe ? 1'b0 : 1'bz;
endmodule
