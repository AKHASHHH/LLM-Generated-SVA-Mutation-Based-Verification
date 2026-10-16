module rtl_gpt_1 (output logic [68:0] dbg,
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

    logic        en;
    logic        mode;
    logic        ie;
    logic [7:0]  psc;
    logic [15:0] shadow;
    logic [15:0] active;
    logic [15:0] count;
    logic [7:0]  pcnt;
    logic        pend;
    logic        ovf;

    logic        access_cycle;
    logic        mapped;
    logic        read_only;
    logic        write_ctrl;
    logic        write_load;
    logic        write_status;
    logic        write_cmd;
    logic        start;
    logic        restart_cmd;
    logic        tick;
    logic        expire;

    assign access_cycle = PSEL && PENABLE;
    assign mapped = (PADDR[7:2] <= 6'h06);
    assign read_only = (PADDR[7:2] == 6'h02) ||
                       (PADDR[7:2] == 6'h05) ||
                       (PADDR[7:2] == 6'h06);
    assign PREADY = 1'b1;
    assign PSLVERR = access_cycle && (!mapped || (PWRITE && read_only));

    assign write_ctrl   = access_cycle && PWRITE && !PSLVERR && (PADDR[7:2] == 6'h00);
    assign write_load   = access_cycle && PWRITE && !PSLVERR && (PADDR[7:2] == 6'h01);
    assign write_status = access_cycle && PWRITE && !PSLVERR && (PADDR[7:2] == 6'h03);
    assign write_cmd    = access_cycle && PWRITE && !PSLVERR && (PADDR[7:2] == 6'h04);

    assign start       = write_ctrl && PWDATA[0] && !en;
    assign restart_cmd = write_cmd && PWDATA[0];
    assign tick        = en && (pcnt >= psc);
    assign expire      = tick && (count == 16'h0000);
    assign irq         = pend && ie;

    always_comb begin
        PRDATA = 32'h00000000;
        if (access_cycle && !PWRITE) begin
            case (PADDR[7:2])
                6'h00: PRDATA = {16'b0, psc, 5'b0, ie, mode, en};
                6'h01: PRDATA = {16'b0, shadow};
                6'h02: PRDATA = {16'b0, count};
                6'h03: PRDATA = {30'b0, ovf, pend};
                6'h04: PRDATA = 32'b0;
                6'h05: PRDATA = {16'b0, active};
                6'h06: PRDATA = {24'b0, pcnt};
                default: PRDATA = 32'b0;
            endcase
        end
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            en     <= 1'b0;
            mode   <= 1'b0;
            ie     <= 1'b0;
            psc    <= 8'b0;
            shadow <= 16'b0;
            active <= 16'b0;
            count  <= 16'b0;
            pcnt   <= 8'b0;
            pend   <= 1'b0;
            ovf    <= 1'b0;
        end else begin
            if (write_ctrl) begin
                mode <= PWDATA[1];
                ie   <= PWDATA[2];
                psc  <= PWDATA[15:8];
            end
            if (write_load)
                shadow <= PWDATA[15:0];

            if (expire && mode)
                en <= 1'b0;
            else if (write_ctrl)
                en <= PWDATA[0];

            if (start || restart_cmd) begin
                active <= shadow;
                count  <= shadow;
                pcnt   <= 8'b0;
            end else if (en) begin
                if (tick) begin
                    pcnt <= 8'b0;
                    if (expire) begin
                        if (!mode) begin
                            active <= shadow;
                            count  <= shadow;
                        end
                    end else begin
                        count <= count - 16'd1;
                    end
                end else begin
                    pcnt <= pcnt + 8'd1;
                end
            end

            if (expire)
                pend <= 1'b1;
            else if (write_status && PWDATA[0])
                pend <= 1'b0;

            if (expire && pend)
                ovf <= 1'b1;
            else if (write_status && PWDATA[1])
                ovf <= 1'b0;
        end
    end
assign dbg = {en,mode,ie,psc,shadow,active,count,pcnt,pend,ovf};
endmodule
