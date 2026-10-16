// HARNESS FIXTURE ONLY (not a generated checker, never reported): proves the bind and isolation plumbing.
module apb_timer_bb_sva (input logic PCLK, PRESETn, PSEL, PENABLE, PWRITE, input logic [7:0] PADDR,
  input logic [31:0] PWDATA, PRDATA, input logic PREADY, PSLVERR, irq);
  FIX_pready: assert property (@(posedge PCLK) disable iff (!PRESETn) PREADY);
endmodule
