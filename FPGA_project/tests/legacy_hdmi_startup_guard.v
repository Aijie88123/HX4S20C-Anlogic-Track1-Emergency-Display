module legacy_hdmi_startup_guard #(
    parameter integer SETTLE_FRAMES=16,UNLOCK_FRAMES=180
)(input clk,async_reset,memory_ready,frame_sync,video_locked,
  output reg output_reset=1'b1,output wire video_ready);
    localparam MAX_FRAMES=SETTLE_FRAMES>UNLOCK_FRAMES?SETTLE_FRAMES:UNLOCK_FRAMES;
    localparam CW=$clog2(MAX_FRAMES)>0?$clog2(MAX_FRAMES):1;
    reg [CW-1:0] frames;
    reg [1:0] ready_sync,lock_sync;
    reg frame_d;
    wire frame_edge=frame_sync&&!frame_d;
    assign video_ready=!output_reset && ready_sync[1] && lock_sync[1];
    always @(posedge clk or posedge async_reset)
      if(async_reset)begin
        output_reset<=1;frames<=0;ready_sync<=0;lock_sync<=0;frame_d<=0;
      end else begin
        ready_sync<={ready_sync[0],memory_ready};
        lock_sync<={lock_sync[0],video_locked};frame_d<=frame_sync;
        if(!ready_sync[1])begin output_reset<=1;frames<=0;end
        else if(frame_edge)begin
          if(output_reset)begin
            if(frames==SETTLE_FRAMES-1)begin output_reset<=0;frames<=0;end
            else frames<=frames+1'b1;
          end else if(lock_sync[1])frames<=0;
          else if(frames==UNLOCK_FRAMES-1)begin output_reset<=1;frames<=0;end
          else frames<=frames+1'b1;
        end
      end
endmodule
