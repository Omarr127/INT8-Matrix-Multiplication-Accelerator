// =============================================================================
// mac_unit.sv
// -----------------------------------------------------------------------------
// Single INT8 Multiply-Accumulate (MAC) unit.
//
// This is the fundamental compute primitive of the accelerator. Every
// Processing Element (PE) in the systolic-style array instantiates exactly
// one of these. Each cycle it can:
//   - clear_acc = 1 : start a brand-new accumulation (acc <= product)
//   - en = 1        : accumulate the current product into the running sum
//   - en = 0        : hold the current accumulator value
//
// Inputs are signed 8-bit (INT8), the accumulator is wide (32-bit by
// default) to avoid overflow across the full reduction dimension K:
//   worst case per term = 127 * 127 = 16129 (~15 bits)
//   summed over K terms  -> well within 32 bits for any realistic K.
// =============================================================================

module mac_unit #(
    parameter int DATA_WIDTH = 8,   // INT8 operands
    parameter int ACC_WIDTH  = 32   // wide accumulator to prevent overflow
)(
    input  logic                            clk,
    input  logic                            rst_n,      // async active-low reset
    input  logic                            clear_acc,  // start new accumulation
    input  logic                            en,         // MAC enable this cycle
    input  logic signed [DATA_WIDTH-1:0]    a_in,       // activation operand
    input  logic signed [DATA_WIDTH-1:0]    b_in,       // weight operand
    output logic signed [ACC_WIDTH-1:0]     acc_out     // running accumulation
);

    // Full-precision product (no truncation) of the two INT8 operands.
    logic signed [2*DATA_WIDTH-1:0] product;

    always_comb begin
        product = a_in * b_in;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
        end else if (en) begin
            if (clear_acc)
                acc_out <= {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product}; // sign-extended load
            else
                acc_out <= acc_out + {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
        end
        // else: hold current value (implicit)
    end

endmodule
