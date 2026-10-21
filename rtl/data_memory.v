module data_memory(
    input clk,
    input rst_n,

    input [31:0] addr,
    input [31:0] sdata,

    input mem_write,
    input mem_read,
    input [1:0] mem_size,
    input load_unsigned,

    output reg [31:0] ldata,
    output reg align_error,
    output reg addr_error
);

    reg [31:0] raw_data;
    reg [31:0] selected_data;

    localparam [1:0] MEM_BYTE = 2'b00;
    localparam [1:0] MEM_HALF = 2'b01;
    localparam [1:0] MEM_WORD = 2'b10;

    reg [13:0] word_index;
    reg [3:0] byte_enable;
    reg [31:0] write_data;

    reg [31:0] mem [0:16383];

    wire mem_access;
    assign mem_access = mem_write || mem_read;

    integer i;

    always@(*)begin

        word_index  = addr[15:2];
        byte_enable = 4'b0000;
        write_data  = 32'b0;
        align_error = 1'b0;
        addr_error   = 1'b0;
        raw_data = 32'b0;
        selected_data = 32'b0;
        ldata = 32'b0;

        if(addr[31:16] != 16'h0001 && mem_access)begin
            addr_error = 1;
        end

        else if(mem_write && mem_read)begin
            addr_error = 1;
        end
        else begin
            addr_error = 0;

            //Load
            if(mem_read)begin
                raw_data = mem[word_index];
                case(mem_size) 

                    MEM_BYTE:begin
                        selected_data = raw_data >> 8*addr[1:0];

                        if(load_unsigned)begin
                            ldata = {24'b0, selected_data[7:0]};
                        end
                        else begin
                            ldata = {{24{selected_data[7]}}, selected_data[7:0]};
                        end

                    end
                    MEM_HALF:begin
                        if(addr[0] != 1'b0)begin
                            align_error = 1;
                        end
                        else begin
                            //selected_data = raw_data >> 16*addr[1];
                            selected_data = raw_data[addr[1]*16 +: 16];
                            if(load_unsigned)begin
                                ldata = {16'b0, selected_data[15:0]};
                            end
                            else begin
                                ldata = {{16{selected_data[15]}}, selected_data[15:0]};
                            end
                        end
                    end
                    MEM_WORD:begin
                        if(addr[1:0] != 2'b00)begin
                            align_error = 1;
                        end
                        else begin
                            ldata = raw_data;
                        end
                    end
                    default:begin
                        addr_error = 1;
                    end
                endcase
            end

            //Store
            if(mem_write)begin
                case(mem_size)

                    MEM_BYTE:begin
                        byte_enable = 4'b0001 << addr[1:0];
                        write_data = {24'b0, sdata[7:0]} << 8 * addr[1:0];
                        align_error = 0;
                    end

                    MEM_HALF:begin
                        if(addr[0] != 1'b0)begin
                            align_error = 1;
                        end
                        else begin
                            byte_enable = 4'b0011 << addr[1:0];
                            write_data = {16'b0, sdata[15:0]} << 16* addr[1];
                            align_error = 0;
                        end
                    end
                    MEM_WORD:begin
                        if(addr[1:0] != 2'b00)begin
                            align_error = 1;
                        end
                        else begin
                            byte_enable = 4'b1111;
                            write_data = sdata[31:0];
                            align_error = 0;
                        end
                    end

                    default:begin
                        addr_error = 1'b1;
                    end
                endcase
            end
        end
    end

    always @(posedge clk) begin

        if (rst_n && mem_write && !mem_read && !addr_error && !align_error) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (byte_enable[i]) begin
                    mem[word_index][i*8 +: 8] <= write_data[i*8 +: 8];
                end
            end

        end
    end

endmodule
