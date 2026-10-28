// ═══════════════════════════════════════════════════════════════════════════════
// Module: ascon_mega_round_4r
// Specification: NIST SP 800-232 (Ascon-128 / Ascon-128a)
// Architecture: 4-Round Unrolled Datapath with Boolean Factoring & Inversion Absorption
// Operation Count: 113 Word-Level Logic Operations (88 XOR, 12 AND, 8 OR, 5 NOT, 40 Rotations)
// Prior Art: Round-constant inversion absorption technique by Rhys Weatherley (2022)
// Note: Operator counts are word-level AST counts; physical cell counts and PPA require
//       target-specific standard cell synthesis and timing closure.
// ═══════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps

module ascon_mega_round_4r #(
    parameter STAGES = 1 // 1: Pure combinational 1-cycle quad-round datapath
                         // 2: 2-stage registered pipeline (Round 1-2 -> Reg -> Round 3-4)
                         // 4: 4-stage fully pipelined high-throughput engine
)(
    input  wire        clk,
    input  wire        rst_n,      // Active-low asynchronous reset
    input  wire        enable,     // Datapath enable
    
    // 4 Sequential Round Constants (64-bit each)
    input  wire [63:0] cr1,        // Round 1 Constant (e.g. 0x00000000000000F0)
    input  wire [63:0] cr2,        // Round 2 Constant (e.g. 0x00000000000000E1)
    input  wire [63:0] cr3,        // Round 3 Constant (e.g. 0x00000000000000D2)
    input  wire [63:0] cr4,        // Round 4 Constant (e.g. 0x00000000000000C3)
    
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
    // ROUND 1: Non-Linear Core & Constant cr1 (18 Ops)
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] x2_1 = x2 ^ cr1;
    wire [63:0] a0_1 = x0 ^ x4;
    wire [63:0] a4_1 = x4 ^ x3;
    wire [63:0] a2_1 = x2_1 ^ x1;
    wire [63:0] na0_1 = ~a0_1;

    wire [63:0] t1_1 = x2_1 & a2_1;
    wire [63:0] t3_1 = x4 & a4_1;
    wire [63:0] t0_1 = na0_1 & x1;

    wire [63:0] b1_1 = x2_1 ^ (a2_1 | x3);
    wire [63:0] b3_1 = x4 ^ (a4_1 | a0_1);
    wire [63:0] b0_1 = a0_1 ^ t1_1;
    wire [63:0] b4_1 = a4_1 ^ t0_1;

    wire [63:0] c2_1_inv = a2_1 ^ t3_1; // Inversion omitted, saving 1 NOT gate
    wire [63:0] c1_1     = b1_1 ^ b0_1;
    wire [63:0] c0_1     = b0_1 ^ b4_1;
    wire [63:0] c3_1     = b3_1 ^ c2_1_inv;
    wire [63:0] c4_1     = b4_1;

    // Linear Diffusion 1 (10 XORs)
    wire [63:0] ror_c0_1_19 = {c0_1[18:0], c0_1[63:19]};
    wire [63:0] ror_c0_1_28 = {c0_1[27:0], c0_1[63:28]};
    wire [63:0] y0_1 = c0_1 ^ ror_c0_1_19 ^ ror_c0_1_28;

    wire [63:0] ror_c1_1_61 = {c1_1[60:0], c1_1[63:61]};
    wire [63:0] ror_c1_1_39 = {c1_1[38:0], c1_1[63:39]};
    wire [63:0] y1_1 = c1_1 ^ ror_c1_1_61 ^ ror_c1_1_39;

    wire [63:0] ror_c2_1_1  = {c2_1_inv[0], c2_1_inv[63:1]};
    wire [63:0] ror_c2_1_6  = {c2_1_inv[5:0], c2_1_inv[63:6]};
    wire [63:0] y2_1 = c2_1_inv ^ ror_c2_1_1 ^ ror_c2_1_6;

    wire [63:0] ror_c3_1_10 = {c3_1[9:0], c3_1[63:10]};
    wire [63:0] ror_c3_1_17 = {c3_1[16:0], c3_1[63:17]};
    wire [63:0] y3_1 = c3_1 ^ ror_c3_1_10 ^ ror_c3_1_17;

    wire [63:0] ror_c4_1_7  = {c4_1[6:0], c4_1[63:7]};
    wire [63:0] ror_c4_1_41 = {c4_1[40:0], c4_1[63:41]};
    wire [63:0] y4_1 = c4_1 ^ ror_c4_1_7 ^ ror_c4_1_41;

    // Optional Pipe 1 Register
    wire [63:0] s1_y0, s1_y1, s1_y2, s1_y3, s1_y4;
    wire [63:0] s1_cr2, s1_cr3, s1_cr4;
    wire        s1_valid;

    generate
        if (STAGES == 4) begin : gen_pipe1
            reg [63:0] r_y0, r_y1, r_y2, r_y3, r_y4, r_cr2, r_cr3, r_cr4;
            reg        r_val;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_y0 <= 64'd0; r_y1 <= 64'd0; r_y2 <= 64'd0; r_y3 <= 64'd0; r_y4 <= 64'd0;
                    r_cr2 <= 64'd0; r_cr3 <= 64'd0; r_cr4 <= 64'd0; r_val <= 1'b0;
                end else if (enable) begin
                    r_y0 <= y0_1; r_y1 <= y1_1; r_y2 <= y2_1; r_y3 <= y3_1; r_y4 <= y4_1;
                    r_cr2 <= cr2; r_cr3 <= cr3; r_cr4 <= cr4; r_val <= 1'b1;
                end else begin
                    r_val <= 1'b0;
                end
            end
            assign s1_y0 = r_y0; assign s1_y1 = r_y1; assign s1_y2 = r_y2; assign s1_y3 = r_y3; assign s1_y4 = r_y4;
            assign s1_cr2 = r_cr2; assign s1_cr3 = r_cr3; assign s1_cr4 = r_cr4; assign s1_valid = r_val;
        end else begin : gen_comb1
            assign s1_y0 = y0_1; assign s1_y1 = y1_1; assign s1_y2 = y2_1; assign s1_y3 = y3_1; assign s1_y4 = y4_1;
            assign s1_cr2 = cr2; assign s1_cr3 = cr3; assign s1_cr4 = cr4; assign s1_valid = enable;
        end
    endgenerate

    // ─────────────────────────────────────────────────────────────────────────
    // ROUND 2: Non-Linear Core & Constant cr2 Inverted Absorption (17 Ops)
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] y2_2 = s1_y2 ^ (~s1_cr2); // Free inverter absorption
    wire [63:0] a0_2 = s1_y0 ^ s1_y4;
    wire [63:0] a4_2 = s1_y4 ^ s1_y3;
    wire [63:0] a2_2 = y2_2 ^ s1_y1;
    wire [63:0] na0_2 = ~a0_2;

    wire [63:0] t1_2 = y2_2 & a2_2;
    wire [63:0] t3_2 = s1_y4 & a4_2;
    wire [63:0] t0_2 = na0_2 & s1_y1;

    wire [63:0] b1_2 = y2_2 ^ (a2_2 | s1_y3);
    wire [63:0] b3_2 = s1_y4 ^ (a4_2 | a0_2);
    wire [63:0] b0_2 = a0_2 ^ t1_2;
    wire [63:0] b4_2 = a4_2 ^ t0_2;

    wire [63:0] c2_2_inv = a2_2 ^ t3_2; // Inversion omitted again, saving 1 NOT gate
    wire [63:0] c1_2     = b1_2 ^ b0_2;
    wire [63:0] c0_2     = b0_2 ^ b4_2;
    wire [63:0] c3_2     = b3_2 ^ c2_2_inv;
    wire [63:0] c4_2     = b4_2;

    // Linear Diffusion 2 (10 XORs)
    wire [63:0] ror_c0_2_19 = {c0_2[18:0], c0_2[63:19]};
    wire [63:0] ror_c0_2_28 = {c0_2[27:0], c0_2[63:28]};
    wire [63:0] y0_2 = c0_2 ^ ror_c0_2_19 ^ ror_c0_2_28;

    wire [63:0] ror_c1_2_61 = {c1_2[60:0], c1_2[63:61]};
    wire [63:0] ror_c1_2_39 = {c1_2[38:0], c1_2[63:39]};
    wire [63:0] y1_2 = c1_2 ^ ror_c1_2_61 ^ ror_c1_2_39;

    wire [63:0] ror_c2_2_1  = {c2_2_inv[0], c2_2_inv[63:1]};
    wire [63:0] ror_c2_2_6  = {c2_2_inv[5:0], c2_2_inv[63:6]};
    wire [63:0] y2_2_diff = c2_2_inv ^ ror_c2_2_1 ^ ror_c2_2_6;

    wire [63:0] ror_c3_2_10 = {c3_2[9:0], c3_2[63:10]};
    wire [63:0] ror_c3_2_17 = {c3_2[16:0], c3_2[63:17]};
    wire [63:0] y3_2 = c3_2 ^ ror_c3_2_10 ^ ror_c3_2_17;

    wire [63:0] ror_c4_2_7  = {c4_2[6:0], c4_2[63:7]};
    wire [63:0] ror_c4_2_41 = {c4_2[40:0], c4_2[63:41]};
    wire [63:0] y4_2 = c4_2 ^ ror_c4_2_7 ^ ror_c4_2_41;

    // Optional Pipe 2 Register (Active if STAGES == 2 or STAGES == 4)
    wire [63:0] s2_y0, s2_y1, s2_y2, s2_y3, s2_y4;
    wire [63:0] s2_cr3, s2_cr4;
    wire        s2_valid;

    generate
        if (STAGES >= 2) begin : gen_pipe2
            reg [63:0] r_y0, r_y1, r_y2, r_y3, r_y4, r_cr3, r_cr4;
            reg        r_val;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_y0 <= 64'd0; r_y1 <= 64'd0; r_y2 <= 64'd0; r_y3 <= 64'd0; r_y4 <= 64'd0;
                    r_cr3 <= 64'd0; r_cr4 <= 64'd0; r_val <= 1'b0;
                end else if (s1_valid) begin
                    r_y0 <= y0_2; r_y1 <= y1_2; r_y2 <= y2_2_diff; r_y3 <= y3_2; r_y4 <= y4_2;
                    r_cr3 <= s1_cr3; r_cr4 <= s1_cr4; r_val <= 1'b1;
                end else begin
                    r_val <= 1'b0;
                end
            end
            assign s2_y0 = r_y0; assign s2_y1 = r_y1; assign s2_y2 = r_y2; assign s2_y3 = r_y3; assign s2_y4 = r_y4;
            assign s2_cr3 = r_cr3; assign s2_cr4 = r_cr4; assign s2_valid = r_val;
        end else begin : gen_comb2
            assign s2_y0 = y0_2; assign s2_y1 = y1_2; assign s2_y2 = y2_2_diff; assign s2_y3 = y3_2; assign s2_y4 = y4_2;
            assign s2_cr3 = s1_cr3; assign s2_cr4 = s1_cr4; assign s2_valid = s1_valid;
        end
    endgenerate

    // ─────────────────────────────────────────────────────────────────────────
    // ROUND 3: Non-Linear Core & Constant cr3 Inverted Absorption (17 Ops)
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] y2_3 = s2_y2 ^ (~s2_cr3); // Free inverter absorption
    wire [63:0] a0_3 = s2_y0 ^ s2_y4;
    wire [63:0] a4_3 = s2_y4 ^ s2_y3;
    wire [63:0] a2_3 = y2_3 ^ s2_y1;
    wire [63:0] na0_3 = ~a0_3;

    wire [63:0] t1_3 = y2_3 & a2_3;
    wire [63:0] t3_3 = s2_y4 & a4_3;
    wire [63:0] t0_3 = na0_3 & s2_y1;

    wire [63:0] b1_3 = y2_3 ^ (a2_3 | s2_y3);
    wire [63:0] b3_3 = s2_y4 ^ (a4_3 | a0_3);
    wire [63:0] b0_3 = a0_3 ^ t1_3;
    wire [63:0] b4_3 = a4_3 ^ t0_3;

    wire [63:0] c2_3_inv = a2_3 ^ t3_3; // Inversion omitted again, saving 1 NOT gate
    wire [63:0] c1_3     = b1_3 ^ b0_3;
    wire [63:0] c0_3     = b0_3 ^ b4_3;
    wire [63:0] c3_3     = b3_3 ^ c2_3_inv;
    wire [63:0] c4_3     = b4_3;

    // Linear Diffusion 3 (10 XORs)
    wire [63:0] ror_c0_3_19 = {c0_3[18:0], c0_3[63:19]};
    wire [63:0] ror_c0_3_28 = {c0_3[27:0], c0_3[63:28]};
    wire [63:0] y0_3 = c0_3 ^ ror_c0_3_19 ^ ror_c0_3_28;

    wire [63:0] ror_c1_3_61 = {c1_3[60:0], c1_3[63:61]};
    wire [63:0] ror_c1_3_39 = {c1_3[38:0], c1_3[63:39]};
    wire [63:0] y1_3 = c1_3 ^ ror_c1_3_61 ^ ror_c1_3_39;

    wire [63:0] ror_c2_3_1  = {c2_3_inv[0], c2_3_inv[63:1]};
    wire [63:0] ror_c2_3_6  = {c2_3_inv[5:0], c2_3_inv[63:6]};
    wire [63:0] y2_3_diff = c2_3_inv ^ ror_c2_3_1 ^ ror_c2_3_6;

    wire [63:0] ror_c3_3_10 = {c3_3[9:0], c3_3[63:10]};
    wire [63:0] ror_c3_3_17 = {c3_3[16:0], c3_3[63:17]};
    wire [63:0] y3_3 = c3_3 ^ ror_c3_3_10 ^ ror_c3_3_17;

    wire [63:0] ror_c4_3_7  = {c4_3[6:0], c4_3[63:7]};
    wire [63:0] ror_c4_3_41 = {c4_3[40:0], c4_3[63:41]};
    wire [63:0] y4_3 = c4_3 ^ ror_c4_3_7 ^ ror_c4_3_41;

    // Optional Pipe 3 Register (Active if STAGES == 4)
    wire [63:0] s3_y0, s3_y1, s3_y2, s3_y3, s3_y4;
    wire [63:0] s3_cr4;
    wire        s3_valid;

    generate
        if (STAGES == 4) begin : gen_pipe3
            reg [63:0] r_y0, r_y1, r_y2, r_y3, r_y4, r_cr4;
            reg        r_val;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    r_y0 <= 64'd0; r_y1 <= 64'd0; r_y2 <= 64'd0; r_y3 <= 64'd0; r_y4 <= 64'd0;
                    r_cr4 <= 64'd0; r_val <= 1'b0;
                end else if (s2_valid) begin
                    r_y0 <= y0_3; r_y1 <= y1_3; r_y2 <= y2_3_diff; r_y3 <= y3_3; r_y4 <= y4_3;
                    r_cr4 <= s2_cr4; r_val <= 1'b1;
                end else begin
                    r_val <= 1'b0;
                end
            end
            assign s3_y0 = r_y0; assign s3_y1 = r_y1; assign s3_y2 = r_y2; assign s3_y3 = r_y3; assign s3_y4 = r_y4;
            assign s3_cr4 = r_cr4; assign s3_valid = r_val;
        end else begin : gen_comb3
            assign s3_y0 = y0_3; assign s3_y1 = y1_3; assign s3_y2 = y2_3_diff; assign s3_y3 = y3_3; assign s3_y4 = y4_3;
            assign s3_cr4 = s2_cr4; assign s3_valid = s2_valid;
        end
    endgenerate

    // ─────────────────────────────────────────────────────────────────────────
    // ROUND 4: Non-Linear Core & Final Boundary Restoration (18 Ops)
    // ─────────────────────────────────────────────────────────────────────────
    wire [63:0] y2_4 = s3_y2 ^ (~s3_cr4); // Free inverter absorption
    wire [63:0] a0_4 = s3_y0 ^ s3_y4;
    wire [63:0] a4_4 = s3_y4 ^ s3_y3;
    wire [63:0] a2_4 = y2_4 ^ s3_y1;
    wire [63:0] na0_4 = ~a0_4;

    wire [63:0] t1_4 = y2_4 & a2_4;
    wire [63:0] t3_4 = s3_y4 & a4_4;
    wire [63:0] t0_4 = na0_4 & s3_y1;

    wire [63:0] b1_4 = y2_4 ^ (a2_4 | s3_y3);
    wire [63:0] b3_4 = s3_y4 ^ (a4_4 | a0_4);
    wire [63:0] b0_4 = a0_4 ^ t1_4;
    wire [63:0] b4_4 = a4_4 ^ t0_4;

    wire [63:0] c2_4_inv = a2_4 ^ t3_4;
    wire [63:0] c1_4     = b1_4 ^ b0_4;
    wire [63:0] c0_4     = b0_4 ^ b4_4;
    wire [63:0] c3_4     = b3_4 ^ c2_4_inv;
    wire [63:0] c4_4     = b4_4;
    wire [63:0] c2_4     = ~c2_4_inv; // 1 final NOT to restore standard Ascon state

    // Linear Diffusion 4 (10 XORs)
    wire [63:0] ror_c0_4_19 = {c0_4[18:0], c0_4[63:19]};
    wire [63:0] ror_c0_4_28 = {c0_4[27:0], c0_4[63:28]};
    wire [63:0] z0_comb     = c0_4 ^ ror_c0_4_19 ^ ror_c0_4_28;

    wire [63:0] ror_c1_4_61 = {c1_4[60:0], c1_4[63:61]};
    wire [63:0] ror_c1_4_39 = {c1_4[38:0], c1_4[63:39]};
    wire [63:0] z1_comb     = c1_4 ^ ror_c1_4_61 ^ ror_c1_4_39;

    wire [63:0] ror_c2_4_1  = {c2_4[0], c2_4[63:1]};
    wire [63:0] ror_c2_4_6  = {c2_4[5:0], c2_4[63:6]};
    wire [63:0] z2_comb     = c2_4 ^ ror_c2_4_1 ^ ror_c2_4_6;

    wire [63:0] ror_c3_4_10 = {c3_4[9:0], c3_4[63:10]};
    wire [63:0] ror_c3_4_17 = {c3_4[16:0], c3_4[63:17]};
    wire [63:0] z3_comb     = c3_4 ^ ror_c3_4_10 ^ ror_c3_4_17;

    wire [63:0] ror_c4_4_7  = {c4_4[6:0], c4_4[63:7]};
    wire [63:0] ror_c4_4_41 = {c4_4[40:0], c4_4[63:41]};
    wire [63:0] z4_comb     = c4_4 ^ ror_c4_4_7 ^ ror_c4_4_41;

    // Output assignments
    assign z0    = z0_comb;
    assign z1    = z1_comb;
    assign z2    = z2_comb;
    assign z3    = z3_comb;
    assign z4    = z4_comb;
    assign valid = s3_valid;

endmodule
