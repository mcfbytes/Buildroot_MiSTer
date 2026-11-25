// SPDX-License-Identifier: GPL-3.0-or-later
// Programs the ADV7513 over its FPGA-side I2C once after reset: 1080p60 RGB 4:4:4 in, HDMI out.
// The table follows Main_MiSTer's video.cpp init (public, GPL-3.0); I2C address 0x39 (0x72 write).
module de25_adv7513_init #(
	parameter CLK_HZ  = 50_000_000,
	parameter I2C_HZ  = 100_000,
	parameter WAIT_CY = CLK_HZ / 5      // 200 ms for the ADV7513 to come out of power-on
) (
	input  wire clk,
	input  wire rst_n,
	output reg  scl_oe,                 // 1 = pull SCL low (open drain)
	output reg  sda_oe,                 // 1 = pull SDA low
	input  wire sda_in,
	output reg  done,
	output reg  nack                    // sticky: some byte was not acknowledged
);
	localparam QDIV = CLK_HZ / (I2C_HZ * 4);
	localparam N = 43;

	function [15:0] entry(input [5:0] i);
		case (i)
			0: entry = 16'h98_03;  1: entry = 16'hD6_C0;  2: entry = 16'h41_10;  3: entry = 16'h9A_70;
			4: entry = 16'h9C_30;  5: entry = 16'h9D_61;  6: entry = 16'hA2_A4;  7: entry = 16'hA3_A4;
			8: entry = 16'hE0_D0;  9: entry = 16'h15_20; 10: entry = 16'h16_38; 11: entry = 16'h17_02;
			12: entry = 16'h3B_80; 13: entry = 16'h3C_00; 14: entry = 16'h48_08; 15: entry = 16'h49_A8;
			16: entry = 16'h40_00; 17: entry = 16'h4A_80; 18: entry = 16'h4C_00; 19: entry = 16'h55_10;
			20: entry = 16'h56_08; 21: entry = 16'h57_08; 22: entry = 16'h59_00; 23: entry = 16'h73_01;
			24: entry = 16'h96_FF; 25: entry = 16'h99_02; 26: entry = 16'h9B_18; 27: entry = 16'h9F_00;
			28: entry = 16'hA1_00; 29: entry = 16'hA4_08; 30: entry = 16'hA5_04; 31: entry = 16'hA6_00;
			32: entry = 16'hA7_00; 33: entry = 16'hA8_00; 34: entry = 16'hA9_00; 35: entry = 16'hAA_00;
			36: entry = 16'hAB_40; 37: entry = 16'hB9_00; 38: entry = 16'hBA_60; 39: entry = 16'hBB_00;
			40: entry = 16'hDE_9C; 41: entry = 16'hE4_60; 42: entry = 16'hAF_06;
			default: entry = 16'h00_00;
		endcase
	endfunction

	localparam S_WAIT = 0, S_START = 1, S_BIT = 2, S_STOP = 3, S_GAP = 4, S_DONE = 5;
	reg [2:0]  st;
	reg [31:0] cnt;                     // wait counter, then quarter-period divider
	reg [1:0]  q;                       // quarter of the current SCL period
	reg [5:0]  idx;                     // table entry
	reg [1:0]  byte_n;                  // 0 = address, 1 = register, 2 = value
	reg [3:0]  bit_n;                   // 7..0 data, 8 = ACK slot
	wire [15:0] e = entry(idx);
	wire [7:0] cur = byte_n == 0 ? 8'h72 : byte_n == 1 ? e[15:8] : e[7:0];

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			st <= S_WAIT; cnt <= 0; q <= 0; idx <= 0; byte_n <= 0; bit_n <= 0;
			scl_oe <= 0; sda_oe <= 0; done <= 0; nack <= 0;
		end else if (st == S_WAIT) begin
			if (cnt == WAIT_CY) begin cnt <= 0; st <= S_START; q <= 0; end
			else cnt <= cnt + 1;
		end else if (st == S_DONE) begin
			done <= 1;
		end else if (cnt != QDIV - 1) begin
			cnt <= cnt + 1;
		end else begin
			cnt <= 0;
			q <= q + 2'd1;
			case (st)
				S_START: case (q)       // SDA falls while SCL is high
					0: begin scl_oe <= 0; sda_oe <= 0; end
					1: sda_oe <= 1;
					2: scl_oe <= 1;
					3: begin st <= S_BIT; byte_n <= 0; bit_n <= 4'd7; end
				endcase
				S_BIT: case (q)         // change SDA with SCL low, sample with SCL high
					0: sda_oe <= (bit_n == 8) ? 1'b0 : ~cur[bit_n[2:0]];
					1: scl_oe <= 0;
					2: if (bit_n == 8 && sda_in) nack <= 1;
					3: begin
						scl_oe <= 1;
						if (bit_n == 0) bit_n <= 4'd8;
						else if (bit_n == 8) begin
							if (byte_n == 2) st <= S_STOP;
							else begin byte_n <= byte_n + 2'd1; bit_n <= 4'd7; end
						end else bit_n <= bit_n - 4'd1;
					end
				endcase
				S_STOP: case (q)        // SDA rises while SCL is high
					0: sda_oe <= 1;
					1: scl_oe <= 0;
					2: sda_oe <= 0;
					3: st <= S_GAP;
				endcase
				S_GAP: if (q == 3) begin
					if (idx == N - 1) st <= S_DONE;
					else begin idx <= idx + 6'd1; st <= S_START; end
				end
				default: ;
			endcase
		end
	end
endmodule
