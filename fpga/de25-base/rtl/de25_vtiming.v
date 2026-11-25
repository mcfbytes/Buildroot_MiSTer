// SPDX-License-Identifier: GPL-3.0-or-later
// CEA-861 1920x1080p60 timing (VIC 16) at a 148.5 MHz pixel clock; positive syncs.
module de25_vtiming (
	input  wire        clk,
	input  wire        rst_n,
	output reg         hs,
	output reg         vs,
	output reg         de,
	output reg  [11:0] x,
	output reg  [10:0] y
);
	localparam H_ACT = 1920, H_FP = 88, H_SYNC = 44, H_BP = 148;
	localparam V_ACT = 1080, V_FP = 4,  V_SYNC = 5,  V_BP = 36;
	localparam H_TOT = H_ACT + H_FP + H_SYNC + H_BP;   // 2200
	localparam V_TOT = V_ACT + V_FP + V_SYNC + V_BP;   // 1125

	reg [11:0] hc;
	reg [10:0] vc;

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			hc <= 0; vc <= 0;
			hs <= 0; vs <= 0; de <= 0; x <= 0; y <= 0;
		end else begin
			if (hc == H_TOT - 1) begin
				hc <= 0;
				vc <= (vc == V_TOT - 1) ? 11'd0 : vc + 11'd1;
			end else begin
				hc <= hc + 12'd1;
			end
			// Registered outputs, one clock behind the counters.
			hs <= (hc >= H_ACT + H_FP) && (hc < H_ACT + H_FP + H_SYNC);
			vs <= (vc >= V_ACT + V_FP) && (vc < V_ACT + V_FP + V_SYNC);
			de <= (hc < H_ACT) && (vc < V_ACT);
			x  <= hc;
			y  <= vc;
		end
	end
endmodule
