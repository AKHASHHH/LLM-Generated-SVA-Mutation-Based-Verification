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

  // Black-box checker: only bus transactions and observed read data are used.
  // No timer tick, expiration, counter, or next-state model is constructed.
  wire access = PSEL && PENABLE;
  wire rd     = access && !PWRITE;
  wire wr     = access &&  PWRITE;
  wire [5:0] regsel = PADDR[7:2];

  localparam logic [5:0] CTRL   = 6'h00;
  localparam logic [5:0] LOAD   = 6'h01;
  localparam logic [5:0] COUNT  = 6'h02;
  localparam logic [5:0] STATUS = 6'h03;
  localparam logic [5:0] CMD    = 6'h04;
  localparam logic [5:0] ACTIVE = 6'h05;
  localparam logic [5:0] PSCNT  = 6'h06;

  wire mapped = (regsel <= PSCNT);
  wire read_only = (regsel == COUNT || regsel == ACTIVE ||
                    regsel == PSCNT);
  wire err_expected = access && (!mapped || (PWRITE && read_only));
  wire ctrl_write = wr && (regsel == CTRL) && !PSLVERR;
  wire load_write = wr && (regsel == LOAD) && !PSLVERR;
  wire status_write = wr && (regsel == STATUS) && !PSLVERR;
  wire restart_write = wr && (regsel == CMD) && !PSLVERR && PWDATA[0];

  // Bus-observed/written configuration only; EN is intentionally NOT modeled.
  logic [15:0] observed_shadow;
  logic [9:0] observed_configuration; // {PSC[7:0], IE, MODE}
  logic stopped_known;
  logic status_known;
  logic [1:0] observed_status;

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      observed_shadow        <= 16'h0000;
      observed_configuration <= 10'h000;
      stopped_known          <= 1'b1;
      status_known           <= 1'b1;
      observed_status        <= 2'b00;
    end else begin
      if (load_write)
        observed_shadow <= PWDATA[15:0];
      if (ctrl_write)
        observed_configuration <= {PWDATA[15:8], PWDATA[2:1]};

      // A written EN=0 guarantees the following cycle is stopped, even
      // if one-shot completion and/or a periodic expiration coincided.
      // A written EN=1 does not guarantee it remains enabled.
      if (ctrl_write)
        stopped_known <= !PWDATA[0];

      // No expiration is possible while the timer is known stopped.
      // Do not predict STATUS across an enabled interval or the final
      // enabled cycle in which software writes EN=0.
      if (ctrl_write && PWDATA[0])
        status_known <= 1'b0;
      else if (ctrl_write && !PWDATA[0] && !stopped_known)
        status_known <= 1'b0;
      else if (stopped_known) begin
        if (status_write && status_known)
          observed_status <= observed_status & ~PWDATA[1:0];
        if (rd && regsel == STATUS && !PSLVERR) begin
          observed_status <= PRDATA[1:0];
          status_known <= 1'b1;
        end
      end

      // RESTART does not enable a stopped timer or set flags.
      // No checker state update is required for this command.
    end
  end

  // APB handshake and error response are combinational in every cycle,
  // irrespective of reset, setup-phase history, or address alignment.
  R_APB_3: assert property (@(posedge PCLK) PREADY == 1'b1);
  R_APB_8: assert property (@(posedge PCLK)
    PSLVERR == err_expected);
  R_APB_7: assert property (@(posedge PCLK)
    (!rd || !mapped) |-> (PRDATA == 32'h00000000));

  // All reserved read-data bits are zero. CMD always reads as zero.
  R_APB_6_CTRL: assert property (@(posedge PCLK)
    (rd && regsel == CTRL) |-> (PRDATA[31:16] == 16'h0000 &&
                                 PRDATA[7:3] == 5'b00000));
  R_APB_6_LOAD: assert property (@(posedge PCLK)
    (rd && regsel == LOAD) |-> (PRDATA[31:16] == 16'h0000));
  R_APB_6_COUNT: assert property (@(posedge PCLK)
    (rd && regsel == COUNT) |-> (PRDATA[31:16] == 16'h0000));
  R_APB_6_STATUS: assert property (@(posedge PCLK)
    (rd && regsel == STATUS) |-> (PRDATA[31:2] == 30'h00000000));
  R_APB_6_CMD: assert property (@(posedge PCLK)
    (rd && regsel == CMD) |-> (PRDATA == 32'h00000000));
  R_APB_6_ACTIVE: assert property (@(posedge PCLK)
    (rd && regsel == ACTIVE) |-> (PRDATA[31:16] == 16'h0000));
  R_APB_6_PSCNT: assert property (@(posedge PCLK)
    (rd && regsel == PSCNT) |-> (PRDATA[31:8] == 24'h000000));

  // SHADOW and the non-EN CTRL fields are entirely software controlled.
  // Their reference values are obtained solely from accepted APB writes.
  R_TMR_11: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (rd && regsel == LOAD) |->
      (PRDATA == {16'h0000, observed_shadow}));
  R_PRI_6: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (rd && regsel == CTRL) |->
      ({PRDATA[15:8], PRDATA[2:1]} == observed_configuration));
  R_PRI_2: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (rd && regsel == CTRL && stopped_known) |-> !PRDATA[0]);

  // STATUS can be checked against readback-derived state only in intervals
  // proven stopped from a prior CTRL write (or reset). During those
  // intervals, W1C is the sole possible source of flag changes.
  R_INT_2: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (rd && regsel == STATUS && stopped_known && status_known) |->
      (PRDATA[0] == observed_status[0]));
  R_INT_4: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (rd && regsel == STATUS && stopped_known && status_known) |->
      (PRDATA[1] == observed_status[1]));

  // A STATUS read exposes PEND for that same cycle. IE comes from the
  // last successful CTRL write (or reset), without reconstructing EN.
  R_INT_6: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (rd && regsel == STATUS) |->
      (irq == (PRDATA[0] && observed_configuration[1])));
  R_INT_6_KNOWN: assert property (@(posedge PCLK) disable iff (!PRESETn)
    (stopped_known && status_known) |->
      (irq == (observed_status[0] && observed_configuration[1])));

  // Asynchronous reset state is observable through the defined outputs.
  // Assertions at rising edges during reset avoid delta-cycle races.
  R_RST_1_IRQ: assert property (@(posedge PCLK)
    !PRESETn |-> (irq == 1'b0));
  R_RST_4_READ: assert property (@(posedge PCLK)
    (!PRESETn && rd && mapped) |-> (PRDATA == 32'h00000000));
  R_RST_2: assert property (@(posedge PCLK)
    (!PRESETn && rd && regsel == CTRL) |->
      (PRDATA == 32'h00000000));

endmodule
