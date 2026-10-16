module rtl_claude_1 (output logic [68:0] dbg,
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

  localparam logic [5:0] A_CTRL   = 6'd0;
  localparam logic [5:0] A_LOAD   = 6'd1;
  localparam logic [5:0] A_COUNT  = 6'd2;
  localparam logic [5:0] A_STATUS = 6'd3;
  localparam logic [5:0] A_CMD    = 6'd4;
  localparam logic [5:0] A_ACTIVE = 6'd5;
  localparam logic [5:0] A_PSCNT  = 6'd6;

  logic        en_q, mode_q, ie_q;
  logic [7:0]  psc_q;
  logic [15:0] shadow_q, active_q, count_q;
  logic [7:0]  pcnt_q;
  logic        pend_q, ovf_q;

  logic [5:0]  idx;
  logic        access, mapped, ro_reg, err, wr_ok, rd_ok;
  logic        wr_ctrl, wr_load, wr_status, wr_cmd;
  logic        start, restart, tick, expire;

  assign idx    = PADDR[7:2];
  assign access = PSEL & PENABLE;

  always_comb begin
    mapped = 1'b0;
    ro_reg = 1'b0;
    case (idx)
      A_CTRL, A_LOAD, A_STATUS, A_CMD: mapped = 1'b1;
      A_COUNT, A_ACTIVE, A_PSCNT: begin
        mapped = 1'b1;
        ro_reg = 1'b1;
      end
      default: mapped = 1'b0;
    endcase
  end

  assign err   = access & (~mapped | (PWRITE & ro_reg));
  assign wr_ok = access & PWRITE & ~err;
  assign rd_ok = access & ~PWRITE & mapped;

  assign wr_ctrl   = wr_ok & (idx == A_CTRL);
  assign wr_load   = wr_ok & (idx == A_LOAD);
  assign wr_status = wr_ok & (idx == A_STATUS);
  assign wr_cmd    = wr_ok & (idx == A_CMD);

  assign start   = wr_ctrl & PWDATA[0] & ~en_q;
  assign restart = wr_cmd & PWDATA[0];
  assign tick    = en_q & (pcnt_q >= psc_q);
  assign expire  = tick & (count_q == 16'd0);

  assign PREADY  = 1'b1;
  assign PSLVERR = err;
  assign irq     = pend_q & ie_q;

  always_comb begin
    PRDATA = 32'd0;
    if (rd_ok) begin
      case (idx)
        A_CTRL:   PRDATA = {16'b0, psc_q, 5'b0, ie_q, mode_q, en_q};
        A_LOAD:   PRDATA = {16'b0, shadow_q};
        A_COUNT:  PRDATA = {16'b0, count_q};
        A_STATUS: PRDATA = {30'b0, ovf_q, pend_q};
        A_CMD:    PRDATA = 32'd0;
        A_ACTIVE: PRDATA = {16'b0, active_q};
        A_PSCNT:  PRDATA = {24'b0, pcnt_q};
        default:  PRDATA = 32'd0;
      endcase
    end
  end

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
      // CTRL fields
      if (wr_ctrl) begin
        mode_q <= PWDATA[1];
        ie_q   <= PWDATA[2];
        psc_q  <= PWDATA[15:8];
      end

      // SHADOW
      if (wr_load) begin
        shadow_q <= PWDATA[15:0];
      end

      // EN
      if (expire & mode_q) begin
        en_q <= 1'b0;
      end else if (wr_ctrl) begin
        en_q <= PWDATA[0];
      end

      // COUNT, ACTIVE, PCNT
      if (start | restart) begin
        active_q <= shadow_q;
        count_q  <= shadow_q;
        pcnt_q   <= 8'd0;
      end else if (expire) begin
        pcnt_q <= 8'd0;
        if (!mode_q) begin
          active_q <= shadow_q;
          count_q  <= shadow_q;
        end
      end else if (tick) begin
        count_q <= count_q - 16'd1;
        pcnt_q  <= 8'd0;
      end else if (en_q) begin
        pcnt_q <= pcnt_q + 8'd1;
      end

      // PEND
      if (expire) begin
        pend_q <= 1'b1;
      end else if (wr_status & PWDATA[0]) begin
        pend_q <= 1'b0;
      end

      // OVF
      if (expire & pend_q) begin
        ovf_q <= 1'b1;
      end else if (wr_status & PWDATA[1]) begin
        ovf_q <= 1'b0;
      end
    end
  end

assign dbg = {en_q,mode_q,ie_q,psc_q,shadow_q,active_q,count_q,pcnt_q,pend_q,ovf_q};
endmodule
