/*
* Module describing a 32-bit ripple carry adder, with no carry output or input
*/
module adder32 import calculator_pkg::*; (
    input logic [DATA_W - 1 : 0] a_i,
    input logic [DATA_W - 1 : 0] b_i,
    output logic [DATA_W - 1 : 0] sum_o
);

    //array of cin's for adder. needs 33rd bit for last adder
    logic [DATA_W - 1 : 0] carry_array;   

    //TODO: use a generate block to chain together 32 full adders. 
    //generate block for building the large adder out of smaller, full adders
    generate
        //generate zeroth adder so first carry in bit handled separately
        full_adder adder (
            .a(a_i[0]),
            .b(b_i[0]),
            .cin('0),
            .s(sum_o[0]),
            .cout(carry_array[0])
        );

        //generate remaining adders
        for (genvar i = 1; i < 32; i++) begin
            full_adder g_adder (
                .a(a_i[i]),
                .b(b_i[i]),
                .cin(carry_array[i - 1]),
                .s(sum_o[i]),
                .cout(carry_array[i])
            );
        end
    endgenerate
endmodule