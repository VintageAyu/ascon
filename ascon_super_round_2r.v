// ═══════════════════════════════════════════════════════════════════════════════
// Module: ascon_super_round_2r
// Specification: NIST SP 800-232 (Ascon-128 / Ascon-128a)
// Architecture: 2-Round Unrolled Datapath with Boolean Factoring & Inversion Absorption
// Operation Count: 57 Word-Level Logic Operations (44 XOR, 6 AND, 4 OR, 3 NOT, 20 Rotations)
// Prior Art: Round-constant inversion absorption technique by Rhys Weatherley (2022)
// Note: Operator counts are word-level AST counts; physical cell counts and PPA require
//       target-specific standard cell synthesis and timing closure.
// ═══════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps

module ascon_super_round_2r #(
    parameter PIPELINED = 0 // 0: Pure combinational 1-cycle datapath
                            // 1: 2-stage registered pipeline (Round 1 -> Reg -> Round 2)
)(
    input  wire        clk,
    input  wire        rst_n,      // Active-low asynchronous reset
    input  wire        enable,     // Datapath enable
    
    // Round Constants (64-bit each)
    input  wire [63:0] cr1,        // Round 1 Constant (e.g. 0x00000000000000F0)
    input  wire [63:0] cr2,        // Round 2 Constant (e.g. 0x00000000000000E1)
    
    // 320-Bit State Input (5 x 64-bit words)
    input  wire [63:0] x0,
    input  wire [63:0] x1,
    input  wire [63:0] x2,
    input  wire [63:0] x3,
    input  wire [63:0] x4,
    
    // 320-Bit State Output (5 x 64-bit words)
    output wire [63:0] z0,
    output wire [63:0] z1,
    output wire [63:0] z2,
    output wire [63:0] z3,
    output wire [63:0] z4,
    output wire        valid
);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 1: Round 1 Non-Linear Core & Constant Addition
    // ─────────────────────────────────────────────────────────────────────────
    // Addition of Round 1 constant cr1 to word x2
    wire [63:0] x2_r1 = x2 ^ cr1;

    // Linear pre-mixing
    wire [63:0] a0 = x0 ^ x4;
    wire [63:0] a4 = x4 ^ x3;
    wire [63:0] a2 = x2_r1 ^ x1;
    wire [63:0] na0 = ~a0;

    // Non-linear conjunction terms (Chi layer)
    wire [63:0] t1 = x2_r1 & a2;
    wire [63:0] t3 = x4 & a4;
    wire [63:0] t0 = na0 & x1;

    // Output recombination with optimized Boolean factoring
    wire [63:0] b1 = x2_r1 ^ (a2 | x3);
    wire [63:0] b3 = x4 ^ (a4 | a0);
    wire [63:0] b0 = a0 ^ t1;
    wire [63:0] b4 = a4 ^ t0;

    // Pre-diffusion state wires
    // In standard Ascon, c2 = ~c2_inv. Here, we OMIT the inverter on c2_inv,
    // propagating the un-inverted state directly into the Round 1 linear diffusion.
    wire [63:0] c2_inv = a2 ^ t3;
    wire [63:0] c1     = b1 ^ b0;
    wire [63:0] c0     = b0 ^ b4;
    wire [63:0] c3     = b3 ^ c2_inv;
    wire [63:0] c4     = b4;

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 2: Round 1 Linear Diffusion Layer Sigma 1
    // Rotations in hardware are 0-cost wire re-indexing: {w[r-1:0], w[63:r]}
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] ror_c0_19 = {c0[18:0], c0[63:19]};
    wire [63:0] ror_c0_28 = {c0[27:0], c0[63:28]};
    wire [63:0] y0_stage1 = c0 ^ ror_c0_19 ^ ror_c0_28;

    wire [63:0] ror_c1_61 = {c1[60:0], c1[63:61]};
    wire [63:0] ror_c1_39 = {c1[38:0], c1[63:39]};
    wire [63:0] y1_stage1 = c1 ^ ror_c1_61 ^ ror_c1_39;

    // Inversion-Absorption Property:
    // Sigma_2(c2) = Sigma_2(c2_inv ^ 1) = Sigma_2(c2_inv) ^ 1
    // We compute y2_stage1 using c2_inv directly, leaving the ^ 1 to be
    // absorbed into the subsequent round constant addition cr2!
    wire [63:0] ror_c2_1  = {c2_inv[0], c2_inv[63:1]};
    wire [63:0] ror_c2_6  = {c2_inv[5:0], c2_inv[63:6]};
    wire [63:0] y2_stage1 = c2_inv ^ ror_c2_1 ^ ror_c2_6;

    wire [63:0] ror_c3_10 = {c3[9:0], c3[63:10]};
    wire [63:0] ror_c3_17 = {c3[16:0], c3[63:17]};
    wire [63:0] y3_stage1 = c3 ^ ror_c3_10 ^ ror_c3_17;

    wire [63:0] ror_c4_7  = {c4[6:0], c4[63:7]};
    wire [63:0] ror_c4_41 = {c4[40:0], c4[63:41]};
    wire [63:0] y4_stage1 = c4 ^ ror_c4_7 ^ ror_c4_41;

    // ─────────────────────────────────────────────────────────────────────────
    // Optional Pipeline Register (Between Round 1 and Round 2)
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] y0;
    wire [63:0] y1;
    wire [63:0] y2;
    wire [63:0] y3;
    wire [63:0] y4;
    wire [63:0] cr2_pipe;
    wire        stage1_valid;

    generate
        if (PIPELINED) begin : gen_pipeline_reg
            reg [63:0] reg_y0, reg_y1, reg_y2, reg_y3, reg_y4, reg_cr2;
            reg        reg_valid;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    reg_y0    <= 64'd0;
                    reg_y1    <= 64'd0;
                    reg_y2    <= 64'd0;
                    reg_y3    <= 64'd0;
                    reg_y4    <= 64'd0;
                    reg_cr2   <= 64'd0;
                    reg_valid <= 1'b0;
                end else if (enable) begin
                    reg_y0    <= y0_stage1;
                    reg_y1    <= y1_stage1;
                    reg_y2    <= y2_stage1;
                    reg_y3    <= y3_stage1;
                    reg_y4    <= y4_stage1;
                    reg_cr2   <= cr2;
                    reg_valid <= 1'b1;
                end else begin
                    reg_valid <= 1'b0;
                end
            end

            assign y0           = reg_y0;
            assign y1           = reg_y1;
            assign y2           = reg_y2;
            assign y3           = reg_y3;
            assign y4           = reg_y4;
            assign cr2_pipe     = reg_cr2;
            assign stage1_valid = reg_valid;
        end else begin : gen_comb_passthrough
            assign y0           = y0_stage1;
            assign y1           = y1_stage1;
            assign y2           = y2_stage1;
            assign y3           = y3_stage1;
            assign y4           = y4_stage1;
            assign cr2_pipe     = cr2;
            assign stage1_valid = enable;
        end
    endgenerate

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 3: Round 2 Non-Linear Core with Inverted Constant Absorption
    // Since y2 = Sigma_2(c2_inv) was missing the inversion ^ 1:
    // (y2 ^ 1) ^ cr2 == y2 ^ (~cr2).
    // In silicon synthesis, (~cr2) requires 0 additional gates (absorbed into
    // XNOR standard cells or pre-inverted control wires).
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] y2_r2 = y2 ^ (~cr2_pipe);

    // Round 2 linear pre-mixing
    wire [63:0] a0_2  = y0 ^ y4;
    wire [63:0] a4_2  = y4 ^ y3;
    wire [63:0] a2_2  = y2_r2 ^ y1;
    wire [63:0] na0_2 = ~a0_2;

    // Round 2 non-linear conjunction terms
    wire [63:0] t1_2  = y2_r2 & a2_2;
    wire [63:0] t3_2  = y4 & a4_2;
    wire [63:0] t0_2  = na0_2 & y1;

    // Round 2 output recombination
    wire [63:0] b1_2     = y2_r2 ^ (a2_2 | y3);
    wire [63:0] b3_2     = y4 ^ (a4_2 | a0_2);
    wire [63:0] b0_2     = a0_2 ^ t1_2;
    wire [63:0] b4_2     = a4_2 ^ t0_2;

    wire [63:0] c2_2_inv = a2_2 ^ t3_2;
    wire [63:0] c1_2     = b1_2 ^ b0_2;
    wire [63:0] c0_2     = b0_2 ^ b4_2;
    wire [63:0] c3_2     = b3_2 ^ c2_2_inv;
    wire [63:0] c4_2     = b4_2;
    wire [63:0] c2_2     = ~c2_2_inv; // Inversion applied at super-round boundary

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 4: Round 2 Linear Diffusion Layer Sigma 2
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] ror_c0_2_19 = {c0_2[18:0], c0_2[63:19]};
    wire [63:0] ror_c0_2_28 = {c0_2[27:0], c0_2[63:28]};
    wire [63:0] z0_comb     = c0_2 ^ ror_c0_2_19 ^ ror_c0_2_28;

    wire [63:0] ror_c1_2_61 = {c1_2[60:0], c1_2[63:61]};
    wire [63:0] ror_c1_2_39 = {c1_2[38:0], c1_2[63:39]};
    wire [63:0] z1_comb     = c1_2 ^ ror_c1_2_61 ^ ror_c1_2_39;

    wire [63:0] ror_c2_2_1  = {c2_2[0], c2_2[63:1]};
    wire [63:0] ror_c2_2_6  = {c2_2[5:0], c2_2[63:6]};
    wire [63:0] z2_comb     = c2_2 ^ ror_c2_2_1 ^ ror_c2_2_6;

    wire [63:0] ror_c3_2_10 = {c3_2[9:0], c3_2[63:10]};
    wire [63:0] ror_c3_2_17 = {c3_2[16:0], c3_2[63:17]};
    wire [63:0] z3_comb     = c3_2 ^ ror_c3_2_10 ^ ror_c3_2_17;

    wire [63:0] ror_c4_2_7  = {c4_2[6:0], c4_2[63:7]};
    wire [63:0] ror_c4_2_41 = {c4_2[40:0], c4_2[63:41]};
    wire [63:0] z4_comb     = c4_2 ^ ror_c4_2_7 ^ ror_c4_2_41;

    // Output assignments
    assign z0    = z0_comb;
    assign z1    = z1_comb;
    assign z2    = z2_comb;
    assign z3    = z3_comb;
    assign z4    = z4_comb;
    assign valid = stage1_valid;

endmodule
