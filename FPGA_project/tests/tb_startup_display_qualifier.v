`timescale 1ns/1ps
module tb_startup_display_qualifier;
    reg clk=0,rst=1,complete=0,normal=1,vs=0,de=0,pixel_ready=1,hdmi=0;
    always #5 clk=~clk;
    wire ready;
    wire [8:0] bar=ready?9'd511:9'd0;
    startup_display_qualifier dut(.clk(clk),.rst(rst),.image_complete(complete),
        .normal_active(normal),.frame_sync(vs),.pixel_de(de),.pixel_ready(pixel_ready),
        .hdmi_ready(hdmi),.display_ready(ready));
    task boundary;begin
        @(negedge clk);de=0;vs=1;repeat(3)@(negedge clk);vs=0;
        repeat(3)@(negedge clk);
    end endtask
    task pixels(input bad);begin
        @(negedge clk);de=1;pixel_ready=1;repeat(5)@(negedge clk);
        pixel_ready=!bad;@(negedge clk);pixel_ready=1;
        repeat(5)@(negedge clk);de=0;
    end endtask
    task require_zero;begin
        if(ready || bar!==0)$fatal(1,"Unqualified display advertised completion");
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;hdmi=1;
        pixels(0);boundary;pixels(0);boundary;require_zero;
        // Incomplete first raster after cache commit must not count.
        complete=1;pixels(0);boundary;require_zero;
        pixels(0);boundary;require_zero;
        pixels(0);boundary;if(!ready)$fatal(1,"Two full clean frames did not qualify");
        // A missing source row clears readiness at the next frame boundary.
        pixels(1);boundary;require_zero;
        pixels(0);boundary;require_zero;
        pixels(0);boundary;if(!ready)$fatal(1,"Read recovery did not requalify");
        // HDMI readiness is independent from successful card/cache loading.
        hdmi=0;repeat(3)@(negedge clk);require_zero;
        pixels(0);boundary;require_zero;
        hdmi=1;pixels(0);boundary;if(!ready)$fatal(1,"HDMI relock did not restore ready");
        // Map mode ignores the inactive normal-image reader.
        normal=0;pixel_ready=0;boundary;boundary;
        if(!ready)$fatal(1,"Inactive image reader invalidated map display");
        hdmi=0;repeat(3)@(negedge clk);require_zero;
        hdmi=1;boundary;if(!ready)$fatal(1,"Map-mode HDMI relock lost validated cache");
        normal=1;pixel_ready=1;boundary; // re-arm at a normal-frame boundary
        boundary;require_zero; // no active pixels is not a clean frame
        pixels(0);boundary;require_zero;pixels(0);boundary;
        if(!ready)$fatal(1,"Normal-mode qualification did not recover");
        complete=0;repeat(3)@(negedge clk);require_zero;
        $display("PASS: zero progress until committed image, two complete clean frames and HDMI ready; partial first frame rejected, missing row/empty frame recovery, HDMI loss/relock, inactive map reader and cache reset");
        $finish;
    end
    initial begin #100000;$fatal(1,"Qualifier timeout");end
endmodule
