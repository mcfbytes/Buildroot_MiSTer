// SPDX-License-Identifier: GPL-3.0-or-later
// The boot splash: a 1-bit logo bitmap, scaled up and centred, over a dark background.
// One pipeline stage: rgb and the delayed syncs line up with each other.
module de25_splash #(
	parameter LOGO_W = 128,          // bitmap size in source pixels
	parameter LOGO_H = 32,
	parameter SCALE_SH = 3,          // scale = 1 << SCALE_SH (8x -> 1024x256)
	parameter LOGO_HEX = "de25_splash_logo.hex"
) (
	input  wire        clk,
	input  wire        hs_in, vs_in, de_in,
	input  wire [11:0] x,
	input  wire [10:0] y,
	output reg         hs, vs, de,
	output reg  [23:0] rgb
);
	localparam W = LOGO_W << SCALE_SH, H = LOGO_H << SCALE_SH;
	localparam X0 = (1920 - W) / 2, Y0 = (1080 - H) / 2;

	reg [LOGO_W-1:0] rom [0:LOGO_H-1];
	initial $readmemh(LOGO_HEX, rom);

	wire        in_logo = (x >= X0) && (x < X0 + W) && (y >= Y0) && (y < Y0 + H);
	wire [11:0] lx = (x - X0) >> SCALE_SH;
	wire [10:0] ly = (y - Y0) >> SCALE_SH;
	wire [LOGO_W-1:0] row = rom[ly[$clog2(LOGO_H)-1:0]];
	wire        lit = in_logo && row[LOGO_W - 1 - lx[$clog2(LOGO_W)-1:0]];
	// A thin bar under the logo, so a dark-on-dark failure still shows something.
	wire        bar = (y >= Y0 + H + 48) && (y < Y0 + H + 56) && (x >= X0) && (x < X0 + W);

	always @(posedge clk) begin
		hs  <= hs_in; vs <= vs_in; de <= de_in;
		rgb <= !de_in ? 24'h000000 : lit ? 24'hF0F0F0 : bar ? 24'hE05A1E : 24'h101820;
	end
endmodule
