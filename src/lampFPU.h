// Copyright 2019 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// Licence, Version 2.0 (the "Licence"); you may not use this file except in
// compliance with the Licence. You may obtain a copy of the Licence at
// https://solderpad.org/licenses/SHL-2.0/. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this Licence is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the Licence for the
// specific language governing permissions and limitations under the Licence.
//
// Authors (in alphabetical order):
// Andrea Galimberti    <andrea.galimberti@polimi.it>
// Davide Zoni          <davide.zoni@polimi.it>
//
// Date: 30.09.2019

`ifndef lampFPU
`define lampFPU

	parameter LAMP_FLOAT_DW		=	16;
	parameter LAMP_FLOAT_S_DW 	=	1;
	parameter LAMP_FLOAT_E_DW 	=	8;
	parameter LAMP_FLOAT_F_DW 	=	7;

	parameter LAMP_INTEGER_DW	=	32;
//	parameter LAMP_INTEGER_S_DW	=	1;
//	parameter LAMP_INTEGER_F_DW	=	31;

	parameter LAMP_FLOAT_E_BIAS	=	(2 ** (LAMP_FLOAT_E_DW - 1)) - 1;
	parameter LAMP_FLOAT_E_MAX	=	(2 ** LAMP_FLOAT_E_DW) - 1;

//	parameter INF				=	15'h7f80;
//	parameter ZERO				=	15'h0000;
//	parameter SNAN				=	15'h7fbf;
//	parameter QNAN				=	15'h7fc0;

	//	used in TB only
//	parameter PLUS_INF			=	16'h7f80;
//	parameter MINUS_INF			=	16'hff80;
//	parameter PLUS_ZERO			=	16'h0000;
//	parameter MINUS_ZERO		=	16'h8000;

	parameter INF_E_F			=	15'b111111110000000; // w/o sign
