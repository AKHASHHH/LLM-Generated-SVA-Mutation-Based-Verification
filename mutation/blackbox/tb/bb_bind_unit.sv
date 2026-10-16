// Fallback hook (setenv BB_BIND_MODE unit): same connections as bb_bind.sv, but the bind directives sit at
// compilation-unit scope, so no second -top is needed. bb_hook is bound too and prints the BBHOOK liveness line.
module bb_hook;
  initial #2 $display("BBHOOK checker instance tb_top.u_bb bound; u_bb.PCLK=%b u_bb.PRESETn=%b", tb_top.u_bb.PCLK, tb_top.u_bb.PRESETn);
endmodule
bind tb_top apb_timer_bb_sva u_bb (
  .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
  .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR), .irq(irq));
bind tb_top bb_hook u_bb_hook ();
