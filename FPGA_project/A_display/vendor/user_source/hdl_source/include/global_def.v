


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Parenthesize macros before substitution: without this, 64000000 /
// SDR_CLK_PERIOD expands to 64000000 / 1000000000 / 125000000 = 0.
// 125 MHz -> 8 ns. Target 32 ms (1953 clocks/row), retaining margin
// for refresh deferred while the encrypted controller drains a burst.
`define   SDR_CLK_PERIOD                   (1000000000/125000000)
`define   SELF_REFRESH_INTERVAL            (32000000/`SDR_CLK_PERIOD/(2**(`ROW_WIDTH)))

