/*
==============================================================================
ttlc_io.v:  Tiny Tapeout Logic Controller (MC14500 based) I/O module

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

module ttlc_io
(
   input  wire          clk,           // Clock signal
   input  wire          rst,           // Synchronous reset input
   (* keep = "true" *)
   input  wire [7:0]    address,       // 12-bit address bus
   input  wire          mem_write,     // Memory write enable
   input  wire          data_in,       // Data input for writes
   input  wire          rr_value,      // RR output from MC14500B
   input  wire [47:0]   input_pins,    // External input pins
   output reg  [47:0]   output_pins,   // Driven from internal registers, renumbered
   (* keep = "true" *)
   output wire          data_out,      // Data output pin, continuously assigned
   output wire [7:0]    port_out,
   input  wire [7:0]    port_in,
   output wire          ttlc_int
);

   // Internal memory for temporary storage and output register
   reg  [31:0]   temp_storage;

   // A large vector that contains all read back values
   wire [138:0] read_values;

   // Assign values to the large vector
   assign read_values = {1'b1, 1'b0, rr_value, port_in, temp_storage, input_pins, output_pins};
   assign port_out = temp_storage[7:0];
   assign ttlc_int = temp_storage[8];

   // Continuous assignment to data_out using bit slicing
   //assign data_out = address < 192 ? read_values[address[7:0]] : 1'b0;
   assign data_out = read_values[address];

   // Handle writing operations
   always @(posedge clk)
   begin
      if (rst)
      begin
         // Reset temporary storage and output registers when RST is high
         temp_storage <= 32'h0;
         output_pins <= 48'h0;
      end
      else
      begin
         if (mem_write)
         begin
            // Test if writing to output_pins or temp_storage
            if (address < 48)
               output_pins[address[5:0]] <= data_in;

            // Writing to temp_storage
            //else if (address >= 128 && address < 192)
            else if (address[6] & address[5])
               temp_storage[address[4:0]] <= data_in;
         end
      end
   end

endmodule

