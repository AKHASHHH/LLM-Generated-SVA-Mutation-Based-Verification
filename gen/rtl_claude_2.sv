module apb_timer (
  input  logic        PCLK,
  input  logic        PRESETn,
  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic        PWRITE,
  input  logic [7:0]  PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        PSLVERR,
  output logic        irq
);

  // Architectural state
  logic        en_q, mode_q, ie_q;
  logic [7:0]  psc_q;
  logic [15:0] shadow_q, active_q, count_q;
  logic [7:0]  pcnt_q;
  logic        pend_q, ovf_q;

  // Register offsets (PADDR[7:2])
  localparam logic [5:0] A_CTRL   = 6'h00;
  localparam logic [5:0] A_LOAD   = 6'h01;
  localparam logic [5:0] A_COUNT  = 6'h02;
  localparam logic [5:0] A_STATUS = 6'h03;
  localparam logic [5:0] A_CMD    = 6'h04;
  localparam logic [5:0] A_ACTIVE = 6'h05;
  localparam logic [5:0] A_PSCNT  = 6'h06;

  logic       access;
  logic [5:0] sel;
  logic       mapped;
  logic       ro_off;
  logic       err;
  logic       wr_ok;
  logic       rd_ok;

  assign access = PSEL & PENABLE;
  assign sel    = PADDR[7:2];
  assign mapped = (sel == A_CTRL)   || (sel == A_LOAD)   || (sel == A_COUNT) ||
                  (sel == A_STATUS) || (sel == A_CMD)    || (sel == A_ACTIVE) ||
                  (sel == A_PSCNT);
  assign ro_off = (sel == A_COUNT) || (sel == A_ACTIVE) || (sel == A_PSCNT);
  assign err    = access & (~mapped | (PWRITE & ro_off));
  assign wr_ok  = access & PWRITE & mapped & ~ro_off;
  assign rd_ok  = access & ~PWRITE & mapped;

  assign PREADY  = 1'b1;
  assign PSLVERR = err;
  assign irq     = pend_q & ie_q;

  // Read data
  always_comb begin
    PRDATA = 32'b0;
    if (rd_ok) begin
      case (sel)
        A_CTRL:   PRDATA = {16'b0, psc_q, 5'b0, ie_q, mode_q, en_q};
        A_LOAD:   PRDATA = {16'b0, shadow_q};
        A_COUNT:  PRDATA = {16'b0, count_q};
        A_STATUS: PRDATA = {30'b0, ovf_q, pend_q};
        A_CMD:    PRDATA = 32'b0;
        A_ACTIVE: PRDATA = {16'b0, active_q};
        A_PSCNT:  PRDATA = {24'b0, pcnt_q};
        default:  PRDATA = 32'b0;
      endcase
    end
  end

  // Event decode
  logic wr_ctrl, wr_load, wr_status, wr_cmd;
  logic start, restart, tick, expire;

  assign wr_ctrl   = wr_ok & (sel == A_CTRL);
  assign wr_load   = wr_ok & (sel == A_LOAD);
  assign wr_status = wr_ok & (sel == A_STATUS);
  assign wr_cmd    = wr_ok & (sel == A_CMD);

  assign start   = wr_ctrl & PWDATA[0] & ~en_q;
  assign restart = wr_cmd & PWDATA[0];
  assign tick    = en_q & (pcnt_q >= psc_q);
  assign expire  = tick & (count_q == 16'd0);

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      en_q     <= 1'b0;
      mode_q   <= 1'b0;
      ie_q     <= 1'b0;
      psc_q    <= 8'd0;
      shadow_q <= 16'd0;
      active_q <= 16'd0;
      count_q  <= 16'd0;
      pcnt_q   <= 8'd0;
      pend_q   <= 1'b0;
      ovf_q    <= 1'b0;
    end else begin
      // SHADOW
      if (wr_load)
        shadow_q <= PWDATA[15:0];

      // MODE, IE, PSC
      if (wr_ctrl) begin
        mode_q <= PWDATA[1];
        ie_q   <= PWDATA[2];
        psc_q  <= PWDATA[15:8];
      end

      // EN
      if (expire && mode_q)
        en_q <= 1'b0;
      else if (wr_ctrl)
        en_q <= PWDATA[0];

      // COUNT, ACTIVE, PCNT
      if (start || restart) begin
        active_q <= shadow_q;
        count_q  <= shadow_q;
        pcnt_q   <= 8'd0;
      end else if (expire) begin
        pcnt_q <= 8'd0;
        if (!mode_q) begin
          active_q <= shadow_q;
          count_q  <= shadow_q;
        end
      end else if (en_q) begin
        if (tick) begin
          pcnt_q  <= 8'd0;
          count_q <= count_q - 16'd1;
        end else begin
          pcnt_q <= pcnt_q + 8'd1;
        end
      end

      // PEND
      if (expire)
        pend_q <= 1'b1;
      else if (wr_status & PWDATA[0])
        pend_q <= 1'b0;

      // OVF
      if (expire & pend_q)
        ovf_q <= 1'b1;
      else if (wr_status & PWDATA[1])
        ovf_q <= 1'b0;
    end
  end

endmodule
