module WB_mux(
    input [31:0] alu_result,
    input [31:0] ldata,
    input [31:0] pc_plus4,
    input [31:0] imm,
    input [31:0] target_result,
    input [2:0] wb_sel,
    output reg [31:0] wb_data
);

    // Datapath interface conventions
    localparam [2:0] WB_ALU    = 3'b000;
    localparam [2:0] WB_LOAD   = 3'b001;
    localparam [2:0] WB_PC4    = 3'b010;
    localparam [2:0] WB_IMM    = 3'b011;
    localparam [2:0] WB_TARGET = 3'b100; // Raw target-adder result (PC + U-imm for AUIPC)

    always@(*)begin
        case(wb_sel)
            WB_ALU:wb_data = alu_result;
            WB_LOAD:wb_data = ldata;
            WB_PC4:wb_data = pc_plus4;
            WB_IMM:wb_data = imm;
            WB_TARGET:wb_data = target_result;
            default:wb_data = 32'b0;
        endcase
    end

endmodule
