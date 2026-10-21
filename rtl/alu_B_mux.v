module alu_B_mux(
    input [31:0] rdata2,
    input [31:0] imm,
    input alu_src_b,
    output reg [31:0] alu_B_operator
);
    always@(*)begin
        if(alu_src_b == 1'b1)begin
            alu_B_operator = imm;
        end
        else begin
            alu_B_operator = rdata2;
        end
    end

endmodule
