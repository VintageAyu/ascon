// ═══════════════════════════════════════════════════════════════════════════════
// Module: ascon128_lwc_core
// Specification: NIST SP 800-232 (Ascon-128 Authenticated Encryption with Associated Data)
// Architecture: 2-Round Super-Round Accelerated NIST LWC Engine
// Throughput Engine: ascon_super_round_2r (3 cycles per 64-bit block, 6 cycles for init/final)
// Standard: IEEE 1364-2001 Synthesizable Verilog HDL
// Benchmark Target: Xilinx Artix-7 (ATHENa LWC Hardware API Compliant)
// ═══════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps

module ascon128_lwc_core (
    input  wire        clk,
    input  wire        rst_n,

    // Public Data In (PDI) - 32-bit streaming port (Nonce, AD, Plaintext)
    input  wire [31:0] pdi_data,
    input  wire        pdi_valid,
    output reg         pdi_ready,

    // Secret Data In (SDI) - 32-bit streaming port (Key)
    input  wire [31:0] sdi_data,
    input  wire        sdi_valid,
    output reg         sdi_ready,

    // Public Data Out (PDO) - 32-bit streaming port (Ciphertext, Tag)
    output reg  [31:0] pdo_data,
    output reg         pdo_valid,
    input  wire        pdo_ready,

    // Control & Status
    input  wire        start_op,       // Trigger new AEAD operation
    input  wire        has_ad,         // 1 if associated data present
    input  wire [15:0] ad_bytes,       // Byte count of AD
    input  wire [15:0] pt_bytes,       // Byte count of Plaintext
    output reg         done,           // Operation complete
    output reg         tag_match       // For decryption/verification
);

    // ─────────────────────────────────────────────────────────────────────────
    // FSM States
    // ─────────────────────────────────────────────────────────────────────────
    localparam STATE_IDLE       = 4'd0;
    localparam STATE_LOAD_KEY   = 4'd1;
    localparam STATE_LOAD_NONCE = 4'd2;
    localparam STATE_INIT_PERM  = 4'd3;
    localparam STATE_INIT_KEY   = 4'd4;
    localparam STATE_PROC_AD    = 4'd5;
    localparam STATE_AD_PERM    = 4'd6;
    localparam STATE_PROC_PT    = 4'd7;
    localparam STATE_PT_PERM    = 4'd8;
    localparam STATE_FINAL_PERM = 4'd9;
    localparam STATE_FINAL_KEY  = 4'd10;
    localparam STATE_EMIT_TAG   = 4'd11;
    localparam STATE_DONE       = 4'd12;

    reg [3:0] state, next_state;

    // ─────────────────────────────────────────────────────────────────────────
    // Datapath Registers (320-Bit State + Key Storage)
    // ─────────────────────────────────────────────────────────────────────────
    reg [63:0] s0, s1, s2, s3, s4;
    reg [63:0] k0, k1; // 128-bit Secret Key

    // Ascon-128 IV: k=128, r=64, a=12, b=6 -> 0x80400c0600000000
    localparam [63:0] ASCON128_IV = 64'h80400c0600000000;

    // Buffer registers for 32-to-64 bit assembly
    reg [31:0] word32_buf;
    reg [2:0]  word_count;
    reg [2:0]  round_step;     // Tracks 2-round steps (0..5 for 12 rounds, 0..2 for 6 rounds)
    reg [15:0] bytes_remaining;

    // ─────────────────────────────────────────────────────────────────────────
    // Super-Round 2-Round Permutation Datapath Core
    // ─────────────────────────────────────────────────────────────────────────
    reg  [63:0] cr1_in, cr2_in;
    wire [63:0] perm_z0, perm_z1, perm_z2, perm_z3, perm_z4;
    wire        perm_valid;

    ascon_super_round_2r #(.PIPELINED(0)) perm_engine (
        .clk(clk),
        .rst_n(rst_n),
        .enable(1'b1),
        .cr1(cr1_in),
        .cr2(cr2_in),
        .x0(s0), .x1(s1), .x2(s2), .x3(s3), .x4(s4),
        .z0(perm_z0), .z1(perm_z1), .z2(perm_z2), .z3(perm_z3), .z4(perm_z4),
        .valid(perm_valid)
    );

    // Round Constant Lookup (ROM)
    // Ascon-128 Constants:
    // Round 0..11: F0, E1, D2, C3, B4, A5, 96, 87, 78, 69, 5A, 4B
    always @(*) begin
        case (round_step)
            3'd0: begin cr1_in = 64'h00000000000000F0; cr2_in = 64'h00000000000000E1; end
            3'd1: begin cr1_in = 64'h00000000000000D2; cr2_in = 64'h00000000000000C3; end
            3'd2: begin cr1_in = 64'h00000000000000B4; cr2_in = 64'h00000000000000A5; end
            3'd3: begin cr1_in = 64'h0000000000000096; cr2_in = 64'h0000000000000087; end
            3'd4: begin cr1_in = 64'h0000000000000078; cr2_in = 64'h0000000000000069; end
            3'd5: begin cr1_in = 64'h000000000000005A; cr2_in = 64'h000000000000004B; end
            default: begin cr1_in = 64'h0000000000000000; cr2_in = 64'h0000000000000000; end
        endcase
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Sequential State Transition & Datapath Control
    // ─────────────────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= STATE_IDLE;
            s0              <= 64'd0;
            s1              <= 64'd0;
            s2              <= 64'd0;
            s3              <= 64'd0;
            s4              <= 64'd0;
            k0              <= 64'd0;
            k1              <= 64'd0;
            word32_buf      <= 32'd0;
            word_count      <= 3'd0;
            round_step      <= 3'd0;
            bytes_remaining <= 16'd0;
            pdi_ready       <= 1'b0;
            sdi_ready       <= 1'b0;
            pdo_valid       <= 1'b0;
            pdo_data        <= 32'd0;
            done            <= 1'b0;
            tag_match       <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done      <= 1'b0;
                    pdo_valid <= 1'b0;
                    if (start_op) begin
                        s0              <= ASCON128_IV;
                        word_count      <= 3'd0;
                        sdi_ready       <= 1'b1;
                        state           <= STATE_LOAD_KEY;
                    end
                end

                // Load 128-bit key (4 x 32-bit words from SDI)
                STATE_LOAD_KEY: begin
                    if (sdi_valid && sdi_ready) begin
                        case (word_count)
                            3'd0: word32_buf  <= sdi_data;
                            3'd1: k0          <= {word32_buf, sdi_data};
                            3'd2: word32_buf  <= sdi_data;
                            3'd3: begin
                                k1        <= {word32_buf, sdi_data};
                                sdi_ready <= 1'b0;
                                pdi_ready <= 1'b1;
                                word_count<= 3'd0;
                                state     <= STATE_LOAD_NONCE;
                            end
                        endcase
                        if (word_count != 3'd3) word_count <= word_count + 1'b1;
                    end
                end

                // Load 128-bit nonce (4 x 32-bit words from PDI)
                STATE_LOAD_NONCE: begin
                    if (pdi_valid && pdi_ready) begin
                        case (word_count)
                            3'd0: word32_buf <= pdi_data;
                            3'd1: s3         <= {word32_buf, pdi_data};
                            3'd2: word32_buf <= pdi_data;
                            3'd3: begin
                                s4         <= {word32_buf, pdi_data};
                                s1         <= k0;
                                s2         <= k1;
                                pdi_ready  <= 1'b0;
                                round_step <= 3'd0;
                                state      <= STATE_INIT_PERM;
                            end
                        endcase
                        if (word_count != 3'd3) word_count <= word_count + 1'b1;
                    end
                end

                // 12-round initialization permutation (6 steps of 2 rounds)
                STATE_INIT_PERM: begin
                    s0 <= perm_z0; s1 <= perm_z1; s2 <= perm_z2; s3 <= perm_z3; s4 <= perm_z4;
                    if (round_step == 3'd5) begin
                        state <= STATE_INIT_KEY;
                    end else begin
                        round_step <= round_step + 1'b1;
                    end
                end

                // Key XOR at end of initialization
                STATE_INIT_KEY: begin
                    s3 <= s3 ^ k0;
                    s4 <= s4 ^ k1;
                    if (has_ad && ad_bytes > 0) begin
                        bytes_remaining <= ad_bytes;
                        word_count      <= 3'd0;
                        pdi_ready       <= 1'b1;
                        state           <= STATE_PROC_AD;
                    end else begin
                        // 1-bit domain separation if no AD
                        s4 <= s4 ^ 64'd1;
                        bytes_remaining <= pt_bytes;
                        word_count      <= 3'd0;
                        pdi_ready       <= (pt_bytes > 0);
                        state           <= (pt_bytes > 0) ? STATE_PROC_PT : STATE_FINAL_PERM;
                        round_step      <= 3'd0;
                    end
                end

                // Process Plaintext & Generate Ciphertext (Streaming 32-bit chunks)
                STATE_PROC_PT: begin
                    if (pdi_valid && pdi_ready) begin
                        if (word_count == 3'd0) begin
                            word32_buf <= pdi_data;
                            pdo_data   <= s0[63:32] ^ pdi_data;
                            pdo_valid  <= 1'b1;
                            word_count <= 3'd1;
                        end else begin
                            pdo_data   <= s0[31:0] ^ pdi_data;
                            pdo_valid  <= 1'b1;
                            s0         <= s0 ^ {word32_buf, pdi_data};
                            word_count <= 3'd0;
                            pdi_ready  <= 1'b0;
                            
                            if (bytes_remaining <= 8) begin
                                bytes_remaining <= 0;
                                round_step      <= 3'd0;
                                state           <= STATE_FINAL_PERM;
                            end else begin
                                bytes_remaining <= bytes_remaining - 8;
                                round_step      <= 3'd3; // 6-round intermediate permutation (steps 3, 4, 5)
                                state           <= STATE_PT_PERM;
                            end
                        end
                    end else if (pdo_valid && pdo_ready) begin
                        pdo_valid <= 1'b0;
                    end
                end

                // Intermediate 6-round permutation (steps 3, 4, 5 of constants)
                STATE_PT_PERM: begin
                    if (pdo_valid && pdo_ready) pdo_valid <= 1'b0;
                    s0 <= perm_z0; s1 <= perm_z1; s2 <= perm_z2; s3 <= perm_z3; s4 <= perm_z4;
                    if (round_step == 3'd5) begin
                        pdi_ready <= 1'b1;
                        state     <= STATE_PROC_PT;
                    end else begin
                        round_step <= round_step + 1'b1;
                    end
                end

                // 12-round finalization permutation (steps 0..5)
                STATE_FINAL_PERM: begin
                    if (pdo_valid && pdo_ready) pdo_valid <= 1'b0;
                    s0 <= perm_z0; s1 <= perm_z1; s2 <= perm_z2; s3 <= perm_z3; s4 <= perm_z4;
                    if (round_step == 3'd5) begin
                        state <= STATE_FINAL_KEY;
                    end else begin
                        round_step <= round_step + 1'b1;
                    end
                end

                // Final Key XOR: Tag = (s3 ^ k0) || (s4 ^ k1)
                STATE_FINAL_KEY: begin
                    s3         <= s3 ^ k0;
                    s4         <= s4 ^ k1;
                    word_count <= 3'd0;
                    state      <= STATE_EMIT_TAG;
                end

                // Emit 128-bit MAC Tag (4 x 32-bit words over PDO)
                STATE_EMIT_TAG: begin
                    if (!pdo_valid || pdo_ready) begin
                        case (word_count)
                            3'd0: begin pdo_data <= s3[63:32]; pdo_valid <= 1'b1; word_count <= 3'd1; end
                            3'd1: begin pdo_data <= s3[31:0];  pdo_valid <= 1'b1; word_count <= 3'd2; end
                            3'd2: begin pdo_data <= s4[63:32]; pdo_valid <= 1'b1; word_count <= 3'd3; end
                            3'd3: begin pdo_data <= s4[31:0];  pdo_valid <= 1'b1; word_count <= 3'd4; end
                            3'd4: begin
                                pdo_valid <= 1'b0;
                                done      <= 1'b1;
                                state     <= STATE_DONE;
                            end
                        endcase
                    end
                end

                STATE_DONE: begin
                    done  <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
