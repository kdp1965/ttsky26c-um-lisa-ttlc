/*
================================================================================
lisa_rx8n:  Lisa Peripheral Design for RX 8bit No parity

Copyright 1998-2015 Ken Pettit

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

Written April 8, 1998
Kenneth D. Pettit
================================================================================
*/

module lisa_rx8n
  #(
   parameter DEPTH_LOG2 = 3                     // the receive FIFO: 8 bytes
   )
  (
   // Timing and reset inputs
   input  wire                clk,              // System clock 
   input  wire                rst_n,            // Active low reset

   input  wire                baud_ref,         // Baud Rate reference
   input  wire                rxd,              // RX data
   input  wire                rd,               // Read signal: its rising edge takes the byte

   output wire [7:0]          d,                // Output parallel data (the oldest byte)
   output wire                data_avail,       // '1' when data available
   output reg                 rx_strobe,        // one clock per byte received
   output wire [7:0]          rx_byte,          // ... that byte
   output reg                 overrun           // a byte arrived with the FIFO full (sticky until read empty)
   );

   // ================================================
   // Internal signals
   // ================================================
   reg  [7:0]        bit_count;                 // Count 0 to 160
   reg  [7:0]        shift;                     // Shift register

   reg               s_last_rd;                 // Previous read signal
   reg               s_rxd;                     // 
   reg               s_baud_edge;

   // The receive FIFO (TT07 held one byte: a second one arriving before the
   // program read the first was lost - the console of a program fetching
   // from a plain SPI flash lost every other character of a burst)
   reg  [7:0]        fifo[0:(1 << DEPTH_LOG2) - 1];
   reg  [DEPTH_LOG2:0] wr_ptr;
   reg  [DEPTH_LOG2:0] rd_ptr;
   wire              empty = wr_ptr == rd_ptr;
   wire              full  = (wr_ptr[DEPTH_LOG2-1:0] == rd_ptr[DEPTH_LOG2-1:0]) &&
                             (wr_ptr[DEPTH_LOG2] != rd_ptr[DEPTH_LOG2]);
   wire              push;
   reg  [7:0]        rx_byte_r;                 // the byte, taken at the stop bit's middle
   assign push = rx_strobe;

   assign d = fifo[rd_ptr[DEPTH_LOG2-1:0]];
   assign data_avail = !empty;
   assign rx_byte = rx_byte_r;

   // ================================================
   // The read side: the rising edge of rd pops a byte
   // ================================================
   always @(posedge clk)
   begin
      if (~rst_n)
      begin
         s_last_rd <= 1'b0;
         rd_ptr <= {(DEPTH_LOG2+1){1'b0}};
      end
      else
      begin
         if (rd & ~s_last_rd && !empty)
            rd_ptr <= rd_ptr + 1'b1;

         s_last_rd <= rd;
      end
   end

   // ================================================
   // The write side
   // ================================================
   always @(posedge clk)
   begin
      if (~rst_n)
      begin
         wr_ptr <= {(DEPTH_LOG2+1){1'b0}};
         overrun <= 1'b0;
      end
      else
      begin
         if (push)
         begin
            if (!full)
            begin
               fifo[wr_ptr[DEPTH_LOG2-1:0]] <= rx_byte_r;
               wr_ptr <= wr_ptr + 1'b1;
            end
            else
               overrun <= 1'b1;
         end
         else if (empty)
            overrun <= 1'b0;
      end
   end

   // ================================================
   // RX data state machine
   // ================================================
   always @(posedge clk)
   begin
      if (~rst_n)
      begin
         bit_count <= 8'd160;
         shift <= 8'h0;
         s_rxd <= 1'b1;
         s_baud_edge <= 1'b0;
         rx_strobe <= 1'b0;
         rx_byte_r <= 8'h0;
      end
      else
      begin
         // Create baud_ref edge detect
         s_baud_edge <= baud_ref;
         rx_strobe <= 1'b0;

         // Detect rising edge of baud_ref
         if (baud_ref & !s_baud_edge)
         begin
            // Save the RX sample
            s_rxd <= rxd;

            // Check if there is a receive active
            if (bit_count > 151)
            begin
               // --------------------------------------------
               // No receive active.  Check for start bit
               // --------------------------------------------
               if (s_rxd == 1'b0)
                  bit_count <= 1;               // Start bit found
            end
            else
            begin
               // --------------------------------------------
               // Receive Active.  Increment bit/clock counter
               // --------------------------------------------
               bit_count <= bit_count + 1;

               // Check if in middle of a bit time
               if (bit_count[3:0] == 4'h7)
               begin
                  // Shift the register bits
                  shift[6:0] <= shift[7:1];

                  // Check if in middle of last bit.  Latch data to output
                  // buffer and reset the counter.
                  if (bit_count[7:4] == 4'h9)
                  begin
                     rx_strobe <= 1'b1;         // the byte: into the FIFO
                     rx_byte_r <= shift;        // (shift moves on in this clock)
                     bit_count <= 160;
                  end
                  else
                     shift[7] <= s_rxd;
               end
            end
         end
      end
   end

endmodule

