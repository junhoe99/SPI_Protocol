`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/10 13:33:02
// Design Name: 
// Module Name: spi_slave
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


module spi_slave (
    // global signals
    input logic clk,
    input logic reset,
    // SPI Master External signals
    input logic sclk,
    input logic mosi,
    output logic miso,
    input logic cs,
    // Internal Signals(Naming Convention : SI/ SO Phase에 따라 구분)
    /// SI PHASE Signals (MOSI -> si_data)
    output logic [7:0] si_data,  //rx_data
    output logic si_done,  //rx_done
    // SO PHASE Signals (so_data -> MISO)
    input logic [7:0] so_data,  // tx_data( System -> SPI_slave )
    output logic       so_ready,  // so_ready : SPI Slave가 특정 System으로부터 tx_data를 받을 준비가 되었음을 알리는 신호
    input  logic       so_start  // so_start : 특정 System이 SPI_slave로 tx_data를 보내기 시작했음을 알리는 신호
);

    //------------------------------------------------------------------
    // CDC Problem Solving : Synchronizer & Edge Detector
    //------------------------------------------------------------------

    logic sclk_sync0, sclk_sync1;

    /// Synchronizer
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sclk_sync0 <= 1'b0;
            sclk_sync1 <= 1'b0;
        end else begin
            sclk_sync0 <= sclk;
            sclk_sync1 <= sclk_sync0;
        end
    end


    /// Edge Detector (Rising Edge) : 데이터 샘플링 시점을 포착하기 위한 rising edge 검출
    assign sclk_rising_edge  = (sclk_sync0 & ~sclk_sync1);
    /// Edge Detector (Falling Edge) : 전송할 데이터가 바뀌는 시점을 포착하기 위한 falling edge 검출 
    assign sclk_falling_edge = (~sclk_sync0 & sclk_sync1);





    //--------------------------------------------
    // SI PHASE :
    // Rising edge에서 MOSI data를 sampling해서 so_data(rx_data)로 바꾸는 Phase
    //--------------------------------------------
    typedef enum {
        SI_IDLE,
        SI_PHASE
    } si_state_e;

    si_state_e si_state, si_state_next;


    // Internal Registers
    logic [7:0] si_data_reg, si_data_next;
    logic [2:0] si_bit_cnt_reg, si_bit_cnt_next;
    logic si_done_reg, si_done_next;
    // State Register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            si_state <= SI_IDLE;
            si_bit_cnt_reg <= 0;
            si_data_reg    <= 0;
            si_done_reg    <= 0;
        end else begin
            si_state <= si_state_next;
            si_bit_cnt_reg <= si_bit_cnt_next;
            si_data_reg    <= si_data_next;
            si_done_reg    <= si_done_next;
        end
    end

    // Next State Logic & Output Logic
    always_comb begin
        si_done_next    = si_done_reg;
        si_state_next   = si_state;
        si_bit_cnt_next = si_bit_cnt_reg;
        si_data_next    = si_data_reg;

        case (si_state)
            SI_IDLE: begin
                si_done_next = 1'b0;  // rx_done 신호 초기화
                if (!cs) begin
                    si_state_next = SI_PHASE;
                end
            end

            SI_PHASE: begin
                if (!cs) begin
                    if (sclk_rising_edge) begin
                        si_data_next = {si_data_reg[6:0], mosi};  //rx_data 샘플링은 rising edge에서 수행
                        si_bit_cnt_next = si_bit_cnt_reg + 1;
                        if(si_bit_cnt_reg == 7)begin            // 8bit짜리 모든 data를 수신하면 끝 
                            si_bit_cnt_next = 0;
                            si_state_next   = SI_IDLE;
                            si_done_next    = 1'b1;               // MOSI값을 모두 sampling해서 8bit짜리 so_data로 변환했음을 알리는 신호
                        end
                    end
                end else begin
                    si_state_next = SI_IDLE;
                end
            end
        endcase
    end


    assign si_data = si_data_reg;
    assign si_done = si_done_reg;


    //--------------------------------------------
    // SO PHASE :   
    //  특정 System이 SPI_slave로 보낸 tx_data를 MISO로 바꾸는 Phase
    //--------------------------------------------
    typedef enum {
        SO_IDLE,
        SO_PHASE
    } so_state_e;

    so_state_e so_state, so_state_next;


    // Internal Registers
    logic [7:0] so_data_reg, so_data_next;
    logic [2:0] so_bit_cnt_reg, so_bit_cnt_next;

    // State Register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            so_state <= SO_IDLE;
            so_bit_cnt_reg <= 0;
            so_data_reg    <= 0;
        end else begin
            so_state <= so_state_next;
            so_bit_cnt_reg <= so_bit_cnt_next;
            so_data_reg    <= so_data_next;
        end
    end

    // Next State Logic & Output Logic
    always_comb begin
        so_state_next   = so_state;
        so_bit_cnt_next = so_bit_cnt_reg;
        so_data_next    = so_data_reg;
        so_ready        = 1'b0;
        case (so_state)
            SO_IDLE: begin
                so_ready = 1'b1;  // 특정 시스템으로부터 tx_data data를 받을 준비가 되었음을 알리는 신호
                if (!cs) so_ready = 1'b1;
                if (so_start) begin
                    so_state_next = SO_PHASE;
                    so_data_next = so_data;  // tx_data를 so_data_reg에 로드
                    so_bit_cnt_next = 0;
                end
            end

            SO_PHASE: begin
                if (!cs) begin
                    if (sclk_falling_edge)
                        so_data_next = {
                            so_data_reg[6:0], 1'b0
                        };  //MISO 데이터 셋업은 falling edge에서 수행
                    if(si_bit_cnt_reg == 7)begin            // 8bit짜리 모든 data를 수신하면 끝 
                        so_bit_cnt_next = 0;
                        so_state_next = SO_IDLE;
                    end else begin
                        so_bit_cnt_next = so_bit_cnt_reg + 1;
                    end
                end else begin
                    so_state_next = SO_IDLE;
                end
            end
        endcase
    end


    assign miso = (!cs) ? so_data_reg[7] : 1'bz; // MISO는 so_data_reg의 MSB부터 전송
endmodule
