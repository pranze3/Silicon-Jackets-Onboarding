module calc_tb_top;

  import calc_tb_pkg::*;
  import calculator_pkg::*;

  parameter int DataSize = DATA_W;
  parameter int AddrSize = ADDR_W;
  typedef calc_tb_pkg::calc_seq_item#(DataSize, AddrSize) seq_item_t;

  logic clk = 0;
  logic rst;
  state_t state;
  logic [DataSize-1:0] rd_data;
  logic reset_test_active;

  calc_if #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_if(.clk(clk));
  top_lvl my_calc(
    .clk(clk),
    .rst(calc_if.reset),
    `ifdef VCS
    .read_start_addr(calc_if.read_start_addr),
    .read_end_addr(calc_if.read_end_addr),
    .write_start_addr(calc_if.write_start_addr),
    .write_end_addr(calc_if.write_end_addr)
    `endif
    `ifdef CADENCE
    .read_start_addr(calc_if.calc.read_start_addr),
    .read_end_addr(calc_if.calc.read_end_addr),
    .write_start_addr(calc_if.calc.write_start_addr),
    .write_end_addr(calc_if.calc.write_end_addr)
    `endif
  );

  assign rst = calc_if.reset;
  assign state = my_calc.u_ctrl.state;
  `ifdef VCS
  assign calc_if.wr_en = my_calc.write;
  assign calc_if.rd_en = my_calc.read;
  assign calc_if.wr_data = my_calc.w_data;
  assign calc_if.rd_data = my_calc.r_data;
  assign calc_if.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.curr_rd_addr = my_calc.r_addr;
  assign calc_if.curr_wr_addr = my_calc.w_addr;
  assign calc_if.loc_sel = my_calc.loc_sel;
  `endif
  `ifdef CADENCE
  assign calc_if.calc.wr_en = my_calc.write;
  assign calc_if.calc.rd_en = my_calc.read;
  assign calc_if.calc.wr_data = my_calc.w_data;
  assign calc_if.calc.rd_data = my_calc.r_data;
  assign calc_if.calc.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.calc.curr_rd_addr = my_calc.r_addr;
  assign calc_if.calc.curr_wr_addr = my_calc.w_addr;
  assign calc_if.calc.loc_sel = my_calc.loc_sel;
  `endif

  calc_tb_pkg::calc_driver #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_driver_h;
  calc_tb_pkg::calc_sequencer #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_sequencer_h;
  calc_tb_pkg::calc_monitor #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_monitor_h;
  calc_tb_pkg::calc_sb #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_sb_h;

  always #5 clk = ~clk;

  task write_sram(input [AddrSize-1:0] addr, input [DataSize-1:0] data, input logic block_sel);
    @(posedge clk);
    if (!block_sel) begin
      my_calc.sram_A.mem[addr] = data;
    end
    else begin
      my_calc.sram_B.mem[addr] = data;
    end
    calc_driver_h.initialize_sram(addr, data, block_sel);
  endtask

  initial begin
    `ifdef VCS
    $fsdbDumpon;
    $fsdbDumpfile("simulation.fsdb");
    $fsdbDumpvars(0, calc_tb_top, "+mda", "+all", "+trace_process");
    $fsdbDumpMDA;
    `endif
    `ifdef CADENCE
    $shm_open("waves.shm");
    $shm_probe("AC");
    `endif

    calc_monitor_h = new(calc_if);
    calc_sb_h = new(calc_monitor_h.mon_box);
    calc_sequencer_h = new();
    calc_driver_h = new(calc_if, calc_sequencer_h.calc_box);
    fork
      calc_monitor_h.main();
      calc_sb_h.main();
    join_none
    calc_if.reset <= 1;
    for (int i = 0; i < 2 ** AddrSize; i++) begin
      write_sram(i, $random, 0);
      write_sram(i, $random, 1);
    end

    //Explicit SRAM addresses for zero input cases (not just x)
    $display("Setting up zero input test cases at explicit addresses");
    write_sram(8'd100, 32'h00000000, 0); // SRAM_A[100] = 0
    write_sram(8'd100, 32'h00000000, 1); // SRAM_B[100] = 0
    write_sram(8'd101, 32'h00000000, 0); // SRAM_A[101] = 0
    write_sram(8'd101, 32'h00000000, 1); // SRAM_B[101] = 0

    repeat (100) @(posedge clk);

    // Directed part
    $display("Directed Testing");
    
    // Test case 1 - normal addition
    $display("Test case 1 - normal addition");
    begin
      logic [31:0] a1 = 32'h12345678;
      logic [31:0] b1 = 32'h87654321;
      logic [31:0] a2, b2;
      logic [31:0] exp_lo, exp_hi;
      logic [31:0] got_lo, got_hi;
      
      write_sram(5, a1, 0);
      write_sram(5, b1, 1);
      
      a2 = my_calc.sram_A.mem[6];
      b2 = my_calc.sram_B.mem[6];
      exp_lo = a1 + b1;
      exp_hi = a2 + b2;
      
      calc_driver_h.start_calc(5, 6, 15, 15);
      @(calc_if.cb iff calc_if.cb.ready);
      
      got_lo = my_calc.sram_A.mem[15];
      got_hi = my_calc.sram_B.mem[15];
      
      if (got_lo == exp_lo && got_hi == exp_hi) begin
        $display("NORMAL ADDITION PASS");
      end else begin
        $error("  FAIL: exp[0x%h,0x%h] got[0x%h,0x%h]", exp_hi, exp_lo, got_hi, got_lo);
      end
    end

    // Test case 2 - addition with overflow
    $display("Test case 2 - addition with overflow");
    begin
      logic [31:0] a1 = 32'hFFFFFFFF;
      logic [31:0] b1 = 32'h00000001;
      logic [31:0] a2, b2;
      logic [31:0] exp_lo, exp_hi;
      logic [31:0] got_lo, got_hi;
      
      write_sram(10, a1, 0);
      write_sram(10, b1, 1);
      
      a2 = my_calc.sram_A.mem[11];
      b2 = my_calc.sram_B.mem[11];
      exp_lo = a1 + b1;
      exp_hi = a2 + b2;
      
      calc_driver_h.start_calc(10, 11, 20, 20);
      @(calc_if.cb iff calc_if.cb.ready);
      
      got_lo = my_calc.sram_A.mem[20];
      got_hi = my_calc.sram_B.mem[20];
      
      if (got_lo == exp_lo && got_hi == exp_hi) begin
        $display("ADDITION WITH OVERFLOW PASS");
      end else begin
        $error("  FAIL: exp[0x%h,0x%h] got[0x%h,0x%h]", exp_hi, exp_lo, got_hi, got_lo);
      end
    end

    // Test case 3 - zero input case with explicit addresses
    $display("Test case 3 - zero inputs at explicit addresses 100,101");
    begin
      logic [31:0] exp_lo, exp_hi;
      logic [31:0] got_lo, got_hi;
      
      calc_driver_h.start_calc(100, 101, 200, 200);
      @(calc_if.cb iff calc_if.cb.ready);
      
      exp_lo = 32'h00000000 + 32'h00000000; // 0
      exp_hi = 32'h00000000 + 32'h00000000; // 0
      got_lo = my_calc.sram_A.mem[200];
      got_hi = my_calc.sram_B.mem[200];
      
      if (got_lo == exp_lo && got_hi == exp_hi) begin
        $display("ZERO INPUT PASS");
      end else begin
        $error("ZERO INPUT FAIL: exp[0x%h,0x%h] got[0x%h,0x%h]", exp_hi, exp_lo, got_hi, got_lo);
      end
    end

    // Test case 4 - multiple operations
    $display("Test case 4 - multiple operations");
    begin
      logic [31:0] exp_lo, exp_hi;
      logic [31:0] got_lo, got_hi;
      
      write_sram(50, 32'h11111111, 0);
      write_sram(50, 32'h22222222, 1);
      write_sram(51, 32'h33333333, 0);
      write_sram(51, 32'h44444444, 1);
      write_sram(52, 32'h55555555, 0);
      write_sram(52, 32'h66666666, 1);
      write_sram(53, 32'h77777777, 0);
      write_sram(53, 32'h88888888, 1);
      
      calc_driver_h.start_calc(50, 53, 100, 101);
      @(calc_if.cb iff calc_if.cb.ready);
      
      exp_lo = 32'h11111111 + 32'h22222222;
      exp_hi = 32'h33333333 + 32'h44444444;
      got_lo = my_calc.sram_A.mem[100];
      got_hi = my_calc.sram_B.mem[100];
      
      if (got_lo == exp_lo && got_hi == exp_hi) begin
        $display("MULTIPLE OPS PASS");
      end else begin
        $error("MULTIPLE FAIL: exp[0x%h,0x%h] got[0x%h,0x%h]", exp_hi, exp_lo, got_hi, got_lo);
      end
    end

    // ===================================================
// Test case 5 - Reset during S_READ state
// ===================================================
$display("Test case 5 - reset during READ state");
begin
  write_sram(170, 32'h11111111, 0);
  write_sram(170, 32'h22222222, 1);

  fork
    begin
      calc_driver_h.start_calc(170, 171, 250, 250);
      @(calc_if.cb iff calc_if.cb.ready);
    end
    begin
      wait (state == S_READ);
      calc_sb_h.handle_reset();
      calc_if.reset <= 1;
      @(posedge clk);
      calc_if.reset <= 0;
    end
  join_any
  disable fork;

  @(posedge clk);
  if (state == S_IDLE) $display("READ TO IDLE RESET PASS");
  else $error("READ TO IDLE RESET FAIL, state=%s", state.name());
end


// ===================================================
// Test case 6 - Reset during S_ADD state
// ===================================================
$display("Test case 6 - reset during ADD state");
reset_test_active = 1;
begin
  write_sram(180, 32'h33333333, 0);
  write_sram(180, 32'h44444444, 1);

  fork
    begin
      calc_driver_h.start_calc(180, 181, 260, 260);
      @(calc_if.cb iff calc_if.cb.ready);
    end
    begin
      wait (state == S_ADD);
      calc_sb_h.handle_reset();
      calc_if.reset <= 1;
      @(posedge clk);
      calc_if.reset <= 0;
    end
  join_any
  disable fork;

  @(posedge clk);
  if (state == S_IDLE) $display("ADD TO IDLE RESET PASS");
  else $error("ADD TO IDLE RESET FAIL, state=%s", state.name());
end
reset_test_active = 0;

// ===================================================
// Test case 7 - Reset during S_WRITE state
// ===================================================
$display("Test case 7 - reset during WRITE state");
reset_test_active = 1;
begin
  write_sram(190, 32'h55555555, 0);
  write_sram(190, 32'h66666666, 1);

  fork
    begin
      calc_driver_h.start_calc(190, 191, 270, 270);
      @(calc_if.cb iff calc_if.cb.ready);
    end
    begin
      wait (state == S_WRITE);
      calc_sb_h.handle_reset();
      calc_if.reset <= 1;
      @(posedge clk);
      calc_if.reset <= 0;
    end
  join_any
  disable fork;

  @(posedge clk);
  if (state == S_IDLE) $display("WRITE TO IDLE RESET PASS");
  else $error("WRITE TO IDLE RESET FAIL, state=%s", state.name());
end
reset_test_active = 0;


    // Test case 8 - Conditional coverage: write completes before read
    $display("Test case 8 - write pointer hits end first (conditional coverage)");
    begin
      write_sram(70, 32'h10203040, 0);
      write_sram(70, 32'h50607080, 1);
      write_sram(71, 32'h11223344, 0); 
      write_sram(71, 32'h55667788, 1);
      write_sram(72, 32'h12345678, 0);
      write_sram(72, 32'h9ABCDEF0, 1);
      write_sram(73, 32'hAAAABBBB, 0);
      write_sram(73, 32'hCCCCDDDD, 1);
      
      // 4 read addresses (70-73) but only 1 write address (90-90)
      // This hits: rptr_q < read_end_addr (0) AND wptr_q >= write_end_addr (1)
      calc_driver_h.start_calc(70, 73, 90, 90);
      @(calc_if.cb iff calc_if.cb.ready);
      
      $display("WRITE END FIRST CONDITIONAL COVERAGE COMPLETE");
    end

    // Random part
    $display("Randomized Testing");
    for (int test_num = 0; test_num < 10; test_num++) begin
      seq_item_t random_seq;
      random_seq = new();
      
      if (!random_seq.randomize()) begin
        $error("Failed to randomize sequence item for test %0d", test_num);
        continue;
      end
      
      $display("Random Test %0d: R[0x%0h:0x%0h] W[0x%0h:0x%0h]", 
               test_num + 1, 
               random_seq.read_start_addr, random_seq.read_end_addr,
               random_seq.write_start_addr, random_seq.write_end_addr);
      
      calc_sequencer_h.calc_box.put(random_seq);
      calc_driver_h.drive();
      @(calc_if.cb iff calc_if.cb.ready);
      
      $display("Random Test %0d: PASS", test_num + 1);
    end

    repeat (100) @(posedge clk);

    $display("TEST PASSED");
    $finish;
  end

  /********************
        ASSERTIONS
  *********************/

  property reset_check;
    @(posedge clk) rst |=> (state == S_IDLE);
  endproperty
  RESET: assert property(reset_check);

  property addr_check;
    @(posedge clk) my_calc.read |-> 
      (my_calc.r_addr >= my_calc.u_ctrl.read_start_addr) && 
      (my_calc.r_addr <= my_calc.u_ctrl.read_end_addr);
  endproperty
  VALID_INPUT_ADDRESS: assert property(addr_check);

property buffer_toggle;
  @(posedge clk) disable iff (rst || reset_test_active)
  (state == S_ADD && my_calc.u_ctrl.bufsel_q == 0) |=> ##1 (my_calc.u_ctrl.bufsel_q == 1);
endproperty
BUFFER_LOC_TOGGLES: assert property(buffer_toggle);

endmodule