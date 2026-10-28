# Ascon-Ramanujan: Sub-20 Gate Ascon Substitution & Fused Permutation RTL

[![Standard: NIST SP 800-232](https://img.shields.io/badge/Standard-NIST%20SP%20800--232-blue.svg)](https://csrc.nist.gov/pubs/sp/800/232/ipd)
[![HDL: IEEE 1364-2001](https://img.shields.io/badge/HDL-Verilog%202001-green.svg)](https://standards.ieee.org/)
[![Verification: 100% Proven](https://img.shields.io/badge/Verification-100%25%20Bit--for--Bit%20Match-brightgreen.svg)](#-verification--reproducibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Author: Ayu Chauhan](https://img.shields.io/badge/Author-Ayu%20Chauhan-orange.svg)](mailto:theayuchauhan@gmail.com)

Synthesizable IEEE 1364-2001 Verilog HDL reference cores and algebraic circuit optimizations for the **NIST SP 800-232 Ascon** authenticated cipher family, developed by **Ayu Chauhan** under *Project Ramanujan*.

---

## 🏆 Key Discoveries & Contributions

1. **18-Gate Standalone S-Box (`ascon_sbox_18gate.v`)**:
   - Reduces the standard 22-gate NIST Chi implementation down to **strictly 18 gates** (11 XOR, 3 AND, 2 OR, 2 NOT).
   - Preserves the theoretical multiplicative complexity lower bound of **exactly 5 non-linear quadratic operations** ($3\text{ AND} + 2\text{ OR} = 5$).
   - Formally proved via Boolean absorption ($u \oplus (\neg u \land v) \equiv u \lor v$) and dual-variable self-masking ($x \land (x \oplus y) \equiv x \land \neg y$).
2. **17-Gate Fused Round S-Box**:
   - In unrolled pipelines, the output inverter on $c_2$ is absorbed into the subsequent round constant through the linear diffusion invariant ($\Sigma_2(\neg x) = \neg \Sigma_2(x)$), dropping the internal substitution layer to **17 gates**.
3. **57-Operation 2-Round Super-Round Core (`ascon_super_round_2r.v`)**:
   - Executes 2 unrolled rounds in **57 word-level operations** (44 XOR, 6 AND, 4 OR, 3 NOT) versus 66 in the reference design (**9 operations saved per 2-round block**).
4. **Streaming AEAD Hardware Engine (`ascon128_lwc_core.v`)**:
   - ATHENa / NIST LWC compliant 32-bit streaming interface.
   - Steady-state throughput: **3.20 Gbps at 150 MHz** (64 bits every 3 clock cycles).
   - Bit-for-bit verified against NIST Known Answer Tests (KAT).

---

## 📊 Comparative Complexity

### 5-Bit Non-Linear Substitution Layer ($S_5$)

| Architecture | XOR | AND | OR | NOT | Non-Linear Total | Total Gates |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **NIST SP 800-232 Reference** | 11 | 5 | 0 | 6 | 5 | **22** |
| **Classical Minimal-Inverter** | 11 | 5 | 0 | 4 | 5 | **20** |
| **This Work: Standalone S-Box** | **11** | **3** | **2** | **2** | **5** | **18** |
| **This Work: Fused Internal S-Box** | **11** | **3** | **2** | **1** | **5** | **17** |

---

## 📁 Repository Structure

```text
├── ascon_sbox_18gate.v           # Standalone 18-gate 5-bit Ascon S-box
├── ascon_super_round_2r.v        # Synthesizable 2-round fused super-round core (57 ops)
├── ascon_mega_round_4r.v         # Synthesizable 4-round fused mega-round core (113 ops)
├── ascon128_lwc_core.v           # Full NIST LWC / ATHENa streaming AEAD engine
├── tb_ascon_sbox_18gate.v        # Exhaustive 32-vector self-checking Verilog testbench
├── tb_ascon_super_round_2r.v     # 2-round self-checking KAT testbench
├── tb_ascon_mega_round_4r.v      # 4-round self-checking KAT testbench
├── tb_ascon128_lwc.v             # NIST AEAD self-checking testbench
├── test_sbox_exhaustive.py       # Python standalone exhaustive S-box verification
├── verify_verilog_equivalence.py # 64,000-bitslice Python equivalence checker
├── run_ascon128_lwc_simulation.py# Full cycle-accurate AEAD simulator
├── synth_artix7.tcl              # Headless Vivado batch synthesis script
├── paper/
│   ├── paper.tex                 # Publication-grade academic paper (IEEE / IACR format)
│   └── paper.md                  # Markdown version of research paper
├── CITATION.cff                  # Citation metadata
├── LICENSE                       # MIT License
└── README.md
```

---

## 🧠 Mathematical Proofs

### Theorem 1: Boolean Absorption via Disjunction
$$\forall u, v \in \mathbb{F}_2: \quad u \oplus ((\neg u) \land v) \equiv u \lor v$$

*Proof*:
- When $u = 0$: $0 \oplus (1 \land v) = v = 0 \lor v$.
- When $u = 1$: $1 \oplus (0 \land v) = 1 = 1 \lor v$.
Because this holds for all evaluations, the replacement of $x_2 \oplus [a_2 \oplus ((\neg a_2) \land x_3)]$ with $x_2 \oplus (a_2 \lor x_3)$ is exact and eliminates the inverter on $a_2$.

### Theorem 2: Dual-Variable Conjunction Self-Masking
$$\forall x, y \in \mathbb{F}_2, \text{ with } a = x \oplus y: \quad x \land a \equiv x \land (\neg y)$$

*Proof*:
- When $x = 0$: both sides evaluate to 0.
- When $x = 1$: $1 \land (1 \oplus y) = \neg y = 1 \land \neg y$.
Hence, $t_1 = x_2 \land a_2$ and $t_3 = x_4 \land a_4$ eliminate inverters on $x_1$ and $x_3$ with zero auxiliary gates.

---

## ⚡ Verilog S-Box Implementation (`ascon_sbox_18gate.v`)

```verilog
module ascon_sbox_18gate (
    input  wire x0, x1, x2, x3, x4,  // 5-bit input state vector
    output wire y0, y1, y2, y3, y4,  // 5-bit output state vector
    output wire y2_inv               // Pre-inversion output for fused rounds
);
    // Affine Input Pre-mixing (3 XOR)
    wire a0 = x0 ^ x4;
    wire a4 = x4 ^ x3;
    wire a2 = x2 ^ x1;

    // Conjunctions with Inverter Elimination (3 AND, 1 NOT)
    wire na0 = ~a0;
    wire t1  = x2 & a2;   // x2 & ~x1 without inverter
    wire t3  = x4 & a4;   // x4 & ~x3 without inverter
    wire t0  = na0 & x1;

    // Boolean Absorption Recombination (2 OR, 4 XOR)
    wire b1 = x2 ^ (a2 | x3);  // Eliminates ~a2
    wire b3 = x4 ^ (a4 | a0);  // Eliminates ~a4
    wire b0 = a0 ^ t1;
    wire b4 = a4 ^ t0;

    // Output Linear Mixing (4 XOR, 1 NOT)
    wire c2_inv = a2 ^ t3;
    wire c1     = b1 ^ b0;
    wire c0     = b0 ^ b4;
    wire c3     = b3 ^ c2_inv;
    wire c4     = b4;
    wire c2     = ~c2_inv;

    assign y0 = c0;
    assign y1 = c1;
    assign y2 = c2;
    assign y3 = c3;
    assign y4 = c4;
    assign y2_inv = c2_inv;
endmodule
```

---

## 🧪 Verification & Reproducibility

### 1. Exhaustive 32/32 S-Box Test
```bash
python test_sbox_exhaustive.py
```
*Expected output*: `✓ All 32/32 inputs evaluated: 100% bit-for-bit equivalence with NIST SP 800-232.`

### 2. 64,000-Bitslice Parallel Equivalence Test
```bash
python verify_verilog_equivalence.py
```
*Expected output*: `✓ 2-Round Core: 64,000/64,000 bitslices validated (0 errors).`

### 3. Full NIST LWC AEAD Hardware Simulation
```bash
python run_ascon128_lwc_simulation.py
```
*Expected output*:
```text
Expected Tag: 5008e52f9b5291a4b80958b5a332b823
Got Tag:      5008e52f9b5291a4b80958b5a332b823
100% BIT-FOR-BIT MATCH (Throughput: 3.20 Gbps @ 150 MHz)
```

### 4. IEEE 1364-2001 Verilog Simulation (Icarus Verilog)
```bash
# Test 18-gate S-box
iverilog -o tb_sbox.vvp tb_ascon_sbox_18gate.v ascon_sbox_18gate.v
vvp tb_sbox.vvp

# Test 2-round super-round core
iverilog -o tb_2r.vvp tb_ascon_super_round_2r.v ascon_super_round_2r.v
vvp tb_2r.vvp

# Test full NIST LWC AEAD engine
iverilog -o tb_lwc.vvp tb_ascon128_lwc.v ascon128_lwc_core.v ascon_super_round_2r.v
vvp tb_lwc.vvp
```

---

## 📄 Academic Research Paper

The complete academic paper is available in the [`paper/`](paper/) directory:
- [LaTeX Source (`paper/paper.tex`)](paper/paper.tex)
- [Markdown Pre-print (`paper/paper.md`)](paper/paper.md)

---

## 📜 Citation & Attribution

If you use this circuit design, HDL code, or research results in your work, please cite:

```bibtex
@article{chauhan2026ascon,
  title={Sub-20 Gate Ascon Substitution and Invariant-Fused Permutation Datapaths for NIST SP 800-232},
  author={Chauhan, Ayu},
  year={2026},
  publisher={Project Ramanujan Cryptographic Discovery Laboratory},
  url={https://github.com/VintageAyu/ascon-ramanujan}
}
```

---

## ⚖️ License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.  
Copyright (c) 2026 Ayu Chauhan.
