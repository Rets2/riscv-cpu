module target_adder(
    input [31:0] target_A_operator,
    input [31:0] imm,
    output reg [31:0] target_result
);
    always@(*)begin
        target_result = target_A_operator + imm;
    end

endmodule
