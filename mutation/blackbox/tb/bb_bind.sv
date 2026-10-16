// Experiment 2 hook. Attaches the black-box checker to the UNCHANGED white-box tb_top (compiled without
// +define+WITH_SVA; add this file and -top bb_bind). The checker receives only the 11 DUT port signals at
// the DUT boundary: the TB-driven inputs and the DUT's own outputs (never the reference instance's).
// BBHOOK: proves the checker instance exists. tb_top.u_bb.PCLK only resolves if the bind elaborated, so an
// unbound checker is a compile error, never a silent "0 failures". This line is harness code; the checker
// itself is not touched.
module bb_bind;
  bind tb_top apb_timer_bb_sva u_bb (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
    .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR), .irq(irq));
  initial #2 $display("BBHOOK checker instance tb_top.u_bb bound; u_bb.PCLK=%b u_bb.PRESETn=%b", tb_top.u_bb.PCLK, tb_top.u_bb.PRESETn);
endmodule
