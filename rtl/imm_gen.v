module imm_gen(
    input wire [31:0] inst,
    input wire [2:0] imm_sel,
    output reg [31:0] imm
);
    localparam I_Type = 3'b000;
    localparam S_Type = 3'b001;
    localparam B_Type = 3'b010;
    localparam U_Type = 3'b011;
    localparam J_Type = 3'b100;
    //其他先不写

    always@(*) begin
        case(imm_sel)
        I_Type:imm = {{20{inst[31]}}, inst[31:20]};
        S_Type:imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        B_Type:imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
        U_Type:imm = {inst[31:12], 12'b0};
        J_Type:imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
        default:imm = 32'b0;
        endcase
    end

endmodule
