
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

    // Testbench compatibility only.
    // No internal DUT signals are used by H1 or H2.
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

    // =========================================================
    // APB register addresses
    // =========================================================

    localparam logic [5:0] CTRL_REG   = 6'h00;
    localparam logic [5:0] LOAD_REG   = 6'h01;
    localparam logic [5:0] STATUS_REG = 6'h03;
    localparam logic [5:0] PSCNT_REG  = 6'h06;

    // =========================================================
    // APB transaction decoding
    // =========================================================

    wire apb_read =
        PSEL && PENABLE && !PWRITE &&
        PREADY && !PSLVERR;

    wire apb_write =
        PSEL && PENABLE && PWRITE &&
        PREADY && !PSLVERR;

    wire ctrl_write =
        apb_write && (PADDR[7:2] == CTRL_REG);

    wire load_write =
        apb_write && (PADDR[7:2] == LOAD_REG);

    wire status_write =
        apb_write && (PADDR[7:2] == STATUS_REG);

    wire pscnt_read =
        apb_read && (PADDR[7:2] == PSCNT_REG);

    // =========================================================
    // H1: Prescaler bound
    // =========================================================

    logic [7:0] tracked_psc;
    logic       periodic_running;
    logic [2:0] settle_cycles;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tracked_psc      <= 8'd0;
            periodic_running <= 1'b0;
            settle_cycles    <= 3'd0;
        end
        else begin
            if (ctrl_write) begin
                tracked_psc <= PWDATA[15:8];

                // Only use intervals known to be periodic.
                periodic_running <=
                    PWDATA[0] && !PWDATA[1];

                // Allow the new PSC threshold to take effect.
                settle_cycles <= 3'd0;
            end
            else if (periodic_running &&
                     settle_cycles < 3'd3) begin
                settle_cycles <= settle_cycles + 3'd1;
            end
        end
    end

    wire safe_to_check =
        periodic_running &&
        (settle_cycles == 3'd3);

    // Under stable periodic operation, a PSCNT read must
    // never return a value above the programmed threshold.
    H1_prescaler_bound: assert property (
        @(posedge PCLK)
        disable iff (!PRESETn)
        (pscnt_read && safe_to_check)
        |-> (PRDATA[7:0] <= tracked_psc)
    );

    // =========================================================
    // H2: Pending flag independence from interrupt enable
    // =========================================================

    logic [15:0] h2_shadow;
    logic        h2_known_stopped;
    logic        h2_arm;
    logic        h2_expect_pend;
    logic        h2_ie;

    // A software write with PEND clear requested.
    wire h2_pend_clear =
        status_write && PWDATA[0];

    // A known one-shot start:
    // LOAD=0, PSC=0, MODE=1, IE=0, EN=1.
    //
    // This ensures expiration during the first enabled cycle.
    wire h2_known_start =
        ctrl_write &&
        h2_known_stopped &&
        (h2_shadow == 16'd0) &&
        (PWDATA[15:8] == 8'd0) &&
        (PWDATA[2:0] == 3'b011);

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            h2_shadow        <= 16'd0;
            h2_known_stopped <= 1'b1;
            h2_arm           <= 1'b0;
            h2_expect_pend   <= 1'b0;
            h2_ie            <= 1'b0;
        end
        else begin
            if (load_write)
                h2_shadow <= PWDATA[15:0];

            if (ctrl_write) begin
                h2_ie <= PWDATA[2];

                // A write that disables EN guarantees stopped
                // operation on the following cycle.
                h2_known_stopped <= !PWDATA[0];
            end

            // Recognize the start on the next clock.
            h2_arm <= h2_known_start;

            // Expiration is guaranteed in the first enabled
            // cycle for this known configuration.
            if (h2_arm) begin
                h2_expect_pend   <= 1'b1;
                h2_known_stopped <= 1'b1;
            end
            else if (h2_pend_clear) begin
                h2_expect_pend <= 1'b0;
            end
        end
    end

    // Once PEND must be set, enabling IE must assert irq.
    // No internal PEND or IE signal is inspected.
    H2_pending_mask_independence: assert property (
        @(posedge PCLK)
        disable iff (!PRESETn)
        (h2_expect_pend && h2_ie)
        |-> (irq === 1'b1)
    );

endmodule

