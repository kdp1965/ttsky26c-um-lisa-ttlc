/*
==============================================================================
mc14500b.v:  Implementation of the Motorola MC14500B.

Copyright 2024 by Ken Pettit <pettitkd@gmail.com>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.

==============================================================================
*/

module mc14500b
(
   input  wire             clk,
   input  wire             RST,
   input  wire             DATA,
   input  wire             I0,
   input  wire             I1,
   input  wire             I2,
   input  wire             I3,

   input  wire             run,

   output wire             WRITE,
   output wire             DATA_OUT,
   output wire             RR,
   output wire             JMP,
   output wire             RTN,
   output wire             FLAG_O,
   output wire             FLAG_F
);

   reg   [3:0]          r_inst;
   reg                  r_skip;
   reg                  r_oen;
   reg                  r_ien;
   reg                  r_rr;
   reg                  r_data;
   reg                  r_flagO;
   reg                  r_flagF;
   reg                  r_sto1;
   reg                  r_sto2;
   reg                  r_run;
   reg                  r_stall;

   wire                 op_ld;
   wire                 op_ldc;
   wire                 op_and;
   wire                 op_andc;
   wire                 op_or;
   wire                 op_orc;
   wire                 op_xnor;
   wire                 op_sto;
   wire                 op_stoc;
   wire                 op_ien;
   wire                 op_oen;
   wire                 op_jmp;
   wire                 op_rtn;
   wire                 op_skz;
   wire                 op_nopf;

   wire [3:0]           inst_in;

   assign inst_in  = {I3, I2, I1, I0};
   assign WRITE    = r_oen & r_sto1;
   assign DATA_OUT = op_sto ? r_rr : op_stoc ? ~r_rr : 1'bx;
   assign RR       = r_rr;
   assign FLAG_O   = r_flagO;
   assign FLAG_F   = r_flagF;
   assign JMP      = op_jmp;
   assign RTN      = op_rtn;

   /*
   ================================================================================
   Latch the instruction register and DATA in at the falling clock edge
   We also latch the O and F flags on falling edge, so do them here also.
   ================================================================================
   */
