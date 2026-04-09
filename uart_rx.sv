\TLV_version 1d: tl-x.org
\SV
/* verilator lint_off UNUSED */
/* verilator lint_off DECLFILENAME */
/* verilator lint_off WIDTH */

// UART TRANSMITTER DESIGN

module UART_TX #(parameter word_size = 8)(
    input [word_size -1:0] data_bus,
    input load_tx_datareg,      //load data reg
          byte_ready,           //signal ready
          t_byte,               //signal tx start
          rst_b,                //resets internal regs
          clk,                  
    output serial_out
);

wire load_tx_DR, load_tx_SHFTREG, start, shift, clear, bc_lt_bcmax; 

control_unit tx_cu(
    .load_tx_DR(load_tx_DR),
    .load_tx_SHFTREG(load_tx_SHFTREG),
    .start(start),
    .shift(shift),
    .clear(clear),
    .load_tx_datareg(load_tx_datareg),
    .byte_ready(byte_ready),
    .t_byte(t_byte),
    .clk(clk),
    .rst_b(rst_b),
    .bc_lt_bcmax(bc_lt_bcmax));

datapath_unit tx_du(
    .load_tx_DR(load_tx_DR),
    .load_tx_SHFTREG(load_tx_SHFTREG),
    .start(start),
    .shift(shift),
    .clear(clear),
    .clk(clk),
    .rst_b(rst_b),
    .serial_out(serial_out),
    .bc_lt_bcmax(bc_lt_bcmax),
    .data_bus(data_bus));

endmodule


module control_unit #(
    parameter one_hot_count = 3,
              state_count = one_hot_count,
              size_bit_count = 3,

              idle = 3'b001,
              waiting = 3'b010,
              sending = 3'b100,
              all_ones = 9'b1_1111_1111
    )(
        input load_tx_datareg,      //load data reg
              byte_ready,           //signal ready
              t_byte,               //signal tx start
              rst_b,                //resets internal regs
              clk,
              bc_lt_bcmax,
        output reg load_tx_DR,
                   load_tx_SHFTREG,
                   start,
                   shift,
                   clear
);
reg [state_count-1:0] state, next_state;
always @(state, load_tx_datareg, byte_ready, t_byte, bc_lt_bcmax) begin:OUTPUT_AND_NEXT_STATE
    load_tx_DR = 0;
    load_tx_SHFTREG = 0;
    start = 0;
    shift = 0;
    clear = 0;
    next_state = idle;
    case(state)
        idle: if(load_tx_datareg == 1'b1)begin
            load_tx_DR = 1;
            next_state = idle;
        end
        else if(byte_ready == 1'b1)begin
            load_tx_SHFTREG = 1;
            next_state = waiting;
        end

        waiting: if(t_byte == 1)begin
            start = 1;
            next_state = sending;
        end
        else
            next_state = waiting;

        sending: if(bc_lt_bcmax)begin
            shift = 1;
            next_state = sending;
        end
        else begin
            clear = 1;
            next_state = idle;
        end

        default: next_state = idle;
    endcase
end

always @(posedge clk, negedge rst_b)begin:STATE_TRANSITIONS
    if(rst_b == 1'b0)
        state<=idle;
    else
        state<=next_state;
end

endmodule


module datapath_unit #(
    parameter word_size = 8,
              size_bit_count = 3,
              all_ones = {(word_size+1){1'b1}}
          )(
    input load_tx_DR,
          load_tx_SHFTREG,
          start,
          shift,
          clear,
          clk,
          rst_b,
    input [word_size-1:0] data_bus,

    output serial_out,
           bc_lt_bcmax
);

reg [word_size-1:0] tx_datareg;
reg [word_size:0] tx_shftreg;

reg [size_bit_count:0] bit_count;

assign serial_out = tx_shftreg[0];
assign bc_lt_bcmax = (bit_count < word_size + 1);

always @(posedge clk, negedge rst_b)
    if(rst_b == 0)begin
        tx_shftreg <= all_ones;
        bit_count <= 0;
    end
    else begin:REGISTER_TRANSFERS
        if(load_tx_DR == 1'b1)
            tx_datareg <= data_bus;

        if(load_tx_SHFTREG == 1'b1)
            tx_shftreg <= {tx_datareg, 1'b1};

        if(start == 1'b1)
            tx_shftreg[0] <= 0;

        if(clear == 1'b1)
            bit_count <= 0;

        if(shift == 1'b1)begin
            tx_shftreg <= {1'b1, tx_shftreg[word_size:1]};

            bit_count <= bit_count + 1;
        end
    end
endmodule


// MAKERCHIP TOP ENVIRONMENT (TB)------------------------------------------------------------------------------------

module top(input logic clk, input logic reset, input logic [31:0] cyc_cnt, output logic passed, failed);

    reg load_tx_datareg, byte_ready, t_byte;
    reg [7:0] data_bus;
    wire serial_out;
    
    // Makerchip's native reset is active high.My design uses active low
    wire rst_b = ~reset; 

    UART_TX uut(
        .data_bus(data_bus),
        .load_tx_datareg(load_tx_datareg),
        .byte_ready(byte_ready),
        .t_byte(t_byte),
        .rst_b(rst_b), 
        .clk(clk),
        .serial_out(serial_out) // Connected unmapped output
    );

    // Synchronous, cycle-based stimulus generation
    always @(posedge clk) begin
        if (reset) begin
            load_tx_datareg <= 0;
            byte_ready <= 0;
            t_byte <= 0;
            data_bus <= 8'h00;
        end else begin
            // Default signals to 0 so we don't have to manually de-assert them
            load_tx_datareg <= 0;
            byte_ready <= 0;
            t_byte <= 0;

            // Apply stimulus based on specific clock cycle numbers
            case (cyc_cnt)
                32'd2:  begin data_bus <= 8'ha7; load_tx_datareg <= 1; end
                32'd4:  begin byte_ready <= 1; end
                32'd8:  begin t_byte <= 1; end
                32'd9:  begin data_bus <= 8'h1a; load_tx_datareg <= 1; end
                32'd12: begin load_tx_datareg <= 1; end
                32'd13: begin data_bus <= 8'hb4; end
            endcase
        end
    end

    // End simulation after enough cycles have passed to transmit the data
    assign passed = (cyc_cnt > 32'd35);
    assign failed = 1'b0;

\SV
endmodule
