class calc_driver #(int DataSize, int AddrSize);

  // typedef to simplify parameterized type usage
  typedef calc_tb_pkg::calc_seq_item#(DataSize, AddrSize) seq_item_t;

  mailbox #(seq_item_t) drv_box;
  virtual interface calc_if #(.DataSize(DataSize), .AddrSize(AddrSize)) calcVif;

  function new(virtual interface calc_if #(DataSize, AddrSize) calcVif,
               mailbox #(seq_item_t) drv_box);
    this.calcVif = calcVif;
    this.drv_box = drv_box;
  endfunction

  task reset_task();
    $display("[%0t] DRIVER: Applying reset", $time);
    calcVif.cb.reset <= 1;
    repeat (5) @(calcVif.cb); // hold reset for 5 cycles
    calcVif.cb.reset <= 0;
    @(calcVif.cb);
    $display("[%0t] DRIVER: Reset released", $time);
  endtask

  virtual task initialize_sram(input [AddrSize-1:0] addr,
                               input [DataSize-1:0] data,
                               input logic block_sel);

    @(calcVif.cb);
    calcVif.cb.initialize         <= 1;
    calcVif.cb.initialize_addr    <= addr;
    calcVif.cb.initialize_data    <= data;
    calcVif.cb.initialize_loc_sel <= block_sel;

    $display("[%0t] DRIVER: Initializing SRAM_%s at Addr=0x%0h with Data=0x%0h",
             $time, (block_sel ? "B" : "A"), addr, data);

    @(calcVif.cb);
    calcVif.cb.initialize <= 0;
  endtask : initialize_sram

  virtual task start_calc(input logic [AddrSize-1:0] read_start_addr,
                          input logic [AddrSize-1:0] read_end_addr,
                          input logic [AddrSize-1:0] write_start_addr,
                          input logic [AddrSize-1:0] write_end_addr,
                          input bit direct = 1);

    int delay;
    seq_item_t trans;

    @(calcVif.cb);
    calcVif.cb.read_start_addr  <= read_start_addr;
    calcVif.cb.read_end_addr    <= read_end_addr;
    calcVif.cb.write_start_addr <= write_start_addr;
    calcVif.cb.write_end_addr   <= write_end_addr;

    $display("[%0t] DRIVER: Starting calculation. R:[0x%0h-0x%0h] W:[0x%0h-0x%0h]",
             $time, read_start_addr, read_end_addr,
             write_start_addr, write_end_addr);

    reset_task(); // ensure DUT starts clean
    @(calcVif.cb iff calcVif.cb.ready);

    if (!direct) begin
      if (drv_box.try_peek(trans)) begin
        delay = $urandom_range(0, 5); // Random delay
        repeat (delay) @(calcVif.cb);
      end
    end
  endtask : start_calc

  virtual task drive();
    seq_item_t trans;
    while (drv_box.try_get(trans)) begin
      start_calc(trans.read_start_addr,
                 trans.read_end_addr,
                 trans.write_start_addr,
                 trans.write_end_addr,
                 0);
    end
  endtask : drive

endclass : calc_driver
