// =============================================================================
// int8_matmul_accelerator.sv
// -----------------------------------------------------------------------------
// Top-level INT8 matrix-multiplication accelerator.
//
// Computes  C[N x M] = A[N x K] * B[K x M]   (INT8 in, wide-accumulate out)
//
// Architecture: output-stationary MAC array.
//   - An N x M grid of mac_units is instantiated (one per output element).
//   - A_mem holds the N x K activation matrix, B_mem holds the K x M weight
//     matrix, both loaded via a simple memory-mapped write port.
//   - On 'start', the control FSM drives K sequential cycles. On reduction
//     step k, row i of the array is fed A_mem[i][k] and column j is fed
//     B_mem[k][j]; every PE[i][j] computes and accumulates its own
//     A[i][k]*B[k][j] term locally and in parallel with all other PEs.
//   - After K cycles every PE holds C[i][j] = sum_k A[i][k]*B[k][j].
//   - Results are read out through a memory-mapped read port, either as the
//     raw 32-bit accumulation or as a requantized INT8 value.
//
// This is the same core operation (and the same "spatial array of MACs
// fed by row/column broadcast" structure) used by real weight/output-
// stationary NPU accelerators (e.g. TPU-style systolic arrays), scaled down
// to a size that is easy to simulate, understand, and eventually map to an
// FPGA fabric.
//
//   Block diagram (N = M = K = 4 default):
//
//        B_mem[k][0..3]  (broadcast down columns)
//              |   |   |   |
//              v   v   v   v
//   A_mem[0][k]-> PE  PE  PE  PE   -> C[0][0..3]
//   A_mem[1][k]-> PE  PE  PE  PE   -> C[1][0..3]
//   A_mem[2][k]-> PE  PE  PE  PE   -> C[2][0..3]
//   A_mem[3][k]-> PE  PE  PE  PE   -> C[3][0..3]
//        (broadcast across rows)
//
// =============================================================================

module int8_matmul_accelerator #(
    parameter int N          = 4,   // rows of A / rows of C
    parameter int K          = 4,   // cols of A / rows of B  (reduction dim)
    parameter int M          = 4,   // cols of B / cols of C
    parameter int DATA_WIDTH = 8,   // INT8 operands
    parameter int ACC_WIDTH  = 32   // wide accumulator
)(
    input  logic clk,
    input  logic rst_n,

    // ---- matrix load port (host writes A and B before starting) ----
    input  logic                              wr_en,
    input  logic                              wr_target,     // 0 = A, 1 = B
    input  logic [$clog2((N*K>K*M)?N*K:K*M)-1:0] wr_addr,     // flat row-major address
    input  logic signed [DATA_WIDTH-1:0]      wr_data,

    // ---- control ----
    input  logic start,     // pulse to begin (or restart) the K-cycle compute
    output logic done,      // result matrix valid in C once asserted

    // ---- result read port ----
    input  logic                              rd_en,
    input  logic [$clog2(N*M)-1:0]            rd_addr,       // flat row-major address into C
    output logic signed [ACC_WIDTH-1:0]       rd_data_raw,   // full-precision accumulator
    output logic signed [DATA_WIDTH-1:0]      rd_data_q,     // requantized INT8 result
    input  logic [4:0]                        rd_shift       // requantization shift for rd_data_q
);

    // -------------------------------------------------------------------
    // Operand memories (simple register files - small enough for a demo
    // accelerator; a larger design would back these with BRAM).
    // -------------------------------------------------------------------
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

    // -------------------------------------------------------------------
    // Control FSM
    // -------------------------------------------------------------------
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

    // -------------------------------------------------------------------
    // N x M array of MAC units (one PE per output element)
    // -------------------------------------------------------------------
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
                    .a_in      (A_mem[gi][k_cnt]),   // row-broadcast
                    .b_in      (B_mem[k_cnt][gj]),   // column-broadcast
                    .acc_out   (C_mem[gi][gj])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------
    // Result readout (registered, one cycle latency)
    // -------------------------------------------------------------------
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
