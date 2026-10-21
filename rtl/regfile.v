module regfile(
    input clk,
    input rst_n,
    input we,
    input [4:0] waddr,
    input [31:0] wdata,
    input [4:0] raddr1,
    output reg [31:0] rdata1,
    input [4:0] raddr2,
    output reg [31:0] rdata2
);

    reg [31:0] registers [31:0];
    //读出的组合逻辑
    always @(*)begin
        if(raddr1 == 0)begin
            rdata1 = 0;
        end
        else begin
            rdata1 = registers[raddr1];
        end

        if(raddr2 == 0)begin
            rdata2 = 0;
        end
        else begin
            rdata2 = registers[raddr2];
        end
    end
    //写入的时序逻辑
    integer i;
    wire wr_fire;
    assign wr_fire = we && (waddr != 5'd0);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            for(i = 0 ; i <= 31 ; i = i + 1)begin
                registers[i] <= 0;
            end
        end
        else begin
            if(wr_fire)begin
                registers[waddr] <= wdata;
            end
        end
    end



endmodule
