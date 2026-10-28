"""
Ascon Fused Round Algorithmic Equivalence Checker
═════════════════════════════════════════════════
Functional cross-validation script verifying that:
1. Python simulation of 57-op 2-round equations matches NIST SP 800-232 across random test vectors.
2. Python simulation of 113-op 4-round equations matches NIST SP 800-232 across random test vectors.
3. Cascaded rounds correctly match the full 12-round Ascon-128 permutation.

Note: This script validates the mathematical equations in Python. True RTL verification
requires compiling and simulating the Verilog testbenches (tb_ascon_*.v) with Icarus Verilog
or Verilator, or running formal Combinational Equivalence Checking (CEC) via Yosys/ABC.
"""

import os
import sys
import time
import random
import shutil
import subprocess

MASK64 = 0xFFFFFFFFFFFFFFFF

def ror64(val: int, r: int) -> int:
    val = val & MASK64
    r = r % 64
    if r == 0:
        return val
    return ((val >> r) | (val << (64 - r))) & MASK64

def nist_single_round(x0, x1, x2, x3, x4, round_const):
    x2 ^= round_const
    x0 ^= x4; x4 ^= x3; x2 ^= x1
    t0 = (~x0) & x1
    t1 = (~x1) & x2
    t2 = (~x2) & x3
    t3 = (~x3) & x4
    t4 = (~x4) & x0
    x0 ^= t1; x1 ^= t2; x2 ^= t3; x3 ^= t4; x4 ^= t0
    x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = (~x2) & MASK64
    y0 = x0 ^ ror64(x0, 19) ^ ror64(x0, 28)
    y1 = x1 ^ ror64(x1, 61) ^ ror64(x1, 39)
    y2 = x2 ^ ror64(x2, 1)  ^ ror64(x2, 6)
    y3 = x3 ^ ror64(x3, 10) ^ ror64(x3, 17)
    y4 = x4 ^ ror64(x4, 7)  ^ ror64(x4, 41)
    return (y0 & MASK64, y1 & MASK64, y2 & MASK64, y3 & MASK64, y4 & MASK64)

def simulate_super_round_2r(x0, x1, x2, x3, x4, cr1, cr2):
    """Line-by-line RTL equivalence for ascon_super_round_2r.v"""
    # Round 1
    x2_r1 = (x2 ^ cr1) & MASK64
    a0 = (x0 ^ x4) & MASK64
    a4 = (x4 ^ x3) & MASK64
    a2 = (x2_r1 ^ x1) & MASK64
    na0 = (~a0) & MASK64

    t1 = (x2_r1 & a2) & MASK64
    t3 = (x4 & a4) & MASK64
    t0 = (na0 & x1) & MASK64

    b1 = (x2_r1 ^ (a2 | x3)) & MASK64
    b3 = (x4 ^ (a4 | a0)) & MASK64
    b0 = (a0 ^ t1) & MASK64
    b4 = (a4 ^ t0) & MASK64

    c2_inv = (a2 ^ t3) & MASK64
    c1 = (b1 ^ b0) & MASK64
    c0 = (b0 ^ b4) & MASK64
    c3 = (b3 ^ c2_inv) & MASK64
    c4 = b4

    y0 = (c0 ^ ror64(c0, 19) ^ ror64(c0, 28)) & MASK64
    y1 = (c1 ^ ror64(c1, 61) ^ ror64(c1, 39)) & MASK64
    y2 = (c2_inv ^ ror64(c2_inv, 1) ^ ror64(c2_inv, 6)) & MASK64
    y3 = (c3 ^ ror64(c3, 10) ^ ror64(c3, 17)) & MASK64
    y4 = (c4 ^ ror64(c4, 7) ^ ror64(c4, 41)) & MASK64

    # Round 2
    y2_r2 = (y2 ^ ((~cr2) & MASK64)) & MASK64
    a0_2 = (y0 ^ y4) & MASK64
    a4_2 = (y4 ^ y3) & MASK64
    a2_2 = (y2_r2 ^ y1) & MASK64
    na0_2 = (~a0_2) & MASK64

    t1_2 = (y2_r2 & a2_2) & MASK64
    t3_2 = (y4 & a4_2) & MASK64
    t0_2 = (na0_2 & y1) & MASK64

    b1_2 = (y2_r2 ^ (a2_2 | y3)) & MASK64
    b3_2 = (y4 ^ (a4_2 | a0_2)) & MASK64
    b0_2 = (a0_2 ^ t1_2) & MASK64
    b4_2 = (a4_2 ^ t0_2) & MASK64

    c2_2_inv = (a2_2 ^ t3_2) & MASK64
    c1_2 = (b1_2 ^ b0_2) & MASK64
    c0_2 = (b0_2 ^ b4_2) & MASK64
    c3_2 = (b3_2 ^ c2_2_inv) & MASK64
    c4_2 = b4_2
    c2_2 = (~c2_2_inv) & MASK64

    z0 = (c0_2 ^ ror64(c0_2, 19) ^ ror64(c0_2, 28)) & MASK64
    z1 = (c1_2 ^ ror64(c1_2, 61) ^ ror64(c1_2, 39)) & MASK64
    z2 = (c2_2 ^ ror64(c2_2, 1) ^ ror64(c2_2, 6)) & MASK64
    z3 = (c3_2 ^ ror64(c3_2, 10) ^ ror64(c3_2, 17)) & MASK64
    z4 = (c4_2 ^ ror64(c4_2, 7) ^ ror64(c4_2, 41)) & MASK64

    return (z0, z1, z2, z3, z4)

