/// sta-blackbox

`default_nettype wire

module RAM32 (
`ifdef USE_POWER_PINS
    input VPWR,
    input VGND,
`endif
    input CLK,
    input [3:0] WE0,
    input EN0,
    input [4:0] A0,
    input [31:0] Di0,
    output reg [31:0] Do0
);
  reg [31:0] RAM[31:0];

  // Read during write of the same word: the DFFRAM macro's storage is
  // latches written in the clock after the inputs are sampled and read
  // through a combinational mux, so Do0 shows the byte just written
  // (write-first).  The TT07 read-modify-write cache bug depended on it.
  always @(posedge CLK)
    if (EN0) begin
      Do0[7:0]   <= WE0[0] ? Di0[7:0]   : RAM[A0][7:0];
      Do0[15:8]  <= WE0[1] ? Di0[15:8]  : RAM[A0][15:8];
      Do0[23:16] <= WE0[2] ? Di0[23:16] : RAM[A0][23:16];
      Do0[31:24] <= WE0[3] ? Di0[31:24] : RAM[A0][31:24];
      if (WE0[0]) RAM[A0][7:0] <= Di0[7:0];
      if (WE0[1]) RAM[A0][15:8] <= Di0[15:8];
      if (WE0[2]) RAM[A0][23:16] <= Di0[23:16];
      if (WE0[3]) RAM[A0][31:24] <= Di0[31:24];
    end else begin
      Do0 <= 32'b0;
    end

endmodule
