module pc_plus4(
    input [31:0] pc_current,
    output reg [31:0] pc_plus4
);
    always@(*)begin
        pc_plus4 = pc_current + 32'd4;
    end


endmodule
