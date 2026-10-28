#!/usr/bin/env python3
"""
Exhaustive Verification & Gate-Level Accounting for the 18-Gate Ascon S-Box
Author: Ayu Chauhan <theayuchauhan@gmail.com>
Specification: NIST SP 800-232
"""

import sys

# NIST SP 800-232 Section 3.2 Reference Lookup Table
# Directly generated from the canonical bitslice equations:
#   x0 ^= x4; x4 ^= x3; x2 ^= x1;
#   t0 = (~x0) & x1; t1 = (~x1) & x2; t2 = (~x2) & x3; t3 = (~x3) & x4; t4 = (~x4) & x0;
#   x0 ^= t1; x1 ^= t2; x2 ^= t3; x3 ^= t4; x4 ^= t0;
#   x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = ~x2;
NIST_SBOX_LUT = [
    0x04, 0x0b, 0x1f, 0x14, 0x1a, 0x15, 0x09, 0x02,
    0x1b, 0x05, 0x08, 0x12, 0x1d, 0x03, 0x06, 0x1c,
    0x1e, 0x13, 0x07, 0x0e, 0x00, 0x0d, 0x11, 0x18,
    0x10, 0x0c, 0x01, 0x19, 0x16, 0x0a, 0x0f, 0x17
]

def ascon_sbox_18gate(x0: int, x1: int, x2: int, x3: int, x4: int):
    """
    Computes Ascon 5-bit S-box using exactly 18 logic gates:
    - 11 XOR
    - 3 AND
    - 2 OR
    - 2 NOT (1 in unrolled mode)
    """
    # 3 XOR
    a0 = x0 ^ x4
    a4 = x4 ^ x3
    a2 = x2 ^ x1

    # 1 NOT, 3 AND
    na0 = 1 ^ a0
    t1  = x2 & a2       # x2 & (x2 ^ x1) == x2 & ~x1
    t3  = x4 & a4       # x4 & (x4 ^ x3) == x4 & ~x3
    t0  = na0 & x1

    # 2 OR, 4 XOR
    b1 = x2 ^ (a2 | x3) # u ^ (~u & v) == u | v
    b3 = x4 ^ (a4 | a0)
    b0 = a0 ^ t1
    b4 = a4 ^ t0

    # 4 XOR, 1 NOT
    c2_inv = a2 ^ t3
    c1     = b1 ^ b0
    c0     = b0 ^ b4
    c3     = b3 ^ c2_inv
    c4     = b4
    c2     = 1 ^ c2_inv

    return c0, c1, c2, c3, c4, c2_inv

def main():
    print("=" * 75)
    print("  EXHAUSTIVE ASCON S-BOX VERIFICATION (NIST SP 800-232)")
    print("  Author: Ayu Chauhan <theayuchauhan@gmail.com>")
    print("=" * 75)

    errors = 0
    for idx in range(32):
        x0 = (idx >> 4) & 1
        x1 = (idx >> 3) & 1
        x2 = (idx >> 2) & 1
        x3 = (idx >> 1) & 1
        x4 = (idx >> 0) & 1

        c0, c1, c2, c3, c4, c2_inv = ascon_sbox_18gate(x0, x1, x2, x3, x4)
        out_val = (c0 << 4) | (c1 << 3) | (c2 << 2) | (c3 << 1) | c4
        expected = NIST_SBOX_LUT[idx]

        if out_val != expected:
            print(f"FAIL [Index {idx:02d}]: Input={idx:02x} Expected={expected:02x} Got={out_val:02x}")
            errors += 1

    if errors == 0:
        print("✓ All 32/32 inputs evaluated: 100% bit-for-bit equivalence with NIST SP 800-232.")
        print("-" * 75)
        print("GATE ACCOUNTING:")
        print("  • Linear:      11 XOR gates")
        print("  • Non-Linear:   5 gates (3 AND + 2 OR)  [Theoretical Minimum]")
        print("  • Inverters:    2 NOT gates (1 NOT in unrolled datapath)")
        print("  • TOTAL GATES: 18 Gates (Standalone) / 17 Gates (Fused Round)")
        print("=" * 75)
    else:
        print(f"FAILED: {errors} mismatches detected.")
        sys.exit(1)

if __name__ == "__main__":
    main()
