// ═══════════════════════════════════════════════════════════════════════════════
// Testbench: tb_ascon_sbox_18gate
// Verification: Exhaustive 32-vector self-checking test against NIST SP 800-232
// Author: Ayu Chauhan <theayuchauhan@gmail.com>
// ═══════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps

module tb_ascon_sbox_18gate;

    reg  x0, x1, x2, x3, x4;
    wire y0, y1, y2, y3, y4;
    wire y2_inv;

    // Instantiate Unit Under Test (UUT)
    ascon_sbox_18gate uut (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3), .x4(x4),
        .y0(y0), .y1(y1), .y2(y2), .y3(y3), .y4(y4),
        .y2_inv(y2_inv)
    );

    // NIST SP 800-232 Ascon S-box Lookup Table (32 values)
    reg [4:0] nist_lut [0:31];
    integer i, errors;
    reg [4:0] expected_out;
    wire [4:0] actual_out = {y0, y1, y2, y3, y4};

    initial begin
        // Initialize NIST reference lookup table (32 entries)
        nist_lut[0]  = 5'h04; nist_lut[1]  = 5'h0b; nist_lut[2]  = 5'h1f; nist_lut[3]  = 5'h14;
        nist_lut[4]  = 5'h1a; nist_lut[5]  = 5'h15; nist_lut[6]  = 5'h09; nist_lut[7]  = 5'h02;
        nist_lut[8]  = 5'h1b; nist_lut[9]  = 5'h05; nist_lut[10] = 5'h08; nist_lut[11] = 5'h12;
        nist_lut[12] = 5'h1d; nist_lut[13] = 5'h03; nist_lut[14] = 5'h06; nist_lut[15] = 5'h1c;
        nist_lut[16] = 5'h1e; nist_lut[17] = 5'h13; nist_lut[18] = 5'h07; nist_lut[19] = 5'h0e;
        nist_lut[20] = 5'h00; nist_lut[21] = 5'h0d; nist_lut[22] = 5'h11; nist_lut[23] = 5'h18;
        nist_lut[24] = 5'h10; nist_lut[25] = 5'h0c; nist_lut[26] = 5'h01; nist_lut[27] = 5'h19;
        nist_lut[28] = 5'h16; nist_lut[29] = 5'h0a; nist_lut[30] = 5'h0f; nist_lut[31] = 5'h17;

        errors = 0;
        $display("===========================================================================");
        $display("  VERIFYING 18-GATE ASCON S-BOX AGAINST NIST SP 800-232 SPECIFICATION");
        $display("  Author: Ayu Chauhan | Architecture: 18 Gates (11 XOR, 3 AND, 2 OR, 2 NOT)");
        $display("===========================================================================");

        for (i = 0; i < 32; i = i + 1) begin
            x0 = i[4];
            x1 = i[3];
            x2 = i[2];
            x3 = i[1];
            x4 = i[0];
            #1; // propagate combinational delay

            expected_out = nist_lut[i];
            if (actual_out !== expected_out) begin
                $display("FAIL [Vector %02d]: In={%b,%b,%b,%b,%b} Expected=%b (%02h) Got=%b (%02h)",
                         i, x0, x1, x2, x3, x4, expected_out, expected_out, actual_out, actual_out);
                errors = errors + 1;
            end

            // Also check that y2_inv is the exact complement of y2
            if (y2_inv !== ~y2) begin
                $display("FAIL [Vector %02d]: y2_inv mismatch! y2=%b, y2_inv=%b", i, y2, y2_inv);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("===========================================================================");
            $display("  SUCCESS: 32/32 VECTORS MATCHED EXACTLY WITH NIST SP 800-232 (0 ERRORS)");
            $display("  Multiplicative Complexity: Exactly 5 Quadratic Gates (3 AND + 2 OR)");
            $display("  Linear Complexity: 11 XOR gates");
            $display("  Inverters: 2 NOT gates (1 in unrolled mode)");
            $display("===========================================================================");
        end else begin
            $display("ERROR: %0d vector mismatches detected!", errors);
            $fatal(1);
        end

        $finish;
    end

endmodule
