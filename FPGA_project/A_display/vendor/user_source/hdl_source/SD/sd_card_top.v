
module sd_card_top
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // SD card low speed mode frequency division parameter,spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter  SPI_HIGH_SPEED_DIV = 0,          // SD card high speed mode frequency division parameter,spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer POWERUP_WAIT_MS = 100,
    parameter integer INIT_TIMEOUT_MS = 2000
)
(
	input            clk,
	input            rst,
	output           SD_nCS,                    //SD card chip select (SPI mode)
	output           SD_DCLK,                   //SD card clock
	output           SD_MOSI,                   //SD card controller data output
	input            SD_MISO,                   //SD card controller data input
	output           sd_init_done,              //SD card initialization is complete
	input            sd_sec_read,               //SD card sector read
	input[31:0]      sd_sec_read_addr,          //SD card sector read address
	output[7:0]      sd_sec_read_data,          //SD card sector read data
	output           sd_sec_read_data_valid,    //SD card sector read data valid
	output           sd_sec_read_end,           //SD card sector read end
	input            sd_sec_write,              //SD card sector write
	input[31:0]      sd_sec_write_addr,         //SD card sector write address
	input[7:0]       sd_sec_write_data,         //SD card sector write data
	output           sd_sec_write_data_req,     //SD card sector write data next clock is valid
	output           sd_sec_write_end           //SD card sector write end
);
wire[15:0]           spi_clk_div;               //SPI module clock division parameter
wire                 cmd_req;                   //SD card command request
wire                 cmd_req_ack;               //SD card command request response
wire                 cmd_req_error;             //SD card command request error
wire[47:0]           cmd;                       //SD card command
wire[7:0]            cmd_r1;                    //SD card expect response
wire[15:0]           cmd_data_len;              //SD card command read data length
wire                 block_read_req;            //SD card sector data read request
wire                 block_read_valid;          //SD card sector data read data valid
wire[7:0]            block_read_data;           //SD card sector data read data
wire                 block_read_req_ack;        //SD card sector data read response
wire                 block_write_req;           //SD card sector data write request
wire[7:0]            block_write_data;          //SD card sector data write data next clock is valid
wire                 block_write_data_rd;       //SD card sector data write data
wire                 block_write_req_ack;       //SD card sector data write response

wire                 nCS_ctrl;                  //SPI module chip select control
wire                 spi_wr_req;                //SPI module data sending request
wire                 spi_wr_ack;                //SPI module data request response
wire[7:0]            spi_data_in;               //SPI module send data
wire[7:0]            spi_data_out;              //SPI module data returned
wire[15:0]           clk_div;
wire controller_rst;
wire spi_mosi;
assign SD_MOSI = controller_rst ? 1'b1 : spi_mosi;
// Only the TF transport is restarted. A failed cold initialization must
// recover before sd_init_done, without resetting the HDMI/SDRAM system.
sd_startup_guard #(.CLK_FREQ_HZ(CLK_FREQ_HZ),
    .POWERUP_WAIT_MS(POWERUP_WAIT_MS), .INIT_TIMEOUT_MS(INIT_TIMEOUT_MS))
u_startup_guard (.clk(clk), .rst(rst), .init_done(sd_init_done),
                 .controller_rst(controller_rst));
sd_card_sec_read_write
#(
	.SPI_LOW_SPEED_DIV(SPI_LOW_SPEED_DIV),
	.SPI_HIGH_SPEED_DIV(SPI_HIGH_SPEED_DIV)
)
sd_card_sec_read_write_m0(
	.clk                            (clk                    ),
	.rst                            (controller_rst         ),
	.sd_init_done                   (sd_init_done           ),
	.sd_sec_read                    (sd_sec_read            ),
	.sd_sec_read_addr               (sd_sec_read_addr       ),
	.sd_sec_read_data               (sd_sec_read_data       ),
	.sd_sec_read_data_valid         (sd_sec_read_data_valid ),
	.sd_sec_read_end                (sd_sec_read_end        ),
	.sd_sec_write                   (sd_sec_write           ),
	.sd_sec_write_addr              (sd_sec_write_addr      ),
	.sd_sec_write_data              (sd_sec_write_data      ),
	.sd_sec_write_data_req          (sd_sec_write_data_req  ),
	.sd_sec_write_end               (sd_sec_write_end       ),
	.spi_clk_div                    (spi_clk_div            ),
	.cmd_req                        (cmd_req                ),
	.cmd_req_ack                    (cmd_req_ack            ),
	.cmd_req_error                  (cmd_req_error          ),
	.cmd                            (cmd                    ),
	.cmd_r1                         (cmd_r1                 ),
	.cmd_data_len                   (cmd_data_len           ),
	.block_read_req                 (block_read_req         ),
	.block_read_valid               (block_read_valid       ),
	.block_read_data                (block_read_data        ),
	.block_read_req_ack             (block_read_req_ack     ),
	.block_write_req                (block_write_req        ),
	.block_write_data               (block_write_data       ),
	.block_write_data_rd            (block_write_data_rd    ),
	.block_write_req_ack            (block_write_req_ack    )
);

