
// requantize_unit.sv
// Converts a wide (e.g. 32-bit) accumulator value back down to an INT8

module requantize_unit #(
    parameter int ACC_WIDTH = 32,
    parameter int OUT_WIDTH = 8
)(
    input  logic signed [ACC_WIDTH-1:0] acc_in,
    input  logic [4:0]                  shift,  
    output logic signed [OUT_WIDTH-1:0] data_out
);

    localparam signed [ACC_WIDTH-1:0] OUT_MAX = (1 <<< (OUT_WIDTH-1)) - 1;   
    localparam signed [ACC_WIDTH-1:0] OUT_MIN = -(1 <<< (OUT_WIDTH-1));      

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
