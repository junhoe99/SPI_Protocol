`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/10 11:35:07
// Design Name: 
// Module Name: tb_CPOL_CPHA
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


module tb_CPOL_CPHA ();

    // Internal Signals
    logic       clk;
    logic       reset;
    logic       start;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic       tx_ready;
    logic       done;
    logic       cs;
    logic       cpol;
    logic       cpha;
    logic [7:0] so_data;
    logic       so_ready;
    logic       so_start;
    logic       sclk;
    logic       mosi;
    logic       miso;
    logic [7:0] si_data;
    logic       si_done;

    // Clock generation
    always #5 clk = ~clk;

    spi_slave dut (.*);

    spi_master uut (.*);


    task spi_slave_out(byte data);
        @(posedge clk);
        wait (so_ready);
        so_data  = data;
        so_start = 1;
        @(posedge clk);
        so_start = 0;
    endtask

    task spi_mode(bit polarity, bit phase);
        cpol = polarity;
        cpha = phase;
    endtask

    task spi_write(byte data);
        @(posedge clk);
        cs = 1'b0;
        wait (tx_ready);
        start   = 1;
        tx_data = data;
        @(posedge clk);
        start = 0;
        wait (done);
        @(posedge clk);
        cs = 1'b1;
    endtask



    initial begin
        clk = 0;
        reset = 1;
        start = 0;
        tx_data = 8'h00;
        cs = 1;
        cpol = 0;
        cpha = 0;
        so_data = 8'h00;
        so_start = 0;
        #20;
        reset = 0;
        #10;

        repeat (5) @(posedge clk);

        spi_mode(1'b0, 1'b0);  // MODE 0

        fork
            spi_write(8'hf0);
            spi_slave_out(8'h0f);
        join


        #20;
        $finish;
    end

endmodule