def simulate_mega_round_4r(x0, x1, x2, x3, x4, cr1, cr2, cr3, cr4):
    """Line-by-line RTL equivalence for ascon_mega_round_4r.v"""
    # Round 1
    x2_1 = (x2 ^ cr1) & MASK64
    a0_1 = (x0 ^ x4) & MASK64
    a4_1 = (x4 ^ x3) & MASK64
    a2_1 = (x2_1 ^ x1) & MASK64
    na0_1 = (~a0_1) & MASK64
    t1_1 = (x2_1 & a2_1) & MASK64
    t3_1 = (x4 & a4_1) & MASK64
    t0_1 = (na0_1 & x1) & MASK64
    b1_1 = (x2_1 ^ (a2_1 | x3)) & MASK64
    b3_1 = (x4 ^ (a4_1 | a0_1)) & MASK64
    b0_1 = (a0_1 ^ t1_1) & MASK64
    b4_1 = (a4_1 ^ t0_1) & MASK64
    c2_1_inv = (a2_1 ^ t3_1) & MASK64
    c1_1 = (b1_1 ^ b0_1) & MASK64
    c0_1 = (b0_1 ^ b4_1) & MASK64
    c3_1 = (b3_1 ^ c2_1_inv) & MASK64
    c4_1 = b4_1

    y0_1 = (c0_1 ^ ror64(c0_1, 19) ^ ror64(c0_1, 28)) & MASK64
    y1_1 = (c1_1 ^ ror64(c1_1, 61) ^ ror64(c1_1, 39)) & MASK64
    y2_1 = (c2_1_inv ^ ror64(c2_1_inv, 1) ^ ror64(c2_1_inv, 6)) & MASK64
    y3_1 = (c3_1 ^ ror64(c3_1, 10) ^ ror64(c3_1, 17)) & MASK64
    y4_1 = (c4_1 ^ ror64(c4_1, 7) ^ ror64(c4_1, 41)) & MASK64

    # Round 2
    y2_2 = (y2_1 ^ ((~cr2) & MASK64)) & MASK64
    a0_2 = (y0_1 ^ y4_1) & MASK64
    a4_2 = (y4_1 ^ y3_1) & MASK64
    a2_2 = (y2_2 ^ y1_1) & MASK64
    na0_2 = (~a0_2) & MASK64
    t1_2 = (y2_2 & a2_2) & MASK64
    t3_2 = (y4_1 & a4_2) & MASK64
    t0_2 = (na0_2 & y1_1) & MASK64
    b1_2 = (y2_2 ^ (a2_2 | y3_1)) & MASK64
    b3_2 = (y4_1 ^ (a4_2 | a0_2)) & MASK64
    b0_2 = (a0_2 ^ t1_2) & MASK64
    b4_2 = (a4_2 ^ t0_2) & MASK64
    c2_2_inv = (a2_2 ^ t3_2) & MASK64
    c1_2 = (b1_2 ^ b0_2) & MASK64
    c0_2 = (b0_2 ^ b4_2) & MASK64
    c3_2 = (b3_2 ^ c2_2_inv) & MASK64
    c4_2 = b4_2

    y0_2 = (c0_2 ^ ror64(c0_2, 19) ^ ror64(c0_2, 28)) & MASK64
    y1_2 = (c1_2 ^ ror64(c1_2, 61) ^ ror64(c1_2, 39)) & MASK64
    y2_2_diff = (c2_2_inv ^ ror64(c2_2_inv, 1) ^ ror64(c2_2_inv, 6)) & MASK64
    y3_2 = (c3_2 ^ ror64(c3_2, 10) ^ ror64(c3_2, 17)) & MASK64
    y4_2 = (c4_2 ^ ror64(c4_2, 7) ^ ror64(c4_2, 41)) & MASK64

    # Round 3
    y2_3 = (y2_2_diff ^ ((~cr3) & MASK64)) & MASK64
    a0_3 = (y0_2 ^ y4_2) & MASK64
    a4_3 = (y4_2 ^ y3_2) & MASK64
    a2_3 = (y2_3 ^ y1_2) & MASK64
    na0_3 = (~a0_3) & MASK64
    t1_3 = (y2_3 & a2_3) & MASK64
    t3_3 = (y4_2 & a4_3) & MASK64
    t0_3 = (na0_3 & y1_2) & MASK64
    b1_3 = (y2_3 ^ (a2_3 | y3_2)) & MASK64
    b3_3 = (y4_2 ^ (a4_3 | a0_3)) & MASK64
    b0_3 = (a0_3 ^ t1_3) & MASK64
    b4_3 = (a4_3 ^ t0_3) & MASK64
    c2_3_inv = (a2_3 ^ t3_3) & MASK64
    c1_3 = (b1_3 ^ b0_3) & MASK64
    c0_3 = (b0_3 ^ b4_3) & MASK64
    c3_3 = (b3_3 ^ c2_3_inv) & MASK64
    c4_3 = b4_3

    y0_3 = (c0_3 ^ ror64(c0_3, 19) ^ ror64(c0_3, 28)) & MASK64
    y1_3 = (c1_3 ^ ror64(c1_3, 61) ^ ror64(c1_3, 39)) & MASK64
    y2_3_diff = (c2_3_inv ^ ror64(c2_3_inv, 1) ^ ror64(c2_3_inv, 6)) & MASK64
    y3_3 = (c3_3 ^ ror64(c3_3, 10) ^ ror64(c3_3, 17)) & MASK64
    y4_3 = (c4_3 ^ ror64(c4_3, 7) ^ ror64(c4_3, 41)) & MASK64

    # Round 4
    y2_4 = (y2_3_diff ^ ((~cr4) & MASK64)) & MASK64
    a0_4 = (y0_3 ^ y4_3) & MASK64
    a4_4 = (y4_3 ^ y3_3) & MASK64
    a2_4 = (y2_4 ^ y1_3) & MASK64
    na0_4 = (~a0_4) & MASK64
    t1_4 = (y2_4 & a2_4) & MASK64
    t3_4 = (y4_3 & a4_4) & MASK64
    t0_4 = (na0_4 & y1_3) & MASK64
    b1_4 = (y2_4 ^ (a2_4 | y3_3)) & MASK64
    b3_4 = (y4_3 ^ (a4_4 | a0_4)) & MASK64
    b0_4 = (a0_4 ^ t1_4) & MASK64
    b4_4 = (a4_4 ^ t0_4) & MASK64
    c2_4_inv = (a2_4 ^ t3_4) & MASK64
    c1_4 = (b1_4 ^ b0_4) & MASK64
    c0_4 = (b0_4 ^ b4_4) & MASK64
    c3_4 = (b3_4 ^ c2_4_inv) & MASK64
    c4_4 = b4_4
    c2_4 = (~c2_4_inv) & MASK64

    z0 = (c0_4 ^ ror64(c0_4, 19) ^ ror64(c0_4, 28)) & MASK64
    z1 = (c1_4 ^ ror64(c1_4, 61) ^ ror64(c1_4, 39)) & MASK64
    z2 = (c2_4 ^ ror64(c2_4, 1) ^ ror64(c2_4, 6)) & MASK64
    z3 = (c3_4 ^ ror64(c3_4, 10) ^ ror64(c3_4, 17)) & MASK64
    z4 = (c4_4 ^ ror64(c4_4, 7) ^ ror64(c4_4, 41)) & MASK64

    return (z0, z1, z2, z3, z4)

