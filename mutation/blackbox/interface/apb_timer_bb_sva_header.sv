// Black-box checker interface contract (Experiment 2). Header only: the generated file must use
// exactly this module name and port list. Inputs are the 11 external ports of apb_timer, nothing else.
module apb_timer_bb_sva (
  input logic        PCLK,
  input logic        PRESETn,
  input logic        PSEL,
  input logic        PENABLE,
  input logic        PWRITE,
  input logic [7:0]  PADDR,
  input logic [31:0] PWDATA,
  input logic [31:0] PRDATA,
  input logic        PREADY,
  input logic        PSLVERR,
  input logic        irq
);
endmodule
