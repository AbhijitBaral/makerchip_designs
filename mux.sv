\TLV_version 1d: tl-x.org
\SV
/* verilator lint_off UNUSED */
/* verilator lint_off DECLFILENAME */

// 1. Define your sub-module
module mux (input i0 , input i1 , input sel , output reg y);
   always @ (*) begin
      if(sel)
         y = i1;
      else
         y = i0;
   end
endmodule

// 2. Define the 'top' module interface as required by Makerchip
module top(input logic clk, input logic reset, input logic [31:0] cyc_cnt, output logic passed, failed);
   
   // Internal signals for testing
   logic i0, i1, sel, y;

   // 3. Simple Testbench Logic (Stimulus)
   // Since we aren't using TLV random signals, we use SV blocks
   always @(posedge clk) begin
      i0  <= cyc_cnt[0]; // Toggles every cycle
      i1  <= cyc_cnt[1]; // Toggles every 2 cycles
      sel <= cyc_cnt[2]; // Toggles every 4 cycles
   end

   // 4. Instantiate your module
   mux dut (
      .i0(i0), 
      .i1(i1), 
      .sel(sel), 
      .y(y)
   );

   // 5. Makerchip Status Logic
   assign passed = cyc_cnt > 32'h20; // Pass after 32 cycles
   assign failed = 1'b0;

\SV
endmodule // 6. Close the module in a final SV region
