/* 
 * This top_level module integrates the controller, memory, adder, and result buffer to form a complete calculator system.
 * It handles memory reads/writes, arithmetic operations, and result buffering.
 */
module top_lvl import calculator_pkg::*; (
    input  logic                 clk,
    input  logic                 rst,

    // Memory Config
    input  logic [ADDR_W-1:0]    read_start_addr,
    input  logic [ADDR_W-1:0]    read_end_addr,
    input  logic [ADDR_W-1:0]    write_start_addr,
    input  logic [ADDR_W-1:0]    write_end_addr
    
);

    // Controller wires
    logic              write, read;
	logic [ADDR_W-1:0] r_addr, w_addr;
    logic [MEM_WORD_SIZE-1:0] r_data, w_data;
    logic [31:0]       op_a,   op_b;
    logic              buffer_control;

    // Result buffer wires
    logic [MEM_WORD_SIZE-1:0] buffer_word;   // 64-bit output of buffer
    logic                     loc_sel;       // 1 upper
    assign loc_sel = buffer_control;   

   
	controller u_ctrl (
        .clk_i              (clk),
        .rst_i              (rst),
        .read_start_addr    (read_start_addr ),
        .read_end_addr      (read_end_addr   ),
        .write_start_addr   (write_start_addr),
        .write_end_addr     (write_end_addr  ),
        .write              (write),
        .w_addr             (w_addr),
        .w_data             (w_data),
        .read               (read),
        .r_addr             (r_addr),
        .r_data             (r_data),
        .buffer_control     (buffer_control),
        .op_a               (op_a),
        .op_b               (op_b),
        .buff_result        (buffer_word)
    );

    // Memory Insntantiation
    wire [31:0] w_data_A = w_data[31:0];
    wire [31:0] w_data_B = w_data[63:32];
    wire [31:0] r_data_A, r_data_B;
    assign r_data = {r_data_A, r_data_B};

    //TODO: Look at the sky130_sram_2kbyte_1rw1r_32x512_8 module and instantiate it using variables defined above.
    // Note: This module has two ports, port 0 for read and write and port 1 for read only. We are not using port 1 in this design.    
  	/*
     * .clk0 : sram macro clock input
     * .csb0 : chip select, active low. Refer to sky130_sram instantiation to see what value to use for both read and write operations in port 0. 
     * .web0 : write enable, active low. Refer to sky130_sram instantiation to see what value to use for both read and write operations in port 0.
     * .wmask0 : write mask, used to select which bits to write. For this design, we will write all bits, so use 4'hF.
     * .addr0 : address to read/write
     * .din0 : data to write
     * .dout0 : data read from memory
     */
  	sky130_sram_2kbyte_1rw1r_32x512_8 sram_A (
        .clk0   (clk),  
        .csb0   (~write),
        .web0   (~write), 
        .wmask0 (4'hF), 
        .addr0  (w_addr), 
        .din0   (w_data_A),
        .dout0  (), 
        .clk1   (clk), 
        .csb1   (~read), 
        .addr1  (r_addr), 
        .dout1  (r_data_A) 
    );
    //TODO: Instantiate the second SRAM for the lower half of the memory.
    sky130_sram_2kbyte_1rw1r_32x512_8 sram_B (
        .clk0   (clk),  
        .csb0   (~write),
        .web0   (~write), 
        .wmask0 (4'hF), 
        .addr0  (w_addr), 
        .din0   (w_data_B),
        .dout0  (), 
        .clk1   (clk), 
        .csb1   (~read), 
        .addr1  (r_addr), 
        .dout1  (r_data_B) 
    );
  	
  	// adder
    logic [31:0] sum32;
    adder32 u_adder (
        .a_i    (op_a),
        .b_i    (op_b),
        .sum_o  (sum32)
    );
 
    result_buffer u_resbuf (
        .clk_i    (clk),
        .rst_i    (rst),
        .result_i (sum32),              // 32-bit adder result
        .loc_sel  (loc_sel),
        .buffer_o (buffer_word)
    );
endmodule
