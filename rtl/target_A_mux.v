module target_A_mux(
    input [31:0] pc_current,
    input [31:0] rdata1,
    input [1:0] jump_type,
    output reg [31:0] target_A_operator
);

    localparam [1:0] JMP_NONE = 2'b00;
    localparam [1:0] JMP_JAL  = 2'b01;
    localparam [1:0] JMP_JALR = 2'b10;

    always@(*)begin
        if(jump_type == JMP_JALR)begin
            target_A_operator = rdata1;
        end
        else begin
            target_A_operator = pc_current;
        end
    end

endmodule
