module rtl_gpt_2 (output logic [68:0] dbg,
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
    logic        start_event;
    logic        restart_event;
    logic        tick_event;
    logic        expire_event;

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

    assign start_event   = write_ctrl && PWDATA[0] && !en;
    assign restart_event = write_cmd && PWDATA[0];
    assign tick_event    = en && (pcnt >= psc);
    assign expire_event  = tick_event && (count == 16'h0000);

    always_comb begin
        PRDATA = 32'h00000000;
        if (access_cycle && !PWRITE && mapped) begin
            case (PADDR[7:2])
                6'h00: PRDATA = {16'h0000, psc, 5'b00000, ie, mode, en};
                6'h01: PRDATA = {16'h0000, shadow};
                6'h02: PRDATA = {16'h0000, count};
                6'h03: PRDATA = {30'h00000000, ovf, pend};
                6'h04: PRDATA = 32'h00000000;
                6'h05: PRDATA = {16'h0000, active};
                6'h06: PRDATA = {24'h000000, pcnt};
                default: PRDATA = 32'h00000000;
            endcase
        end
    end

    assign irq = pend && ie;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            en     <= 1'b0;
            mode   <= 1'b0;
            ie     <= 1'b0;
            psc    <= 8'h00;
            shadow <= 16'h0000;
            active <= 16'h0000;
            count  <= 16'h0000;
            pcnt   <= 8'h00;
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

            if (expire_event && mode)
                en <= 1'b0;
            else if (write_ctrl)
                en <= PWDATA[0];

            if (start_event || restart_event) begin
                active <= shadow;
                count  <= shadow;
                pcnt   <= 8'h00;
            end else if (en) begin
                if (tick_event) begin
                    pcnt <= 8'h00;
                    if (expire_event) begin
                        if (!mode) begin
                            active <= shadow;
                            count  <= shadow;
                        end
                    end else begin
                        count <= count - 16'h0001;
                    end
                end else begin
                    pcnt <= pcnt + 8'h01;
                end
            end

            if (expire_event)
                pend <= 1'b1;
            else if (write_status && PWDATA[0])
                pend <= 1'b0;

            if (expire_event && pend)
                ovf <= 1'b1;
            else if (write_status && PWDATA[1])
                ovf <= 1'b0;
        end
    end
assign dbg = {en,mode,ie,psc,shadow,active,count,pcnt,pend,ovf};
endmodule
