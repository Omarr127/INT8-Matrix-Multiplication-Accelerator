// =============================================================================
// control_fsm.sv
// -----------------------------------------------------------------------------
// Sequences the accelerator through its compute phase.
//
// Matrix loading (A_mem / B_mem writes) and result readout (C_mem reads) are
// handled directly by simple memory-mapped ports in the top module and are
// NOT gated by this FSM - a host can load a new matrix at any time in IDLE
// or DONE. This FSM's only job is to drive the K-cycle MAC reduction that
// every PE in the array performs in lock-step.
//
// States:
//   IDLE : waiting for 'start' pulse from host
//   RUN  : drives k_cnt = 0 .. K-1, one MAC step per cycle, across the array
//   DONE : result valid and held in C_mem; returns to RUN on a new 'start'
//          pulse (recompute with newly loaded matrices), or stays here.
// =============================================================================

module control_fsm #(
    parameter int K = 4   // reduction (inner) dimension
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,          // pulse: begin/restart compute
    output logic mac_en,         // drive to every PE's mac_unit.en
    output logic clear_acc,      // drive to every PE's mac_unit.clear_acc
    output logic [$clog2(K)-1:0] k_cnt,   // current reduction index (selects A col / B row)
    output logic done            // result valid in C_mem
);

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;
    state_t state, next_state;

    logic [$clog2(K)-1:0] k_cnt_r;

    // ---- state register ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // ---- next-state logic ----
    always_comb begin
        next_state = state;
        unique case (state)
            S_IDLE:  if (start) next_state = S_RUN;
            S_RUN:   if (k_cnt_r == K-1) next_state = S_DONE;
            S_DONE:  if (start) next_state = S_RUN; // allow re-trigger for new matrices
            default: next_state = S_IDLE;
        endcase
    end

    // ---- k_cnt counter ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k_cnt_r <= '0;
        end else if (state == S_IDLE && start) begin
            k_cnt_r <= '0;
        end else if (state == S_RUN) begin
            k_cnt_r <= k_cnt_r + 1'b1;
        end
    end

    assign k_cnt     = k_cnt_r;
    assign mac_en     = (state == S_RUN);
    assign clear_acc  = (state == S_RUN) && (k_cnt_r == '0);
    assign done       = (state == S_DONE);

endmodule
