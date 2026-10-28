// ═══════════════════════════════════════════════════════════════════════════════
// Module: ascon_sbox_18gate
// Specification: NIST SP 800-232 (Ascon 5-Bit Non-Linear Substitution Layer S_5)
// Author: Ayu Chauhan <theayuchauhan@gmail.com>
// Project: Project Ramanujan Autonomous Cryptographic Discovery
//
// Description:
//   Optimal 18-gate combinational implementation of the Ascon 5-bit S-box.
//   Achieves 18 gates (11 XOR, 3 AND, 2 OR, 2 NOT) down from the 22-gate
//   standard NIST reference (11 XOR, 5 AND, 6 NOT) while preserving the
//   proven optimal algebraic degree and multiplicative complexity of 5
//   quadratic non-linear operations (3 AND + 2 OR).
//
// Gate Breakdown:
//   - Non-linear operations: 5 (3 AND + 2 OR)  [Provably optimal]
//   - Linear operations:     11 XOR
//   - Inverters:             2 NOT (na0 and c2)
//   - Total Gate Count:      18 Logic Gates
//
// Unrolled Pipeline Note:
//   In unrolled / cascaded hardware rounds, the output inverter on c2 can be
//   omitted entirely (providing c2_inv) and absorbed into the subsequent round
//   constant via the linear diffusion invariant Sigma_2(~x) = ~Sigma_2(x),
//   reducing internal round cost to strictly 17 gates.
// ═══════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps

module ascon_sbox_18gate (
    input  wire x0, x1, x2, x3, x4,  // 5-bit input state vector
    output wire y0, y1, y2, y3, y4,  // 5-bit output state vector
    output wire y2_inv               // Pre-inversion output for fused rounds
);

    // ─────────────────────────────────────────────────────────────────────────
    // Step 1: Linear Affine Input Pre-mixing (3 XOR)
    // ─────────────────────────────────────────────────────────────────────────
    wire a0 = x0 ^ x4;
    wire a4 = x4 ^ x3;
    wire a2 = x2 ^ x1;

    // ─────────────────────────────────────────────────────────────────────────
    // Step 2: Non-Linear Conjunctions & Inverter-Eliminated Terms (3 AND, 1 NOT)
    //
    // Identity A: x2 & a2 = x2 & (x2 ^ x1) == x2 & (~x1)
    //   -> Eliminates inverter on x1!
    //
    // Identity B: x4 & a4 = x4 & (x4 ^ x3) == x4 & (~x3)
    //   -> Eliminates inverter on x3!
    // ─────────────────────────────────────────────────────────────────────────
    wire na0 = ~a0;       // Inverter 1
    wire t1  = x2 & a2;   // AND 1 (Equivalent to x2 & ~x1 without inverter)
    wire t3  = x4 & a4;   // AND 2 (Equivalent to x4 & ~x3 without inverter)
    wire t0  = na0 & x1;  // AND 3

    // ─────────────────────────────────────────────────────────────────────────
    // Step 3: Boolean Absorption Recombination (2 OR, 2 XOR)
    //
    // Identity C: u ^ ((~u) & v) == u | v
    //   -> b1 = x2 ^ (a2 | x3) eliminates inverter on a2!
    //   -> b3 = x4 ^ (a4 | a0) eliminates inverter on a4!
    // ─────────────────────────────────────────────────────────────────────────
    wire b1 = x2 ^ (a2 | x3);  // OR 1 + XOR 4
    wire b3 = x4 ^ (a4 | a0);  // OR 2 + XOR 5
    wire b0 = a0 ^ t1;         // XOR 6
    wire b4 = a4 ^ t0;         // XOR 7

    // ─────────────────────────────────────────────────────────────────────────
    // Step 4: Output Linear Mixing (4 XOR, 1 NOT)
    // ─────────────────────────────────────────────────────────────────────────
    wire c2_inv = a2 ^ t3;     // XOR 8
    wire c1     = b1 ^ b0;     // XOR 9
    wire c0     = b0 ^ b4;     // XOR 10
    wire c3     = b3 ^ c2_inv; // XOR 11
    wire c4     = b4;          // 0 gates (wire alias)
    wire c2     = ~c2_inv;     // Inverter 2

    // Assignments
    assign y0     = c0;
    assign y1     = c1;
    assign y2     = c2;
    assign y3     = c3;
    assign y4     = c4;
    assign y2_inv = c2_inv;

endmodule
