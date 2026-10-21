module inst_mem(
    input [31:0] addr,
    output reg [31:0] inst,
    output reg addr_error
);

    reg [31:0] mem [0:16383];

    integer i;

    initial begin
        //NOP
        for (i = 0; i < 16384; i = i + 1)
            mem[i] = 32'h00000013;

        mem[0] = 32'h00500093;  // addi x1, x0, 5
        mem[1] = 32'h00A00113;  // addi x2, x0, 10
        mem[2] = 32'h002081B3;  // add  x3, x1, x2
    end
    
    always@(*)begin
        if ((addr[1:0] != 2'b00) || (addr[31:16] != 16'h0000)) begin
            addr_error = 1;
            inst = 32'hFFFFFFFF;//必须给一个指令，否则引入Latch
        end
        else begin
            addr_error = 0;
            inst = mem [addr[15:2]];
        end
    end

endmodule
