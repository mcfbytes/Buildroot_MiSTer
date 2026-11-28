// SPDX-License-Identifier: GPL-3.0-or-later
// Framebuffer control registers on the LW bridge (Avalon-MM, 32-bit, read latency 1).
// Map: docs/de25-base-image.md §6. Defaults match MiSTer_fb's own: 640x480 XRGB8888, stride 2560.
module de25_fb_regs (
	input  wire        clk,
	input  wire        rst_n,
	input  wire [3:0]  address,          // word address
	input  wire        read,
	input  wire        write,
	input  wire [31:0] writedata,
	output reg  [31:0] readdata,
	output reg         enable,
	output reg  [39:0] base,
	output reg  [11:0] width,
	output reg  [10:0] height,
	output reg  [15:0] stride,
	input  wire        underrun,         // pulse, from the reader
	input  wire        frame,            // pulse, once per frame the reader starts
	input  wire [2:0]  scale             // the scale in use
);
	localparam [31:0] MAGIC = 32'hDE25_FB5A, VERSION = 32'd1;
	reg        underrun_st;
	reg [15:0] frames;

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			enable <= 1'b0; base <= 40'h00_A000_1000;
			width <= 12'd640; height <= 11'd480; stride <= 16'd2560;
			underrun_st <= 1'b0; frames <= 16'd0; readdata <= 32'd0;
		end else begin
			if (underrun) underrun_st <= 1'b1;
			if (frame) frames <= frames + 16'd1;
			if (write) case (address)
				4'd2: enable <= writedata[0];
				4'd3: base[31:0] <= {writedata[31:8], 8'h00};   // 256-byte aligned
				4'd4: base[39:32] <= writedata[7:0];
				4'd5: width <= writedata[11:0];
				4'd6: height <= writedata[10:0];
				4'd7: stride <= {writedata[15:8], 8'h00};
				4'd9: if (writedata[0]) underrun_st <= 1'b0;  // write 1 to clear
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
				4'd9: readdata <= {frames, 9'd0, scale, 3'd0, underrun_st};
				default: readdata <= 32'd0;
			endcase
		end
	end
endmodule
