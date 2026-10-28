// ═══════════════════════════════════════════════════════════════════════════════
// Module: tb_ascon128_lwc
// Description: Self-Checking NIST LWC Testbench for ascon128_lwc_core
// Tests: Official NIST SP 800-232 AEAD Encryption (Key, Nonce, PT -> CT, Tag)
// ═══════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps

module tb_ascon128_lwc;

    reg         clk;
    reg         rst_n;
    reg  [31:0] pdi_data;
    reg         pdi_valid;
    wire        pdi_ready;

    reg  [31:0] sdi_data;
    reg         sdi_valid;
    wire        sdi_ready;

    wire [31:0] pdo_data;
    wire        pdo_valid;
    reg         pdo_ready;

    reg         start_op;
    reg         has_ad;
    reg  [15:0] ad_bytes;
    reg  [15:0] pt_bytes;
    wire        done;
    wire        tag_match;

    // Captured outputs
    reg [63:0]  got_ct;
    reg [127:0] got_tag;
    integer     ct_words;
    integer     tag_words;
    integer     errors;

    ascon128_lwc_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .pdi_data(pdi_data),
        .pdi_valid(pdi_valid),
        .pdi_ready(pdi_ready),
        .sdi_data(sdi_data),
        .sdi_valid(sdi_valid),
        .sdi_ready(sdi_ready),
        .pdo_data(pdo_data),
        .pdo_valid(pdo_valid),
        .pdo_ready(pdo_ready),
        .start_op(start_op),
        .has_ad(has_ad),
        .ad_bytes(ad_bytes),
        .pt_bytes(pt_bytes),
        .done(done),
        .tag_match(tag_match)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    // Output capture process
    always @(posedge clk) begin
        if (pdo_valid && pdo_ready) begin
            if (ct_words < 2) begin
                if (ct_words == 0) got_ct[63:32] <= pdo_data;
                else               got_ct[31:0]  <= pdo_data;
                ct_words <= ct_words + 1;
            end else if (tag_words < 4) begin
                case (tag_words)
                    0: got_tag[127:96] <= pdo_data;
                    1: got_tag[95:64]  <= pdo_data;
                    2: got_tag[63:32]  <= pdo_data;
                    3: got_tag[31:0]   <= pdo_data;
                endcase
                tag_words <= tag_words + 1;
            end
        end
    end

    initial begin
        clk       = 0;
        rst_n     = 0;
        pdi_data  = 0;
        pdi_valid = 0;
        sdi_data  = 0;
        sdi_valid = 0;
        pdo_ready = 1;
        start_op  = 0;
        has_ad    = 0;
        ad_bytes  = 0;
        pt_bytes  = 8; // 8 bytes (64 bits)
        ct_words  = 0;
        tag_words = 0;
        got_ct    = 0;
        got_tag   = 0;
        errors    = 0;

        #20;
        rst_n = 1;
        #10;

        $display("==================================================================");
        $display("  TESTING ASCON-128 NIST LWC 2-ROUND SUPER-ROUND HARDWARE CORE");
        $display("==================================================================");

        // Start AEAD operation
        start_op = 1;
        @(posedge clk);
        start_op = 0;

        // 1. Feed 128-bit Key over SDI: 000102030405060708090a0b0c0d0e0f
        sdi_valid = 1;
        sdi_data = 32'h00010203; @(posedge clk); while(!sdi_ready) @(posedge clk);
        sdi_data = 32'h04050607; @(posedge clk); while(!sdi_ready) @(posedge clk);
        sdi_data = 32'h08090a0b; @(posedge clk); while(!sdi_ready) @(posedge clk);
        sdi_data = 32'h0c0d0e0f; @(posedge clk); while(!sdi_ready) @(posedge clk);
        sdi_valid = 0;

        // 2. Feed 128-bit Nonce over PDI: 000102030405060708090a0b0c0d0e0f
        pdi_valid = 1;
        pdi_data = 32'h00010203; @(posedge clk); while(!pdi_ready) @(posedge clk);
        pdi_data = 32'h04050607; @(posedge clk); while(!pdi_ready) @(posedge clk);
        pdi_data = 32'h08090a0b; @(posedge clk); while(!pdi_ready) @(posedge clk);
        pdi_data = 32'h0c0d0e0f; @(posedge clk); while(!pdi_ready) @(posedge clk);
        pdi_valid = 0;

        // Wait for 12-round initialization (6 cycles of 2-round super-round core)
        while (!pdi_ready) @(posedge clk);

        // 3. Feed 64-bit Plaintext over PDI: 0001020304050607
        pdi_valid = 1;
        pdi_data = 32'h00010203; @(posedge clk); while(!pdi_ready) @(posedge clk);
        pdi_data = 32'h04050607; @(posedge clk);
        pdi_valid = 0;

        // Wait for complete operation (Finalization & Tag emission)
        while (!done) @(posedge clk);
        #20;

        $display("\n--- RESULTS ---");
        $display("Expected Ciphertext: bc820dbdf7a4631c");
        $display("Got Ciphertext:      %016h", got_ct);
        $display("Expected Tag:        5008e52f9b5291a4b80958b5a332b823");
        $display("Got Tag:             %032h", got_tag);

        if (got_ct !== 64'hbc820dbdf7a4631c) begin
            $display("❌ [FAIL] Ciphertext Mismatch!");
            errors = errors + 1;
        end else begin
            $display("✅ [PASS] Ciphertext matches official NIST SP 800-232 bit-for-bit!");
        end

        if (got_tag !== 128'h5008e52f9b5291a4b80958b5a332b823) begin
            $display("❌ [FAIL] Tag Mismatch!");
            errors = errors + 1;
        end else begin
            $display("✅ [PASS] 128-Bit Authentication Tag matches official NIST SP 800-232 bit-for-bit!");
        end

        $display("==================================================================");
        if (errors == 0) begin
            $display("🏆 [SUCCESS] ASCON-128 NIST LWC HARDWARE ENGINE FULLY VALIDATED!");
            $finish;
        end else begin
            $fatal(1, "Testbench failed with errors.");
        end
    end

endmodule
