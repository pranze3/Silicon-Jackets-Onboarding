/*
* Module describing a 64-bit result buffer and the mux for controlling where
* in the buffer an adder's result is placed.
* 
* synchronous active high reset on posedge clk
*/
module result_buffer import calculator_pkg::*; (
    input logic clk_i,                              //clock signal
    input logic rst_i,                              //reset signal

    input logic [DATA_W-1 : 0] result_i,       //result from ALU
    input logic loc_sel,                            //mux control signal
    output logic [MEM_WORD_SIZE-1 : 0] buffer_o   //64-bit output of buffer
);

    //declare 64-bit buffer
    logic [MEM_WORD_SIZE-1 : 0] internal_buffer;

    //send data from buffer to module output
    assign buffer_o = internal_buffer;

    //TODO: Write a sequential block to write the next values into the buffer. Also implement a synchronous reset that clears the buffer.
    //write data into buffer
    always_ff @(posedge clk_i) begin
        if (rst_i) begin            //active high reset on posedge
            internal_buffer <= '0;  //zero out on reset
        end else begin
            //assign data to buffer
            if (loc_sel)
                internal_buffer[MEM_WORD_SIZE-1:DATA_W] <= result_i;
            else
                internal_buffer[DATA_W-1:0] <= result_i;
        end
    end
endmodule