sd_card_cmd sd_card_cmd_m0(
	.sys_clk                        (clk                    ),
	.rst                            (controller_rst         ),
	.spi_clk_div                    (spi_clk_div            ),
	.cmd_req                        (cmd_req                ),
	.cmd_req_ack                    (cmd_req_ack            ),
	.cmd_req_error                  (cmd_req_error          ),
	.cmd                            (cmd                    ),
	.cmd_r1                         (cmd_r1                 ),
	.cmd_data_len                   (cmd_data_len           ),
	.block_read_req                 (block_read_req         ),
	.block_read_req_ack             (block_read_req_ack     ),
	.block_read_data                (block_read_data        ),
	.block_read_valid               (block_read_valid       ),
	.block_write_req                (block_write_req        ),
	.block_write_data               (block_write_data       ),
	.block_write_data_rd            (block_write_data_rd    ),
	.block_write_req_ack            (block_write_req_ack    ),
	.nCS_ctrl                       (nCS_ctrl               ),
	.clk_div                        (clk_div                ),
	.spi_wr_req                     (spi_wr_req             ),
	.spi_wr_ack                     (spi_wr_ack             ),
	.spi_data_in                    (spi_data_in            ),
	.spi_data_out                   (spi_data_out           )

);

spi_master spi_master_m0(
	.sys_clk                        (clk                    ),
	.rst                            (controller_rst         ),
	.nCS                            (SD_nCS                 ),
	.DCLK                           (SD_DCLK                ),
	.MOSI                           (spi_mosi               ),
	.MISO                           (SD_MISO                ),
	.clk_div                        (clk_div                ),
	.CPOL                           (1'b1                   ),
	.CPHA                           (1'b1                   ),
	.nCS_ctrl                       (nCS_ctrl               ),
	.wr_req                         (spi_wr_req             ),
	.wr_ack                         (spi_wr_ack             ),
	.data_in                        (spi_data_in            ),
	.data_out                       (spi_data_out           )
);
endmodule

module sd_startup_guard #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer POWERUP_WAIT_MS = 100,
    parameter integer INIT_TIMEOUT_MS = 2000
)(input wire clk, rst, init_done, output wire controller_rst);
    localparam integer WAIT_TICKS_RAW = (CLK_FREQ_HZ / 1000) * POWERUP_WAIT_MS;
    localparam integer WAIT_TICKS = WAIT_TICKS_RAW > 0 ? WAIT_TICKS_RAW : 1;
    localparam integer TIMEOUT_TICKS_RAW = (CLK_FREQ_HZ / 1000) * INIT_TIMEOUT_MS;
    localparam integer TIMEOUT_TICKS = TIMEOUT_TICKS_RAW > 0 ? TIMEOUT_TICKS_RAW : 1;
    localparam integer WAIT_BITS = WAIT_TICKS > 1 ? $clog2(WAIT_TICKS) : 1;
    localparam integer TIMEOUT_BITS = TIMEOUT_TICKS > 1 ? $clog2(TIMEOUT_TICKS) : 1;
    reg [WAIT_BITS-1:0] wait_count;
    reg [TIMEOUT_BITS-1:0] init_count;
    reg controller_run;
    assign controller_rst = rst | ~controller_run;
    always @(posedge clk or posedge rst) begin
        if(rst)begin
            controller_run <= 1'b0;
            wait_count <= WAIT_TICKS - 1;
            init_count <= 0;
        end else if(!controller_run)begin
            init_count <= 0;
            if(wait_count == 0) controller_run <= 1'b1;
            else wait_count <= wait_count - 1'b1;
        end else if(init_done)begin
            init_count <= 0;
        end else if(INIT_TIMEOUT_MS != 0)begin
            if(init_count == TIMEOUT_TICKS - 1)begin
                // Reset the SPI shifter and both command FSMs together,
                // wait for card settling, then send the idle clocks again.
                controller_run <= 1'b0;
                wait_count <= WAIT_TICKS - 1;
                init_count <= 0;
            end else init_count <= init_count + 1'b1;
        end
    end
endmodule
