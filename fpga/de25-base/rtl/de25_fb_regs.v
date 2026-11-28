// SPDX-License-Identifier: GPL-3.0-or-later
// Framebuffer control registers on the LW bridge (Avalon-MM, 32-bit, fixed read latency 1, no wait).
// Map: docs/de25-base-image.md §6.1. Defaults match MiSTer_fb's own: 640x480 XRGB8888, stride 2560.
module de25_fb_regs (
	input  wire        clk,
	input  wire        rst_n,            // synchronous to clk
	input  wire [3:0]  address,          // word address
	input  wire        read,
	input  wire        write,
	input  wire [3:0]  byteenable,
	input  wire [31:0] writedata,
	output reg  [31:0] readdata,
	output reg         enable,
	output reg  [39:0] base,
	output reg  [11:0] width,
	output reg  [10:0] height,
	output reg  [15:0] stride,
	input  wire        underrun,         // pulse, from the reader
	input  wire        rerror,           // pulse, from the reader
	input  wire        frame,            // pulse, once per frame the reader starts
	input  wire [2:0]  scale,            // the scale in use
	input  wire        init_done,        // the ADV7513 init, same clock
	input  wire        init_nack
);
	localparam [31:0] MAGIC = 32'hDE25_FB5A, VERSION = 32'd2;
	reg        underrun_st, rerror_st;
	reg [15:0] frames;

	// Merge a write into a register under the byte enables.
	function [31:0] merge(input [31:0] old, input [31:0] d, input [3:0] be);
		merge = {be[3] ? d[31:24] : old[31:24], be[2] ? d[23:16] : old[23:16],
		         be[1] ? d[15:8]  : old[15:8],  be[0] ? d[7:0]   : old[7:0]};
	endfunction
	wire [31:0] w_base_lo = merge(base[31:0], writedata, byteenable);
	wire [31:0] w_base_hi = merge({24'd0, base[39:32]}, writedata, byteenable);
	wire [31:0] w_width   = merge({20'd0, width}, writedata, byteenable);
	wire [31:0] w_height  = merge({21'd0, height}, writedata, byteenable);
	wire [31:0] w_stride  = merge({16'd0, stride}, writedata, byteenable);
	wire        clr       = write && address == 4'd9 && byteenable[0];

	always @(posedge clk) begin
		if (!rst_n) begin
			enable <= 1'b0; base <= 40'h00_A000_1000;
			width <= 12'd640; height <= 11'd480; stride <= 16'd2560;
			underrun_st <= 1'b0; rerror_st <= 1'b0; frames <= 16'd0; readdata <= 32'd0;
		end else begin
			if (frame) frames <= frames + 16'd1;
			// A new event wins over a clear in the same cycle (write 1 to clear).
			if (underrun) underrun_st <= 1'b1; else if (clr && writedata[0]) underrun_st <= 1'b0;
			if (rerror)   rerror_st   <= 1'b1; else if (clr && writedata[1]) rerror_st   <= 1'b0;
			if (write) case (address)
				4'd2: if (byteenable[0]) enable <= writedata[0];
				4'd3: base[31:0] <= {w_base_lo[31:8], 8'h00};   // 256-byte aligned
				4'd4: base[39:32] <= w_base_hi[7:0];
				4'd5: width <= w_width[11:0];
				4'd6: height <= w_height[10:0];
				4'd7: stride <= {w_stride[15:8], 8'h00};
				default: ;
			endcase
			if (read) case (address)
				4'd0: readdata <= MAGIC;
				4'd1: readdata <= VERSION;
				4'd2: readdata <= {31'd0, enable};
				4'd3: readdata <= base[31:0];
				4'd4: readdata <= {24'd0, base[39:32]};
				4'd5: readdata <= {20'd0, width};
				4'd6: readdata <= {21'd0, height};
				4'd7: readdata <= {16'd0, stride};
				4'd9: readdata <= {frames, 7'd0, init_nack, init_done, scale, 2'd0, rerror_st, underrun_st};
				default: readdata <= 32'd0;
			endcase
		end
	end
endmodule