//   always @*
//      if (r_skip)
//         r_inst = 4'h0;
//      else
//         r_inst = inst_in;

   always @(negedge clk)
   begin
      if (RST)
      begin
         r_inst <= 4'h0;
         r_data <= 1'b0;
         r_flagO <= 1'b0;
         r_flagF <= 1'b0;
      end
      else
      begin
         if (run | r_run)
         begin
            // For SKP opcode, we load NOPO to skip the opcode
            if (r_skip)
               r_inst <= 4'h0;
            else
               r_inst <= inst_in;
         end

         // Allow updates only if the processor is running
         if (r_run && !r_stall)
         begin
            // Latch the input data
            r_data <= r_ien & DATA;

            // Implement the O flag
            if (!r_skip && inst_in == 4'h0)
               r_flagO <= 1'b1;
            else
               r_flagO <= 1'b0;

            // Implement the F flag
            if (!r_skip && inst_in == 4'hF)
               r_flagF <= 1'b1;
            else
               r_flagF <= 1'b0;
         end
         else
         begin
            r_flagO <= 1'b0;
            r_flagF <= 1'b0;
         end
      end
   end

   /*
   ================================================================================
   Decode the instructions
   ================================================================================
   */
   assign op_ld   = r_inst == 4'h1;
   assign op_ldc  = r_inst == 4'h2;
   assign op_and  = r_inst == 4'h3;
   assign op_andc = r_inst == 4'h4;
   assign op_or   = r_inst == 4'h5;
   assign op_orc  = r_inst == 4'h6;
   assign op_xnor = r_inst == 4'h7;
   assign op_sto  = r_inst == 4'h8;
   assign op_stoc = r_inst == 4'h9;
   assign op_ien  = r_inst == 4'hA;
   assign op_oen  = r_inst == 4'hB;
   assign op_jmp  = r_inst == 4'hC;
   assign op_rtn  = r_inst == 4'hD;
   assign op_skz  = r_inst == 4'hE;
   assign op_nopf = inst_in == 4'hF;

   /*
   ================================================================================
   Implement the OEN and IEN registers
   ================================================================================
   */
   always @(posedge clk)
   begin
      if (RST)
      begin
         r_oen   <= 1'b1;
         r_ien   <= 1'b1;
         r_stall <= 1'b0;
         r_run   <= 1'b0;
      end
      else
      begin
         // Register the run signal
         r_run <= run;

         if (r_run)
            r_stall <= op_jmp | op_rtn | op_nopf;
         else
            r_stall <= 1'b0;

         // Allow updates only if the processor is running
         if (r_run & !r_stall)
         begin
            // During an OEN instruction, set the r_oen register based on DATA
            if (op_oen)
               r_oen <= DATA;

            // During an IEN instruction, set the r_ien register based on DATA
            if (op_ien)
               r_ien <= DATA;
         end
      end
   end

   /*
   ================================================================================
   Implement the Result Register (RR)
   ================================================================================
   */
   always @(posedge clk)
   begin
      if (RST)
         r_rr <= 1'b0;
      else
      begin
         // Allow updates only if the processor is running
         if (r_run & !r_stall)
         begin
            // Process RR opcodes 
            case (1'b1)
               op_ld:      r_rr <= r_data;
               op_ldc:     r_rr <= ~r_data;
               op_and:     r_rr <= r_rr & r_data;
               op_andc:    r_rr <= r_rr & ~r_data;
               op_or:      r_rr <= r_rr | r_data;
               op_orc:     r_rr <= r_rr | ~r_data;
               op_xnor:    r_rr <= ~(r_rr ^ r_data);
            endcase
         end
      end
   end

   /*
   ================================================================================
   Implement the Skip register
   ================================================================================
   */
   always @(posedge clk)
   begin
      if (RST)
         r_skip <= 1'b0;
      else
      begin
         // Allow updates only if the processor is running
         if (r_run & !r_stall)
         begin
            if (op_skz && r_rr == 1'b0)
               r_skip <= 1'b1;
            else
               r_skip <= 1'b0;
         end
      end
   end

   /*
   ================================================================================
   Implement the Write control register 1
   ================================================================================
   */
   reg  r_sto2_n;
   always @*
`ifdef SIMULATION
      r_sto2_n = #5 ~r_sto2;
`else
      r_sto2_n = ~r_sto2;
`endif

   always @(negedge clk or negedge r_sto2_n)
   begin
      if (~r_sto2_n)
         r_sto1 <= 1'b0;
      else
      begin
         if (RST)
            r_sto1 <= 1'b0;

         // Allow updates only if the processor is running
         else if (r_run & !r_stall)
         begin
            // Test for incomming sto or stoc
            if (inst_in == 4'h8 || inst_in == 4'h9)
               r_sto1 <= 1'b1;
         end
      end
   end

   /*
   ================================================================================
   Implement the Write control register 2
   ================================================================================
   */
   always @(posedge clk or negedge r_sto1)
   begin
      if (~r_sto1)
         r_sto2 <= 1'b0;
      else
      begin
         // Simply capture the r_sto1 value
         r_sto2 <= r_sto1;
      end
   end

`ifdef SIMULATION
   reg [63:0] ascii_instr;

   /*
   ==================================================
   Assign ascii_instr 
   ==================================================
   */
   always @*
   begin
      case (inst_in)
      4'h0:                   ascii_instr = "NOPO";
      4'h1:                   ascii_instr = "LD";
      4'h2:                   ascii_instr = "LDC";
      4'h3:                   ascii_instr = "AND";
      4'h4:                   ascii_instr = "ANDC";
      4'h5:                   ascii_instr = "OR";
      4'h6:                   ascii_instr = "ORC";
      4'h7:                   ascii_instr = "XNOR";
      4'h8:                   ascii_instr = "STO";
      4'h9:                   ascii_instr = "STOC";
      4'ha:                   ascii_instr = "IEN";
      4'hb:                   ascii_instr = "OEN";
      4'hc:                   ascii_instr = "JMP";
      4'hd:                   ascii_instr = "RTN";
      4'he:                   ascii_instr = "SKZ";
      4'hf:                   ascii_instr = "NOPF";
      endcase
   end
`endif

endmodule

