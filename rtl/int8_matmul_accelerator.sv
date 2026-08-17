
// int8_matmul_accelerator.sv-
// Top-level INT8 matrix-multiplication accelerator.
// Computes  C[N x M] = A[N x K] * B[K x M]   (INT8 in, wide-accumulate out)

module int8_matmul_accelerator #(
    parameter int N          = 4,   
    parameter int K          = 4,   
    parameter int M          = 4,  
    parameter int DATA_WIDTH = 8,   // INT8 operands
    parameter int ACC_WIDTH  = 32   
)(
    input  logic clk,
    input  logic rst_n,

    //matrix load port 
    input  logic                              wr_en,
    input  logic                              wr_target,     // 0 = A, 1 = B
    input  logic [$clog2((N*K>K*M)?N*K:K*M)-1:0] wr_addr,    
    input  logic signed [DATA_WIDTH-1:0]      wr_data,

    // control
    input  logic start,     
    output logic done,      

    //result read port
    input  logic                              rd_en,
    input  logic [$clog2(N*M)-1:0]            rd_addr,    
    output logic signed [ACC_WIDTH-1:0]       rd_data_raw,   
    output logic signed [DATA_WIDTH-1:0]      rd_data_q,     // requantized INT8 result
    input  logic [4:0]                        rd_shift       
);

   
    // Operand memories (simple register files - small enough for a demo)
    logic signed [DATA_WIDTH-1:0] A_mem [0:N-1][0:K-1];
    logic signed [DATA_WIDTH-1:0] B_mem [0:K-1][0:M-1];

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wr_target == 1'b0)
                A_mem[wr_addr / K][wr_addr % K] <= wr_data;
            else
                B_mem[wr_addr / M][wr_addr % M] <= wr_data;
        end
    end

    
    // Control FSM
    logic mac_en, clear_acc;
    logic [$clog2(K)-1:0] k_cnt;

    control_fsm #(.K(K)) u_fsm (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .mac_en    (mac_en),
        .clear_acc (clear_acc),
        .k_cnt     (k_cnt),
        .done      (done)
    );

    // N x M array of MAC units (one PE per output element)
    logic signed [ACC_WIDTH-1:0] C_mem [0:N-1][0:M-1];

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi++) begin : ROW
            for (gj = 0; gj < M; gj++) begin : COL
                mac_unit #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH)
                ) u_mac (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clear_acc (clear_acc),
                    .en        (mac_en),
                    .a_in      (A_mem[gi][k_cnt]),  
                    .b_in      (B_mem[k_cnt][gj]),   
                    .acc_out   (C_mem[gi][gj])
                );
            end
        end
    endgenerate

    // Result readout
    logic signed [ACC_WIDTH-1:0] rd_data_raw_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_data_raw_r <= '0;
        else if (rd_en)
            rd_data_raw_r <= C_mem[rd_addr / M][rd_addr % M];
    end

    assign rd_data_raw = rd_data_raw_r;

    requantize_unit #(
        .ACC_WIDTH (ACC_WIDTH),
        .OUT_WIDTH (DATA_WIDTH)
    ) u_requant (
        .acc_in   (rd_data_raw_r),
        .shift    (rd_shift),
        .data_out (rd_data_q)
    );

endmodule