def main():
    print("=" * 75)
    print("  ASCON 2-ROUND & 4-ROUND ALGORITHMIC EQUIVALENCE CHECKER")
    print("=" * 75)

    base_dir = os.path.dirname(__file__)
    file_2r = os.path.join(base_dir, "ascon_super_round_2r.v")
    file_4r = os.path.join(base_dir, "ascon_mega_round_4r.v")

    assert os.path.exists(file_2r), f"Missing {file_2r}"
    assert os.path.exists(file_4r), f"Missing {file_4r}"
    print(f"✓ Found RTL Module 1: {file_2r}")
    print(f"✓ Found RTL Module 2: {file_4r}")

    rng = random.Random(0xBADC0FFEE0123)

    # 1. Verify 2-Round Super-Round Core
    print("\n[PART 1] Verifying 2-Round Super-Round Core (57 Ops)...")
    t0 = time.perf_counter()
    for i in range(1000):
        x0, x1, x2, x3, x4 = [rng.getrandbits(64) for _ in range(5)]
        cr1, cr2 = rng.getrandbits(64), rng.getrandbits(64)

        # Expected NIST 2 rounds
        w0, w1, w2, w3, w4 = nist_single_round(x0, x1, x2, x3, x4, cr1)
        exp = nist_single_round(w0, w1, w2, w3, w4, cr2)
        got = simulate_super_round_2r(x0, x1, x2, x3, x4, cr1, cr2)

        if got != exp:
            print(f"❌ 2-Round Mismatch at vector #{i}!")
            sys.exit(1)
    ms_2r = (time.perf_counter() - t0) * 1000
    print(f"✓ 2-Round Core: 64,000/64,000 bitslices validated in {ms_2r:.2f}ms (0 errors).")

    # 2. Verify 4-Round Mega-Round Core
    print("\n[PART 2] Verifying 4-Round Mega-Round Core (113 Ops)...")
    t1 = time.perf_counter()
    for i in range(1000):
        x0, x1, x2, x3, x4 = [rng.getrandbits(64) for _ in range(5)]
        cr1, cr2, cr3, cr4 = [rng.getrandbits(64) for _ in range(4)]

        # Expected NIST 4 rounds
        w0, w1, w2, w3, w4 = nist_single_round(x0, x1, x2, x3, x4, cr1)
        w0, w1, w2, w3, w4 = nist_single_round(w0, w1, w2, w3, w4, cr2)
        w0, w1, w2, w3, w4 = nist_single_round(w0, w1, w2, w3, w4, cr3)
        exp = nist_single_round(w0, w1, w2, w3, w4, cr4)

        got = simulate_mega_round_4r(x0, x1, x2, x3, x4, cr1, cr2, cr3, cr4)

        if got != exp:
            print(f"❌ 4-Round Mismatch at vector #{i}!")
            sys.exit(1)
    ms_4r = (time.perf_counter() - t1) * 1000
    print(f"✓ 4-Round Core: 64,000/64,000 bitslices validated in {ms_4r:.2f}ms (0 errors).")

    # 3. Complete 12-Round Cascading Permutation Test
    print("\n[PART 3] Full 12-Round Ascon-128 Cascading Permutation Test...")
    ASCON_CR = [
        0x00000000000000F0, 0x00000000000000E1,
        0x00000000000000D2, 0x00000000000000C3,
        0x00000000000000B4, 0x00000000000000A5,
        0x0000000000000096, 0x0000000000000087,
        0x0000000000000078, 0x0000000000000069,
        0x000000000000005A, 0x000000000000004B
    ]
    # Ascon IV state
    sx0, sx1, sx2, sx3, sx4 = (
        0x80400C0600000000, 0x0001020304050607,
        0x08090A0B0C0D0E0F, 0x1011121314151617,
        0x18191A1B1C1D1E1F
    )
    # NIST 12 rounds
    nx0, nx1, nx2, nx3, nx4 = sx0, sx1, sx2, sx3, nx4 = sx0, sx1, sx2, sx3, sx4
    for r in range(12):
        nx0, nx1, nx2, nx3, nx4 = nist_single_round(nx0, nx1, nx2, nx3, nx4, ASCON_CR[r])

    # Method A: 6 x 2-Round Super-Rounds
    a0, a1, a2, a3, a4 = sx0, sx1, sx2, sx3, sx4
    for b in range(6):
        a0, a1, a2, a3, a4 = simulate_super_round_2r(a0, a1, a2, a3, a4, ASCON_CR[2*b], ASCON_CR[2*b+1])
    assert (a0, a1, a2, a3, a4) == (nx0, nx1, nx2, nx3, nx4), "Method A failed!"
    print("✓ 6 x 2-Round Super-Round Blocks produce identical 12-round Ascon-128 final state.")

    # Method B: 3 x 4-Round Mega-Rounds
    m0, m1, m2, m3, m4 = sx0, sx1, sx2, sx3, sx4
    for b in range(3):
        m0, m1, m2, m3, m4 = simulate_mega_round_4r(
            m0, m1, m2, m3, m4,
            ASCON_CR[4*b], ASCON_CR[4*b+1], ASCON_CR[4*b+2], ASCON_CR[4*b+3]
        )
    assert (m0, m1, m2, m3, m4) == (nx0, nx1, nx2, nx3, nx4), "Method B failed!"
    print("✓ 3 x 4-Round Mega-Round Blocks produce identical 12-round Ascon-128 final state.")

    # Check for Verilog tools
    has_iverilog = shutil.which("iverilog") is not None
    print("\n" + "=" * 75)
    print("✓ PYTHON ALGORITHMIC FUNCTIONAL VALIDATION COMPLETED (0 ERRORS)")
    if has_iverilog:
        print("ℹ Icarus Verilog detected on PATH. Run tb_ascon_*.v with iverilog to verify RTL.")
    else:
        print("ℹ Note: True RTL verification requires running HDL simulators (iverilog/verilator)")
        print("  or formal Combinational Equivalence Checking (Yosys/ABC).")
    print("=" * 75)

if __name__ == "__main__":
    main()
