`timescale 1ns/1ps

// Verilog-2001 self-checking testbench for imm_gen.
// Expected values are fixed ISA-derived constants, not DUT expressions.
module tb_imm_gen;
    reg  [31:0] inst;
    reg  [2:0]  imm_sel;
    wire [31:0] imm;

    integer pass_count;
    integer fail_count;

    localparam [2:0] I_Type = 3'b000;
    localparam [2:0] S_Type = 3'b001;
    localparam [2:0] B_Type = 3'b010;
    localparam [2:0] U_Type = 3'b011;
    localparam [2:0] J_Type = 3'b100;

    imm_gen dut_imm_gen (
        .inst(inst),
        .imm_sel(imm_sel),
        .imm(imm)
    );

    task check_case;
        input [8*32-1:0] case_name;
        input [31:0] instruction;
        input [2:0] sel;
        input [31:0] expected;
        begin
            inst    = instruction;
            imm_sel = sel;
            #2; // allow combinational logic to settle
            if (imm !== expected) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s: inst=%h sel=%b expected=%h actual=%h",
                         case_name, inst, imm_sel, expected, imm);
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", case_name);
            end
        end
    endtask

    initial begin
        inst       = 32'd0;
        imm_sel    = I_Type;
        pass_count = 0;
        fail_count = 0;
        #2;

        // I tests
        check_case("I_negative_original", 32'hA5203654, I_Type, 32'hFFFFFA52);
        check_case("I_positive_original", 32'h7F4D99A2, I_Type, 32'h000007F4);

        //我自己写了上面两个cases
        //B-Type One-Hot-Test
        
        check_case("I_zero", 32'h00000013, I_Type, 32'h00000000);
        check_case("I_max_positive", 32'h7FF00013, I_Type, 32'h000007FF);
        check_case("I_min_negative", 32'h80000013, I_Type, 32'hFFFFF800);
        check_case("I_minus_one", 32'hFFF00013, I_Type, 32'hFFFFFFFF);

        // S tests
        check_case("S_zero", 32'h00000023, S_Type, 32'h00000000);
        check_case("S_positive_eight", 32'h00000423, S_Type, 32'h00000008);
        check_case("S_low_field_bit0", 32'h000000A3, S_Type, 32'h00000001);
        check_case("S_upper_field_bit5", 32'h02000023, S_Type, 32'h00000020);
        check_case("S_max_positive", 32'h7E000FA3, S_Type, 32'h000007FF);
        check_case("S_min_negative", 32'h80000023, S_Type, 32'hFFFFF800);
        check_case("S_minus_one", 32'hFE000FA3, S_Type, 32'hFFFFFFFF);

        // B tests
        check_case("B_zero", 32'h00000063, B_Type, 32'h00000000);
        check_case("B_inst7_only_valid_beq", 32'h000000E3, B_Type, 32'h00000800);
        check_case("B_inst8_only_valid_beq", 32'h00000163, B_Type, 32'h00000002);
        check_case("B_offset_plus_32", 32'h02000063, B_Type, 32'h00000020);
        check_case("B_max_positive", 32'h7E000FE3, B_Type, 32'h00000FFE);
        check_case("B_min_negative", 32'h80000063, B_Type, 32'hFFFFF000);
        check_case("B_minus_two", 32'hFE000FE3, B_Type, 32'hFFFFFFFE);

        // U tests
        check_case("U_zero", 32'h00000037, U_Type, 32'h00000000);
        check_case("U_small_high", 32'h00001037, U_Type, 32'h00001000);
        check_case("U_mid_pattern", 32'h12345037, U_Type, 32'h12345000);
        check_case("U_high_sign_bit", 32'h80000037, U_Type, 32'h80000000);
        check_case("U_all_high_ones", 32'hFFFFF037, U_Type, 32'hFFFFF000);
        check_case("U_random_pattern", 32'hDEADB037, U_Type, 32'hDEADB000);

        // J tests
        check_case("J_zero", 32'h0000006F, J_Type, 32'h00000000);
        check_case("J_offset_plus_two", 32'h0020006F, J_Type, 32'h00000002);
        check_case("J_inst20_to_imm11", 32'h0010006F, J_Type, 32'h00000800);
        check_case("J_inst12_to_imm12", 32'h0000106F, J_Type, 32'h00001000);
        check_case("J_inst16_to_imm16", 32'h0001006F, J_Type, 32'h00010000);
        check_case("J_max_positive", 32'h7FFFF06F, J_Type, 32'h000FFFFE);
        check_case("J_min_negative", 32'h8000006F, J_Type, 32'hFFF00000);
        check_case("J_minus_two", 32'hFFFFF06F, J_Type, 32'hFFFFFFFE);

        // Switch tests
        check_case("Switch_same_inst_I", 32'h00000080, I_Type, 32'h00000000);
        check_case("Switch_same_inst_S", 32'h00000080, S_Type, 32'h00000001);
        check_case("Switch_same_inst_B", 32'h00000080, B_Type, 32'h00000800);
        check_case("Switch_same_inst_U", 32'h00000080, U_Type, 32'h00000000);
        check_case("Switch_same_inst_J", 32'h00000080, J_Type, 32'h00000000);
        // Invalid tests
        check_case("Invalid_sel_5", 32'hFFFFFFFF, 3'b101, 32'h00000000);
        check_case("Invalid_sel_6", 32'hFFFFFFFF, 3'b110, 32'h00000000);
        check_case("Invalid_sel_7", 32'hFFFFFFFF, 3'b111, 32'h00000000);

        // 4-state selector behavior under Verilog case/default
        check_case("Unknown_sel_X", 32'hFFFFFFFF, 3'bx00, 32'h00000000);
        check_case("Unknown_sel_Z", 32'hFFFFFFFF, 3'bzzz, 32'h00000000);

        $display("-----------------------------------------------------------");
        $display("IMM_GEN TEST SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("ALL IMM_GEN TESTS PASSED");
        end else begin
            $display("IMM_GEN TESTS FAILED");
`ifdef USE_SV_FATAL
            // Optional: compile as SystemVerilog (+define+USE_SV_FATAL)
            // to return nonzero status in automated regressions.
            $fatal(1, "imm_gen verification failed");
`endif
        end
        $finish;
    end
endmodule
