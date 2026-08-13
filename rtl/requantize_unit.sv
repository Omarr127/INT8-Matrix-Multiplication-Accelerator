// =============================================================================
// requantize_unit.sv
// -----------------------------------------------------------------------------
// Converts a wide (e.g. 32-bit) accumulator value back down to an INT8
// result, the way a real NPU output stage would before writing activations
// back out for the next layer.
//
// Implements: out = saturate( round( acc >>> shift ), INT8_MIN, INT8_MAX )
//
// 'shift' is a runtime-programmable arithmetic right-shift standing in for
// the combined input/weight quantization scale of a real INT8 pipeline
// (in a full flow this would be derived from scale_a * scale_b / scale_out).
// Rounding is round-half-up via the classic "add half the divisor, then
// shift" trick, applied only to positive shift amounts.
// =============================================================================

module requantize_unit #(
    parameter int ACC_WIDTH = 32,
    parameter int OUT_WIDTH = 8
)(
    input  logic signed [ACC_WIDTH-1:0] acc_in,
    input  logic [4:0]                  shift,   // 0-31 right-shift amount
    output logic signed [OUT_WIDTH-1:0] data_out
);

    localparam signed [ACC_WIDTH-1:0] OUT_MAX = (1 <<< (OUT_WIDTH-1)) - 1;   //  127 for INT8
    localparam signed [ACC_WIDTH-1:0] OUT_MIN = -(1 <<< (OUT_WIDTH-1));      // -128 for INT8

    logic signed [ACC_WIDTH-1:0] rounded;
    logic signed [ACC_WIDTH-1:0] half;

    always_comb begin
        // round-half-up before shifting: add 2^(shift-1) then arithmetic shift
        half    = (shift == 0) ? '0 : (1 <<< (shift-1));
        rounded = (acc_in + half) >>> shift;

        if (rounded > OUT_MAX)
            data_out = OUT_WIDTH'(OUT_MAX);
        else if (rounded < OUT_MIN)
            data_out = OUT_WIDTH'(OUT_MIN);
        else
            data_out = OUT_WIDTH'(rounded);
    end

endmodule
