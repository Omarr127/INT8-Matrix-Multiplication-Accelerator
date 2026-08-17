// =============================================================================
// tb_int8_matmul_accelerator.sv
// -----------------------------------------------------------------------------
// Self-checking testbench for int8_matmul_accelerator.

`timescale 1ns/1ps

module tb_int8_matmul_accelerator;

    localparam int N = 4, K = 4, M = 4;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int WR_AW = $clog2((N*K>K*M)?N*K:K*M);
    localparam int RD_AW = $clog2(N*M);

    logic clk = 0;
    logic rst_n;

    logic                         wr_en;
    logic                         wr_target;
    logic [WR_AW-1:0]             wr_addr;
    logic signed [DATA_WIDTH-1:0] wr_data;

    logic start, done;

    logic                          rd_en;
    logic [RD_AW-1:0]              rd_addr;
    logic signed [ACC_WIDTH-1:0]   rd_data_raw;
    logic signed [DATA_WIDTH-1:0]  rd_data_q;
    logic [4:0]                    rd_shift;

    int errors = 0;
    int checks = 0;

    //  clock: 10ns period 
    always #5 clk = ~clk;

    //  DUT 
    int8_matmul_accelerator #(
        .N(N), .K(K), .M(M),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .wr_target   (wr_target),
        .wr_addr     (wr_addr),
        .wr_data     (wr_data),
        .start       (start),
        .done        (done),
        .rd_en       (rd_en),
        .rd_addr     (rd_addr),
        .rd_data_raw (rd_data_raw),
        .rd_data_q   (rd_data_q),
        .rd_shift    (rd_shift)
    );

    // software golden model storage
    int signed A_ref [0:N-1][0:K-1];
    int signed B_ref [0:K-1][0:M-1];
    logic signed [ACC_WIDTH-1:0] C_ref [0:N-1][0:M-1];

    
    // Tasks  
    task automatic reset_dut();
        wr_en = 0; wr_target = 0; wr_addr = '0; wr_data = '0;
        start = 0; rd_en = 0; rd_addr = '0; rd_shift = 0;
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
    endtask

    task automatic load_matrices();
        // Load A (target 0)
        for (int i = 0; i < N; i++) begin
            for (int k = 0; k < K; k++) begin
                @(negedge clk);
                wr_en     = 1;
                wr_target = 1'b0;
                wr_addr   = i*K + k;
                wr_data   = A_ref[i][k];
            end
        end

        // Load B (target 1)
        for (int k = 0; k < K; k++) begin
            for (int j = 0; j < M; j++) begin
                @(negedge clk);
                wr_en     = 1;
                wr_target = 1'b1;
                wr_addr   = k*M + j;
                wr_data   = B_ref[k][j];
            end
        end

        @(negedge clk);
        wr_en = 0;
    endtask

    task automatic compute_golden();
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < M; j++) begin
                automatic longint sum = 0;
                for (int k = 0; k < K; k++)
                    sum += A_ref[i][k] * B_ref[k][j];
                C_ref[i][j] = sum[ACC_WIDTH-1:0];
            end
        end
    endtask

    task automatic run_and_check(string test_name);
        compute_golden();

        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;

        // wait for done 
        for (int t = 0; t < K+5 && !done; t++) @(negedge clk);

        if (!done) begin
            $display("[FAIL] %0s: DUT never asserted done", test_name);
            errors++;
        end

        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < M; j++) begin
                @(negedge clk);
                rd_en   = 1;
                rd_addr = i*M + j;
                @(negedge clk);           
                rd_en = 0;
                checks++;
                if (rd_data_raw !== C_ref[i][j]) begin
                    $display("[FAIL] %0s: C[%0d][%0d] = %0d, expected %0d",
                              test_name, i, j, rd_data_raw, C_ref[i][j]);
                    errors++;
                end
            end
        end
        $display("[INFO] %0s: checked %0d elements", test_name, N*M);
    endtask


    // Main test sequence
`ifdef DUMP_VCD
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_int8_matmul_accelerator);
    end
`endif

    initial begin
        reset_dut();

        // Directed test: simple hand-verifiable values
        for (int i = 0; i < N; i++)
            for (int k = 0; k < K; k++)
                A_ref[i][k] = (i == k) ? 2 : 1;   

        for (int k = 0; k < K; k++)
            for (int j = 0; j < M; j++)
                B_ref[k][j] = j + 1;              

        load_matrices();
        run_and_check("Directed test (small positive values)");

        // Edge-value test: extremes of INT8 range 
        A_ref[0][0]=127;  A_ref[0][1]=-128; A_ref[0][2]=0;    A_ref[0][3]=127;
        A_ref[1][0]=-128; A_ref[1][1]=127;  A_ref[1][2]=-128; A_ref[1][3]=0;
        A_ref[2][0]=1;    A_ref[2][1]=-1;   A_ref[2][2]=127;  A_ref[2][3]=-128;
        A_ref[3][0]=-128; A_ref[3][1]=-128; A_ref[3][2]=127;  A_ref[3][3]=127;

        B_ref[0][0]=127;  B_ref[0][1]=-128; B_ref[0][2]=1;    B_ref[0][3]=0;
        B_ref[1][0]=-128; B_ref[1][1]=127;  B_ref[1][2]=-1;   B_ref[1][3]=127;
        B_ref[2][0]=0;    B_ref[2][1]=-128; B_ref[2][2]=127;  B_ref[2][3]=-128;
        B_ref[3][0]=127;  B_ref[3][1]=127;  B_ref[3][2]=-128; B_ref[3][3]=-128;

        load_matrices();
        run_and_check("Edge-value test (+127/-128/0 saturation stress)");

        // Randomized tests
        for (int trial = 0; trial < 20; trial++) begin
            for (int i = 0; i < N; i++)
                for (int k = 0; k < K; k++)
                    A_ref[i][k] = $signed($urandom_range(0, 255)) - 128; 

            for (int k = 0; k < K; k++)
                for (int j = 0; j < M; j++)
                    B_ref[k][j] = $signed($urandom_range(0, 255)) - 128;

            load_matrices();
            run_and_check($sformatf("Randomized trial %0d", trial));
        end

        // Requantization saturation check 
        for (int i = 0; i < N; i++)
            for (int k = 0; k < K; k++)
                A_ref[i][k] = 127;
        for (int k = 0; k < K; k++)
            for (int j = 0; j < M; j++)
                B_ref[k][j] = 127;

        load_matrices();
        compute_golden();

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        for (int t = 0; t < K+5 && !done; t++) @(negedge clk);

        @(negedge clk);
        rd_en = 1; rd_addr = 0; rd_shift = 0; 
        @(negedge clk);
        rd_en = 0;
        checks++;
        if (rd_data_q !== 127) begin
            $display("[FAIL] Requantization saturation: got %0d, expected 127", rd_data_q);
            errors++;
        end else begin
            $display("[INFO] Requantization saturation test passed (rd_data_q = %0d)", rd_data_q);
        end

        // Summary 
        $display("--------------------------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks, 0 errors)", checks);
        else
            $display("TESTS FAILED: %0d errors out of %0d checks", errors, checks);
        $display("--------------------------------------------------");

        $finish;
    end

    // Safety timeout
    initial begin
        #100000;
        $display("[FAIL] Testbench timeout - simulation did not finish");
        $finish;
    end

endmodule