//	parameter SNAN_E_F			=	15'b111111110111111; // w/o sign
	parameter QNAN_E_F			=	15'b111111111000000; // w/o sign
	parameter ZERO_E_F			=	15'b000000000000000; // w/o sign

	//	div-only
	parameter LAMP_APPROX_DW	=	4;
	parameter LAMP_PREC_DW		=	8;
	parameter LAMP_APPROX_MULS	=	$clog2 ((LAMP_FLOAT_DW+1)/LAMP_APPROX_DW);

   parameter FPU_RNDMODE_NEAREST	 = 1'b0;

	function logic [LAMP_FLOAT_S_DW+LAMP_FLOAT_E_DW+LAMP_FLOAT_F_DW-1:0] FUNC_splitOperand(input [LAMP_FLOAT_DW-1:0] op);
		FUNC_splitOperand = op;
	endfunction

	function logic [LAMP_FLOAT_E_DW+1-1:0] FUNC_extendExp(input [LAMP_FLOAT_E_DW-1:0] e_op, input isDN);
		FUNC_extendExp = { 1'b0, e_op[7:1], (e_op[0] | isDN) };
	endfunction

	function logic [LAMP_FLOAT_F_DW+1-1:0] FUNC_extendFrac(input [LAMP_FLOAT_F_DW-1:0] f_op, input isDN, input isZ);
		FUNC_extendFrac =	{ (~isDN & ~isZ), f_op};
	endfunction

	function logic FUNC_op1_GT_op2(
			input [LAMP_FLOAT_F_DW+1-1:0] f_op1, input [LAMP_FLOAT_E_DW+1-1:0] e_op1,
			input [LAMP_FLOAT_F_DW+1-1:0] f_op2, input [LAMP_FLOAT_E_DW+1-1:0] e_op2
	);
		logic 		e_op1_GT_op2, e_op1_EQ_op2;
		logic 		f_op1_GT_op2;
		logic 		op1_GT_op2;

		e_op1_GT_op2 	= (e_op1 > e_op2);
		e_op1_EQ_op2 	= (e_op1 == e_op2);

		f_op1_GT_op2 	= (f_op1 > f_op2);

		op1_GT_op2		= e_op1_GT_op2 | (e_op1_EQ_op2 & f_op1_GT_op2);

		FUNC_op1_GT_op2 =	op1_GT_op2;
	endfunction

	function logic [$clog2(1+1+LAMP_FLOAT_F_DW+3)-1:0] FUNC_AddSubPostNorm_numLeadingZeros( input [1+1+LAMP_FLOAT_F_DW+3-1:0] f_initial_res);

		casez(f_initial_res)
			12'b1???????????: FUNC_AddSubPostNorm_numLeadingZeros =  'd0;
			12'b01??????????: FUNC_AddSubPostNorm_numLeadingZeros =  'd0;
			12'b001?????????: FUNC_AddSubPostNorm_numLeadingZeros =  'd1;
			12'b0001????????: FUNC_AddSubPostNorm_numLeadingZeros =  'd2;
			12'b00001???????: FUNC_AddSubPostNorm_numLeadingZeros =  'd3;
			12'b000001??????: FUNC_AddSubPostNorm_numLeadingZeros =  'd4;
			12'b0000001?????: FUNC_AddSubPostNorm_numLeadingZeros =  'd5;
			12'b00000001????: FUNC_AddSubPostNorm_numLeadingZeros =  'd6;
			12'b000000001???: FUNC_AddSubPostNorm_numLeadingZeros =  'd7;
			12'b0000000001??: FUNC_AddSubPostNorm_numLeadingZeros =  'd8;
			12'b00000000001?: FUNC_AddSubPostNorm_numLeadingZeros =  'd9;
			12'b000000000001: FUNC_AddSubPostNorm_numLeadingZeros =  'd10;
			12'b000000000000: FUNC_AddSubPostNorm_numLeadingZeros =  'd0; // zero result
		endcase
	endfunction

	function logic [$clog2(LAMP_FLOAT_F_DW+1)-1:0] FUNC_numLeadingZeros(
					input logic [(LAMP_FLOAT_F_DW+1)-1:0] f_i
				);
				    casez(f_i)
				      8'b1???????: FUNC_numLeadingZeros = 'd0;
				      8'b01??????: FUNC_numLeadingZeros = 'd1;
				      8'b001?????: FUNC_numLeadingZeros = 'd2;
				      8'b0001????: FUNC_numLeadingZeros = 'd3;
				      8'b00001???: FUNC_numLeadingZeros = 'd4;
				      8'b000001??: FUNC_numLeadingZeros = 'd5;
				      8'b0000001?: FUNC_numLeadingZeros = 'd6;
				      8'b00000001: FUNC_numLeadingZeros = 'd7;
				      8'b00000000: FUNC_numLeadingZeros = 'd0; // zero result
    				endcase
	endfunction

	function logic [$clog2(LAMP_INTEGER_DW)-1:0] FUNC_i2f_integerExponent(
					input logic [LAMP_INTEGER_DW-1:0] int32_i
				);
					casez(int32_i)
						32'b1???????????????????????????????: FUNC_i2f_integerExponent = 'd31;
						32'b01??????????????????????????????: FUNC_i2f_integerExponent = 'd30;
						32'b001?????????????????????????????: FUNC_i2f_integerExponent = 'd29;
						32'b0001????????????????????????????: FUNC_i2f_integerExponent = 'd28;
						32'b00001???????????????????????????: FUNC_i2f_integerExponent = 'd27;
						32'b000001??????????????????????????: FUNC_i2f_integerExponent = 'd26;
						32'b0000001?????????????????????????: FUNC_i2f_integerExponent = 'd25;
						32'b00000001????????????????????????: FUNC_i2f_integerExponent = 'd24;
						32'b000000001???????????????????????: FUNC_i2f_integerExponent = 'd23;
						32'b0000000001??????????????????????: FUNC_i2f_integerExponent = 'd22;
						32'b00000000001?????????????????????: FUNC_i2f_integerExponent = 'd21;
						32'b000000000001????????????????????: FUNC_i2f_integerExponent = 'd20;
						32'b0000000000001???????????????????: FUNC_i2f_integerExponent = 'd19;
						32'b00000000000001??????????????????: FUNC_i2f_integerExponent = 'd18;
						32'b000000000000001?????????????????: FUNC_i2f_integerExponent = 'd17;
						32'b0000000000000001????????????????: FUNC_i2f_integerExponent = 'd16;
						32'b00000000000000001???????????????: FUNC_i2f_integerExponent = 'd15;
						32'b000000000000000001??????????????: FUNC_i2f_integerExponent = 'd14;
						32'b0000000000000000001?????????????: FUNC_i2f_integerExponent = 'd13;
						32'b00000000000000000001????????????: FUNC_i2f_integerExponent = 'd12;
						32'b000000000000000000001???????????: FUNC_i2f_integerExponent = 'd11;
						32'b0000000000000000000001??????????: FUNC_i2f_integerExponent = 'd10;
						32'b00000000000000000000001?????????: FUNC_i2f_integerExponent = 'd9;
						32'b000000000000000000000001????????: FUNC_i2f_integerExponent = 'd8;
						32'b0000000000000000000000001???????: FUNC_i2f_integerExponent = 'd7;
						32'b00000000000000000000000001??????: FUNC_i2f_integerExponent = 'd6;
						32'b000000000000000000000000001?????: FUNC_i2f_integerExponent = 'd5;
						32'b0000000000000000000000000001????: FUNC_i2f_integerExponent = 'd4;
						32'b00000000000000000000000000001???: FUNC_i2f_integerExponent = 'd3;
						32'b000000000000000000000000000001??: FUNC_i2f_integerExponent = 'd2;
						32'b0000000000000000000000000000001?: FUNC_i2f_integerExponent = 'd1;
						32'b0000000000000000000000000000000?: FUNC_i2f_integerExponent = 'd0;
					endcase
	endfunction

	/*
	* FUNC_addsub_calcStickyBit:
	*
	* Calculate the sticky bit in add sub operations.
	*
	* Input: the f mantissa extended with 3 LSB, i.e., G,R,S, one
	* hidden bit, i.e., MSB-1, and an extra MSB for ovf or 2'complement.
	*
	* Output: the computed sticky bit
	*/
`ifdef DONT_COMPILE
	function logic FUNC_addsub_calcStickyBit(
					input logic [(1+LAMP_FLOAT_F_DW+3)-1:0] f_i,
					input logic [(LAMP_FLOAT_E_DW+1)-1:0] num_shr_i
				);
			    case(num_shr_i)
			    	9'd0 :		FUNC_addsub_calcStickyBit = 1'b0;		// no right shift -> 0 sticky
					9'd1 :		FUNC_addsub_calcStickyBit = 1'b0;		// two added zero bits G,R
					9'd2 :		FUNC_addsub_calcStickyBit = 1'b0;		// two added zero bits G,R
					9'd3 :		FUNC_addsub_calcStickyBit = f_i[3];
					9'd4 :		FUNC_addsub_calcStickyBit = |f_i[3+:1];
			    	9'd5 :		FUNC_addsub_calcStickyBit = |f_i[3+:2];
			    	9'd6 :		FUNC_addsub_calcStickyBit = |f_i[3+:3];
			    	9'd7 :		FUNC_addsub_calcStickyBit = |f_i[3+:4];
			    	9'd8 :		FUNC_addsub_calcStickyBit = |f_i[3+:5];
			    	9'd9 :		FUNC_addsub_calcStickyBit = |f_i[3+:6];
					default:	FUNC_addsub_calcStickyBit = |f_i[3+:7];
			    endcase
		endfunction
`endif

	function logic[LAMP_APPROX_DW-1:0] FUNC_approxRecip(
      /* verilator lint_off UNUSEDSIGNAL */
		input [(1+LAMP_FLOAT_F_DW)-1:0] f_i
      /* verilator lint_on UNUSEDSIGNAL */
	);
		case(f_i[(1+LAMP_FLOAT_F_DW)-2-:LAMP_APPROX_DW])
			'b0000	:	FUNC_approxRecip = 'b1111;
			'b0001	:	FUNC_approxRecip = 'b1101;
			'b0010	:	FUNC_approxRecip = 'b1100;
			'b0011	:	FUNC_approxRecip = 'b1010;
			'b0100	:	FUNC_approxRecip = 'b1001;
			'b0101	:	FUNC_approxRecip = 'b1000;
			'b0110	:	FUNC_approxRecip = 'b0111;
			'b0111	:	FUNC_approxRecip = 'b0110;
			'b1000	:	FUNC_approxRecip = 'b0101;
			'b1001	:	FUNC_approxRecip = 'b0100;
			'b1010	:	FUNC_approxRecip = 'b0011;
			'b1011	:	FUNC_approxRecip = 'b0011;
			'b1100	:	FUNC_approxRecip = 'b0010;
			'b1101	:	FUNC_approxRecip = 'b0001;
			'b1110	:	FUNC_approxRecip = 'b0001;
			'b1111	:	FUNC_approxRecip = 'b0000;
		endcase
	endfunction

`endif

