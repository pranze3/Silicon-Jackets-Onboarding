class calc_sb #(int DataSize, int AddrSize);

  // Local typedef for convenience
  typedef calc_tb_pkg::calc_seq_item#(DataSize, AddrSize) seq_item_t;

  // Golden model memories
  int mem_a [2**AddrSize];
  int mem_b [2**AddrSize];

  // Tracking for 2 reads before a write
  logic second_read = 0;
  int first_read_lower, first_read_upper;   // operands from first read
  int second_read_lower, second_read_upper; // operands from second read

  mailbox #(seq_item_t) sb_box;

  // Constructor
  function new(mailbox #(seq_item_t) sb_box);
    this.sb_box = sb_box;
    // initialize memory contents to zero
    for (int i = 0; i < 2**AddrSize; i++) begin
      mem_a[i] = 0;
      mem_b[i] = 0;
    end
  endfunction

  // Reset state when DUT is reset
  function void handle_reset();
    $display("[%0t] SB: Reset detected - clearing state", $time);
    second_read = 0;
    first_read_lower = 0;
    first_read_upper = 0;
    second_read_lower = 0;
    second_read_upper = 0;
  endfunction

  // Main scoreboard loop
  task main();
    seq_item_t trans;
    // Use int instead of longint - instructor feedback
    int first_sum, second_sum;
    int expected_lo, expected_hi;
    int dut_lo, dut_hi;
    
    forever begin
      sb_box.get(trans);

      // =====================================================
      // Initialization - just check initialize flag
      // =====================================================
      if (trans.initialize) begin
        if (trans.loc_sel == 0) begin
          mem_a[trans.curr_wr_addr] = trans.lower_data;
          $display("[%0t] SB: Init SRAM_A[%0d] = 0x%0h",
                   $time, trans.curr_wr_addr, trans.lower_data);
        end else begin
          mem_b[trans.curr_wr_addr] = trans.upper_data;
          $display("[%0t] SB: Init SRAM_B[%0d] = 0x%0h",
                   $time, trans.curr_wr_addr, trans.upper_data);
        end
      end

      // =====================================================
      // READs (rdn_wr = 0 means read)
      // =====================================================
      else if (!trans.rdn_wr && !trans.initialize) begin
        if (!second_read) begin
          // First read: capture operands
          first_read_lower = mem_a[trans.curr_rd_addr];
          first_read_upper = mem_b[trans.curr_rd_addr];
          second_read = 1;

          if (trans.lower_data !== first_read_lower ||
              trans.upper_data !== first_read_upper) begin
            $error("[%0t] SB: READ mismatch @ Addr=0x%0h | Exp(lo=0x%0h hi=0x%0h) Got(lo=0x%0h hi=0x%0h)",
                   $time, trans.curr_rd_addr,
                   first_read_lower, first_read_upper,
                   trans.lower_data, trans.upper_data);
            $finish;
          end else begin
            $display("[%0t] SB: First READ verified @ Addr=0x%0h | lo=0x%0h hi=0x%0h",
                     $time, trans.curr_rd_addr,
                     trans.lower_data, trans.upper_data);
          end
        end else begin
          // Second read: capture operands
          second_read_lower = mem_a[trans.curr_rd_addr];
          second_read_upper = mem_b[trans.curr_rd_addr];

          if (trans.lower_data !== second_read_lower ||
              trans.upper_data !== second_read_upper) begin
            $error("[%0t] SB: Second READ mismatch @ Addr=0x%0h | Exp(lo=0x%0h hi=0x%0h) Got(lo=0x%0h hi=0x%0h)",
                   $time, trans.curr_rd_addr,
                   second_read_lower, second_read_upper,
                   trans.lower_data, trans.upper_data);
            $finish;
          end else begin
            $display("[%0t] SB: Second READ verified @ Addr=0x%0h | lo=0x%0h hi=0x%0h",
                     $time, trans.curr_rd_addr,
                     trans.lower_data, trans.upper_data);
          end
        end
      end

      // =====================================================
      // WRITEs (rdn_wr = 1 means write)
      // =====================================================
      else if (trans.rdn_wr && !trans.initialize) begin
        // Check if we have valid read data
        if (!second_read) begin
          $error("[%0t] SB: WRITE received but no reads completed - resetting state", $time);
          handle_reset();
          continue;
        end
        
        // Calculate expected results - use int, handles overflow same as DUT
        first_sum = first_read_lower + first_read_upper;
        second_sum = second_read_lower + second_read_upper;
        
        expected_lo = first_sum;     // Lower buffer gets first read result
        expected_hi = second_sum;    // Upper buffer gets second read result

        dut_lo = trans.lower_data;
        dut_hi = trans.upper_data;

        if (dut_lo !== expected_lo || dut_hi !== expected_hi) begin
          $error("[%0t] SB: WRITE mismatch @ Addr=0x%0h | Exp(lo=0x%0h hi=0x%0h) Got(lo=0x%0h hi=0x%0h)",
                 $time, trans.curr_wr_addr,
                 expected_lo, expected_hi,
                 dut_lo, dut_hi);
          $error("[%0t] SB: Debug - First read: 0x%0h + 0x%0h = 0x%0h", 
                 $time, first_read_lower, first_read_upper, first_sum);
          $error("[%0t] SB: Debug - Second read: 0x%0h + 0x%0h = 0x%0h", 
                 $time, second_read_lower, second_read_upper, second_sum);
          $finish;
        end else begin
          $display("[%0t] SB: WRITE verified @ Addr=0x%0h | lo=0x%0h hi=0x%0h (PASS)",
                   $time, trans.curr_wr_addr,
                   dut_lo, dut_hi);
        end

        // Update memories with DUT result
        mem_a[trans.curr_wr_addr] = dut_lo;
        mem_b[trans.curr_wr_addr] = dut_hi;
        
        // Reset state for next sequence
        second_read = 0;
        $display("[%0t] SB: Write complete, ready for next sequence", $time);
      end
    end
  endtask

endclass : calc_sb