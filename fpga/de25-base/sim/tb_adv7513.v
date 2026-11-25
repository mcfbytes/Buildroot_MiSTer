// SPDX-License-Identifier: GPL-3.0-or-later
// de25_adv7513_init against an I2C slave model that ACKs address 0x39 and logs each write.
`timescale 1ns/1ps
module tb_adv7513;
	reg clk = 0, rst_n = 0;
	always #1 clk = ~clk;
	wire scl_oe, sda_oe, done, nack;
	reg  slave_ack = 0;
	wire scl = scl_oe ? 1'b0 : 1'b1;
	wire sda = (sda_oe || slave_ack) ? 1'b0 : 1'b1;
	de25_adv7513_init #(.CLK_HZ(1600), .I2C_HZ(100), .WAIT_CY(50)) dut (
		.clk(clk), .rst_n(rst_n), .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_in(sda), .done(done), .nack(nack));

	// Slave: START/STOP detection, MSB-first shift on SCL rise, ACK in the 9th clock.
	reg scl_d = 1, sda_d = 1;
	integer nbit = 0, nbyte = 0, writes = 0, starts = 0, framing = 0;
	reg [7:0] sh = 0, b0 = 0, b1 = 0;
	always @(posedge clk) begin
		if (scl && scl_d && sda_d && !sda) begin nbit = 0; nbyte = 0; starts = starts + 1; end
		if (scl && scl_d && !sda_d && sda) begin
			if (nbyte == 3) writes = writes + 1; else framing = framing + 1;
			if (nbyte == 3 && (writes == 1 || writes == 43)) $display("write %0d: addr=%02h reg=%02h", writes, b0, b1);
		end
		if (scl && !scl_d) begin
			if (nbit < 8) sh = {sh[6:0], sda};
			nbit = nbit + 1;
		end
		if (!scl && scl_d) begin
			if (nbit == 8) begin
				if (nbyte == 0) b0 = sh; else if (nbyte == 1) b1 = sh;
				slave_ack = (nbyte != 0) || (sh == 8'h72);
			end else if (nbit == 9) begin
				slave_ack = 0; nbit = 0; nbyte = nbyte + 1;
			end
		end
		scl_d = scl; sda_d = sda;
	end

	initial begin
		#10 rst_n = 1;
		wait (done);
		repeat (20) @(posedge clk);
		$display("starts=%0d writes=%0d framing_errors=%0d nack=%0d", starts, writes, framing, nack);
		$finish;
	end
	initial begin #20000000 $display("TIMEOUT"); $finish; end
endmodule
