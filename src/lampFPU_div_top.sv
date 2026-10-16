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

`include "lampFPU.h"

module lampFPU_div_top (
   input  wire                      clk,
   input  wire                      rst,
   input  wire                      do_div,
   input  wire                      padv_i,
   input  wire                      rndMode_i,
   input  wire [LAMP_FLOAT_DW-1:0]  op1_i,
   input  wire [LAMP_FLOAT_DW-1:0]  op2_i,
   output reg  [LAMP_FLOAT_DW-1:0]  result_o,
   output reg                       isResultValid_o,
   output wire                      isReady_o,
	output reg	[LAMP_FLOAT_S_DW-1:0] 			s_op1_r,
	output reg	[(LAMP_FLOAT_E_DW+1)-1:0] 		extE_op1_r,
	output reg									isInf_op1_r,
	output reg									isZ_op1_r,
	output reg									isSNAN_op1_r,
	output reg									isQNAN_op1_r,
   output reg                          isDN_op1_r,
	output reg	[LAMP_FLOAT_S_DW-1:0] 			s_op2_r,
	output reg	[(LAMP_FLOAT_E_DW+1)-1:0] 		extE_op2_r,
	output reg									isInf_op2_r,
	output reg									isZ_op2_r,
	output reg									isSNAN_op2_r,
	output reg									isQNAN_op2_r,
   output reg                          isDN_op2_r
);

// INPUT wires: to drive registered input
	reg          						rndMode_r, rndMode_r_next;

// OUTPUT wires: to drive registered output
	logic	[LAMP_FLOAT_DW-1:0]			result_o_next;
	logic									isResultValid_o_next;

	//	div outputs
	logic									div_s_res;
	logic	[LAMP_FLOAT_E_DW-1:0]			div_e_res;
	logic	[LAMP_FLOAT_F_DW+5-1:0]			div_f_res;
	logic									div_valid;
	logic									div_isToRound;

	logic									doDiv_r, doDiv_next;

	// FUs results and valid bits
	logic									isResValid;

	//	mul/div only
	logic	[(1+LAMP_FLOAT_F_DW)-1:0] 		extShF_op1_r;
	logic	[$clog2(1+LAMP_FLOAT_F_DW)-1:0]	nlz_op1_r;
	logic	[(1+LAMP_FLOAT_F_DW)-1:0] 		extShF_op2_r;
	logic	[$clog2(1+LAMP_FLOAT_F_DW)-1:0]	nlz_op2_r;

	//	pre-operation wires/regs
	logic	[LAMP_FLOAT_S_DW-1:0] 			s_op1_wire;
	logic	[LAMP_FLOAT_E_DW-1:0] 			e_op1_wire;
	logic	[LAMP_FLOAT_F_DW-1:0] 			f_op1_wire;
	logic	[(LAMP_FLOAT_F_DW+1)-1:0] 		extF_op1_wire;
	logic	[(LAMP_FLOAT_E_DW+1)-1:0] 		extE_op1_wire;
	logic									isDN_op1_wire;
	logic									isZ_op1_wire;
	logic									isInf_op1_wire;
	logic									isSNAN_op1_wire;
	logic									isQNAN_op1_wire;
	logic	[LAMP_FLOAT_S_DW-1:0] 			s_op2_wire;
	logic	[LAMP_FLOAT_E_DW-1:0] 			e_op2_wire;
	logic	[LAMP_FLOAT_F_DW-1:0] 			f_op2_wire;
	logic	[(LAMP_FLOAT_F_DW+1)-1:0] 		extF_op2_wire;
	logic	[(LAMP_FLOAT_E_DW+1)-1:0] 		extE_op2_wire;
	logic									isDN_op2_wire;
	logic									isZ_op2_wire;
	logic									isInf_op2_wire;
	logic									isSNAN_op2_wire;
	logic									isQNAN_op2_wire;
	//	mul/div only
	logic	[(1+LAMP_FLOAT_F_DW)-1:0] 		extShF_op1_wire;
	logic	[$clog2(1+LAMP_FLOAT_F_DW)-1:0]	nlz_op1_wire;
	logic	[(1+LAMP_FLOAT_F_DW)-1:0] 		extShF_op2_wire;
	logic	[$clog2(1+LAMP_FLOAT_F_DW)-1:0]	nlz_op2_wire;

	//	pre-rounding wires/regs
	logic									s_res;
	logic	[LAMP_FLOAT_E_DW-1:0]			e_res;
	logic	[LAMP_FLOAT_F_DW+5-1:0]			f_res;
	logic									isToRound;

	// post-rounding wires/regs
	logic	[LAMP_FLOAT_F_DW-1:0]			f_res_postRnd;
	logic	[LAMP_FLOAT_F_DW-1:0]			f_res_postRnd_mod;
	logic	[LAMP_FLOAT_DW-1:0]			res_postRnd;

//////////////////////////////////////////////////////////////////
// 							state enum							//
//////////////////////////////////////////////////////////////////

	typedef enum logic [1:0]
	{
		IDLE	= 'd0,
		WORK	= 'd1,
		DONE	= 'd2
	}	ssFpuTop_t;

	ssFpuTop_t 	ss, ss_next;

//////////////////////////////////////////////////////////////////
// 						sequential logic						//
//////////////////////////////////////////////////////////////////

	always_ff @(posedge clk)
	begin
		if (rst)
		begin
			ss					<=	IDLE;
		//input
			doDiv_r				<=	1'b0;
			rndMode_r			<=	FPU_RNDMODE_NEAREST;
		//output
			result_o			<=	'0;
			isResultValid_o		<=	1'b0;
			//fpcsr_o			<=	'0;
		end
		else
		begin
			ss					<=	ss_next;
		//input
			doDiv_r				<=	doDiv_next;
			rndMode_r			<=	rndMode_r_next;
		//output
			result_o			<=	result_o_next;
			isResultValid_o		<=	isResultValid_o_next;
		end
	end

//////////////////////////////////////////////////////////////////
// 						combinational logic						//
//////////////////////////////////////////////////////////////////

	always_comb
	begin
		ss_next					=	ss;
		doDiv_next				=	1'b0;

		result_o_next			=	result_o;
		isResultValid_o_next	=	isResultValid_o;

		s_res					=	1'b0;
		e_res					=	'0;
		f_res					=	'0;
		isToRound				=	1'b0;

		isResValid				=	1'b0;
		case (ss)
			IDLE:
			begin
				if (do_div)
				begin
					ss_next							=	WORK;
					doDiv_next		                =	1'b1;
					isResultValid_o_next			=	1'b0;
				end
			end
			WORK:
			begin
                // Do a division
				s_res						=	div_s_res;
				e_res						=	div_e_res;
				f_res						=	div_f_res;
				isToRound					=	div_isToRound;
				isResValid					=	div_valid;

				if (isResValid)
				begin
					result_o_next					=	res_postRnd;
					isResultValid_o_next			=	1'b1;
					ss_next							=	DONE;
				end
			end
			DONE:
			begin
				if (padv_i)
				begin
					isResultValid_o_next			=  1'b0;
					ss_next							=	IDLE;
				end
			end
         default:
					ss_next							=	IDLE;
		endcase
	end

//////////////////////////////////////////////////////////////////
// 			operands pre-processing	- sequential logic			//
//////////////////////////////////////////////////////////////////

   always_comb
   begin
//      s_op1_r			=	s_op1_wire;
//      extE_op1_r		=	extE_op1_wire;
//      isInf_op1_r		=	isInf_op1_wire;
//      isZ_op1_r		=	isZ_op1_wire;
//      isSNAN_op1_r	=	isSNAN_op1_wire;
//      isQNAN_op1_r	=	isQNAN_op1_wire;
      extShF_op1_r	=	extShF_op1_wire;
      nlz_op1_r		=	nlz_op1_wire;
   end

	always_ff @(posedge clk)
	begin
		if (rst)
		begin
			s_op1_r			<=	'0;
			extE_op1_r		<=	'0;
			isInf_op1_r		<=	'0;
			isZ_op1_r		<=	'0;
			isSNAN_op1_r	<=	'0;
			isQNAN_op1_r	<=	'0;
         isDN_op1_r     <= '0;
			s_op2_r			<=	'0;
			extE_op2_r		<=	'0;
			isInf_op2_r		<=	'0;
			isZ_op2_r		<=	'0;
			isSNAN_op2_r	<=	'0;
			isQNAN_op2_r	<=	'0;
         isDN_op2_r     <= '0;
			//	mul/div only
//			extShF_op1_r	<=	'0;
//			nlz_op1_r		<=	'0;
			extShF_op2_r	<=	'0;
			nlz_op2_r		<=	'0;
		end
		else
		begin
			s_op1_r			<=	s_op1_wire;
			extE_op1_r		<=	extE_op1_wire;
			isInf_op1_r		<=	isInf_op1_wire;
			isZ_op1_r		<=	isZ_op1_wire;
			isSNAN_op1_r	<=	isSNAN_op1_wire;
			isQNAN_op1_r	<=	isQNAN_op1_wire;
         isDN_op1_r     <= isDN_op1_wire;
			s_op2_r			<=	s_op2_wire;
			extE_op2_r		<=	extE_op2_wire;
			isInf_op2_r		<=	isInf_op2_wire;
			isZ_op2_r		<=	isZ_op2_wire;
			isSNAN_op2_r	<=	isSNAN_op2_wire;
			isQNAN_op2_r	<=	isQNAN_op2_wire;
         isDN_op2_r     <= isDN_op2_wire;
			//	mul/div only
//			extShF_op1_r	<=	extShF_op1_wire;
//			nlz_op1_r		<=	nlz_op1_wire;
			extShF_op2_r	<=	extShF_op2_wire;
			nlz_op2_r		<=	nlz_op2_wire;
		end
	end

//////////////////////////////////////////////////////////////////
// 			operands pre-processing	- combinational logic		//
//////////////////////////////////////////////////////////////////

	always_comb
	begin
		{s_op1_wire, e_op1_wire, f_op1_wire}										= FUNC_splitOperand(op1_i);
		extE_op1_wire																= FUNC_extendExp(e_op1_wire, isDN_op1_wire);
		extF_op1_wire 																= FUNC_extendFrac(f_op1_wire, isDN_op1_wire, isZ_op1_wire);

		{s_op2_wire, e_op2_wire, f_op2_wire}										= FUNC_splitOperand(op2_i);
		extE_op2_wire																= FUNC_extendExp(e_op2_wire, isDN_op2_wire);
		extF_op2_wire 																= FUNC_extendFrac(f_op2_wire, isDN_op2_wire, isZ_op2_wire);

		//	mul/div only
		nlz_op1_wire																= FUNC_numLeadingZeros(extF_op1_wire);
		nlz_op2_wire																= FUNC_numLeadingZeros(extF_op2_wire);
		extShF_op1_wire																= extF_op1_wire << nlz_op1_wire;
		extShF_op2_wire																= extF_op2_wire << nlz_op2_wire;
		rndMode_r_next					                                            = rndMode_i;
	end

   checkOperand i_checkOperand1
   (
      .op     (op1_i),
      .result ({isInf_op1_wire,isDN_op1_wire,isZ_op1_wire,isSNAN_op1_wire,isQNAN_op1_wire})
   );
   checkOperand i_checkOperand2
   (
      .op     (op2_i),
      .result ({isInf_op2_wire,isDN_op2_wire,isZ_op2_wire,isSNAN_op2_wire,isQNAN_op2_wire})
   );

	// NOTE: fpu ready signal that makes the pipeline to advance.
	// It is simple and plain combinational logic: this should require
	// some cpu-side optimizations to improve the overall system timing
	// in the future. The entire advancing mechanism should be re-designed
	// from scratch

	assign isReady_o = (ss == IDLE) | isResultValid_o;

//////////////////////////////////////////////////////////////////
// 				float rounding - combinational logic			//
//////////////////////////////////////////////////////////////////

	always_comb
	begin
		if (rndMode_r == FPU_RNDMODE_NEAREST)
			f_res_postRnd	= f_res_postRnd_mod;
		else
			f_res_postRnd	= f_res[3+:LAMP_FLOAT_F_DW];
		if (isToRound)
			res_postRnd		= {s_res, e_res, f_res_postRnd};
		else
			res_postRnd		= {s_res, e_res, f_res[5+:LAMP_FLOAT_F_DW]};
	end

   rndToNearestEven i_rndToNearestEven
   (
      .op     ( f_res             ),
      .result ( f_res_postRnd_mod )
   );

	lampFPU_div
		lampFPU_div0 (
			.clk					(clk),
			.rst					(rst),
			//	inputs
			.doDiv_i				(doDiv_r),
			.s_op1_i				(s_op1_r),
			.extShF_op1_i			(extShF_op1_r),
			.extE_op1_i				(extE_op1_r),
			.nlz_op1_i				(nlz_op1_r),
			.isZ_op1_i				(isZ_op1_r),
			.isInf_op1_i			(isInf_op1_r),
			.isSNAN_op1_i			(isSNAN_op1_r),
			.isQNAN_op1_i			(isQNAN_op1_r),
			.s_op2_i				(s_op2_r),
			.extShF_op2_i			(extShF_op2_r),
			.extE_op2_i				(extE_op2_r),
			.nlz_op2_i				(nlz_op2_r),
			.isZ_op2_i				(isZ_op2_r),
			.isInf_op2_i			(isInf_op2_r),
			.isSNAN_op2_i			(isSNAN_op2_r),
			.isQNAN_op2_i			(isQNAN_op2_r),
			//	outputs
			.s_res_o				(div_s_res),
			.e_res_o				(div_e_res),
			.f_res_o				(div_f_res),
			.valid_o				(div_valid),
			.isToRound_o			(div_isToRound)
		);

endmodule
