
`timescale 1ns / 1ps

module spi_slave_tb;

    reg clk = 0;
    reg rst_n = 0;
    reg start_tx = 0;
    reg [7:0] tx_data = 0;
    reg [1:0] spi_mode = 0;

    wire [7:0] rx_data;
    wire done;

    reg sclk = 0;
    reg cs = 1;
    reg mosi = 0;
    wire miso;

    integer mode;
    integer i;
    integer passed = 0;
    integer failed = 0;

    reg [7:0] test_byte = 8'b10100110;

    // Instantiate the SPI slave DUT
    spi_slave #(.WIDTH(8)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .tx_data(tx_data),
        .spi_mode(spi_mode),
        .rx_data(rx_data),
        .done(done),
        .sclk(sclk),
        .cs(cs),
        .mosi(mosi),
        .miso(miso)
    );

    // 100 MHz system clock
    always #5 clk = ~clk;

    initial begin
        // Reset
        #20;
        rst_n = 1;
        #20;

        // Test all four SPI modes
        for (mode = 0; mode < 4; mode = mode + 1) begin

            spi_mode = mode;
            sclk = spi_mode[1];
            cs = 1;
            mosi = 0;

            #20;
            cs = 0;
            #10;

            $display("Testing SPI mode %0d", mode);

            // Transmit one byte, MSB first
            for (i = 7; i >= 0; i = i - 1) begin

                if (spi_mode[0] == 0) begin
                    // CPHA = 0: MOSI set before leading edge
                    mosi = test_byte[i];
                    #10;
                    sclk = ~spi_mode[1];
                    #10;
                    sclk = spi_mode[1];
                end
                else begin
                    // CPHA = 1: MOSI set after leading edge
                    sclk = ~spi_mode[1];
                    #10;
                    mosi = test_byte[i];
                    #10;
                    sclk = spi_mode[1];
                end

            end

            // End the SPI transaction
            cs = 1;
            #100;

            // Check received byte
            if (rx_data === test_byte) begin
                $display(
                    "PASS: Mode %0d, RX = %b",
                    mode, rx_data
                );
                passed = passed + 1;
            end
            else begin
                $display(
                    "FAIL: Mode %0d, expected %b, got %b",
                    mode, test_byte, rx_data
                );
                failed = failed + 1;
            end

            #20;
        end

        // Final test summary
        $display("--------------------------------");
        $display("Test Summary");
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        $display("--------------------------------");

        $finish;
    end

    // Simulation timeout
    initial begin
        #10000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
