module   sky130_fd_sc_hd__and2_4
(
   input  wire A,
   input  wire B,
   output wire X
);

   assign X = A & B;
  
endmodule

module sky130_fd_sc_hd__dlrtp_1
(
   input  wire RESET_B,
   input  wire GATE,
   input  wire D,
   output reg  Q
);

   always @*
   begin
      if (~RESET_B)
         Q = 1'b0;
      else if (GATE)
         Q = D;
   end

endmodule

