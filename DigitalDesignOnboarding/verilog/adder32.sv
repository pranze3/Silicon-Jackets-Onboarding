/*
* Module describing a 32-bit ripple carry adder, with no carry output or input
*/
module adder32 import calculator_pkg::*; (
    input logic [DATA_W - 1 : 0] a_i,
    input logic [DATA_W - 1 : 0] b_i,
    output logic [DATA_W - 1 : 0] sum_o
);

    //TODO: use a generate block to chain together 32 full adders. 
    // Imagine you are connecting 32 single-bit adder modules together. 
    
    //ignoring final carry
    logic [DATA_W:0] carry;
    assign carry[0] = 1'b0;
    generate

        genvar i;
        for (i = 0; i < DATA_W; i++) begin : GEN_FA
            
            assign {carry[i+1], sum_o[i]} = a_i[i] + b_i[i] + carry[i];
            
        end
        
    endgenerate
endmodule