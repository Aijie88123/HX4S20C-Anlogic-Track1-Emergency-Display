`timescale 1ns/1ps
module tb_startup_display_scanout;
    reg clk=0,rst=1,reader_enabled=0;
    always #5 clk=~clk;
    wire req,hs,vs,de,pixel_ready,qualified;
    wire [23:0] rgb;
    integer frames=0,good_pixels=0,bad_pixels=0;
    reg oldvs=0;
    video_scanout_720p scan(.clk(clk),.rst(rst),.read_req(req),
        .read_req_ack(req&&reader_enabled),.read_en(),.read_data(32'h44556600),
        .read_empty(1'b0),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
        .pixel_ready(pixel_ready),.raw_hs(),.raw_vs(),.raw_de(),
        .raw_frame_start(),.raw_x(),.raw_y());
    startup_display_qualifier dut(.clk(clk),.rst(rst),.image_complete(1'b1),
        .normal_active(1'b1),.frame_sync(vs),.pixel_de(de),.pixel_ready(pixel_ready),
        .hdmi_ready(1'b1),.display_ready(qualified));
    always @(posedge clk) begin
        if(!rst)begin
            if(vs&&!oldvs)frames<=frames+1;
            if(de)begin
                if(reader_enabled && pixel_ready)begin
                    if(rgb!==24'h445566)$fatal(1,"Ready pixel did not match FIFO source rgb=%h frame=%0d",rgb,frames);
                    good_pixels<=good_pixels+1;
                end
                if(!pixel_ready)bad_pixels<=bad_pixels+1;
            end
        end
        oldvs<=vs;
    end
    initial begin
        repeat(8)@(negedge clk);rst=0;
        wait(frames==2);repeat(10)@(negedge clk);
        if(qualified || bad_pixels==0)$fatal(1,"Unacknowledged SDRAM reader reported ready");
        @(negedge clk);reader_enabled=1;
        wait(frames==5);repeat(10)@(negedge clk);
        if(!qualified || good_pixels<1843200)$fatal(1,"Healthy full scanout failed qualification pixels=%0d",good_pixels);
        reader_enabled=0;
        wait(frames==7);repeat(10)@(negedge clk);
        if(qualified)$fatal(1,"Missing SDRAM frame did not clear qualification");
        reader_enabled=1;
        wait(frames==10);repeat(10)@(negedge clk);
        if(!qualified)$fatal(1,"SDRAM reader recovery failed");
        $display("PASS: actual 1280x720 scanout qualification, %0d exact healthy RGB pixels, %0d missing-row pixels rejected, SDRAM no-ACK and full recovery; pixel readiness aligned with output DE/RGB",good_pixels,bad_pixels);
        $finish;
    end
    initial begin #140000000;$fatal(1,"Full scanout qualification timeout");end
endmodule
