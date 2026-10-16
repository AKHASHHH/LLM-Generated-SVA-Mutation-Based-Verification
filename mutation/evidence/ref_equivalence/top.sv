module top(input logic PCLK,PRESETn,PSEL,PENABLE,PWRITE,input logic [7:0] PADDR,input logic [31:0] PWDATA);
  logic [31:0] rd0; logic e0,r0,q0; logic [68:0] s0;
  ref_m u0(.dbg(s0),.PCLK,.PRESETn,.PSEL,.PENABLE,.PWRITE,.PADDR,.PWDATA,.PRDATA(rd0),.PREADY(r0),.PSLVERR(e0),.irq(q0));
  logic [31:0] rd1; logic e1,r1,q1; logic [68:0] s1;
  rtl_claude_1 u1(.dbg(s1),.PCLK,.PRESETn,.PSEL,.PENABLE,.PWRITE,.PADDR,.PWDATA,.PRDATA(rd1),.PREADY(r1),.PSLVERR(e1),.irq(q1));
  logic [31:0] rd2; logic e2,r2,q2; logic [68:0] s2;
  rtl_claude_2 u2(.dbg(s2),.PCLK,.PRESETn,.PSEL,.PENABLE,.PWRITE,.PADDR,.PWDATA,.PRDATA(rd2),.PREADY(r2),.PSLVERR(e2),.irq(q2));
  logic [31:0] rd3; logic e3,r3,q3; logic [68:0] s3;
  rtl_gpt_1 u3(.dbg(s3),.PCLK,.PRESETn,.PSEL,.PENABLE,.PWRITE,.PADDR,.PWDATA,.PRDATA(rd3),.PREADY(r3),.PSLVERR(e3),.irq(q3));
  logic [31:0] rd4; logic e4,r4,q4; logic [68:0] s4;
  rtl_gpt_2 u4(.dbg(s4),.PCLK,.PRESETn,.PSEL,.PENABLE,.PWRITE,.PADDR,.PWDATA,.PRDATA(rd4),.PREADY(r4),.PSLVERR(e4),.irq(q4));
  always_comb begin
    eq_out_1: assert(rd1==rd0 && e1==e0 && r1==r0 && q1==q0);
    eq_state_1: assert(s1==s0);
    eq_out_2: assert(rd2==rd0 && e2==e0 && r2==r0 && q2==q0);
    eq_state_2: assert(s2==s0);
    eq_out_3: assert(rd3==rd0 && e3==e0 && r3==r0 && q3==q0);
    eq_state_3: assert(s3==s0);
    eq_out_4: assert(rd4==rd0 && e4==e0 && r4==r0 && q4==q0);
    eq_state_4: assert(s4==s0);
  end
endmodule
