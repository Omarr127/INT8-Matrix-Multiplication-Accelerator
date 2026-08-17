
// mac_unit.sv
// Single INT8 Multiply-Accumulate (MAC) unit.
// This is the fundamental compute primitive of the accelerator.

module mac_unit #(
    parameter int DATA_WIDTH = 8,   // INT8 operands
    parameter int ACC_WIDTH  = 32   // wide accumulator to prevent overflow
)(
    input  logic                            clk,
    input  logic                            rst_n,     
    input  logic                            clear_acc,  
    input  logic                            en,       
    input  logic signed [DATA_WIDTH-1:0]    a_in,      
    input  logic signed [DATA_WIDTH-1:0]    b_in,       
    output logic signed [ACC_WIDTH-1:0]     acc_out     
);

    // Full-precision product of the two INT8 operands.
    logic signed [2*DATA_WIDTH-1:0] product;

    always_comb begin
        product = a_in * b_in;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
        end else if (en) begin
            if (clear_acc)
                acc_out <= {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product}; 
            else
                acc_out <= acc_out + {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
        end
    
    end

endmodule
