`timescale 1ns/1ps

module phase_four_fx_check;
    reg [11:0] x;
    reg [11:0] y;
    reg [2:0] fx_sel;
    wire [7:0] phase_new [0:4];
    wire [7:0] phase_parent [0:4];
    integer px;
    integer py;
    integer mode;
    integer setting;
    integer checks;
    integer retained_checks;
    integer disabled_checks;

    genvar p;
    generate
        for (p = 0; p < 5; p = p + 1) begin : spread_cases
            localparam [7:0] LIMIT = (p == 0) ? 8'd128 :
                                    (p == 1) ? 8'd0 :
                                    (p == 2) ? 8'd17 :
                                    (p == 3) ? 8'd127 : 8'd255;
            transition_fx #(.SPREAD(LIMIT)) candidate (
                .x(x), .y(y), .fx_sel(fx_sel), .phase(phase_new[p])
            );
            transition_fx_phase_trim_parent #(.SPREAD(LIMIT)) parent (
                .x(x), .y(y), .fx_sel(fx_sel), .phase(phase_parent[p])
            );
        end
    endgenerate

    initial begin
        x = 0;
        y = 0;
        fx_sel = 0;
        checks = 0;
        retained_checks = 0;
        disabled_checks = 0;
        for (mode = 0; mode < 8; mode = mode + 1) begin
            fx_sel = mode;
            for (py = 0; py < 720; py = py + 1) begin
                y = py;
                for (px = 0; px < 1280; px = px + 1) begin
                    x = px;
                    #1;
                    for (setting = 0; setting < 5; setting = setting + 1) begin
                        if (mode == 3) begin
                            if (phase_new[setting] !== phase_parent[setting])
                                $fatal(1, "phase mismatch fx=%0d x=%0d y=%0d setting=%0d new=%0d parent=%0d",
                                       mode, px, py, setting,
                                       phase_new[setting], phase_parent[setting]);
                            retained_checks = retained_checks + 1;
                        end else begin
                            if (phase_new[setting] !== 8'd0)
                                $fatal(1, "disabled phase nonzero fx=%0d x=%0d y=%0d setting=%0d phase=%0d",
                                       mode, px, py, setting, phase_new[setting]);
                            disabled_checks = disabled_checks + 1;
                        end
                        checks = checks + 1;
                    end
                end
            end
        end
        $display("PHASE_NO_BLINDS_PASS checks=%0d retained=%0d disabled=%0d width=1280 height=720 spreads=128,0,17,127,255",
                 checks, retained_checks, disabled_checks);
        $finish;
    end
endmodule
