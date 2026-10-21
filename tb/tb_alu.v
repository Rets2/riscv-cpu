`timescale 1ns/1ps

module tb_alu;
    // The testbench drives inputs; the DUT drives the output.
    reg  [31:0] alu_a;
    reg  [31:0] alu_b;
    reg  [3:0]  alu_op;
    wire [31:0] alu_result;

    integer pass_count;
    integer fail_count;

    // Must match the operation encodings in alu.v.
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    alu dut_alu (
        .alu_a(alu_a),
        .alu_b(alu_b),
        .alu_op(alu_op),
        .alu_result(alu_result)
    );

    // Apply inputs, wait for combinational settling, and check result.
    task check_case;
        input [8*32-1:0] case_name;
        input [3:0] op;
        input [31:0] a;
        input [31:0] b;
        input [31:0] expected;
        begin
            alu_a  = a;
            alu_b  = b;
            alu_op = op;
            #2;
            if (alu_result !== expected) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s: op=%h A=%h B=%h expected=%h actual=%h",
                         case_name, op, a, b, expected, alu_result);
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", case_name);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        alu_a  = 32'd0;
        alu_b  = 32'd0;
        alu_op = ALU_ADD;
        #2;

        // Basic functionality and arithmetic wraparound (mod 2^32).
        check_case("ADD_normal",       ALU_ADD,  32'h1010_1010, 32'h0101_0101, 32'h1111_1111);
        check_case("ADD_wrap",         ALU_ADD,  32'hFFFF_FFFF, 32'd1,        32'd0);
        check_case("ADD_signed_edge",  ALU_ADD,  32'h7FFF_FFFF, 32'd1,        32'h8000_0000);
        check_case("SUB_normal",       ALU_SUB,  32'd10,       32'd3,        32'd7);
        check_case("SUB_wrap",         ALU_SUB,  32'd0,        32'd1,        32'hFFFF_FFFF);

        check_case("AND_normal",       ALU_AND,  32'h0000_00CC, 32'h0000_00AA, 32'h0000_0088);
        check_case("OR_normal",        ALU_OR,   32'h0000_00CC, 32'h0000_00AA, 32'h0000_00EE);
        check_case("XOR_normal",       ALU_XOR,  32'h0000_00CC, 32'h0000_00AA, 32'h0000_0066);

        // RV32I register shifts use only B[4:0].
        check_case("SLL_normal",       ALU_SLL,  32'd1,        32'd4,        32'h0000_0010);
        check_case("SLL_shift31",      ALU_SLL,  32'd1,        32'd31,       32'h8000_0000);
        check_case("SLL_shift32_mask", ALU_SLL,  32'd1,        32'd32,       32'd1);
        check_case("SLL_shift33_mask", ALU_SLL,  32'd1,        32'd33,       32'd2);
        check_case("SRL_highbit",      ALU_SRL,  32'h8000_0000, 32'd1,        32'h4000_0000);
        check_case("SRL_shift31",      ALU_SRL,  32'h8000_0000, 32'd31,       32'd1);
        check_case("SRL_shift32_mask", ALU_SRL,  32'h8000_0000, 32'd32,       32'h8000_0000);

        // Arithmetic shift right preserves the sign bit.
        check_case("SRA_negative",     ALU_SRA,  32'h8000_0000, 32'd1,        32'hC000_0000);
        check_case("SRA_minus_one",    ALU_SRA,  32'hFFFF_FFFF, 32'd31,       32'hFFFF_FFFF);
        check_case("SRA_positive",     ALU_SRA,  32'h7FFF_FFFF, 32'd1,        32'h3FFF_FFFF);
        check_case("SRA_shift32_mask", ALU_SRA,  32'h8000_0000, 32'd32,       32'h8000_0000);

        // Signed vs unsigned comparisons must differ on these inputs.
        check_case("SLT_neg_less",     ALU_SLT,  32'hFFFF_FFFF, 32'd1,        32'd1);
        check_case("SLT_pos_vs_neg",   ALU_SLT,  32'h7FFF_FFFF, 32'h8000_0000, 32'd0);
        check_case("SLT_equal",        ALU_SLT,  32'h8000_0000, 32'h8000_0000, 32'd0);
        check_case("SLTU_big_vs_one",  ALU_SLTU, 32'hFFFF_FFFF, 32'd1,        32'd0);
        check_case("SLTU_one_vs_big",  ALU_SLTU, 32'd1,        32'hFFFF_FFFF, 32'd1);
        check_case("SLTU_equal",       ALU_SLTU, 32'd0,        32'd0,        32'd0);

        // Our ALU specification defines unsupported opcodes as zero.
        check_case("INVALID_opcode",   4'b1111,  32'h1234_5678, 32'h8765_4321, 32'd0);

        $display("-------------------------------------------");
        $display("ALU Test Summary: PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL ALU TESTS PASSED");
        else
            $display("ALU TESTS FAILED");
        $finish;
    end
endmodule
