`timescale 1ns/1ps
`default_nettype none

// Smoke test for the three instructions currently initialized in inst_mem.v.
// This test observes internal state; it does not modify the DUT or its memories.
module tb_cpu_top;
    reg clk;
    reg rst_n;
    wire halted;
    wire [3:0] cpu_error;

    integer pass_count;
    integer fail_count;
    integer cycle;

    cpu_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .halted(halted),
        .cpu_error(cpu_error)
    );

    // 10 ns period: the CPU updates architectural state on each rising edge.
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Case inequality also treats any X/Z in the observed value as a failure.
    task automatic check_word(
        input string check_name,
        input [31:0] actual,
        input [31:0] expected
    );
        begin
            if (actual !== expected) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %s: expected=%08h actual=%08h time=%0t",
                         check_name, expected, actual, $time);
            end else begin
                pass_count = pass_count + 1;
            end
        end
    endtask

    // Check the complete register file to catch writes to unintended registers.
    // stage=0 denotes reset; subsequent stages denote executed clock cycles.
    task automatic check_state(
        input integer stage,
        input [31:0] expected_pc,
        input [31:0] expected_x1,
        input [31:0] expected_x2,
        input [31:0] expected_x3
    );
        integer index;
        reg [31:0] expected_value;
        begin
            check_word($sformatf("stage %0d PC", stage),
                       dut.pc_current, expected_pc);
            check_word($sformatf("stage %0d halted", stage),
                       {31'b0, halted}, 32'b0);
            check_word($sformatf("stage %0d cpu_error", stage),
                       {28'b0, cpu_error}, 32'b0);

            for (index = 0; index < 32; index = index + 1) begin
                case (index)
                    1: expected_value = expected_x1;
                    2: expected_value = expected_x2;
                    3: expected_value = expected_x3;
                    default: expected_value = 32'b0;
                endcase
                check_word($sformatf("stage %0d x%0d", stage, index),
                           dut.u_regfile.registers[index], expected_value);
            end

            $display("[STATE] stage=%0d PC=%08h x1=%0d x2=%0d x3=%0d halted=%b error=%h",
                     stage, dut.pc_current,
                     dut.u_regfile.registers[1],
                     dut.u_regfile.registers[2],
                     dut.u_regfile.registers[3], halted, cpu_error);
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 1'b1;
        $timeformat(-9, 0, " ns", 10);

        // Generate an explicit reset edge, hold through two clock cycles,
        // then check reset state and release reset away from a rising edge.
        #1 rst_n = 1'b0;
        repeat (2) @(negedge clk);
        #1;
        check_state(0, 32'h0000_0000, 32'd0, 32'd0, 32'd0);

        // Verify the test's program assumptions rather than silently testing
        // a different program after inst_mem.v has been changed.
        check_word("program[0]: addi x1,x0,5",
                   dut.u_inst_mem.mem[0], 32'h0050_0093);
        check_word("program[1]: addi x2,x0,10",
                   dut.u_inst_mem.mem[1], 32'h00a0_0113);
        check_word("program[2]: add x3,x1,x2",
                   dut.u_inst_mem.mem[2], 32'h0020_81b3);
        for (cycle = 3; cycle < 6; cycle = cycle + 1) begin
            check_word($sformatf("program[%0d]: NOP", cycle),
                       dut.u_inst_mem.mem[cycle], 32'h0000_0013);
        end
        rst_n = 1'b1;

        // Wait past the NBA update and combinational settling before sampling.
        @(posedge clk);
        #1;
        check_state(1, 32'h0000_0004, 32'd5, 32'd0, 32'd0);

        @(posedge clk);
        #1;
        check_state(2, 32'h0000_0008, 32'd5, 32'd10, 32'd0);

        @(posedge clk);
        #1;
        check_state(3, 32'h0000_000c, 32'd5, 32'd10, 32'd15);

        // NOP = addi x0,x0,0: PC advances and all registers retain their values.
        for (cycle = 4; cycle <= 6; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            check_state(cycle, cycle * 4, 32'd5, 32'd10, 32'd15);
        end

        $display("CPU SMOKE SUMMARY: CHECKS_PASS=%0d CHECKS_FAIL=%0d",
                 pass_count, fail_count);
        if (fail_count != 0)
            $fatal(1, "CPU smoke verification failed");

        $display("ALL CPU SMOKE TESTS PASSED");
        $finish;
    end

    // Independent watchdog: catches a test that never reaches its finish point.
    initial begin
        #1000;
        $fatal(1, "CPU smoke TIMEOUT: PC=%h halted=%b error=%h",
               dut.pc_current, halted, cpu_error);
    end
endmodule

`default_nettype wire
