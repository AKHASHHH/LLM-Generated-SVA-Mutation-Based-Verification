// HARNESS FIXTURE ONLY: deliberately reads DUT internal state. The isolation check must reject it.
module apb_timer_bb_sva (input logic PCLK, PRESETn, PSEL, PENABLE, PWRITE, input logic [7:0] PADDR,
  input logic [31:0] PWDATA, PRDATA, input logic PREADY, PSLVERR, irq);
  FIX_leak: assert property (@(posedge PCLK) disable iff (!PRESETn) irq == (tb_top.dut.pend & tb_top.dut.ie));
endmodule
