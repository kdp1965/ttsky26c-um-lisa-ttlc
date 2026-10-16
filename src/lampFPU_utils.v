`include "lampFPU.h"

/*
* 		Nan 	/ 			X		-> 		 Nan
* 		X 		/ 			Nan 	-> (+/-) inf
* (+/-)	inf		/ 			X 		-> (+/-) inf
* 		X 		/ 	(+/-) 	inf 	-> (+/-) 0
* (+/-) !0 		/ 	(+/-) 	0 		-> 		 inf
* (+/-) 0 		/ 	(+/-) 	0 		-> 		 Nan
* (+/-) inf 	/ 	(+/-) 	inf 	-> 		 Nan
*/
module calcInfNanZeroResDiv
(
   input wire isZero_op1_i,
   input wire isInf_op1_i,
   input wire sign_op1_i,
   input wire isSNan_op1_i,
   input wire isQNan_op1_i,
   input wire isZero_op2_i,
   input wire isInf_op2_i,
   input wire sign_op2_i,
   input wire isSNan_op2_i,
   input wire isQNan_op2_i,
   output reg  [4:0] result
);

   reg isNan_op1;
   reg isNan_op2;
	reg isValidRes, isZeroRes, isInfRes, isNanRes, signRes;

   always @*
   begin
		isNan_op1 = isSNan_op1_i || isQNan_op1_i;
		isNan_op2 = isSNan_op2_i || isQNan_op2_i;

		isValidRes	= (isZero_op1_i || isZero_op2_i || isInf_op1_i || isInf_op2_i || isNan_op1 || isNan_op2) ? 1 : 0;
		if (isNan_op1)
		begin //sign is not important, since a Nan remains a nan what-so-ever
			isZeroRes = 0; isInfRes = 0; isNanRes = 1; signRes = sign_op1_i;
		end
		else if (isNan_op2)
		begin
			isZeroRes = 0; isInfRes = 0; isNanRes = 1; signRes = sign_op2_i;
		end
		else // both are not NaN
		begin
			case({isZero_op1_i, isZero_op2_i, isInf_op1_i,isInf_op2_i})
				4'b00_00: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end
				4'b00_01: begin isNanRes = 0; isZeroRes = 1; isInfRes = 0; signRes = sign_op1_i ^ sign_op2_i;	end	//	x	/ inf
				4'b00_10: begin isNanRes = 0; isZeroRes = 0; isInfRes = 1; signRes = sign_op1_i ^ sign_op2_i; 	end	//	inf	/ x
				4'b00_11: begin isNanRes = 1; isZeroRes = 0; isInfRes = 0; signRes = sign_op1_i ^ sign_op2_i; 	end	//	inf	/ inf
				4'b01_00: begin isNanRes = 0; isZeroRes = 0; isInfRes = 1; signRes = sign_op1_i ^ sign_op2_i; 	end	//	x	/ 0
				4'b01_01: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end	//	Impossible
				4'b01_10: begin isNanRes = 0; isZeroRes = 0; isInfRes = 1; signRes = sign_op1_i ^ sign_op2_i; 	end	//	inf	/ 0
				4'b01_11: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end //	Impossible
				4'b10_00: begin isNanRes = 0; isZeroRes = 1; isInfRes = 0; signRes = sign_op1_i ^ sign_op2_i; 	end	//	0	/ x
				4'b10_01: begin isNanRes = 0; isZeroRes = 1; isInfRes = 0; signRes = sign_op1_i ^ sign_op2_i; 	end	//	0	/ inf
				4'b10_10: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end //	Impossible
				4'b10_11: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end //	Impossible
				4'b11_00: begin isNanRes = 1; isZeroRes = 0; isInfRes = 0; signRes = sign_op1_i ^ sign_op2_i; 	end	//	0	/ 0
				4'b11_01: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end //	Impossible
				4'b11_10: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end //	Impossible
				4'b11_11: begin isNanRes = 0; isZeroRes = 0; isInfRes = 0; signRes = 0; 						end //	Impossible
			endcase
		end

		result = {isValidRes, isZeroRes, isInfRes, isNanRes, signRes};
   end
endmodule


module checkOperand
(
   /* verilator lint_off UNUSEDSIGNAL */
   input  wire [LAMP_FLOAT_DW-1:0]  op,
   /* verilator lint_on UNUSEDSIGNAL */
   output reg  [5-1:0]              result
);

   reg [LAMP_FLOAT_E_DW-1:0] e_op;
   reg [LAMP_FLOAT_F_DW-1:0] f_op;
   reg isInf_op, isDN_op, isZ_op, isSNAN_op, isQNAN_op;

   always @*
   begin
      e_op = op[14-:8];
      f_op = op[6:0];
      
      // check deNorm (isDN), +/-inf (isInf), +/-zero (isZ), not a number (isSNaN, isQNaN)
      isInf_op  = (&e_op) &  ~(|f_op); 					// E==0xFF	&&	f==0x0
      isDN_op   = ~(|e_op) & (|f_op);					// E==0x0	&&	f!=0x0
      isZ_op    = ~(|op[14:0]);							// E==0x0	&&	f==0x0
      isSNAN_op = (&e_op) & ~f_op[6] & (|f_op[5:0]);
      isQNAN_op = (&e_op) & f_op[6];
      
      result = {isInf_op, isDN_op, isZ_op, isSNAN_op, isQNAN_op};
   end
endmodule


/* rndToNearestEven (Round-to-nearest-even):
*
* Description: performs the round to nearest even required by the IEEE 754-SP standard
* with a minor modification to trade performance/area with precision.
* instead of adding .1 in some scenarios with a possible 23bit carry chain
* the number of bit in the carry chain is configurable. This way if the
* considered LSB of the f are all 1 a truncation is performed instead of
* a rnd. This removes the possible normalization stage after rounding.
*/
module rndToNearestEven
(
   input wire [(1+1+LAMP_FLOAT_F_DW+3)-1:0] op,
   output reg [LAMP_FLOAT_F_DW-1:0] result
);

   localparam NUM_BIT_TO_RND	=	4;

   reg   								isAddOne;
   reg   [(1+1+LAMP_FLOAT_F_DW+3)-1:0] tempF_1;
   /* verilator lint_off UNUSEDSIGNAL */
   reg   [(1+1+LAMP_FLOAT_F_DW+3)-1:0] tempF;
   /* verilator lint_on UNUSEDSIGNAL */

   always @*
   begin
       //
       // Rnd to nearest even
       //	X0.00 -> X0		|	X1.00 -> X1
       //	X0.01 -> X0		|	X1.01 -> X1
       //	X0.10 -> X0		|	X1.10 -> X1. +1
       //	X0.11 -> X1		|	X1.11 -> X1. +1
       //
       tempF_1 = op;
       case(op[3:1] /*3 bits X.G(S|R)*/ )
          3'b0_00:	begin tempF_1[3] = 0;	isAddOne =0; end
          3'b0_01:	begin tempF_1[3] = 0;	isAddOne =0; end
          3'b0_10:	begin tempF_1[3] = 0;	isAddOne =0; end
          3'b0_11:	begin tempF_1[3] = 1;	isAddOne =0; end
          3'b1_00:	begin tempF_1[3] = 1;	isAddOne =0; end
          3'b1_01:	begin tempF_1[3] = 1; 	isAddOne =0; end
          3'b1_10:	begin tempF_1[3] = 1;	isAddOne =1; end
          3'b1_11:	begin tempF_1[3] = 1;	isAddOne =1; end
       endcase
       
       // limit rnd to NUM_BIT_TO_RND LSBs of the f, truncate otherwise
       // this avoid another normalization step, if any
       if(&tempF_1[3+:NUM_BIT_TO_RND])
          tempF =	tempF_1 ;
       else
          tempF =	tempF_1 + ({11'h0, isAddOne}<<3);
       
       result = tempF[3+:LAMP_FLOAT_F_DW];
   end
endmodule

