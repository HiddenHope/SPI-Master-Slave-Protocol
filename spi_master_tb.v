`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.08.2026 15:08:17
// Design Name: 
// Module Name: spi_master_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spi_master_tb;

parameter WIDTH = 8;

reg clk = 0;
reg rst_n;
reg  start;
reg [WIDTH-1:0] tx_data;
reg [1:0] spi_mode;
// Number of FPGA clock cycles per half SPI-clock period
reg [15:0] clk_div;
reg  miso;

reg [WIDTH-1:0] slave_tx_data;
reg [WIDTH-1:0] slave_shift_reg;

wire mosi;
wire sclk;
wire cs;
wire busy;
wire done;
wire [WIDTH-1:0] rx_data;

always #5 clk = ~clk;

spi_master #(.WIDTH(WIDTH)) dut (.clk(clk), .rst_n(rst_n), .start(start), .tx_data(tx_data), .spi_mode(spi_mode), .clk_div(clk_div), .miso(miso), .mosi(mosi), .sclk(sclk), .cs(cs), .busy(busy), .done(done), .rx_data(rx_data));

task test_mode;
    input [1:0] mode;
    input [WIDTH-1:0] tx;
    input [WIDTH-1:0] expected_rx;

    begin

        spi_mode = mode;
        tx_data  = tx;

        @(posedge clk);
        start = 1;

        @(posedge clk);
        start = 0;

        @(posedge done);

        if (rx_data == expected_rx)
            $display("Mode %0d : TX=%h RX=%h EXPECTED=%h PASS",mode, tx_data, rx_data, expected_rx);
        else
            $display("Mode %0d : TX=%h RX=%h EXPECTED=%h FAIL",mode, tx_data, rx_data, expected_rx);

        @(posedge clk); //one more cycle before next case starts

    end
endtask

initial begin
rst_n    = 0;
start    = 0;
tx_data  = 0;
spi_mode = 0;
clk_div  = 4;
miso     = 0;

slave_tx_data = 8'b01100101;
slave_shift_reg = 0;

repeat(5) @(posedge clk);
rst_n = 1;

test_mode(2'b00, 8'hB2, 8'h65);
test_mode(2'b01, 8'hB2, 8'h65);
test_mode(2'b10, 8'hB2, 8'h65);
test_mode(2'b11, 8'hB2, 8'h65);

$finish;
end

always @(negedge cs) begin
    slave_shift_reg <= slave_tx_data;

    if (!spi_mode[0])
        miso <= slave_tx_data[WIDTH-1];
    else
        miso <= 0;
end

always @(posedge sclk or negedge sclk) begin
    if (!cs) begin
        if (spi_mode[0] == (sclk != spi_mode[1])) begin
            if (spi_mode[0])
                miso <= slave_shift_reg[WIDTH-1];
            else
                miso <= slave_shift_reg[WIDTH-2];
        
            slave_shift_reg <= slave_shift_reg << 1;
        end 
    end
end

endmodule

