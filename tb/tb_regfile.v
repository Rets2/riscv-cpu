`timescale 1ns/1ps

module tb_regfile;

    reg clk;
    reg rst_n;
    reg we;
    reg [4:0] waddr;
    reg [31:0] wdata;
    reg [4:0] raddr1;
    wire [31:0] rdata1;
    reg [4:0] raddr2;
    wire [31:0] rdata2;

    regfile dut_regfile(
        .clk(clk),
        .rst_n(rst_n),
        .we(we),
        .waddr(waddr),
        .wdata(wdata),
        .raddr1(raddr1),
        .rdata1(rdata1),
        .raddr2(raddr2),
        .rdata2(rdata2)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        we = 0;
        

        forever begin
            #10 clk = ~clk;
        end
    end
    
    initial begin
        //复位测试
        @(negedge clk);
        rst_n = 0;
        #2;
        rst_n = 1;
        raddr1 = 11;
        #2;
        if (rdata1 == 32'h0)
            $display("复位成功");
        else
            $display("复位失败");

        //写入并读取
        @(negedge clk);
        waddr = 11;
        wdata = 32'h11111111;
        raddr1 = 11;
        we = 1;
        @(posedge clk);
        #2;
        we = 0;

        @(negedge clk);
        waddr = 12;
        wdata = 32'h12345678;
        raddr2 = 12;
        we = 1;
        @(posedge clk);
        #2;
        we = 0;
        #2;
        if (rdata1 == 32'h11111111 && rdata2 == 32'h12345678)
            $display("写入并读取成功");
        else
            $display("写入并读取失败");

        //we = 0 时写入
        @(negedge clk);
        waddr = 12;
        wdata = 32'h87654321;
        raddr2 = 12;
        @(posedge clk);
        #2;
        if (rdata2 !== 32'h12345678)
            $display("we=0时仍写入");
        else
            $display("we=0时不写入");

        //x0 register
        @(negedge clk);
        raddr1 = 0;
        #2;
        if (rdata1 == 32'h0)
            $display("x0寄存器的值为0");
        else
            $display("x0寄存器的值不为0");
        #2
        waddr = 0;
        wdata = 32'h87654321;
        raddr1 = 0;
        we = 1;
        @(posedge clk);
        #2;
        we = 0;
        #2;
        if (rdata1 == 32'h0)
            $display("x0寄存器的值未被修改");
        else
            $display("x0寄存器的值被修改");

        //x31 register
        @(negedge clk);
        waddr = 31;
        wdata = 32'h87654321;
        raddr1 = 31;
        we = 1;
        @(posedge clk);
        #2;
        we = 0;
        #2;
        if (rdata1 == 32'h87654321)
            $display("x31寄存器的值被正确写入并读取");
        else
            $display("x31寄存器的值未被正确写入并读取");

        $finish;

    end



endmodule

