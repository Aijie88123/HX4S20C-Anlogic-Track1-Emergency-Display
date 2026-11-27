`timescale 1ns/1ps
// Prepare an inactive colour bank, then commit its bank and OSD registers at VS.
// Bank zero is immutable identity, so reset never exposes a previously edited LUT.
module display_parameter_control (
 input wire clk,rst,emergency,vsync,
 input wire brightness_step_toggle,contrast_step_toggle,
 output reg [2:0] brightness,contrast,
 output reg [1:0] palette_bank,
 output wire palette_write_enable,
 output wire [9:0] palette_write_address,
 output wire [7:0] palette_write_value
);
 reg [2:0] brightness_sync,contrast_sync;
 reg [2:0] brightness_pending,contrast_pending;
 reg vsync_d;
 wire brightness_step=brightness_sync[2]^brightness_sync[1];
 wire contrast_step=contrast_sync[2]^contrast_sync[1];
 wire [2:0] brightness_next=brightness_pending+((!emergency && brightness_step)?3'd1:3'd0);
 wire [2:0] contrast_next=contrast_pending+((!emergency && contrast_step)?3'd1:3'd0);
 localparam IDLE=2'd0,BUILD=2'd1,READY=2'd2;
 reg [1:0] state,write_bank;
 reg [2:0] target_b,target_c;
 reg [7:0] index;
 wire [23:0] generated;
 video_enhance u_palette_generator(.in_rgb({index,index,index}),
   .brightness(target_b),.contrast(target_c),.out_rgb(generated));
 assign palette_write_enable=(state==BUILD)&&!rst;
 assign palette_write_address={write_bank,index};
 assign palette_write_value=generated[7:0];
 always @(posedge clk or posedge rst)
  if(rst)begin
   brightness_sync<=0;contrast_sync<=0;
   brightness_pending<=3'd4;contrast_pending<=3'd4;
   brightness<=3'd4;contrast<=3'd4;vsync_d<=1;
   palette_bank<=0;state<=IDLE;write_bank<=1;
   target_b<=4;target_c<=4;index<=0;
  end else begin
   brightness_sync<={brightness_sync[1:0],brightness_step_toggle};
   contrast_sync<={contrast_sync[1:0],contrast_step_toggle};
   brightness_pending<=brightness_next;contrast_pending<=contrast_next;
   vsync_d<=vsync;
   case(state)
    IDLE:if(!emergency&&({brightness_next,contrast_next}!={brightness,contrast}))begin
     target_b<=brightness_next;target_c<=contrast_next;index<=0;
     write_bank<=(palette_bank==1)?2'd2:2'd1;state<=BUILD;
    end
    BUILD:if(index==255)begin
     if({brightness_next,contrast_next}!={target_b,target_c})begin
      target_b<=brightness_next;target_c<=contrast_next;index<=0;
     end else state<=READY;
    end else index<=index+1'b1;
    READY:if({brightness_next,contrast_next}!={target_b,target_c})begin
     target_b<=brightness_next;target_c<=contrast_next;index<=0;state<=BUILD;
    end else if(vsync_d&&!vsync&&!emergency)begin
     brightness<=target_b;contrast<=target_c;palette_bank<=write_bank;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
endmodule
