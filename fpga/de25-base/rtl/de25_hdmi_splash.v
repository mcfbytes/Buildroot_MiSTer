// SPDX-License-Identifier: GPL-3.0-or-later
// HDMI boot splash for the DE25-Nano base image: timing + logo + ADV7513 init.
// pclk is 148.5 MHz from a PLL the base design provides; clk50 is any 50 MHz board clock.
module de25_hdmi_splash (
	input  wire        clk50,
	input  wire        pclk,
	input  wire        rst_n,           // the base design's post-configuration reset
	output wire        HDMI_TX_CLK,
	output wire        HDMI_TX_DE,
	output wire        HDMI_TX_HS,
	output wire        HDMI_TX_VS,
	output wire [23:0] HDMI_TX_D,
	inout  wire        HDMI_I2C_SCL,
	inout  wire        HDMI_I2C_SDA,
	output wire        init_done,
	output wire        init_nack
);
	wire hs0, vs0, de0;
	wire [11:0] x;
	wire [10:0] y;
	reg [1:0] prst = 2'b00;              // rst_n into the pixel domain
	always @(posedge pclk or negedge rst_n) prst <= !rst_n ? 2'b00 : {prst[0], 1'b1};

	de25_vtiming u_t (.clk(pclk), .rst_n(prst[1]), .hs(hs0), .vs(vs0), .de(de0), .x(x), .y(y));
	de25_splash  u_s (.clk(pclk), .hs_in(hs0), .vs_in(vs0), .de_in(de0), .x(x), .y(y),
	                  .hs(HDMI_TX_HS), .vs(HDMI_TX_VS), .de(HDMI_TX_DE), .rgb(HDMI_TX_D));
	// Data changes on the rising edge; the ADV7513 samples on the inverted clock's rising edge.
	assign HDMI_TX_CLK = ~pclk;

	wire scl_oe, sda_oe;
	de25_adv7513_init u_i (.clk(clk50), .rst_n(rst_n), .scl_oe(scl_oe), .sda_oe(sda_oe),
	                       .sda_in(HDMI_I2C_SDA), .done(init_done), .nack(init_nack));
	assign HDMI_I2C_SCL = scl_oe ? 1'b0 : 1'bz;
	assign HDMI_I2C_SDA = sda_oe ? 1'b0 : 1'bz;
endmodule
