`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// SPI Master
//
// SPI Modes:
//
// Mode     CPOL     CPHA
//  0        0        0
//  1        0        1
//  2        1        0
//  3        1        1
//
// spi_mode[1] = CPOL
// spi_mode[0] = CPHA
//
// CPOL:
// Determines the idle level of SCLK.
//
// CPHA:
// Determines whether data is changed/sampled on the leading
// or trailing edge.
//
// MSB is transmitted first.
//
// CS is active-low:
// CS = 0 -> slave selected
// CS = 1 -> slave not selected
//
//////////////////////////////////////////////////////////////////////////////////

module spi_master #(
    parameter WIDTH = 8
)(
    input  clk,
    input  rst_n,
    input  start,
    input  [WIDTH-1:0] tx_data,
    input  [1:0] spi_mode,
    // Number of FPGA clock cycles per half SPI-clock period
    input  [15:0] clk_div,
    input  miso,
    output reg mosi,
    output reg sclk,
    output reg cs,
    output reg busy,
    output reg done,
    output reg [WIDTH-1:0] rx_data
);
    //====================================================================
    // Internal registers
    //====================================================================

    reg [WIDTH-1:0] tx_shift_reg;
    reg [WIDTH-1:0] rx_shift_reg;

    // Can represent 0 through WIDTH
    reg [$clog2(WIDTH + 1)-1:0] bit_counter;

    // SPI clock divider counter
    reg [15:0] clk_counter;

    // Latch SPI configuration at the beginning of a transaction.
    // This prevents spi_mode or clk_div changing in the middle
    // of a transaction.
    reg [1:0] spi_mode_reg;
    reg [15:0] clk_div_reg;

    //====================================================================
    // FSM states
    //====================================================================

    localparam IDLE        = 3'b000;
    localparam LOAD        = 3'b001;
    localparam ASSERT_CS   = 3'b010;
    localparam TRANSFER    = 3'b011;
    localparam DEASSERT_CS = 3'b100;
    localparam COMPLETE    = 3'b101;

    reg [2:0] state;

    //====================================================================
    // Main FSM
    //====================================================================

    always @(posedge clk) begin

        //----------------------------------------------------------------
        // RESET
        //----------------------------------------------------------------

        if (!rst_n) begin

            state        <= IDLE;

            tx_shift_reg <= {WIDTH{1'b0}};
            rx_shift_reg <= {WIDTH{1'b0}};

            bit_counter  <= 0;
            clk_counter  <= 0;
            
            spi_mode_reg <= 2'b00;
            clk_div_reg  <= 16'd1;

            mosi         <= 1'b0;
            sclk         <= 1'b0;
            cs           <= 1'b1;
            busy         <= 1'b0;
            done         <= 1'b0;

            rx_data      <= {WIDTH{1'b0}};

        end

        //----------------------------------------------------------------
        // NORMAL OPERATION
        //----------------------------------------------------------------

        else begin

            // done is a one-clock pulse.
            // It is asserted only in COMPLETE.
            done <= 1'b0;


            case (state)

                //========================================================
                // IDLE
                //========================================================

                IDLE: begin

                    busy <= 1'b0;
                    cs   <= 1'b1;

                    if (start) begin

                        state <= LOAD;

                    end

                end

                //========================================================
                // LOAD
                //========================================================

                LOAD: begin

                    busy <= 1'b1;
                    
                    // Store the configuration for this transaction.
                    spi_mode_reg <= spi_mode;

                    // Prevent clk_div = 0 from causing underflow.
                    if (clk_div == 0)
                        clk_div_reg <= 16'd1;
                    else
                        clk_div_reg <= clk_div;

                    // Load transmit data.
                    tx_shift_reg <= tx_data;

                    // Clear receive register.
                    rx_shift_reg <= {WIDTH{1'b0}};

                    // No bits received yet.
                    bit_counter <= 0;

                    // Reset clock divider.
                    clk_counter <= 0;

                    // SCLK must start at CPOL.
                    sclk <= spi_mode[1];


                    // CPHA = 0:
                   
                    // First bit must already be present on MOSI before the first leading edge.
            
                    // Therefore put the MSB directly onto MOSI.
                    
                    // Since this bit has already been placed on MOSI, shift it out of the TX register now.
                     
                    if (!spi_mode[0]) begin

                        mosi <= tx_data[WIDTH-1];

                        tx_shift_reg <= tx_data << 1;

                    end

                    // CPHA = 1:
                    // First bit is placed on MOSI at the first
                    // leading edge, so MOSI can start at 0.
                    else begin

                        mosi <= 1'b0;

                    end
                    
                    state <= ASSERT_CS;

                end

                //========================================================
                // ASSERT CS
                //========================================================

                ASSERT_CS: begin
                    // Select slave.
                    cs <= 1'b0;
                    state <= TRANSFER;
                end

                //========================================================
                // TRANSFER
                //========================================================

                TRANSFER: begin
                    //----------------------------------------------------------------
                    // Generate SPI clock
                    //----------------------------------------------------------------
                    if (clk_counter < clk_div_reg - 1) begin

                        clk_counter <= clk_counter + 1'b1;

                    end

                    else begin

                        // Restart divider for next half-period.
                        clk_counter <= 0;

                        //----------------------------------------------------------------
                        // LEADING EDGE
                        // Leading edge occurs when:  current SCLK == CPOL
                        //----------------------------------------------------------------

                        if (sclk == spi_mode_reg[1]) begin
                            //------------------------------------------------------------
                            // CPHA = 1
                            // Data changes on leading edge.
                            //------------------------------------------------------------

                            if (spi_mode_reg[0]) begin

                                // Put next MSB onto MOSI.
                                mosi <= tx_shift_reg[WIDTH-1];

                                // Shift toward next bit.
                                tx_shift_reg <= tx_shift_reg << 1;
                            end
                            //------------------------------------------------------------
                            // CPHA = 0
                            // Data is sampled on leading edge.
                            //------------------------------------------------------------

                            else begin

                                // Sample MISO.
                                rx_shift_reg <=
                                    (rx_shift_reg << 1) | miso;
                                    
                                // Check whether this is the final bit.
                                if (bit_counter == WIDTH - 1) begin
                                    // WIDTH bits have now been received.
                                    bit_counter <= bit_counter + 1'b1;

                                end
                                else begin

                                    bit_counter <= bit_counter + 1'b1;

                                end

                            end

                        end
                        //----------------------------------------------------------------
                        // TRAILING EDGE
                        // Trailing edge occurs when: current SCLK != CPOL
                        //----------------------------------------------------------------

                        else begin
                            //------------------------------------------------------------
                            // CPHA = 0
                            // Data changes on trailing edge.
                            //------------------------------------------------------------

                            if (!spi_mode_reg[0]) begin

                                // Put next bit onto MOSI.
                                mosi <= tx_shift_reg[WIDTH-1];

                                // Shift TX register.
                                tx_shift_reg <= tx_shift_reg << 1;


                                // For CPHA=0, the final bit was sampled on the previous leading edge.
                                // This trailing edge completes the final SPI clock cycle. 
                                if (bit_counter == WIDTH) begin

                                    state <= DEASSERT_CS;

                                end

                            end
                            //------------------------------------------------------------
                            // CPHA = 1
                            // Data is sampled on trailing edge.
                            //------------------------------------------------------------

                            else begin

                                // Sample MISO.
                                rx_shift_reg <=
                                    (rx_shift_reg << 1) | miso;

                                // Final bit
                                if (bit_counter == WIDTH - 1) begin

                                    bit_counter <= bit_counter + 1'b1;

                                    // This is the final sampling edge.
                                    state <= DEASSERT_CS;

                                end

                                else begin

                                    bit_counter <= bit_counter + 1'b1;

                                end

                            end

                        end
                        //----------------------------------------------------------------
                        // Toggle SCLK
                        //----------------------------------------------------------------

                        sclk <= ~sclk;

                    end

                end

                //========================================================
                // DEASSERT CS
                //========================================================

                DEASSERT_CS: begin
                    // Slave no longer selected.
                    cs <= 1'b1;
                    // Return SCLK to its idle polarity.
                    sclk <= spi_mode_reg[1];
                    state <= COMPLETE;
                end

                //========================================================
                // COMPLETE
                //========================================================

                COMPLETE: begin
                    // Transfer received data to output register.
                    rx_data <= rx_shift_reg;
                    // Signal that transaction is complete.
                    done <= 1'b1;
                    // Transaction finished.
                    busy <= 1'b0;
                    state <= IDLE;
                end


                //========================================================
                // DEFAULT
                //========================================================
                default: begin

                    state <= IDLE;

                    tx_shift_reg <= {WIDTH{1'b0}};
                    rx_shift_reg <= {WIDTH{1'b0}};

                    bit_counter <= 0;
                    clk_counter <= 0;

                    mosi <= 1'b0;
                    sclk <= 1'b0;

                    cs <= 1'b1;

                    busy <= 1'b0;
                    done <= 1'b0;

                end

            endcase

        end

    end

endmodule