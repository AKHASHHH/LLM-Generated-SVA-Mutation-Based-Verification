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

  // ------------------------------------------------------------------
  // Bus decode (pure functions of the 11 ports)
  // ------------------------------------------------------------------
  localparam logic [5:0] W_CTRL   = 6'd0;  // 0x00
  localparam logic [5:0] W_LOAD   = 6'd1;  // 0x04
  localparam logic [5:0] W_COUNT  = 6'd2;  // 0x08
  localparam logic [5:0] W_STATUS = 6'd3;  // 0x0C
  localparam logic [5:0] W_CMD    = 6'd4;  // 0x10
  localparam logic [5:0] W_ACTIVE = 6'd5;  // 0x14
  localparam logic [5:0] W_PSCNT  = 6'd6;  // 0x18

  wire       acc    = PSEL & PENABLE;
  wire       rd     = acc & ~PWRITE;
  wire       wr     = acc &  PWRITE;
  wire [5:0] word   = PADDR[7:2];                     // PADDR[1:0] ignored (R-APB-4)
  wire       mapped = (word <= W_PSCNT);
  wire       is_ro  = (word == W_COUNT) | (word == W_ACTIVE) | (word == W_PSCNT);
  wire       exp_err = acc & (~mapped | (PWRITE & is_ro));

  wire ctrl_wr   = wr & (word == W_CTRL);
  wire load_wr   = wr & (word == W_LOAD);
  wire status_wr = wr & (word == W_STATUS);
  wire cmd_wr    = wr & (word == W_CMD);

  wire rd_ctrl   = rd & (word == W_CTRL);
  wire rd_load   = rd & (word == W_LOAD);
  wire rd_count  = rd & (word == W_COUNT);
  wire rd_status = rd & (word == W_STATUS);
  wire rd_cmd    = rd & (word == W_CMD);
  wire rd_active = rd & (word == W_ACTIVE);
  wire rd_pscnt  = rd & (word == W_PSCNT);

  // ------------------------------------------------------------------
  // Checker-local bookkeeping. Updated ONLY from values written over APB
  // or values read back on PRDATA. No counting/next-state model.
  // ------------------------------------------------------------------
  logic        rst_seen;   // a reset has been observed (X-guard)
  logic        rst_hit;    // reset fell since last sample (guards $past checks)

  logic        en_wr;      // last EN value written to CTRL (EN == 0 whenever en_wr == 0)
  logic        mode_m;     // MODE (only changes by CTRL write)
  logic        ie_m;       // IE   (only changes by CTRL write)
  logic [7:0]  psc_m;      // PSC  (only changes by CTRL write)
  logic [15:0] shadow_m;   // SHADOW (only changes by LOAD write)

  logic        pend_seen;  // last STATUS read showed PEND=1, no PEND-clear write since
  logic        ovf_seen;   // same for OVF
  logic        pend_z;     // PEND provably 0 (timer provably never enabled since PEND last known 0)
  logic        ovf_z;      // OVF provably 0

  logic        cnt_v,  act_v,  pcnt_v;       // value stable while EN == 0, no start/restart
  logic [15:0] cnt_last, act_last;
  logic [7:0]  pcnt_last;

  wire start_ev   = ctrl_wr & PWDATA[0] & ~en_wr;      // EN is provably 0 here
  wire restart_ev = cmd_wr  & PWDATA[0];

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      rst_seen  <= 1'b1;
      rst_hit   <= 1'b1;
      en_wr     <= 1'b0;
      mode_m    <= 1'b0;
      ie_m      <= 1'b0;
      psc_m     <= 8'h00;
      shadow_m  <= 16'h0000;
      pend_seen <= 1'b0;
      ovf_seen  <= 1'b0;
      pend_z    <= 1'b1;
      ovf_z     <= 1'b1;
      cnt_v     <= 1'b1;  cnt_last  <= 16'h0000;
      act_v     <= 1'b1;  act_last  <= 16'h0000;
      pcnt_v    <= 1'b1;  pcnt_last <= 8'h00;
    end else begin
      rst_hit <= 1'b0;

      if (ctrl_wr) begin
        en_wr  <= PWDATA[0];
        mode_m <= PWDATA[1];
        ie_m   <= PWDATA[2];
        psc_m  <= PWDATA[15:8];
      end
      if (load_wr) shadow_m <= PWDATA[15:0];

      // PEND/OVF readback stickiness
      if (rd_status) begin
        pend_seen <= PRDATA[0];
        ovf_seen  <= PRDATA[1];
      end else if (status_wr) begin
        if (PWDATA[0]) pend_seen <= 1'b0;
        if (PWDATA[1]) ovf_seen  <= 1'b0;
      end

      // PEND/OVF provably zero: set by reset or by a clear write while EN==0
      // (no expiration possible); dropped when the timer may be enabled.
      if (ctrl_wr & PWDATA[0]) begin
        pend_z <= 1'b0;
        ovf_z  <= 1'b0;
      end else if (status_wr & ~en_wr) begin
        if (PWDATA[0]) pend_z <= 1'b1;
        if (PWDATA[1]) ovf_z  <= 1'b1;
      end

      // COUNT / ACTIVE / PCNT hold while EN==0 absent start/restart
      if ((ctrl_wr & PWDATA[0]) | restart_ev) begin
        cnt_v  <= 1'b0;
        act_v  <= 1'b0;
        pcnt_v <= 1'b0;
      end else if (rd & ~en_wr) begin
        if (rd_count)  begin cnt_v  <= 1'b1; cnt_last  <= PRDATA[15:0]; end
        if (rd_active) begin act_v  <= 1'b1; act_last  <= PRDATA[15:0]; end
        if (rd_pscnt)  begin pcnt_v <= 1'b1; pcnt_last <= PRDATA[7:0];  end
      end
    end
  end

  wire dis_x   = (rst_seen !== 1'b1);                                  // before first reset
  wire dis_rst = dis_x | (rst_hit !== 1'b0) | ~PRESETn;                // for multi-cycle checks

  // ------------------------------------------------------------------
  // Reset (R-RST-*)
  // ------------------------------------------------------------------
  // R-RST-1 / R-RST-4: reset-valued state => irq low, every read returns 0
  R_RST_4: assert property (@(posedge PCLK) disable iff (dis_x)
    !PRESETn |-> (irq === 1'b0 && PRDATA === 32'h0));

  // ------------------------------------------------------------------
  // APB interface (R-APB-*)
  // ------------------------------------------------------------------
  R_APB_3: assert property (@(posedge PCLK) disable iff (dis_x)
    PREADY === 1'b1);

  R_APB_8: assert property (@(posedge PCLK) disable iff (dis_x)
    PSLVERR === exp_err);

  // R-APB-7: PRDATA is zero except in a read access cycle to a mapped offset
  R_APB_7: assert property (@(posedge PCLK) disable iff (dis_x)
    !(rd & mapped) |-> (PRDATA === 32'h0));

  // R-APB-6 (+ section 7): read values
  R_APB_6_CTRL: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_ctrl |-> (PRDATA[31:16] === 16'h0 &&
                 PRDATA[15:8]  === psc_m &&
                 PRDATA[7:3]   === 5'h0  &&
                 PRDATA[2]     === ie_m  &&
                 PRDATA[1]     === mode_m &&
                 (PRDATA[0] === 1'b0 || en_wr)));   // EN can be 1 only if last written 1

  R_APB_6_LOAD: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_load |-> (PRDATA === {16'h0, shadow_m}));

  R_APB_6_COUNT: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_count |-> (PRDATA[31:16] === 16'h0));

  R_APB_6_STATUS: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_status |-> (PRDATA[31:2] === 30'h0));

  R_APB_6_CMD: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_cmd |-> (PRDATA === 32'h0));

  R_APB_6_ACTIVE: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_active |-> (PRDATA[31:16] === 16'h0));

  R_APB_6_PSCNT: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_pscnt |-> (PRDATA[31:8] === 24'h0));

  // R-APB-1/2/5/9/10 (no hidden dependence on setup phase, no side effects from
  // reads, non-access cycles, errored accesses, unmapped writes, PADDR[1:0]):
  // enforced through the exact readbacks above and the hold checks below,
  // since the local copies change only on legal, decoded APB writes.

  // ------------------------------------------------------------------
  // Timer operation (R-TMR-*), observed through readback only
  // ------------------------------------------------------------------
  // R-TMR-2: while EN==0 (en_wr==0), COUNT/ACTIVE/PCNT hold until start/restart.
  // Also covers R-TMR-8 (stop), R-TMR-11 (LOAD write does not touch them),
  // R-APB-9, R-APB-10.
  R_TMR_2_COUNT: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_count & cnt_v) |-> (PRDATA[15:0] === cnt_last));

  R_TMR_2_ACTIVE: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_active & act_v) |-> (PRDATA[15:0] === act_last));

  R_TMR_2_PSCNT: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_pscnt & pcnt_v) |-> (PRDATA[7:0] === pcnt_last));

  // R-TMR-7 (start): reload transfer, PCNT=0, EN=1 from the next cycle.
  // Reload uses the SHADOW held in the start cycle (R-TMR-11).
  R_TMR_7_COUNT: assert property (@(posedge PCLK) disable iff (dis_rst)
    start_ev |=> (rd_count |-> (PRDATA[15:0] === $past(shadow_m))));

  R_TMR_7_ACTIVE: assert property (@(posedge PCLK) disable iff (dis_rst)
    start_ev |=> (rd_active |-> (PRDATA[15:0] === $past(shadow_m))));

  R_TMR_7_PSCNT: assert property (@(posedge PCLK) disable iff (dis_rst)
    start_ev |=> (rd_pscnt |-> (PRDATA[7:0] === 8'h00)));

  R_TMR_7_EN: assert property (@(posedge PCLK) disable iff (dis_rst)
    start_ev |=> (rd_ctrl |-> (PRDATA[0] === 1'b1)));

  // R-TMR-9 (restart command): reload transfer and PCNT=0, whether EN is 0 or 1
  R_TMR_9_COUNT: assert property (@(posedge PCLK) disable iff (dis_rst)
    restart_ev |=> (rd_count |-> (PRDATA[15:0] === $past(shadow_m))));

  R_TMR_9_ACTIVE: assert property (@(posedge PCLK) disable iff (dis_rst)
    restart_ev |=> (rd_active |-> (PRDATA[15:0] === $past(shadow_m))));

  R_TMR_9_PSCNT: assert property (@(posedge PCLK) disable iff (dis_rst)
    restart_ev |=> (rd_pscnt |-> (PRDATA[7:0] === 8'h00)));

  // R-TMR-3 (count down, never wraps): back-to-back COUNT reads with COUNT != 0
  // can only hold or decrement by one.
  R_TMR_3: assert property (@(posedge PCLK) disable iff (dis_rst)
    (rd_count && $past(rd_count) && ($past(PRDATA[15:0]) !== 16'h0000)) |->
      (PRDATA[15:0] === $past(PRDATA[15:0]) ||
       PRDATA[15:0] === ($past(PRDATA[15:0]) - 16'h0001)));

  // R-TMR-4 / R-TMR-5: back-to-back COUNT reads with COUNT == 0: stays 0
  // (no tick or one-shot) or reloads to the SHADOW held in the read cycle.
  R_TMR_4: assert property (@(posedge PCLK) disable iff (dis_rst)
    (rd_count && $past(rd_count) && ($past(PRDATA[15:0]) === 16'h0000)) |->
      (PRDATA[15:0] === 16'h0000 || PRDATA[15:0] === $past(shadow_m)));

  // R-TMR-4 / R-TMR-11: ACTIVE changes only by a reload from SHADOW
  R_TMR_11: assert property (@(posedge PCLK) disable iff (dis_rst)
    (rd_active && $past(rd_active)) |->
      (PRDATA[15:0] === $past(PRDATA[15:0]) ||
       PRDATA[15:0] === $past(shadow_m)));

  // R-TMR-1 / R-TMR-13: back-to-back PSCNT reads: hold, clear to 0 (tick), or
  // +1 only when PCNT was below the PSC held in that cycle.
  R_TMR_1: assert property (@(posedge PCLK) disable iff (dis_rst)
    (rd_pscnt && $past(rd_pscnt)) |->
      (PRDATA[7:0] === $past(PRDATA[7:0]) ||
       PRDATA[7:0] === 8'h00 ||
       ({1'b0, PRDATA[7:0]} === ({1'b0, $past(PRDATA[7:0])} + 9'd1) &&
        $past(PRDATA[7:0]) < $past(psc_m))));

  // ------------------------------------------------------------------
  // Status flags and interrupt (R-INT-*)
  // ------------------------------------------------------------------
  // R-INT-2 / R-INT-3: PEND/OVF are sticky: once read as 1 they stay 1
  // until a STATUS write clears them (R-INT-2, R-INT-4).
  R_INT_2: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_status & pend_seen) |-> (PRDATA[0] === 1'b1));

  R_INT_4: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_status & ovf_seen) |-> (PRDATA[1] === 1'b1));

  // R-INT-5: software cannot set PEND/OVF; with the timer provably never enabled
  // since they were last known 0, they must read 0.
  R_INT_5_PEND: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_status & pend_z) |-> (PRDATA[0] === 1'b0));

  R_INT_5_OVF: assert property (@(posedge PCLK) disable iff (dis_x)
    (rd_status & ovf_z) |-> (PRDATA[1] === 1'b0));

  // R-INT-6: irq = PEND & IE, using values held in the same cycle
  R_INT_6_READ: assert property (@(posedge PCLK) disable iff (dis_x)
    rd_status |-> (irq === (PRDATA[0] & ie_m)));

  R_INT_6_IE: assert property (@(posedge PCLK) disable iff (dis_x)
    irq |-> ie_m);

  R_INT_1: assert property (@(posedge PCLK) disable iff (dis_x)
    irq |-> !pend_z);

  // R-INT-2 / R-INT-6 / R-INT-7: irq can fall only through a PEND-clear write,
  // an IE-clear write (or reset)
  R_INT_2_FALL: assert property (@(posedge PCLK) disable iff (dis_rst)
    ($past(irq) && !irq) |->
      $past((status_wr & PWDATA[0]) | (ctrl_wr & ~PWDATA[2])));

endmodule
