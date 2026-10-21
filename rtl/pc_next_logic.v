module pc_next_logic(
    input [31:0] pc_plus4,
    input [31:0] target_result,
    input branch_taken,
    input [1:0] jump_type,
    output reg [31:0] pc_next
);

    localparam [1:0] JMP_NONE = 2'b00;
    localparam [1:0] JMP_JAL  = 2'b01;
    localparam [1:0] JMP_JALR = 2'b10;

    always@(*)begin
        pc_next = pc_plus4;
        case(jump_type)
            JMP_NONE:begin
                case(branch_taken)
                    1'b0:pc_next = pc_plus4;
                    1'b1:pc_next = target_result;
                endcase
            end
            JMP_JAL:begin
                pc_next = target_result;
            end
            JMP_JALR:begin
                pc_next = target_result & ~32'b1;
            end
            default:begin
            end
        endcase
    end

endmodule