`define M_W 7
`define EXP_W 8
`define MULT_W `M_W+`M_W+2
`define EXP_MAX 2**(`EXP_W-1)+2**(`EXP_W)-3

//basically a close copy of https://github.com/ReaLLMASIC/nanoGPT/blob/master/HW/SA/verilog/fadd.sv
module fadd
(
    input  wire [16-1:0] a_in, b_in, // Inputs in the format of IEEE-`EXP_W-154 Representation.
    input  wire          round_to_zero,

    input wire	[0:0]                   s_op1_i,
    input wire	[(`EXP_W +1)-1:0]       extE_op1_i,
    input wire                         isInf_op1_i,
    input wire                         isZ_op1_i,
    input wire                         isSNAN_op1_i,
    input wire                         isQNAN_op1_i,
    input wire                         isDN_op1_i,
    input wire	[0:0]                   s_op2_i,
    input wire	[(`EXP_W+1)-1:0]        extE_op2_i,
    input wire                         isInf_op2_i,
    input wire                         isZ_op2_i,
    input wire                         isSNAN_op2_i,
    input wire                         isQNAN_op2_i,
    input wire                         isDN_op2_i,
    output wire [16-1:0] result // Outputs in the format of IEEE-`EXP_W-154 Representation.
);

   wire isINF;
   wire isNAN;
   wire output_sign;
   wire operation_sub;

   reg  [16-1:0]     operand_a, operand_b;
   wire [2+`M_W+1:0] significand_a, significand_b;
   wire [`EXP_W-1:0] exponent_diff;

   wire [2+`M_W+1:0] significand_b_add;
   wire [2+`M_W+1:0] significand_b_add_twos;

   wire [2+`M_W+1:0] significand_add;
   wire [2+`M_W+1:0] significand_add_temp;
   reg  [3:0]        leftShift;
   reg               a_isZ, b_isZ;
   reg               a_isINF, b_isINF;
   reg               a_isSNAN, b_isSNAN;
   reg               a_isQNAN, b_isQNAN;
   reg               a_isSubnorm, b_isSubnorm;
   reg               a_assumedOne, b_assumedOne;
   reg  [`EXP_W:0]   a_e;
   reg  [`EXP_W:0]   b_e;
   reg  [`EXP_W:0]   e_res;
   reg  [2+`M_W+1:0] f_res;
   /* verilator lint_off UNUSEDSIGNAL */
   reg  [2+`M_W+1:0] f_rounded;
   /* verilator lint_on UNUSEDSIGNAL */
   wire              a_GT_b;

   assign a_GT_b = (a_in[16-2:0] > b_in[16-2:0]);

   always @*
   begin
      //for operations always operand_a must not be less than b_in
      if (a_GT_b)
      begin
         {operand_a,operand_b}      = {a_in,b_in};
         {a_isSubnorm, b_isSubnorm} = {isDN_op1_i, isDN_op2_i};
         {a_isZ, b_isZ}             = {isZ_op1_i, isZ_op2_i};
         {a_isINF, b_isINF}         = {isInf_op1_i, isInf_op2_i};
         {a_isSNAN, b_isSNAN}       = {isSNAN_op1_i, isSNAN_op2_i};
         {a_isQNAN, b_isQNAN}       = {isQNAN_op1_i, isQNAN_op2_i};
         {a_e, b_e}                 = {extE_op1_i, extE_op2_i};
      end
      else
      begin
         {operand_a,operand_b}      = {b_in,a_in};
         {a_isSubnorm, b_isSubnorm} = {isDN_op2_i, isDN_op1_i};
         {a_isZ, b_isZ}             = {isZ_op2_i, isZ_op1_i};
         {a_isINF, b_isINF}         = {isInf_op2_i, isInf_op1_i};
         {a_isSNAN, b_isSNAN}       = {isSNAN_op2_i, isSNAN_op1_i};
         {a_isQNAN, b_isQNAN}       = {isQNAN_op2_i, isQNAN_op1_i};
         {a_e, b_e}                 = {extE_op2_i, extE_op1_i};
      end
   end


//   assign a_isSubnorm  = ~(|operand_a[14 -: 8]) & (|operand_a[6:0]);   // E==0x0   && f!=0x0
//   assign a_isZ        = ~(|operand_a[14:0]);
//   assign a_isINF      = operand_a[14:0] == 15'b111111110000000;
//   assign a_isSNAN     = operand_a[14:0] == 15'b111111110111111;
//   assign a_isQNAN     = operand_a[14:0] == 15'b111111111000000;
//   assign b_isSubnorm  = ~(|operand_b[14 -: 8]) & (|operand_b[6:0]);   // E==0x0   && f!=0x0
//   assign b_isZ        = ~(|operand_b[14:0]);
//   assign b_isINF      = operand_b[14:0] == 15'b111111110000000;
//   assign b_isSNAN     = operand_b[14:0] == 15'b111111110111111;
//   assign b_isQNAN     = operand_b[14:0] == 15'b111111111000000;
   assign a_assumedOne = ~a_isZ & ~a_isSubnorm;
   assign b_assumedOne = ~b_isZ & ~b_isSubnorm;
//   assign a_e          = {1'b0, operand_a[14:`M_W+1], (operand_a[`M_W] | a_isSubnorm)};
//   assign b_e          = {1'b0, operand_b[14:`M_W+1], (operand_b[`M_W] | b_isSubnorm)};

   //Exception flag sets 1 if either one of the exponent is 255.
   assign isINF = a_isINF | b_isINF;
   assign isNAN = a_isSNAN | b_isSNAN | a_isQNAN | b_isQNAN;

   assign operation_sub =  operand_a[16-1] != operand_b[16-1];

   //Assigining significand values according to Hidden Bit.
   assign significand_a = {1'b0,a_assumedOne,operand_a[`M_W-1:0], 2'b0}; // expand the mantissa by 1 bit before addition since its always implied
   assign significand_b = {1'b0,b_assumedOne,operand_b[`M_W-1:0], 2'b0}; // same as above

   //Evaluating Exponent Difference
   //assign exponent_diff = operand_a[16-2:`M_W] - operand_b[16-2:`M_W];
   assign exponent_diff = a_e - b_e;

   //Shifting significand_b to the right according to exponent_diff. Exapmle: if we have 1.0101 >> 2 = 0.0101 then exponent_diff = 2 and significand_b_add = significand_b >> exponent_diff
   assign significand_b_add = significand_b >> exponent_diff;
   assign significand_b_add_twos = operation_sub ? ~significand_b_add + 1 : significand_b_add;

   //------------------------------------------------ADD BLOCK------------------------------------------//
   assign significand_add_temp = significand_a + significand_b_add_twos;
   assign significand_add = operation_sub ? {1'b0, significand_add_temp[2+`M_W:0]} : significand_add_temp;

   always @*
   begin
		casez(significand_add[2 +: 9])
			9'b1????????: leftShift = 'd0;
			9'b01???????: leftShift = 'd0;
			9'b001??????: leftShift = 'd1;
			9'b0001?????: leftShift = 'd2;
			9'b00001????: leftShift = 'd3;
			9'b000001???: leftShift = 'd4;
			9'b0000001??: leftShift = 'd5;
			9'b00000001?: leftShift = 'd6;
			9'b000000001: leftShift = 'd7;
			9'b000000000: leftShift = 'd8;
         default:      leftShift = 'd0;
		endcase
   end

   always @*
   begin
      //Taking care of the resulting mantissa. 
      //If there is a carry, then the result is normalized by shifting the significand right by one bit(because its implied) and incrementing the exponent by one.
      if (significand_add[1+`M_W+2])
      begin
         // Check for overflow
         if (a_e + 1 == 255)
         begin
            // Overflow ocurred
            e_res = 9'hFF;
            f_res = 'h0;
         end
         else
         begin
            // Add one to exponent and shift significand right one
            e_res = a_e + 1;
            f_res = {3'b0, significand_add[1+`M_W+1:1+1]};
         end
      end

      // Check if no shift needed ... already normalized
      else if (significand_add[2+`M_W] == 1)
      begin
         e_res = a_e;
         f_res = {2'b0, significand_add[2+`M_W-1:2+0], |significand_add[1:0], 1'b0};
      end
      else
      begin
         // Check for zero
         if (significand_add == '0)
         begin
            e_res = '0;
            f_res = '0;
         end

         // Do post-normalization
         else if (a_e > 9'(leftShift))
         begin
            e_res = a_e - 9'(leftShift);
            f_res = significand_add << leftShift;
         end
         else
         begin
            e_res = 'h0;
            f_res = significand_add << (a_e - 1);
         end
      end
   end

   assign output_sign = {e_res,f_res} == '0 ? 1'b0 : operand_a[15];// (a_GT_b ? a_in[15] : ~b_in[15]);

   assign f_rounded = (round_to_zero & output_sign) ? f_res : f_res + 2;
   assign result = isINF ? 16'h7F80 : isNAN ? 16'h7fC0 : {output_sign,e_res[7:0],f_rounded[2+6:2+0]};

endmodule


//basically a close copy of https://github.com/ReaLLMASIC/nanoGPT/blob/master/HW/SA/verilog/fmul.sv
module fmul
(
    input [16-1:0] a_in,
    input [16-1:0] b_in,
    input wire	[0:0]                   s_op1_i,
    input wire	[(`EXP_W +1)-1:0]       extE_op1_i,
    input wire                         isInf_op1_i,
    input wire                         isZ_op1_i,
    input wire                         isSNAN_op1_i,
    input wire                         isQNAN_op1_i,
    input wire                         isDN_op1_i,
    input wire	[0:0]                   s_op2_i,
    input wire	[(`EXP_W+1)-1:0]        extE_op2_i,
    input wire                         isInf_op2_i,
    input wire                         isZ_op2_i,
    input wire                         isSNAN_op2_i,
    input wire                         isQNAN_op2_i,
    input wire                         isDN_op2_i,
    output [16-1:0] result
);

    /* verilator lint_off UNUSEDSIGNAL */
    reg [`MULT_W-1:0] mul_fix_out;
    /* verilator lint_on UNUSEDSIGNAL */
    reg [`M_W-1:0] M_result;
    wire [`EXP_W-1:0] e_result;
    wire sign;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [`EXP_W:0] e_result0;
    /* verilator lint_on UNUSEDSIGNAL */
    reg overflow;
    reg zero_check;
   wire              a_isZ, b_isZ;
   wire              a_isINF, b_isINF;
   wire              a_isSNAN, b_isSNAN;
   wire              a_isQNAN, b_isQNAN;
   wire              a_isSubnorm, b_isSubnorm;
   wire              a_assumedOne, b_assumedOne;
   wire [`EXP_W:0]   a_e;
   wire [`EXP_W:0]   b_e;
   int               e_add;

`ifdef DONT_COMPILE
   assign a_isSubnorm  = ~(|a_in[14 -: 8]) & (|a_in[6:0]);   // E==0x0   && f!=0x0
   assign a_isZ        = ~(|a_in[14:0]);
   assign a_isINF      = a_in[14:0] == 15'b111111110000000;
   assign a_isSNAN     = a_in[14:0] == 15'b111111110111111;
   assign a_isQNAN     = a_in[14:0] == 15'b111111111000000;
   assign b_isSubnorm  = ~(|b_in[14 -: 8]) & (|b_in[6:0]);   // E==0x0   && f!=0x0
   assign b_isZ        = ~(|b_in[14:0]);
   assign b_isINF      = b_in[14:0] == 15'b111111110000000;
   assign b_isSNAN     = b_in[14:0] == 15'b111111110111111;
   assign b_isQNAN     = b_in[14:0] == 15'b111111111000000;
   assign a_e          = {1'b0, a_in[14:`M_W+1], (a_in[`M_W] | a_isSubnorm)};
   assign b_e          = {1'b0, b_in[14:`M_W+1], (b_in[`M_W] | b_isSubnorm)};
`endif

   assign a_isSubnorm  = isDN_op1_i;
   assign a_isZ        = isZ_op1_i;
   assign a_isINF      = isInf_op1_i;
   assign a_isSNAN     = isSNAN_op1_i;
   assign a_isQNAN     = isQNAN_op1_i;
   assign b_isSubnorm  = isDN_op2_i;
   assign b_isZ        = isZ_op2_i;
   assign b_isINF      = isInf_op2_i;
   assign b_isSNAN     = isSNAN_op2_i;
   assign b_isQNAN     = isQNAN_op2_i;
   assign a_e          = extE_op1_i;
   assign b_e          = extE_op2_i;
   assign a_assumedOne = ~a_isZ & ~a_isSubnorm;
   assign b_assumedOne = ~b_isZ & ~b_isSubnorm;
    
    // Multiplication logic
    always @* begin
        mul_fix_out = {a_assumedOne, a_in[`M_W-1:0]} * {b_assumedOne, b_in[`M_W-1:0]}; //extend the mantissa by 1 bit before multiplication
    end

    // Zero check
    always @* begin
        if (a_in[16-2:0] == 0 || b_in[16-2:0] == 0) begin
            zero_check = 1'b1;
        end else begin
            zero_check = 1'b0;
        end
    end

    // Generate Mantissa. We are only considering the most significat bits of the product to generate the mantissa.
    always @* begin
        //select two MSBs of the product
        casez(mul_fix_out[`MULT_W-1:`MULT_W-6])
            //Example: If mul_fix_out is 8 bits wide and represents 01xxxxxx (binary), it extracts xxxxxx, assuming the MSBs are 01
            6'b000001: begin M_result = mul_fix_out[`MULT_W-7:`M_W-4]; e_add = -4; end
            6'b00001?: begin M_result = mul_fix_out[`MULT_W-6:`M_W-3]; e_add = -3; end
            6'b0001??: begin M_result = mul_fix_out[`MULT_W-5:`M_W-2]; e_add = -2; end
            6'b001???: begin M_result = mul_fix_out[`MULT_W-4:`M_W-1]; e_add = -1; end
            6'b01????: begin M_result = mul_fix_out[`MULT_W-3:`M_W];   e_add = 0; end
            6'b1?????: begin M_result = mul_fix_out[`MULT_W-2:`M_W+1]; e_add = 1; end
            default:   begin M_result = mul_fix_out[`MULT_W-2:`M_W+1]; e_add = 1; end
        endcase
    end

    // Overflow check
    always @* begin
        //Different cases for overflow:
        //1. If either of the inputs is zero, then the result is zero and there is no overflow.
        //2. Underflow check: If the sum of the exponents is less than the minimum exponent, then the result is zero and there is no overflow. {2'b0,{(EXP_W-1){1'b1}}} is the minimum exponent(001111111 in case of 32bit float)
        //3. Overflow check: If the sum of the exponents is greater than the maximum exponent, then the result is infinity and there is overflow. EXP_MAX is the maximum exponent.
        overflow = (zero_check || (a_e + b_e + {{`EXP_W{1'b0}}, mul_fix_out[`MULT_W-1]}) < {2'b0,{(`EXP_W-1){1'b1}}} || (a_e + b_e + {8'd0, mul_fix_out[`MULT_W-1]}) > `EXP_MAX);

        if (~zero_check) begin
            if (overflow) begin
                e_result0 = {(`EXP_W+1){1'b1}};
            end else begin
                //1. We extend the exponent by 1 bit because the result of addition of two exponents can be 1 bit larger than the exponent itself.
                //2. We add the MSB of the mantissa multiplication(before normalization) to the exponent sum to account for the shifting of the mantissa.
                //3. We subtract the bias from the exponent sum to get the final exponent because just adding two exponents would give us exp1 + exp2 + 2 x bias.
                e_result0 = a_e + b_e + (`EXP_W+1)'(e_add) - {2'b0,{(`EXP_W-1){1'b1}}};
            end
        end else begin
            e_result0 = 0;
        end
    end
    assign e_result = e_result0[`EXP_W-1:0];

    // Sign calculation
    assign sign = a_in[16-1] ^ b_in[16-1];

    wire [`M_W-1:0] overflow_mask;
    assign overflow_mask = overflow ? 0 : {(`M_W){1'b1}};

    assign result = (a_isSNAN | b_isSNAN | a_isQNAN | b_isQNAN) ? 16'h7FC0 :
                    (a_isINF  | b_isINF)                        ? 16'h7F80 :
                           {sign, e_result, overflow_mask & M_result};
endmodule


module itobf16
(
  input  wire signed [15:0] in,
  input  wire               is_signed,
  output reg        [15:0] bf16_out
);

   // First we convert to 32-bit float, then round and truncate to 
   // bfloat16 format since they have the same exponent format.
   reg  [31:0]  pre_round;
   /* verilator lint_off UNUSEDSIGNAL */
   reg  [31:0]  out32;
   /* verilator lint_on UNUSEDSIGNAL */
   reg  [15:0]  sig;
   wire [15:0]  mask;
   reg  [7:0]   exp;
   
   assign mask = 16'hFFFF;

   always @(*)
   begin
      pre_round = 32'h0;
      out32     = 32'h0;
      exp       = 8'h0;
      bf16_out  = 16'h0;

      // If signed, we need the absolute value
      if (is_signed)
         sig = in[15] ? ~in + 1 : in;
      else
         sig = in;
      
      // Test for zero case
      if (in == 0)
      begin
         bf16_out = 16'h0000;
      end
      else
      begin
         integer i;
         exp = 0;
         for (i = 8; i > 0; i = i >> 1)
         begin
            if ((sig & (mask << (16 - i))) == 0)
            begin
               sig = sig << i;
               exp = exp | 8'(i);
            end
         end
            
         // Calculate pre-rounded value
         exp = 142 - exp;
         pre_round = {(is_signed ? in[15] : 1'b0), exp, sig[14:0], 8'h0};

         // Now convert to bfloat16 by rounding and dropping the lower 16 bits
         if (is_signed & in[15])
            out32 = pre_round - 32'h00008000;
         else
            out32 = pre_round + 32'h00008000;

         // Keep the upper 16 bits
         bf16_out = out32[31:16];
      end
   end
endmodule

module bf16toi
(
   input  wire [15:0] bf16_in,
   input  wire        i_signed,

   //	outputs
   output reg  [15:0] i_o
);

   wire 			       f_sign;
   wire [7:0]         f_exp;
   wire [7:0]         f_mant;
   reg  [15:0]        f_mant_shift;

   assign f_sign     = bf16_in[15];
   assign f_exp      = bf16_in[14:7];
   assign f_mant     = {1'b1, bf16_in[6:0]};

   always @*
   begin
      f_mant_shift = 16'h0;

      // Determine shift direction and amount
      if (f_exp < 127)
         i_o = 16'h0;
      else
      begin
         // Test for values that need shift left
         if (f_exp < (127 + (i_signed ? 15 : 16)) ||
               (f_sign == 1'b1 && f_exp == (127 + (i_signed ? 15 : 16)) &&
               f_mant[7] && f_mant[6:0] == 7'h0))
         begin
            // Test for values that need to be shifted right
            if (f_exp < (127 + 7))
               f_mant_shift = {8'h0, f_mant} >> (127 + 7 - f_exp);
            else
               f_mant_shift = {8'h0, f_mant} << (f_exp - (127 + 7));

            // Calculate the output value
            if (i_signed)
               i_o = f_sign ? -{1'b0, f_mant_shift[14:0]} : {1'b0, f_mant_shift[14:0]};
            else
               i_o = f_sign ? 16'h0 : {f_mant_shift};
         end
         else
         begin
            // The floating point is too large
            if (i_signed)
               i_o = f_sign ? -16'(32768) : 16'(32767);
            else
               i_o = 16'(65535);
         end
      end
	end
endmodule

