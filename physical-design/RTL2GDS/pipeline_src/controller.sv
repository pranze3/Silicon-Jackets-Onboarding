module controller import calculator_pkg::*;(
  	input  logic              clk_i,
    input  logic              rst_i,
  
  	// Memory Access
    input  logic [ADDR_W-1:0] read_start_addr,
    input  logic [ADDR_W-1:0] read_end_addr,
    input  logic [ADDR_W-1:0] write_start_addr,
    input  logic [ADDR_W-1:0] write_end_addr,
  
  	// Control
    output logic write,
    output logic [ADDR_W-1:0] w_addr,
    output logic [MEM_WORD_SIZE-1:0] w_data,

    output logic read,
    output logic [ADDR_W-1:0] r_addr,
    input  logic [MEM_WORD_SIZE-1:0] r_data,

  	// Buffer Control (1 = upper, 0, = lower)
    output logic              buffer_control,
  
  	// These go into adder
  	output logic [DATA_W-1:0]       op_a,
    output logic [DATA_W-1:0]       op_b,
  
    input  logic [MEM_WORD_SIZE-1:0]       buff_result
  
); 

    state_t state, next;

	buffer_loc_t buffer_loc;

	logic [ADDR_W-1:0] r_ptr, w_ptr;
  	
	//State reg
	always_ff @(posedge clk_i) begin
		if (rst_i)
			state <= S_IDLE;
		else
			state <= next;
	end
	
	//Next state logic
	always_comb begin
		case (state)
			S_IDLE:  next = S_READ;
			S_READ:  next = S_ADD;
			S_ADD:   next = buffer_loc == UPPER ?  S_WRITE : S_READ;
			S_WRITE: next = (r_ptr > read_end_addr) || (w_ptr > write_end_addr) ? S_END : S_READ;
			S_END: next = S_END;
		endcase
	end

	//Read ptr, write ptr, and buffer loc regs
	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			r_ptr <= read_start_addr;
			w_ptr <= write_start_addr;
			buffer_loc <= LOWER;
		end
		else begin
			case (state)
				S_IDLE: begin
					r_ptr <= r_ptr;
					w_ptr <= w_ptr;
					buffer_loc <= buffer_loc;
				end
				S_READ: begin
					r_ptr <= r_ptr + 1'b1;
					w_ptr <= w_ptr;
					buffer_loc <= buffer_loc;
				end
				S_ADD: begin
					r_ptr <= r_ptr;
					w_ptr <= w_ptr;
					buffer_loc <= buffer_loc == LOWER ? UPPER : LOWER;
				end
				S_WRITE: begin
					r_ptr <= r_ptr;
					w_ptr <= w_ptr + 1'b1;
					buffer_loc <= buffer_loc;
				end
			endcase
		end
	end

	//Combinational outputs
	always_comb begin
		case (state)
			S_IDLE: begin
				write = '0;
				w_addr = '0;
				w_data = '0;
				read = '0;
				r_addr = '0;
				buffer_control = buffer_loc;
				op_a = '0;
				op_b = '0;
			end
			S_READ: begin
				write = '0;
				w_addr = '0;
				w_data = '0;
				read = 1'b1;
				r_addr = r_ptr;
				buffer_control = buffer_loc;
				op_a = r_data[DATA_W-1:0];
				op_b = r_data[MEM_WORD_SIZE-1:DATA_W];
			end
			S_ADD: begin
				write = '0;
				w_addr = '0;
				w_data = '0;
				read = '0;
				r_addr = '0;
				buffer_control = buffer_loc;
				op_a = r_data[DATA_W-1:0];
				op_b = r_data[MEM_WORD_SIZE-1:DATA_W];
			end
			S_WRITE: begin
				write = 1'b1;
				w_addr = w_ptr;
				w_data = buff_result;
				read = '0;
				r_addr = '0;
				buffer_control = buffer_loc;
				op_a = r_data[DATA_W-1:0];
				op_b = r_data[MEM_WORD_SIZE-1:DATA_W];
			end
		endcase
	end

  endmodule