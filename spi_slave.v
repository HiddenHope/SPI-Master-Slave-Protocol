
`timescale 1ns / 1ps

module spi_slave #(parameter WIDTH = 8)
(
    input clk,
    input rst_n,
    input start_tx,
    input [WIDTH-1:0] tx_data,
    input [1:0] spi_mode,

    output reg [WIDTH-1:0] rx_data,
    output reg done,

    input sclk,
    input cs,             // Active low
    input mosi,
    output wire miso
);

localparam COUNT_W = (WIDTH < 2) ? 1 : $clog2(WIDTH + 1);

// SPI mode

wire cpol = spi_mode[1];
wire cpha = spi_mode[0];

// Rising edge of sample_clk is the sampling edge.
wire sample_clk = (cpol ^ cpha) ? ~sclk : sclk;

// RX: SPI clock domain

reg [WIDTH-1:0] rx_shift_reg;
reg [WIDTH-1:0] rx_byte_spi;
reg [COUNT_W-1:0] rx_count;

// Toggle changes each time a byte is received.
reg rx_toggle_spi;

// TX: main clock domain

reg [WIDTH-1:0] tx_mailbox;
reg tx_busy;

// Request and acknowledgement use toggle handshakes.
reg tx_req_toggle;
reg tx_ack_toggle_spi;

reg tx_req_sync1;
reg tx_req_sync2;
reg tx_req_seen;

reg tx_ack_sync1;
reg tx_ack_sync2;
reg tx_ack_seen;

// RX event synchronization
reg rx_sync1;
reg rx_sync2;
reg rx_seen;

// TX transfer in SPI domain
reg [WIDTH-1:0] tx_byte_spi;
reg [COUNT_W-1:0] tx_count;
reg tx_active_spi;
reg tx_ack_toggle;

// MISO bit selection
reg miso_reg;
assign miso = (!cs) ? miso_reg : 1'bz;

// RX capture
always @(posedge sample_clk or posedge cs or negedge rst_n) begin
    if (!rst_n) begin
        rx_shift_reg <= 0;
        rx_byte_spi  <= 0;
        rx_count     <= 0;
        rx_toggle_spi <= 0;
    end
    else if (cs) begin
        rx_shift_reg <= 0;
        rx_count <= 0;
    end
    else begin
        rx_shift_reg <= (rx_shift_reg << 1) | mosi;

        if (rx_count == WIDTH-1) begin
            rx_byte_spi <= (rx_shift_reg << 1) | mosi;
            rx_shift_reg <= 0;
            rx_count <= 0;
            rx_toggle_spi <= ~rx_toggle_spi;
        end
        else begin
            rx_count <= rx_count + 1'b1;
        end
    end
end


// TX: prepare first bit and shift on SPI edges

// For CPHA=0, preload the first bit before the first sampling edge. For CPHA=1, load the byte when the synchronized request is detected; subsequent timing must be verified against the master's edge sequence.

always @(posedge sample_clk or posedge cs or negedge rst_n) begin
    if (!rst_n) begin
        tx_req_sync1 <= 0;
        tx_req_sync2 <= 0;
        tx_req_seen <= 0;

        tx_ack_toggle <= 0;
        tx_byte_spi <= 0;
        tx_count <= 0;
        tx_active_spi <= 0;
        miso_reg <= 0;
    end
    else if (cs) begin
        tx_count <= 0;
        tx_active_spi <= 0;
        miso_reg <= 0;
    end
    else begin
        tx_req_sync1 <= tx_req_toggle;
        tx_req_sync2 <= tx_req_sync1;

        if (tx_req_sync2 != tx_req_seen) begin
            tx_req_seen <= tx_req_sync2;
            tx_byte_spi <= tx_mailbox;
            tx_count <= 0;
            tx_active_spi <= 1'b1;
            miso_reg <= tx_mailbox[WIDTH-1];
            tx_ack_toggle <= ~tx_ack_toggle;
        end
        else if (tx_active_spi) begin
            if (tx_count < WIDTH-1) begin
                tx_count <= tx_count + 1'b1;
                miso_reg <= tx_byte_spi[WIDTH-1-(tx_count+1'b1)];
            end
            else begin
                tx_active_spi <= 1'b0;
                miso_reg <= 1'b0;
            end
        end
    end
end

// Main clock domain

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_sync1 <= 0;
        rx_sync2 <= 0;
        rx_seen <= 0;

        tx_ack_sync1 <= 0;
        tx_ack_sync2 <= 0;
        tx_ack_seen <= 0;

        tx_req_toggle <= 0;
        tx_mailbox <= 0;
        tx_busy <= 0;

        rx_data <= 0;
        done <= 0;
    end
    else begin
        // Synchronize received-byte event.
        rx_sync1 <= rx_toggle_spi;
        rx_sync2 <= rx_sync1;

        // Synchronize TX acknowledgement.
        tx_ack_sync1 <= tx_ack_toggle;
        tx_ack_sync2 <= tx_ack_sync1;

        done <= 1'b0;
        if (rx_sync2 != rx_seen) begin
            rx_seen <= rx_sync2;
            rx_data <= rx_byte_spi;
            done <= 1'b1;
        end
        // Accept a TX request and hold the byte stable.
        if (start_tx && !tx_busy) begin
            tx_mailbox <= tx_data;
            tx_req_toggle <= ~tx_req_toggle;
            tx_busy <= 1'b1;
        end
        // This acknowledgement means the SPI side has accepted the byte.
        if (tx_ack_sync2 != tx_ack_seen) begin
            tx_ack_seen <= tx_ack_sync2;
            tx_busy <= 1'b0;
        end
    end
end

endmodule
