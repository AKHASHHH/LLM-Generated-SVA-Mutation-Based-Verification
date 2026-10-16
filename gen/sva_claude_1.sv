module apb_timer_sva (
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
  input logic        irq,
  // architectural state (spec section 6)
  input logic        a_en,
  input logic        a_mode,
  input logic        a_ie,
  input logic [7:0]  a_psc,
  input logic [15:0] a_shadow,
  input logic [15:0] a_active,
  input logic [15:0] a_count,
  input logic [7:0]  a_pcnt,
  input logic        a_pend,
  input logic        a_ovf
);

  // ------------------------------------------------------------------
  // Derived observation terms (spec section 8.1 definitions)
  // ------------------------------------------------------------------
  localparam logic [7:0] OFF_CTRL   = 8'h00;
  localparam logic [7:0] OFF_LOAD   = 8'h04;
  localparam logic [7:0] OFF_COUNT  = 8'h08;
  localparam logic [7:0] OFF_STATUS = 8'h0C;
  localparam logic [7:0] OFF_CMD    = 8'h10;
  localparam logic [7:0] OFF_ACTIVE = 8'h14;
  localparam logic [7:0] OFF_PSCNT  = 8'h18;

  wire       acc    = PSEL && PENABLE;                       // R-APB-1
  wire [7:0] off    = {PADDR[7:2], 2'b00};                   // R-APB-4
  wire       rd_acc = acc && !PWRITE;
  wire       wr_acc = acc && PWRITE;
  wire       mapped = (off == OFF_CTRL)   || (off == OFF_LOAD)   ||
                      (off == OFF_COUNT)  || (off == OFF_STATUS) ||
                      (off == OFF_CMD)    || (off == OFF_ACTIVE) ||
                      (off == OFF_PSCNT);
  wire       ro_off = (off == OFF_COUNT) || (off == OFF_ACTIVE) || (off == OFF_PSCNT);
  wire       err    = acc && (!mapped || (PWRITE && ro_off));  // R-APB-8

  wire wr_ctrl   = wr_acc && !err && (off == OFF_CTRL);
  wire wr_load   = wr_acc && !err && (off == OFF_LOAD);
  wire wr_status = wr_acc && !err && (off == OFF_STATUS);
  wire wr_cmd    = wr_acc && !err && (off == OFF_CMD);

  wire tick      = a_en && (a_pcnt >= a_psc);
  wire expire    = tick && (a_count == 16'd0);
  wire start     = wr_ctrl && PWDATA[0] && !a_en;
  wire restart   = wr_cmd  && PWDATA[0];
  wire reload_sw = start || restart;
  wire st_clr_p  = wr_status && PWDATA[0];
  wire st_clr_o  = wr_status && PWDATA[1];

  default clocking cb @(posedge PCLK); endclocking
  default disable iff (!PRESETn);

  `define CHK(LBL, ID, PROP) \
    LBL: assert property (PROP) else $error("[%s] assertion %s failed", ID, `"LBL`");
  `define COV(LBL, PROP) \
    LBL: cover property (PROP);

  // ------------------------------------------------------------------
  // Reset (R-RST-1..4, R-PRI-1)
  // ------------------------------------------------------------------
  wire all_reset_vals = !a_en && !a_mode && !a_ie && (a_psc == 8'd0) &&
                        (a_shadow == 16'd0) && (a_active == 16'd0) &&
                        (a_count == 16'd0) && (a_pcnt == 8'd0) &&
                        !a_pend && !a_ovf;

  // Asynchronous: state takes reset value immediately when PRESETn falls.
  always @(negedge PRESETn) begin
    #1;
    if (!PRESETn) begin
      RST1_async_state: assert (all_reset_vals && !irq)
        else $error("[R-RST-1] state/irq not at reset value after PRESETn fell");
    end
  end

  // While PRESETn is low, state holds reset value at every clock edge (R-RST-1, R-RST-2)
  RST1_hold_state: assert property (@(posedge PCLK) disable iff (1'b0)
      !PRESETn |-> all_reset_vals)
    else $error("[R-RST-1][R-RST-2] state not at reset value during reset");

  // Outputs apply unchanged during reset (R-RST-4)
  RST4_irq: assert property (@(posedge PCLK) disable iff (1'b0)
      !PRESETn |-> (irq == 1'b0))
    else $error("[R-RST-4] irq not 0 in reset");
  RST4_pready: assert property (@(posedge PCLK) disable iff (1'b0)
      !PRESETn |-> PREADY)
    else $error("[R-RST-4][R-APB-3] PREADY not 1 in reset");
  RST4_pslverr: assert property (@(posedge PCLK) disable iff (1'b0)
      !PRESETn |-> (PSLVERR == err))
    else $error("[R-RST-4][R-APB-8] PSLVERR wrong in reset");

  // First normal edge after reset uses reset-valued state (R-RST-3)
  RST3_first_edge: assert property (@(posedge PCLK) disable iff (1'b0)
      (!$past(PRESETn) && PRESETn) |-> all_reset_vals)
    else $error("[R-RST-3] state not reset-valued in first cycle after release");

  // ------------------------------------------------------------------
  // Combinational outputs (C-4), checked on both clock edges
  // ------------------------------------------------------------------
  `define OCLK @(posedge PCLK or negedge PCLK) disable iff (1'b0)

  APB3_pready: assert property (`OCLK PREADY === 1'b1)
    else $error("[R-APB-3] PREADY not 1");

  APB8_pslverr: assert property (`OCLK (PSLVERR === err))
    else $error("[R-APB-8] PSLVERR mismatch");
  APB8_pslverr_nonacc: assert property (`OCLK (!acc |-> !PSLVERR))
    else $error("[R-APB-8] PSLVERR in non-access cycle");

  APB6_rd_ctrl: assert property (`OCLK
      (rd_acc && (off == OFF_CTRL)) |->
        (PRDATA === {16'b0, a_psc, 5'b0, a_ie, a_mode, a_en}))
    else $error("[R-APB-6] CTRL read data");
  APB6_rd_load: assert property (`OCLK
      (rd_acc && (off == OFF_LOAD)) |-> (PRDATA === {16'b0, a_shadow}))
    else $error("[R-APB-6] LOAD read data");
  APB6_rd_count: assert property (`OCLK
      (rd_acc && (off == OFF_COUNT)) |-> (PRDATA === {16'b0, a_count}))
    else $error("[R-APB-6] COUNT read data");
  APB6_rd_status: assert property (`OCLK
      (rd_acc && (off == OFF_STATUS)) |-> (PRDATA === {30'b0, a_ovf, a_pend}))
    else $error("[R-APB-6] STATUS read data");
  APB6_rd_cmd: assert property (`OCLK
      (rd_acc && (off == OFF_CMD)) |-> (PRDATA === 32'd0))
    else $error("[R-APB-6] CMD read data (must be 0, no error)");
  APB6_rd_active: assert property (`OCLK
      (rd_acc && (off == OFF_ACTIVE)) |-> (PRDATA === {16'b0, a_active}))
    else $error("[R-APB-6] ACTIVE read data");
  APB6_rd_pscnt: assert property (`OCLK
      (rd_acc && (off == OFF_PSCNT)) |-> (PRDATA === {24'b0, a_pcnt}))
    else $error("[R-APB-6] PSCNT read data");
  APB7_prdata_zero: assert property (`OCLK
      !(rd_acc && mapped) |-> (PRDATA === 32'd0))
    else $error("[R-APB-7] PRDATA not zero outside mapped read access");
  APB8_unmapped_rd_err: assert property (`OCLK
      (rd_acc && !mapped) |-> (PSLVERR && PRDATA === 32'd0))
    else $error("[R-APB-7][R-APB-8] unmapped read");
  APB8_ro_wr_err: assert property (`OCLK
      (wr_acc && mapped && ro_off) |-> PSLVERR)
    else $error("[R-APB-8] write to RO must error");
  APB8_cmd_rd_noerr: assert property (`OCLK
      (rd_acc && (off == OFF_CMD)) |-> !PSLVERR)
    else $error("[R-APB-8] CMD read must not error");
  APB8_wr_ok_noerr: assert property (`OCLK
      (wr_acc && ((off == OFF_CTRL) || (off == OFF_LOAD) ||
                  (off == OFF_STATUS) || (off == OFF_CMD))) |-> !PSLVERR)
    else $error("[R-APB-8] write to writable offset must not error");

  INT6_irq: assert property (`OCLK (irq === (a_pend && a_ie)))
    else $error("[R-INT-6] irq != PEND & IE");

  // ------------------------------------------------------------------
  // SHADOW (R-TMR-11, R-PRI-7, R-APB-5)
  // ------------------------------------------------------------------
  `CHK(TMR11_shadow_write, "R-TMR-11",
       (wr_load |=> (a_shadow == $past(PWDATA[15:0]))))
  `CHK(PRI7_shadow_hold, "R-PRI-7",
       (!wr_load |=> (a_shadow == $past(a_shadow))))
  `CHK(TMR11_load_no_side_effect, "R-TMR-11",
       ((wr_load && !reload_sw && !expire && !tick && a_en) |=>
          (a_count == $past(a_count) && a_active == $past(a_active))))
  `CHK(TMR11_load_not_start, "R-TMR-11",
       ((wr_load && !a_en) |=>
          (a_count == $past(a_count) && a_active == $past(a_active) &&
           a_pcnt == $past(a_pcnt) && !a_en)))

  // ------------------------------------------------------------------
  // CTRL fields MODE / IE / PSC (R-APB-5, R-PRI-6, R-TMR-12)
  // ------------------------------------------------------------------
  `CHK(PRI6_ctrl_write, "R-PRI-6",
       (wr_ctrl |=> (a_mode == $past(PWDATA[1]) && a_ie == $past(PWDATA[2]) &&
                     a_psc == $past(PWDATA[15:8]))))
  `CHK(PRI6_ctrl_hold, "R-PRI-6",
       (!wr_ctrl |=> (a_mode == $past(a_mode) && a_ie == $past(a_ie) &&
                      a_psc == $past(a_psc))))
  `CHK(APB5_reserved_ignored, "R-APB-5",
       (wr_ctrl |=> (a_mode == $past(PWDATA[1]) && a_ie == $past(PWDATA[2]))))

  // ------------------------------------------------------------------
  // EN (R-PRI-2, R-TMR-5, R-TMR-7, R-TMR-8, R-TMR-9)
  // ------------------------------------------------------------------
  `CHK(PRI2_oneshot_expire_clears_en, "R-PRI-2/R-TMR-5",
       ((expire && a_mode) |=> !a_en))
  `CHK(PRI2_ctrl_sets_en, "R-PRI-2/R-TMR-8",
       ((!(expire && a_mode) && wr_ctrl) |=> (a_en == $past(PWDATA[0]))))
  `CHK(PRI2_en_hold, "R-PRI-2",
       ((!(expire && a_mode) && !wr_ctrl) |=> (a_en == $past(a_en))))
  `CHK(TMR7_start_enables, "R-TMR-7",
       (start |=> a_en))
  `CHK(TMR8_stop, "R-TMR-8",
       ((wr_ctrl && !PWDATA[0]) |=> !a_en))
  `CHK(TMR9_restart_en_unchanged, "R-TMR-9",
       ((restart && !(expire && a_mode)) |=> (a_en == $past(a_en))))
  `CHK(TMR4_periodic_expire_en_unchanged, "R-TMR-4",
       ((expire && !a_mode && !wr_ctrl) |=> a_en))

  // ------------------------------------------------------------------
  // COUNT / ACTIVE / PCNT (R-PRI-3, R-TMR-1..3, 7, 9, 10, 13)
  // ------------------------------------------------------------------
  // (1) Start or restart: reload transfer from held SHADOW, PCNT = 0
  `CHK(TMR7_TMR9_reload_transfer, "R-TMR-7/R-TMR-9/R-PRI-3",
       (reload_sw |=> (a_active == $past(a_shadow) && a_count == $past(a_shadow) &&
                       a_pcnt == 8'd0)))
  // (2) Expiration effect
  `CHK(TMR4_periodic_reload, "R-TMR-4/R-PRI-3",
       ((expire && !a_mode && !reload_sw) |=>
          (a_active == $past(a_shadow) && a_count == $past(a_shadow) &&
           a_pcnt == 8'd0)))
  `CHK(TMR5_oneshot_hold, "R-TMR-5/R-PRI-3",
       ((expire && a_mode && !reload_sw) |=>
          (a_count == 16'd0 && a_active == $past(a_active) && a_pcnt == 8'd0)))
  // (3) Tick decrement and prescaler update
  `CHK(TMR3_countdown, "R-TMR-3/R-PRI-3",
       ((tick && (a_count != 16'd0) && !restart) |=>
          (a_count == 16'($past(a_count) - 16'd1) && a_active == $past(a_active) &&
           a_pcnt == 8'd0)))
  `CHK(TMR1_no_tick_prescale, "R-TMR-1/R-PRI-3",
       ((a_en && !tick && !restart) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1) && a_count == $past(a_count) &&
           a_active == $past(a_active))))
  `CHK(TMR1_tick_pcnt_zero, "R-TMR-1",
       ((tick && !restart) |=> (a_pcnt == 8'd0)))
  // (4) Hold when stopped
  `CHK(TMR2_stopped_hold, "R-TMR-2/R-PRI-3",
       ((!a_en && !start && !restart) |=>
          (a_count == $past(a_count) && a_pcnt == $past(a_pcnt) &&
           a_active == $past(a_active))))
  `CHK(TMR3_no_wrap, "R-TMR-3",
       ((a_count == 16'd0 && !tick && !reload_sw) |=> (a_count == 16'd0)))
  `CHK(TMR13_psc_gt_forces_tick, "R-TMR-13",
       ((a_en && (a_pcnt > a_psc) && !restart) |=> (a_pcnt == 8'd0)))
  `CHK(TMR13_psc_change_keeps_pcnt, "R-TMR-13",
       ((wr_ctrl && !a_en && !start) |=> (a_pcnt == $past(a_pcnt))))
  `CHK(TMR12_tick_uses_held_psc, "R-TMR-12",
       ((wr_ctrl && a_en && !restart && (a_pcnt >= a_psc)) |=> (a_pcnt == 8'd0)))
  `CHK(TMR12_notick_uses_held_psc, "R-TMR-12",
       ((wr_ctrl && a_en && (a_pcnt < a_psc)) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1))))
  `CHK(TMR10_ctrl_en_no_start, "R-TMR-10",
       ((wr_ctrl && PWDATA[0] && a_en && !(expire && a_mode) && !(expire && !a_mode) && !tick) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1) && a_count == $past(a_count) &&
           a_active == $past(a_active))))
  `CHK(TMR10_ctrl_en_tick_no_reload, "R-TMR-10",
       ((wr_ctrl && PWDATA[0] && a_en && tick && (a_count != 16'd0)) |=>
          (a_count == 16'($past(a_count) - 16'd1) && a_pcnt == 8'd0 &&
           a_active == $past(a_active))))
  `CHK(TMR8_stop_cycle_still_enabled, "R-TMR-8",
       ((wr_ctrl && !PWDATA[0] && a_en && !tick) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1) && !a_en)))
  `CHK(TMR8_resume_is_reload, "R-TMR-8/R-TMR-7",
       ((wr_ctrl && PWDATA[0] && !a_en) |=>
          (a_count == $past(a_shadow) && a_active == $past(a_shadow))))

  // ------------------------------------------------------------------
  // PEND / OVF / irq (R-INT-1..7, R-PRI-4, R-PRI-5)
  // ------------------------------------------------------------------
  `CHK(INT1_pend_set, "R-INT-1/R-PRI-4",
       (expire |=> a_pend))
  `CHK(INT1_pend_set_ie0, "R-INT-1/R-INT-7",
       ((expire && !a_ie) |=> a_pend))
  `CHK(INT2_pend_clear, "R-INT-2/R-PRI-4",
       ((!expire && st_clr_p) |=> !a_pend))
  `CHK(PRI4_pend_hold, "R-PRI-4",
       ((!expire && !st_clr_p) |=> (a_pend == $past(a_pend))))
  `CHK(INT3_ovf_set, "R-INT-3/R-PRI-5",
       ((expire && a_pend) |=> a_ovf))
  `CHK(INT3_ovf_set_with_clear, "R-INT-3",
       ((expire && a_pend && st_clr_p) |=> (a_ovf && a_pend)))
  `CHK(INT4_ovf_clear, "R-INT-4/R-PRI-5",
       ((!(expire && a_pend) && st_clr_o) |=> !a_ovf))
  `CHK(PRI5_ovf_hold, "R-PRI-5",
       ((!(expire && a_pend) && !st_clr_o) |=> (a_ovf == $past(a_ovf))))
  `CHK(INT5_pend_hw_only, "R-INT-5",
       ((!a_pend && !expire) |=> !a_pend))
  `CHK(INT5_ovf_hw_only, "R-INT-5",
       ((!a_ovf && !(expire && a_pend)) |=> !a_ovf))
  `CHK(INT5_status_write_no_set, "R-INT-5",
       ((wr_status && !expire) |=> (a_pend <= $past(a_pend) && a_ovf <= $past(a_ovf))))
  `CHK(INT_status_zero_noeffect, "R-INT-2/R-INT-4",
       ((wr_status && !PWDATA[0] && !PWDATA[1] && !expire) |=>
          (a_pend == $past(a_pend) && a_ovf == $past(a_ovf))))
  `CHK(TMR7_start_keeps_flags, "R-TMR-7",
       (start |=> (a_pend == ($past(a_pend) || $past(expire)) &&
                   a_ovf  == $past(a_ovf))))
  `CHK(INT7_ie_independent, "R-INT-7",
       (($past(a_ie) != a_ie) |-> irq == (a_pend && a_ie)))

  // ------------------------------------------------------------------
  // Errored access / reads / non-access (R-APB-2, 9, 10)
  // ------------------------------------------------------------------
  `CHK(APB9_err_no_cfg_change, "R-APB-9",
       (err |=> (a_mode == $past(a_mode) && a_ie == $past(a_ie) &&
                 a_psc == $past(a_psc) && a_shadow == $past(a_shadow))))
  `CHK(APB9_err_en, "R-APB-9",
       ((err && !(expire && a_mode)) |=> (a_en == $past(a_en))))
  `CHK(APB9_err_flags, "R-APB-9/R-PRI-4/R-PRI-5",
       (err |=> (a_pend == ($past(a_pend) || $past(expire)) &&
                 a_ovf  == ($past(a_ovf) || ($past(expire) && $past(a_pend))))))
  `CHK(APB9_err_counters_hw_only, "R-APB-9",
       ((err && !expire && !tick && a_en) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1) && a_count == $past(a_count) &&
           a_active == $past(a_active))))
  `CHK(APB9_err_stopped_hold, "R-APB-9",
       ((err && !a_en) |=>
          (a_count == $past(a_count) && a_pcnt == $past(a_pcnt) &&
           a_active == $past(a_active) && !a_en)))
  `CHK(APB9_ro_write_no_effect, "R-APB-9",
       ((wr_acc && mapped && ro_off && !a_en) |=>
          (a_count == $past(a_count) && a_active == $past(a_active) &&
           a_pcnt == $past(a_pcnt))))
  `CHK(APB9_cmd_nowrite_err_restart_ignored, "R-APB-9",
       ((acc && PWRITE && !mapped && PWDATA[0] && !a_en) |=>
          (a_count == $past(a_count) && a_pcnt == $past(a_pcnt))))
  `CHK(APB10_read_no_side_effect_cfg, "R-APB-10",
       (rd_acc |=> (a_mode == $past(a_mode) && a_ie == $past(a_ie) &&
                    a_psc == $past(a_psc) && a_shadow == $past(a_shadow))))
  `CHK(APB10_read_no_side_effect_flags, "R-APB-10",
       (rd_acc |=> (a_pend == ($past(a_pend) || $past(expire)) &&
                    a_ovf  == ($past(a_ovf) || ($past(expire) && $past(a_pend))))))
  `CHK(APB10_read_no_side_effect_en, "R-APB-10",
       ((rd_acc && !(expire && a_mode)) |=> (a_en == $past(a_en))))
  `CHK(APB10_read_stopped_hold, "R-APB-10",
       ((rd_acc && !a_en) |=>
          (a_count == $past(a_count) && a_pcnt == $past(a_pcnt) &&
           a_active == $past(a_active))))
  `CHK(APB10_read_running_hw_only, "R-APB-10",
       ((rd_acc && a_en && !tick) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1) && a_count == $past(a_count) &&
           a_active == $past(a_active))))
  `CHK(APB2_nonacc_cfg, "R-APB-2",
       (!acc |=> (a_mode == $past(a_mode) && a_ie == $past(a_ie) &&
                  a_psc == $past(a_psc) && a_shadow == $past(a_shadow))))
  `CHK(APB2_nonacc_en, "R-APB-2",
       ((!acc && !(expire && a_mode)) |=> (a_en == $past(a_en))))
  `CHK(APB2_nonacc_flags, "R-APB-2",
       (!acc |=> (a_pend == ($past(a_pend) || $past(expire)) &&
                  a_ovf  == ($past(a_ovf) || ($past(expire) && $past(a_pend))))))
  `CHK(APB2_nonacc_stopped_hold, "R-APB-2",
       ((!acc && !a_en) |=>
          (a_count == $past(a_count) && a_pcnt == $past(a_pcnt) &&
           a_active == $past(a_active))))
  `CHK(APB2_nonacc_running_hw_only, "R-APB-2",
       ((!acc && a_en && !tick) |=>
          (a_pcnt == 8'($past(a_pcnt) + 8'd1) && a_count == $past(a_count) &&
           a_active == $past(a_active))))
  `CHK(APB4_paddr_low_bits_ignored_load, "R-APB-4/R-APB-5",
       ((wr_acc && (PADDR[7:2] == 6'h01)) |=> (a_shadow == $past(PWDATA[15:0]))))
  `CHK(APB1_back_to_back_load, "R-APB-1",
       ((wr_load ##1 wr_load) |=> (a_shadow == $past(PWDATA[15:0]))))
  `CHK(APB1_no_setup_needed_status, "R-APB-1/R-INT-2",
       (($past(!PSEL) && wr_status && PWDATA[0] && !expire) |=> !a_pend))

  // ------------------------------------------------------------------
  // Simultaneous-event priority cases (section 10)
  // ------------------------------------------------------------------
  `CHK(PRI3_periodic_exp_load_write, "R-PRI-3/R-TMR-11",
       ((expire && !a_mode && wr_load) |=>
          (a_active == $past(a_shadow) && a_count == $past(a_shadow) &&
           a_shadow == $past(PWDATA[15:0]) && a_pend && a_pcnt == 8'd0)))
  `CHK(PRI4_exp_pend0_status1, "R-PRI-4",
       ((expire && !a_pend && wr_status && PWDATA[0] && !PWDATA[1]) |=>
          (a_pend && a_ovf == $past(a_ovf))))
  `CHK(PRI4_exp_pend1_status1, "R-PRI-4/R-INT-3",
       ((expire && a_pend && wr_status && PWDATA[0] && !PWDATA[1]) |=>
          (a_pend && a_ovf)))
  `CHK(PRI5_exp_pend1_status2or3, "R-PRI-5/R-INT-3/R-INT-4",
       ((expire && a_pend && wr_status && PWDATA[1]) |=> (a_pend && a_ovf)))
  `CHK(PRI5_exp_pend0_status_ovf_clear, "R-PRI-5",
       ((expire && !a_pend && wr_status && PWDATA[1]) |=>
          (a_pend && !a_ovf == !$past(a_ovf) || a_pend)))
  `CHK(PRI2_periodic_exp_ctrl_en0, "R-PRI-2/R-PRI-3",
       ((expire && !a_mode && wr_ctrl && !PWDATA[0]) |=>
          (a_active == $past(a_shadow) && a_count == $past(a_shadow) &&
           a_pend && !a_en)))
  `CHK(PRI2_oneshot_exp_ctrl_en1, "R-PRI-2/R-TMR-10",
       ((expire && a_mode && wr_ctrl && PWDATA[0]) |=>
          (!a_en && a_mode == $past(PWDATA[1]) && a_ie == $past(PWDATA[2]) &&
           a_psc == $past(PWDATA[15:8]) && a_count == 16'd0 &&
           a_active == $past(a_active) && a_pend)))
  `CHK(PRI2_periodic_exp_mode_to_oneshot, "R-PRI-2/R-TMR-12",
       ((expire && !a_mode && wr_ctrl && PWDATA[1] && PWDATA[0]) |=>
          (a_en && a_mode && a_count == $past(a_shadow) &&
           a_active == $past(a_shadow))))
  `CHK(PRI2_oneshot_exp_mode_to_periodic, "R-PRI-2/R-TMR-12",
       ((expire && a_mode && wr_ctrl && !PWDATA[1]) |=>
          (!a_en && !a_mode && a_count == 16'd0)))
  `CHK(TMR12_exp_psc_ie_change, "R-TMR-12",
       ((expire && wr_ctrl) |=>
          (a_psc == $past(PWDATA[15:8]) && a_ie == $past(PWDATA[2]) &&
           a_pcnt == 8'd0 && a_pend)))
  `CHK(PRI3_periodic_exp_restart, "R-PRI-3/R-TMR-9",
       ((expire && !a_mode && restart) |=>
          (a_active == $past(a_shadow) && a_count == $past(a_shadow) &&
           a_pcnt == 8'd0 && a_en && a_pend)))
  `CHK(PRI3_oneshot_exp_restart, "R-PRI-3/R-TMR-9/R-PRI-2",
       ((expire && a_mode && restart) |=>
          (a_active == $past(a_shadow) && a_count == $past(a_shadow) &&
           a_pcnt == 8'd0 && !a_en && a_pend)))
  `CHK(PRI3_exp_restart_ovf, "R-TMR-9/R-INT-3",
       ((expire && restart && a_pend) |=> (a_ovf && a_pend)))
  `CHK(PRI3_tick_noexp_restart, "R-PRI-3/R-TMR-9",
       ((tick && (a_count != 16'd0) && restart) |=>
          (a_count == $past(a_shadow) && a_active == $past(a_shadow) &&
           a_pcnt == 8'd0)))
  `CHK(PRI3_restart_while_stopped, "R-TMR-9",
       ((!a_en && restart) |=>
          (a_count == $past(a_shadow) && a_active == $past(a_shadow) &&
           a_pcnt == 8'd0 && !a_en)))
  `CHK(PRI3_tick_noexp_ctrl_en0, "R-PRI-3/R-TMR-8",
       ((tick && (a_count != 16'd0) && wr_ctrl && !PWDATA[0]) |=>
          (a_count == 16'($past(a_count) - 16'd1) && a_pcnt == 8'd0 && !a_en)))
  `CHK(PRI3_errored_access_hw_only, "R-APB-9",
       ((err && tick && (a_count != 16'd0)) |=>
          (a_count == 16'($past(a_count) - 16'd1) && a_pcnt == 8'd0)))
  `CHK(PRI3_errored_expire_flags, "R-APB-9/R-INT-1",
       ((err && expire) |=> a_pend))
  `CHK(PRI3_start_never_with_expire, "R-TMR-7",
       (!(start && expire)))

  // ------------------------------------------------------------------
  // Coverage of key scenarios
  // ------------------------------------------------------------------
  `COV(c_start,            start)
  `COV(c_restart,          restart)
  `COV(c_periodic_expire,  expire && !a_mode)
  `COV(c_oneshot_expire,   expire && a_mode)
  `COV(c_ovf_set,          expire && a_pend)
  `COV(c_exp_status_clear, expire && st_clr_p)
  `COV(c_exp_load,         expire && wr_load)
  `COV(c_exp_ctrl,         expire && wr_ctrl)
  `COV(c_exp_restart,      expire && restart)
  `COV(c_psc_lower,        a_en && (a_pcnt > a_psc))
  `COV(c_err_access,       err)

  `undef CHK
  `undef COV
  `undef OCLK

endmodule
