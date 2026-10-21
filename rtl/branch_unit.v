module branch_unit(
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [2:0]  branch_type,
    output reg         branch_taken
);

    localparam NONE = 3'b000;
    localparam BEQ = 3'b001;
    localparam BNE = 3'b010;
    localparam BLT = 3'b011;
    localparam BGE = 3'b100;
    localparam BLTU = 3'b101;
    localparam BGEU = 3'b110;
    localparam Reserved = 3'b111;

    always@(*)begin
        branch_taken = 0;
        case(branch_type)
            BEQ:if(rs1_data == rs2_data)branch_taken = 1;
            BNE:if(rs1_data != rs2_data)branch_taken = 1;
            BLT:if($signed(rs1_data) < $signed(rs2_data))branch_taken = 1;
            BGE:if($signed(rs1_data) >= $signed(rs2_data))branch_taken = 1;
            BLTU:if(rs1_data < rs2_data)branch_taken = 1;
            BGEU:if(rs1_data >= rs2_data)branch_taken = 1;
            default:begin
            end
        endcase
    end


endmodule
