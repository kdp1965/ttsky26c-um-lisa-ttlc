/*
==============================================================================
shift_reg_io.v:  Tiny Tapeout Logic Controller (MC14500 based) 
                 shift-register based external I/O interface.

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
module shift_reg_io
(
   input  wire          clk,                 // System clock
   input  wire          rst_n,               // System reset
   input  wire [2:0]    data_in,             // Serial data inputs
   input  wire [47:0]   output_buffer,       // Input to the module, drives the serial output
   input  wire [1:0]    clk_div,             // Clock division factor control (00: /2, 01: /4, 10: /8, 11: /16)
   input  wire          start,               // Start the I/O transfer
   output reg           io_busy,             // Indicates I/O transfer busy
   output wire [2:0]    data_out,            // Serial data outputs
   output reg           latch,               // Latch signal for external register control
   output reg           shift_clk,           // Shift clock output for external shift registers
   output wire [47:0]   input_buffer         // Output from the module, captures the serial input
);

   // Parameters
   localparam integer DATA_WIDTH   = 48;    // Total data width for input and output
   localparam integer SEG_WIDTH    = 16;     // Width of each data segment
   localparam [1:0]   IDLE         = 2'd0,
                      SHIFT_IO     = 2'd1,
                      LATCH        = 2'd2,
                      SHIFT_DONE   = 2'd3;
                      
   wire [15:0]             output_vec[2:0];
//   wire [3:0]              output_idx;

   // Internal Registers for input buffer
   reg  [DATA_WIDTH-1:0]   input_buffer_reg;
   reg  [3:0]              clk_count;        // Counter for clock division
   wire [3:0]              max_count;        // Maximum count value based on clk_div
   reg  [3:0]              shift_count;      // Count for the number of shifts performed
   reg  [1:0]              state;
   reg  [1:0]              after_state;
   reg                     last_clk;

   assign input_buffer = input_buffer_reg; // Assign the internal register to the output
   assign max_count = (clk_div == 2'b00) ? 1 :
                      (clk_div == 2'b01) ? 3 :
                      (clk_div == 2'b10) ? 7 :
                      15;                 // Default to 15 for clk_div == 2'b11

   assign output_vec[0] = output_buffer[15:0];
   assign output_vec[1] = output_buffer[31:16];
   assign output_vec[2] = output_buffer[47:32];
//   assign output_idx    = 4'd15 - shift_count;
   assign data_out[0] = output_vec[0][shift_count];
   assign data_out[1] = output_vec[1][shift_count];
   assign data_out[2] = output_vec[2][shift_count];

   // State Machine for controlling the process
   // Clock and shift logic
   always @(posedge clk)
   begin
      if (~rst_n)
      begin
         input_buffer_reg  <= 48'h0;
         clk_count         <= 4'h0;
         shift_clk         <= 1'b0;
         shift_count       <= 4'h0;              // Reset shift_count
         state             <= IDLE;
         after_state       <= IDLE;
         latch             <= 1'b1;
         io_busy           <= 1'b0;
      end
      else
      begin
         // State machine for shifting data
         case (state)
            IDLE:
            begin
               if (start)
               begin
                  io_busy     <= 1'b1;
                  shift_count <= 4'hf;       // Reset shift count at start of operation
                  last_clk    <= 1'b0;
                  latch       <= 1'b0;       // Pulse to capture inputs before shifting
                  state       <= LATCH;
                  after_state <= SHIFT_IO;
                  clk_count   <= max_count;
//                  data_out[0] <= output_vec[0][15];
//                  data_out[1] <= output_vec[0][15];
//                  data_out[2] <= output_vec[0][15];
               end
               else
                  latch    <= 1'b1;
            end

            SHIFT_IO:
            begin
               latch    <= 1'b1;

               // Clock division for shift_clk
               if (clk_count == 4'h0)
               begin
                  clk_count   <= max_count;
                  if (shift_clk | ~last_clk)
                     shift_clk   <= ~shift_clk;  // Toggle shift clock
               end
               else
                  clk_count <= clk_count - 1;
               
               // Update input data at the rising edge of shift_clk
               if (!shift_clk && clk_count == 0)  // Operate on rising edge of shift_clk
               begin  
                  // Shifting input data in, and preparing output data
                  input_buffer_reg[SEG_WIDTH-1:0]             <= {input_buffer_reg[SEG_WIDTH-2:0], data_in[0]};
                  input_buffer_reg[2*SEG_WIDTH-1:SEG_WIDTH]   <= {input_buffer_reg[2*SEG_WIDTH-2:SEG_WIDTH], data_in[1]};
                  input_buffer_reg[3*SEG_WIDTH-1:2*SEG_WIDTH] <= {input_buffer_reg[3*SEG_WIDTH-2:2*SEG_WIDTH], data_in[2]};
               end

               // Update output data at the falling edge of shift_clk
//               if (shift_clk && clk_count == 0)  // Operate on rising edge of shift_clk
//               begin  
//                  data_out[0] <= output_vec[0][output_idx];
//                  data_out[1] <= output_vec[1][output_idx];
//                  data_out[2] <= output_vec[2][output_idx];
//               end

               // Update the shift count
               if (shift_clk && clk_count == 0 && !last_clk)  // Operate on rising edge of shift_clk
                  shift_count <= shift_count - 1;

               //if (shift_count == CYCLES && shift_clk == 1'b0) // && clk_count == 4'h0)
               if (shift_count == 0 && shift_clk == 1'b1)
                  last_clk <= 1'b1;
               else if (last_clk && clk_count == 0)
               begin
                  last_clk    <= 1'b0;
                  latch       <= 1'b0;     // Pulse to latch the outputs after the final shifting
                  state       <= LATCH;
                  clk_count   <= max_count;
                  after_state <= SHIFT_DONE;
               end
            end

            LATCH:
            begin
               shift_clk <= 1'b0;
               if (clk_count == 4'h0)
               begin
                  clk_count <= max_count;
                  latch     <= 1'b1;
                  state     <= after_state;
               end
               else
                  clk_count <= clk_count - 1;
            end

            SHIFT_DONE:
            begin
               io_busy <= 1'b0;
               state   <= IDLE;
            end
         endcase
      end
   end
endmodule

