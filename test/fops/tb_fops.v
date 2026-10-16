`default_nettype none
`timescale 1ns / 1ps

/* tb_fops: the BF16 adder and multiplier as the core wires them - the
   operand flags from lampFPU_div_top's registered decode (one clock after
   the operands change), fadd / fmul combinational from them. */
module tb_fops;

   reg         clk = 1'b0;
   always #10 clk = ~clk;
   reg         rst_n = 1'b0;
   reg  [15:0] a = 16'h0;
   reg  [15:0] b = 16'h0;
   reg         round_to_zero = 1'b0;
   wire [15:0] sum;
   wire [15:0] product;

   wire        s_op1_w, s_op2_w;
   wire [8:0]  extE_op1_w, extE_op2_w;
   wire        isInf_op1_w, isZ_op1_w, isSNAN_op1_w, isQNAN_op1_w, isDN_op1_w;
   wire        isInf_op2_w, isZ_op2_w, isSNAN_op2_w, isQNAN_op2_w, isDN_op2_w;

   lampFPU_div_top i_div
   (
      .clk             ( clk           ),
      .rst             ( !rst_n        ),
      .do_div          ( 1'b0          ),
      .padv_i          ( 1'b1          ),
      .rndMode_i       ( round_to_zero ),
      .op1_i           ( a             ),
      .op2_i           ( b             ),
      .result_o        (               ),
      .isResultValid_o (               ),
      .isReady_o       (               ),
      .s_op1_r         ( s_op1_w       ),
      .extE_op1_r      ( extE_op1_w    ),
      .isInf_op1_r     ( isInf_op1_w   ),
      .isZ_op1_r       ( isZ_op1_w     ),
      .isSNAN_op1_r    ( isSNAN_op1_w  ),
      .isQNAN_op1_r    ( isQNAN_op1_w  ),
      .isDN_op1_r      ( isDN_op1_w    ),
      .s_op2_r         ( s_op2_w       ),
      .extE_op2_r      ( extE_op2_w    ),
      .isInf_op2_r     ( isInf_op2_w   ),
      .isZ_op2_r       ( isZ_op2_w     ),
      .isSNAN_op2_r    ( isSNAN_op2_w  ),
      .isQNAN_op2_r    ( isQNAN_op2_w  ),
      .isDN_op2_r      ( isDN_op2_w    )
   );

   fadd i_fadd
   (
      .a_in          ( a             ),
      .b_in          ( b             ),
      .round_to_zero ( round_to_zero ),
      .s_op1_i       ( s_op1_w       ),
      .extE_op1_i    ( extE_op1_w    ),
      .isInf_op1_i   ( isInf_op1_w   ),
      .isZ_op1_i     ( isZ_op1_w     ),
      .isSNAN_op1_i  ( isSNAN_op1_w  ),
      .isQNAN_op1_i  ( isQNAN_op1_w  ),
      .isDN_op1_i    ( isDN_op1_w    ),
      .s_op2_i       ( s_op2_w       ),
      .extE_op2_i    ( extE_op2_w    ),
      .isInf_op2_i   ( isInf_op2_w   ),
      .isZ_op2_i     ( isZ_op2_w     ),
      .isSNAN_op2_i  ( isSNAN_op2_w  ),
      .isQNAN_op2_i  ( isQNAN_op2_w  ),
      .isDN_op2_i    ( isDN_op2_w    ),
      .result        ( sum           )
   );

   fmul i_fmul
   (
      .a_in          ( a             ),
      .b_in          ( b             ),
      .s_op1_i       ( s_op1_w       ),
      .extE_op1_i    ( extE_op1_w    ),
      .isInf_op1_i   ( isInf_op1_w   ),
      .isZ_op1_i     ( isZ_op1_w     ),
      .isSNAN_op1_i  ( isSNAN_op1_w  ),
      .isQNAN_op1_i  ( isQNAN_op1_w  ),
      .isDN_op1_i    ( isDN_op1_w    ),
      .s_op2_i       ( s_op2_w       ),
      .extE_op2_i    ( extE_op2_w    ),
      .isInf_op2_i   ( isInf_op2_w   ),
      .isZ_op2_i     ( isZ_op2_w     ),
      .isSNAN_op2_i  ( isSNAN_op2_w  ),
      .isQNAN_op2_i  ( isQNAN_op2_w  ),
      .isDN_op2_i    ( isDN_op2_w    ),
      .result        ( product       )
   );

endmodule
