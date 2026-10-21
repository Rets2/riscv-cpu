`timescale 1ns/1ps
`default_nettype none

// Full directed test for the project's 37 supported instruction kinds.
// Inputs: +IMEM=<program.hex> +EXPECT=<golden.trace>; optional +TRACE.
// Golden states are generated from ISA semantics, never from this DUT's output.
module tb_cpu_rv32i;
    localparam integer IMEM_DEPTH = 16384;
    localparam integer DMEM_DEPTH = 16384;
    localparam integer MEMORY_WORDS = 16;
    localparam integer MAX_STEPS = 512;
    localparam integer HEADER_WORDS = 4;
    // Each row: old PC, instruction, new PC, x0..x31, DMEM words 0..15.
    localparam integer ROW_WORDS = 3 + 32 + MEMORY_WORDS;
    localparam integer EXPECT_DEPTH = HEADER_WORDS + MAX_STEPS * ROW_WORDS;

    reg clk;
    reg rst_n;
    wire halted;
    wire [3:0] cpu_error;
    cpu_top dut (.clk(clk), .rst_n(rst_n), .halted(halted), .cpu_error(cpu_error));

    string imem_file;
    string expect_file;
    reg [31:0] expected [0:EXPECT_DEPTH-1];
    integer hits [0:36];
    integer branch_taken_hits [0:5];
    integer branch_not_taken_hits [0:5];
    integer image_words;
    integer expect_words;
    integer steps;
    integer step;
    integer row;
    integer index;
    integer kind;
    integer pass_count;
    integer fail_count;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Same strict raw-word format as the existing smoke loader.
    task automatic count_hex_words(
        input string path,
        input integer capacity,
        output integer count
    );
        integer fd;
        integer rc;
        integer ch;
        string token;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "Cannot open hex file: %s", path);
            count = 0;
            while (!$feof(fd)) begin
                rc = $fscanf(fd, "%s", token);
                if (rc == 1) begin
                    if (count >= capacity || token.len() != 8)
                        $fatal(1, "Invalid length/capacity at word %0d in %s", count, path);
                    for (ch = 0; ch < 8; ch = ch + 1) begin
                        if (!((token[ch] >= "0" && token[ch] <= "9") ||
                              (token[ch] >= "a" && token[ch] <= "f") ||
                              (token[ch] >= "A" && token[ch] <= "F")))
                            $fatal(1, "Invalid hex word %0d in %s: %s", count, path, token);
                    end
                    count = count + 1;
                end else if (!$feof(fd)) $fatal(1, "Cannot parse %s", path);
            end
            $fclose(fd);
            if (count == 0) $fatal(1, "Empty hex file: %s", path);
        end
    endtask

    task automatic check_word(
        input string name,
        input [31:0] actual,
        input [31:0] wanted
    );
        begin
            if (actual !== wanted) begin
                fail_count = fail_count + 1;
                $display("[FAIL] step=%0d %s expected=%08h actual=%08h time=%0t",
                         step + 1, name, wanted, actual, $time);
            end else pass_count = pass_count + 1;
        end
    endtask

    // Only used for coverage; this does not calculate expected CPU results.
    function automatic integer instruction_kind(input [31:0] word);
        begin
            instruction_kind = -1;
            case (word[6:0])
                7'h33: case ({word[31:25], word[14:12]})
                    10'b0000000_000: instruction_kind = 0;
                    10'b0100000_000: instruction_kind = 1;
                    10'b0000000_001: instruction_kind = 2;
                    10'b0000000_010: instruction_kind = 3;
                    10'b0000000_011: instruction_kind = 4;
                    10'b0000000_100: instruction_kind = 5;
                    10'b0000000_101: instruction_kind = 6;
                    10'b0100000_101: instruction_kind = 7;
                    10'b0000000_110: instruction_kind = 8;
                    10'b0000000_111: instruction_kind = 9;
                    default: instruction_kind = -1;
                endcase
                7'h13: case (word[14:12])
                    0: instruction_kind = 10;
                    2: instruction_kind = 11;
                    3: instruction_kind = 12;
                    4: instruction_kind = 13;
                    6: instruction_kind = 14;
                    7: instruction_kind = 15;
                    1: if (word[31:25] == 0) instruction_kind = 16;
                    5: begin
                        if (word[31:25] == 0) instruction_kind = 17;
                        else if (word[31:25] == 7'h20) instruction_kind = 18;
                    end
                    default: instruction_kind = -1;
                endcase
                7'h03: case (word[14:12])
                    0: instruction_kind = 19;
                    1: instruction_kind = 20;
                    2: instruction_kind = 21;
                    4: instruction_kind = 22;
                    5: instruction_kind = 23;
                    default: instruction_kind = -1;
                endcase
                7'h23: case (word[14:12])
                    0: instruction_kind = 24;
                    1: instruction_kind = 25;
                    2: instruction_kind = 26;
                    default: instruction_kind = -1;
                endcase
                7'h63: case (word[14:12])
                    0: instruction_kind = 27;
                    1: instruction_kind = 28;
                    4: instruction_kind = 29;
                    5: instruction_kind = 30;
                    6: instruction_kind = 31;
                    7: instruction_kind = 32;
                    default: instruction_kind = -1;
                endcase
                7'h6f: instruction_kind = 33;
                7'h67: if (word[14:12] == 0) instruction_kind = 34;
                7'h37: instruction_kind = 35;
                7'h17: instruction_kind = 36;
                default: instruction_kind = -1;
            endcase
        end
    endfunction

    function automatic string instruction_name(input integer number);
        begin
            case (number)
                 0: instruction_name="ADD";    1: instruction_name="SUB";
                 2: instruction_name="SLL";    3: instruction_name="SLT";
                 4: instruction_name="SLTU";   5: instruction_name="XOR";
                 6: instruction_name="SRL";    7: instruction_name="SRA";
                 8: instruction_name="OR";     9: instruction_name="AND";
                10: instruction_name="ADDI";  11: instruction_name="SLTI";
                12: instruction_name="SLTIU"; 13: instruction_name="XORI";
                14: instruction_name="ORI";   15: instruction_name="ANDI";
                16: instruction_name="SLLI";  17: instruction_name="SRLI";
                18: instruction_name="SRAI";  19: instruction_name="LB";
                20: instruction_name="LH";    21: instruction_name="LW";
                22: instruction_name="LBU";   23: instruction_name="LHU";
                24: instruction_name="SB";    25: instruction_name="SH";
                26: instruction_name="SW";    27: instruction_name="BEQ";
                28: instruction_name="BNE";   29: instruction_name="BLT";
                30: instruction_name="BGE";   31: instruction_name="BLTU";
                32: instruction_name="BGEU";  33: instruction_name="JAL";
                34: instruction_name="JALR";  35: instruction_name="LUI";
                36: instruction_name="AUIPC";
                default: instruction_name="UNKNOWN";
            endcase
        end
    endfunction

    initial begin
        pass_count = 0;
        fail_count = 0;
        step = -1;
        rst_n = 1'b1;
        $timeformat(-9, 0, " ns", 10);
        for (index = 0; index < 37; index = index + 1) hits[index] = 0;
        for (index = 0; index < 6; index = index + 1) begin
            branch_taken_hits[index] = 0;
            branch_not_taken_hits[index] = 0;
        end
        if (!$value$plusargs("IMEM=%s", imem_file)) $fatal(1, "Missing +IMEM=<file>");
        if (!$value$plusargs("EXPECT=%s", expect_file)) $fatal(1, "Missing +EXPECT=<file>");

        #1 rst_n = 1'b0;
        count_hex_words(imem_file, IMEM_DEPTH, image_words);
        count_hex_words(expect_file, EXPECT_DEPTH, expect_words);
        $readmemh(imem_file, dut.u_inst_mem.mem, 0, image_words - 1);
        $readmemh(expect_file, expected, 0, expect_words - 1);
        if (expect_words < HEADER_WORDS) $fatal(1, "Incomplete trace header");
        check_word("trace magic", expected[0], 32'h52563332);
        check_word("trace version", expected[1], 32'd1);
        check_word("paired image words", expected[3], image_words);
        steps = expected[2];
        if (steps <= 0 || steps > MAX_STEPS) $fatal(1, "Invalid trace step count");
        check_word("trace length", expect_words, HEADER_WORDS + steps * ROW_WORDS);
        if (fail_count != 0) $fatal(1, "Invalid expected trace");

        // Test fixture only. The CPU's reset does NOT initialize DMEM.
        for (index = 0; index < DMEM_DEPTH; index = index + 1)
            dut.u_data_memory.mem[index] = 32'b0;
        $display("[RV32I] image_words=%0d expected_steps=%0d", image_words, steps);
        repeat (2) @(negedge clk);
        #1;
        check_word("reset PC", dut.pc_current, 0);
        check_word("reset halted", {31'b0, halted}, 0);
        check_word("reset error", {28'b0, cpu_error}, 0);
        for (index = 0; index < 32; index = index + 1)
            check_word($sformatf("reset x%0d", index), dut.u_regfile.registers[index], 0);
        if (fail_count != 0) $fatal(1, "CPU reset failed");
        rst_n = 1'b1;

        for (step = 0; step < steps; step = step + 1) begin
            row = HEADER_WORDS + step * ROW_WORDS;
            check_word("before PC", dut.pc_current, expected[row]);
            check_word("instruction", dut.inst, expected[row + 1]);
            if (fail_count != 0) $fatal(1, "Wrong fetch before step %0d", step + 1);
            kind = instruction_kind(dut.inst);
            if (kind < 0) $fatal(1, "Unsupported instruction in directed suite");

            @(posedge clk);
            #1;
            check_word("after PC", dut.pc_current, expected[row + 2]);
            check_word("halted", {31'b0, halted}, 0);
            check_word("cpu_error", {28'b0, cpu_error}, 0);
            for (index = 0; index < 32; index = index + 1)
                check_word($sformatf("x%0d", index), dut.u_regfile.registers[index], expected[row + 3 + index]);
            for (index = 0; index < MEMORY_WORDS; index = index + 1)
                check_word($sformatf("DMEM[%0d]", index), dut.u_data_memory.mem[index], expected[row + 35 + index]);
            if (fail_count != 0)
                $fatal(1, "RV32I failed at step=%0d PC=%08h instruction=%08h (%s)",
                       step + 1, expected[row], expected[row + 1], instruction_name(kind));

            hits[kind] = hits[kind] + 1;
            if (kind >= 27 && kind <= 32) begin
                if (expected[row + 2] != expected[row] + 4)
                    branch_taken_hits[kind - 27] = branch_taken_hits[kind - 27] + 1;
                else branch_not_taken_hits[kind - 27] = branch_not_taken_hits[kind - 27] + 1;
            end
            if ($test$plusargs("TRACE"))
                $display("[STEP] %0d PC=%08h inst=%08h %s next_PC=%08h",
                         step + 1, expected[row], expected[row + 1], instruction_name(kind), dut.pc_current);
        end

        // Detect unintended writes outside the 64-byte test data window, too.
        for (index = MEMORY_WORDS; index < DMEM_DEPTH; index = index + 1)
            check_word($sformatf("untouched DMEM[%0d]", index), dut.u_data_memory.mem[index], 0);
        for (index = 0; index < 37; index = index + 1) begin
            if (hits[index] == 0) $fatal(1, "Instruction not exercised: %s", instruction_name(index));
            $display("[COVER] %s hits=%0d", instruction_name(index), hits[index]);
        end
        for (index = 0; index < 6; index = index + 1) begin
            if (branch_taken_hits[index] == 0 || branch_not_taken_hits[index] == 0)
                $fatal(1, "Missing branch outcome: %s", instruction_name(index + 27));
            $display("[BRANCH] %s taken=%0d not_taken=%0d", instruction_name(index + 27),
                     branch_taken_hits[index], branch_not_taken_hits[index]);
        end
        $display("RV32I SUMMARY: INSTRUCTION_KINDS=37/37 STEPS=%0d CHECKS_PASS=%0d CHECKS_FAIL=%0d",
                 steps, pass_count, fail_count);
        if (fail_count != 0) $fatal(1, "Unexpected memory write");
        $display("ALL RV32I DIRECTED TESTS PASSED");
        $finish;
    end

    initial begin
        #6000;
        $fatal(1, "RV32I TIMEOUT: PC=%h halted=%b error=%h", dut.pc_current, halted, cpu_error);
    end
endmodule

`default_nettype wire
