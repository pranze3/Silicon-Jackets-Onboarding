class calc_monitor #(int DataSize, int AddrSize);

  // typedef to simplify usage of parameterized transaction type
  typedef calc_tb_pkg::calc_seq_item#(DataSize, AddrSize) seq_item_t;

  logic written = 0;

  virtual interface calc_if #(DataSize, AddrSize) calcVif;
  mailbox #(seq_item_t) mon_box;

  // Constructor
  function new(virtual interface calc_if #(DataSize, AddrSize) calcVif);
    this.calcVif = calcVif;
    this.mon_box = new();
  endfunction

  // Main monitoring loop
  task main();
    forever begin
      @(calcVif.cb);

      // Sanity check
      if (calcVif.cb.rd_en && calcVif.cb.wr_en) begin
        $error("[%0t] MON: rd_en and wr_en both asserted!", $time);
      end

      // --------------------------
      // Handle READ or WRITE ops
      // --------------------------
      if (calcVif.cb.wr_en || calcVif.cb.rd_en) begin
        seq_item_t trans = new();

        // Common fields
        trans.read_start_addr  = calcVif.cb.read_start_addr;
        trans.read_end_addr    = calcVif.cb.read_end_addr;
        trans.write_start_addr = calcVif.cb.write_start_addr;
        trans.write_end_addr   = calcVif.cb.write_end_addr;
        trans.curr_rd_addr     = calcVif.cb.curr_rd_addr;
        trans.curr_wr_addr     = calcVif.cb.curr_wr_addr;
        trans.loc_sel          = calcVif.cb.loc_sel;

        if (calcVif.cb.wr_en) begin
          // WRITE transaction
          trans.rdn_wr     = 1;
          trans.initialize = 0;
          trans.lower_data = calcVif.cb.wr_data[DataSize-1:0];
          trans.upper_data = calcVif.cb.wr_data[2*DataSize-1:DataSize];

          if (!written) begin
            written = 1;
            // Keep write messages - they show final results
            $display("[%0t] MON: Write @ Addr=0x%0h | A=0x%0h B=0x%0h",
                     $time, trans.curr_wr_addr, trans.lower_data, trans.upper_data);
            mon_box.put(trans);
          end

        end else begin
          // READ transaction
          trans.rdn_wr     = 0;
          trans.initialize = 0;
          @(calcVif.cb); // wait 1 cycle for data stable
          written = 0;
          trans.lower_data = calcVif.cb.rd_data[DataSize-1:0];
          trans.upper_data = calcVif.cb.rd_data[2*DataSize-1:DataSize];

          // Comment out verbose read messages to reduce log clutter
          // $display("[%0t] MON: Read @ Addr=0x%0h | A=0x%0h B=0x%0h",
          //          $time, trans.curr_rd_addr, trans.lower_data, trans.upper_data);
          mon_box.put(trans);
        end
      end

      // --------------------------
      // Handle initialization ops
      // --------------------------
      if (calcVif.cb.initialize) begin
        seq_item_t trans = new();
        trans.initialize      = 1;
        trans.rdn_wr          = 0;
        trans.curr_wr_addr    = calcVif.cb.initialize_addr;
        trans.loc_sel         = calcVif.cb.initialize_loc_sel;
        
        if (!calcVif.cb.initialize_loc_sel) begin
          // Initializing SRAM_A (loc_sel = 0)
          trans.lower_data = calcVif.cb.initialize_data;
          trans.upper_data = '0;
        end else begin
          // Initializing SRAM_B (loc_sel = 1)
          trans.lower_data = '0;
          trans.upper_data = calcVif.cb.initialize_data;
        end

        // Keep initialization messages - they're setup info, not too verbose
        $display("[%0t] MON: Initialize SRAM_%s @ Addr=0x%0h Data=0x%0h",
                 $time,
                 (calcVif.cb.initialize_loc_sel ? "B" : "A"),
                 calcVif.cb.initialize_addr,
                 calcVif.cb.initialize_data);

        mon_box.put(trans);
      end
    end
  endtask : main

endclass : calc_monitor