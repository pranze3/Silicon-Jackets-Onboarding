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
    input logic [MEM_WORD_SIZE-1:0] r_data,

  	// Buffer Control (1 = upper, 0, = lower)
    output logic              buffer_control,
  
  	// These go into adder
  	output logic [DATA_W-1:0]       op_a,
    output logic [DATA_W-1:0]       op_b,
  
    input  logic [MEM_WORD_SIZE-1:0]       buff_result
  
); 
	//TODO: Write your controller state machine as you see fit. 
	//HINT: See "6.2 Two Always BLock FSM coding style" from refmaterials/1_fsm_in_systemVerilog.pdf
	// This serves as a good starting point, but you might find it more intuitive to add more than two always blocks.

	//See calculator_pkg.sv for state_t enum definition
  	state_t state, next;

	// registers and pointers
	logic [ADDR_W-1:0] rptr_q, rptr_d; //read point
	logic [ADDR_W-1:0] wptr_q, wptr_d;
	logic bufsel_q, bufsel_d;

	//State reg, other registers as needed
	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			state <= S_IDLE;
			rptr_q <= read_start_addr;
			wptr_q <= write_start_addr;
			bufsel_q <= 1'b0;


		end else begin
			state <= next;
			rptr_q <= rptr_d;
			wptr_q <= wptr_d;
			bufsel_q <= bufsel_d;

		end
	end
	
	//Next state logic, outputs
	always_comb begin

		next = state;
		rptr_d    = rptr_q;
		wptr_d    = wptr_q;
		bufsel_d  = bufsel_q;

		read = 1'b0;
		write = 1'b0;
		r_addr = rptr_q;
		w_addr = wptr_q;
		w_data = buff_result;
		buffer_control = bufsel_q;
		op_a = r_data[31:0];
		op_b = r_data[63:32];

	
		case (state)
			S_IDLE: begin
				rptr_d = read_start_addr;
				wptr_d = write_start_addr;
				bufsel_d = 1'b0;
				next = S_READ;
			end

			S_READ: begin
				read = 1'b1;
				r_addr = rptr_q;
				next = S_ADD;
			end	

			S_ADD: begin

				if (bufsel_q == 1'b0) begin
					bufsel_d = 1'b1; 
					rptr_d = rptr_q + 1;
					next     = S_READ;   // go fetch next pair
				end else begin
					bufsel_d = 1'b0;     // reset back to lower
					next     = S_WRITE;
				end
			end

			S_WRITE: begin
				write = 1'b1;
				w_addr = wptr_q;
				w_data = buff_result;
				wptr_d = wptr_q + 1; //increment write pointer
				rptr_d = rptr_q + 1; //increment read ptr to go to next address pair

				if ((rptr_q >= read_end_addr) || (wptr_q >= write_end_addr)) begin
					next = S_END;
				end else begin 
					next = S_READ;
				end
			end	

			S_END: begin
				next = S_END;
			end

			default: begin
                next = S_IDLE; //start at idle. the deafualt. 
            end
			
		endcase
	end

endmodule
