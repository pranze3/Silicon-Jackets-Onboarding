class calc_seq_item #(int DataSize, int AddrSize);

  rand logic rdn_wr;
  rand logic [AddrSize-1:0] read_start_addr;
  rand logic [AddrSize-1:0] read_end_addr;
  rand logic [AddrSize-1:0] write_start_addr;
  rand logic [AddrSize-1:0] write_end_addr;
  rand logic [DataSize-1:0] lower_data;
  rand logic [DataSize-1:0] upper_data;
  rand logic [AddrSize-1:0] curr_rd_addr;
  rand logic [AddrSize-1:0] curr_wr_addr;
  rand logic loc_sel;
  rand logic initialize;

  // Simplified constraint - instructor feedback
  constraint read_end_gt_start {
    read_end_addr > read_start_addr;
  }
  
  constraint write_end_gt_start {
    write_end_addr >= write_start_addr;
  }
  
  // Fixed address range constraints - instructor feedback about off-by-1 error
  constraint address_ranges_valid {
    read_start_addr inside {[0 : (2**AddrSize)-2]}; 
    read_end_addr inside {[1 : (2**AddrSize)-1]};
    write_start_addr inside {[0 : (2**AddrSize)-2]}; 
    write_end_addr inside {[1 : (2**AddrSize)-1]};
    curr_rd_addr inside {[0 : (2**AddrSize)-1]};
    curr_wr_addr inside {[0 : (2**AddrSize)-1]};

    ((read_end_addr - read_start_addr + 1) % 2) == 0;

    // Fixed constraint - add 1 inside the divide by 2
    (write_end_addr - write_start_addr) == ((read_end_addr - read_start_addr + 1) / 2);
  }

  function new();
  endfunction

  function void display();
    $display($stime, " Rdn_Wr: %b Read Start Addr: 0x%0x, Read End Addr: 0x%0x, Write Start Addr: 0x%0x, Write End Addr: 0x%0x, Data 0x%0x, Current Read Addr: 0x%0x, Current Write Addr: 0x%0x, Buffer location select: %b, SRAM initialization: %b\n",
        rdn_wr, read_start_addr, read_end_addr, write_start_addr, write_end_addr, {upper_data, lower_data}, curr_rd_addr, curr_wr_addr, loc_sel, initialize);
  endfunction

endclass : calc_seq_item