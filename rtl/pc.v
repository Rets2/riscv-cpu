module pc(
    input clk,
    input rst_n,
    input pc_en,
    input [31:0] pc_next,
    output reg [31:0] pc_current
);

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            pc_current <= 32'b0;
        end
        else begin
            if(pc_en)begin
                pc_current <= pc_next;
            end
        end
    end

endmodule
