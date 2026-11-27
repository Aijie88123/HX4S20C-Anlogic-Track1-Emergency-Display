`timescale 1ns/1ps
// A held-data mailbox with request/acknowledge toggles. The source samples
// the scheduler's committed page, never its in-flight load target. The audio
// side acknowledges only when the next complete stereo sample begins.
// A burst while busy retains the newest waiting page; normal video commits
// are many audio samples apart. Both domains share the system reset.
module image_audio_commit_cdc (
    input wire src_clk,
    input wire dst_clk,
    input wire rst,
    input wire src_commit_toggle,
    input wire [2:0] src_page,
    input wire src_valid,
    input wire src_emergency,
    input wire dst_sample_tick,
    output reg [2:0] dst_page,
    output reg dst_pending,
    output reg dst_emergency
);
    reg src_seen;
    reg held_emergency,waiting_emergency;
    reg [2:0] held_page;
    reg req_toggle;
    reg [1:0] ack_sync;
    reg waiting;
    reg [2:0] waiting_page;
    reg [2:0] req_sync;
    reg ack_toggle;
    wire new_commit = (src_commit_toggle != src_seen) && src_valid;

    always @(posedge src_clk or posedge rst) begin
        if (rst) begin
            src_seen <= 1'b0;
            held_page <= 3'd0;
            held_emergency <= 1'b0;
            waiting_emergency <= 1'b0;
            req_toggle <= 1'b0;
            ack_sync <= 2'b00;
            waiting <= 1'b0;
            waiting_page <= 3'd0;
        end else begin
            src_seen <= src_commit_toggle;
            ack_sync <= {ack_sync[0], ack_toggle};
            if (req_toggle == ack_sync[1]) begin
                if (new_commit || waiting) begin
                    held_page <= new_commit ? src_page : waiting_page;
                    held_emergency <= new_commit ? src_emergency : waiting_emergency;
                    req_toggle <= ~req_toggle;
                    waiting <= 1'b0;
                end
            end else if (new_commit) begin
                waiting <= 1'b1;
                waiting_page <= src_page;
                waiting_emergency <= src_emergency;
            end
        end
    end

    always @(posedge dst_clk or posedge rst) begin
        if (rst) begin
            req_sync <= 3'b000;
            ack_toggle <= 1'b0;
            dst_page <= 3'd0;
            dst_emergency <= 1'b0;
            dst_pending <= 1'b0;
        end else begin
            req_sync <= {req_sync[1:0], req_toggle};
            if (!dst_pending && (req_sync[2] != ack_toggle)) begin
                // held_page has been stable for at least three dst clocks,
                // and remains held until this sample-boundary acknowledgment.
                dst_page <= held_page;
                dst_emergency <= held_emergency;
                dst_pending <= 1'b1;
            end
            if (dst_pending && dst_sample_tick) begin
                dst_pending <= 1'b0;
                ack_toggle <= req_sync[2];
            end
        end
    end
endmodule
