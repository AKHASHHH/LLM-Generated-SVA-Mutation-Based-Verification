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

    wire access_cycle = PSEL && PENABLE;
    wire [5:0] reg_index = PADDR[7:2];
    wire mapped = (reg_index <= 6'd6);
    wire read_only = (reg_index == 6'd2) || (reg_index == 6'd5) ||
                     (reg_index == 6'd6);
    wire error_access = access_cycle && (!mapped || (PWRITE && read_only));
    wire write_access = access_cycle && PWRITE && mapped && !read_only;
    wire write_ctrl = write_access && (reg_index == 6'd0);
    wire write_load = write_access && (reg_index == 6'd1);
    wire write_status = write_access && (reg_index == 6'd3);
    wire write_cmd = write_access && (reg_index == 6'd4);
    wire start_event = write_ctrl && PWDATA[0] && !a_en;
    wire restart_event = write_cmd && PWDATA[0];
    wire tick_event = a_en && (a_pcnt >= a_psc);
    wire expiration_event = tick_event && (a_count == 16'd0);
    wire one_shot_expiration = expiration_event && a_mode;
    wire reload_event = start_event || restart_event ||
                        (expiration_event && !a_mode);

    logic [31:0] expected_read;
    always_comb begin
        expected_read = 32'd0;
        if (access_cycle && !PWRITE) begin
            case (reg_index)
                6'd0: expected_read = {16'd0, a_psc, 5'd0, a_ie, a_mode, a_en};
                6'd1: expected_read = {16'd0, a_shadow};
                6'd2: expected_read = {16'd0, a_count};
                6'd3: expected_read = {30'd0, a_ovf, a_pend};
                6'd4: expected_read = 32'd0;
                6'd5: expected_read = {16'd0, a_active};
                6'd6: expected_read = {24'd0, a_pcnt};
                default: expected_read = 32'd0;
            endcase
        end
    end

    // Deferred immediate assertions evaluate after combinational settling.
    always_comb begin
        R_APB_3_PREADY: assert final (PREADY == 1'b1);
        R_APB_8_PSLVERR: assert final (PSLVERR == error_access);
        R_APB_4_6_7_PRDATA: assert final (PRDATA == expected_read);
        R_INT_6_IRQ: assert final (irq == (a_pend && a_ie));
        if (!PRESETn) begin
            R_RST_1_ASYNC_STATE: assert final (
                {a_en, a_mode, a_ie, a_psc, a_shadow, a_active,
                 a_count, a_pcnt, a_pend, a_ovf} == '0);
            R_RST_4_RESET_OUTPUTS: assert final (irq == 1'b0);
        end
    end

    // All right-hand-side expressions are sampled in the access/event cycle.
    // Nonoverlapped implications compare against the following cycle.
    R_PRI_2_TMR_5_7_8_EN: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_en ==
            ($past(one_shot_expiration) ? 1'b0 :
             $past(write_ctrl) ? $past(PWDATA[0]) : $past(a_en)));

    R_PRI_6_CTRL_MODE: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_mode ==
            ($past(write_ctrl) ? $past(PWDATA[1]) : $past(a_mode)));

    R_PRI_6_CTRL_IE: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_ie ==
            ($past(write_ctrl) ? $past(PWDATA[2]) : $past(a_ie)));

    R_PRI_6_TMR_12_13_PSC: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_psc ==
            ($past(write_ctrl) ? $past(PWDATA[15:8]) : $past(a_psc)));

    R_PRI_7_TMR_11_SHADOW: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_shadow ==
            ($past(write_load) ? $past(PWDATA[15:0]) : $past(a_shadow)));

    R_PRI_3_TMR_2_3_4_5_7_9_ACTIVE: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_active ==
            ($past(reload_event) ? $past(a_shadow) : $past(a_active)));

    R_PRI_3_TMR_2_3_4_5_7_9_COUNT: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_count ==
            (($past(start_event) || $past(restart_event) ||
              ($past(expiration_event) && !$past(a_mode))) ? $past(a_shadow) :
             ($past(tick_event) && !$past(expiration_event)) ?
                ($past(a_count) - 16'd1) : $past(a_count)));

    R_PRI_3_TMR_1_2_7_9_13_PCNT: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_pcnt ==
            (($past(start_event) || $past(restart_event) || $past(tick_event)) ?
                8'd0 : $past(a_en) ? ($past(a_pcnt) + 8'd1) : $past(a_pcnt)));

    R_PRI_4_INT_1_2_5_PEND: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_pend ==
            ($past(expiration_event) ? 1'b1 :
             ($past(write_status) && $past(PWDATA[0])) ? 1'b0 :
             $past(a_pend)));

    R_PRI_5_INT_3_4_5_OVF: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        1'b1 |=> a_ovf ==
            (($past(expiration_event) && $past(a_pend)) ? 1'b1 :
             ($past(write_status) && $past(PWDATA[1])) ? 1'b0 :
             $past(a_ovf)));

    // Explicit simultaneous-event checks, including hardware-over-software priority.
    R_PRI_2_ONESHOT_CTRL_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (one_shot_expiration && write_ctrl && PWDATA[0]) |=> !a_en);

    R_PRI_3_RESTART_ONESHOT_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (one_shot_expiration && restart_event) |=>
            (!a_en && a_count == $past(a_shadow) &&
             a_active == $past(a_shadow) && a_pcnt == 8'd0 && a_pend));

    R_PRI_3_7_PERIODIC_LOAD_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (expiration_event && !a_mode && write_load) |=>
            (a_count == $past(a_shadow) && a_active == $past(a_shadow) &&
             a_shadow == $past(PWDATA[15:0])));

    R_PRI_4_PEND_CLEAR_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (expiration_event && write_status && PWDATA[0]) |=> a_pend);

    R_PRI_5_OVF_CLEAR_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (expiration_event && a_pend && write_status && PWDATA[1]) |=> a_ovf);

    R_PRI_3_PERIODIC_STOP_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (expiration_event && !a_mode && write_ctrl && !PWDATA[0]) |=>
            (!a_en && a_count == $past(a_shadow) && a_pend));

    R_PRI_3_TMR_8_STOP_TICK_COLLISION: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (tick_event && !expiration_event && write_ctrl && !PWDATA[0]) |=>
            (!a_en && a_count == ($past(a_count) - 16'd1)));

    R_APB_1_2_9_10_TMR_9_NO_CMD_ZERO: assert property (@(posedge PCLK)
        disable iff (!PRESETn)
        (write_cmd && !PWDATA[0] && !a_en) |=>
            (a_count == $past(a_count) && a_active == $past(a_active) &&
             a_pcnt == $past(a_pcnt)));

    R_RST_2_RESET_EDGE: assert property (@(posedge PCLK)
        (!PRESETn) |=> (!PRESETn ||
          ({a_en, a_mode, a_ie, a_psc, a_shadow, a_active,
            a_count, a_pcnt, a_pend, a_ovf} == '0)));

endmodule
