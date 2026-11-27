module memory_startup_reset (
    input wire clk,
    input wire async_rst,
    output wire rst
);
    reg [15:0] release_pipe = 16'hffff;
    always @(posedge clk or posedge async_rst) begin
        if(async_rst) release_pipe <= 16'hffff;
        else release_pipe <= {release_pipe[14:0], 1'b0};
    end
    assign rst = async_rst | release_pipe[15];
endmodule
