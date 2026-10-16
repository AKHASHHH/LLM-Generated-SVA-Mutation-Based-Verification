
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

    // Compatibility with the existing testbench.
    // These internal signals are deliberately NOT used.
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

    localparam logic [5:0] CTRL  = 6'h00;
    localparam logic [5:0] PSCNT = 6'h06;

    // Detect successful APB transactions.
    wire ctrl_write =
        PSEL && PENABLE && PWRITE &&
        PREADY && !PSLVERR &&
        (PADDR[7:2] == CTRL);

    wire pscnt_read =
        PSEL && PENABLE && !PWRITE &&
        PREADY && !PSLVERR &&
        (PADDR[7:2] == PSCNT);

    // Checker state derived only from APB transactions.
    logic [7:0] tracked_psc;
    logic       periodic_running;
    logic [2:0] settle_cycles;

    // Track software-written timer configuration.
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tracked_psc      <= 8'd0;
            periodic_running <= 1'b0;
            settle_cycles    <= 3'd0;
        end
        else begin
            if (ctrl_write) begin
                tracked_psc <= PWDATA[15:8];

                // Continuous operation is guaranteed in periodic mode
                // after the CTRL write establishes EN=1, MODE=0.
                periodic_running <= PWDATA[0] && !PWDATA[1];

                // Suppress checking while the PSC update takes effect.
                settle_cycles <= 3'd0;
            end
            else if (periodic_running &&
                     settle_cycles < 3'd3) begin
                settle_cycles <= settle_cycles + 3'd1;
            end
        end
    end

    // Wait until the updated threshold has taken effect.
    wire safe_to_check =
        periodic_running &&
        (settle_cycles == 3'd3);

    // H1: Once periodic operation is established and configuration
    // is settled, the prescaler counter must not exceed PSC.
    //
    // PSCNT read exposes PCNT through PRDATA[7:0].
    // The assertion checks the read in the same sampled cycle.
    H1_prescaler_bound: assert property (
        @(posedge PCLK)
        disable iff (!PRESETn)
        (pscnt_read && safe_to_check)
        |-> (PRDATA[7:0] <= tracked_psc)
    );

endmodule

