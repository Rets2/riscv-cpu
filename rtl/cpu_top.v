module cpu_top(
    input clk,
    input rst_n,
    output reg halted,
    output reg [3:0] cpu_error
);
    //pc
    //
    wire [31:0] pc_current;
    wire [31:0] pc_next;
    //inst_mem
    wire [31:0] inst;
    wire imem_addr_error;
    //decoder
    wire [3:0]  alu_op;
    wire alu_src_b;
    wire [2:0]  imm_sel;
    wire reg_write;
    wire [2:0]  wb_sel;
    wire mem_write;
    wire mem_read;
    wire [1:0]  mem_size;
    wire load_unsigned;
    wire [2:0]  branch_type;
    wire [1:0]  jump_type;
    wire illegal_inst;
    //regfile
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    //alu
    wire [31:0] alu_result;
    //alu_B_mux
    wire [31:0] alu_B_operator;
    //imm_gen
    wire [31:0] imm;
    //WB_mux
    wire [31:0] wb_data;
    //DMEM
    wire [31:0] ldata;
    wire dmem_align_error;
    wire dmem_addr_error;
    //pc_plus4
    wire [31:0] pc_plus4;
    //target_adder
    wire [31:0] target_result;
    //target_A_mux
    wire [31:0] target_A_operator;
    //branch_unit
    wire branch_taken;
    //pc_next_Logic

    //cpu system
    //0.cpu本身状态标识
    //1.系统级模块集成接线
    //2.全局的异常状态标志及处理
    //3.与系统其他ip的接口协调

    //对于第二点，需要考虑：哪些模块会出现异常/错误信号？
    //同时需要考虑异常的两个概念
    //一是有效异常
    //二是异常优先级

    reg fault_flag;
    reg [3:0] fault_code;

    //模块实例化
    //取指
    pc u_pc(
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc_en(pc_en),
        .pc_current(pc_current)
    );

    inst_mem u_inst_mem(
        .addr(pc_current),
        .inst(inst),
        .addr_error(imem_addr_error)
    );

    decoder u_decoder(
        .inst(inst),
        .alu_op(alu_op),
        .alu_src_b(alu_src_b),
        .imm_sel(imm_sel),
        .reg_write(reg_write),
        .wb_sel(wb_sel),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .mem_size(mem_size),
        .load_unsigned(load_unsigned),
        .branch_type(branch_type),
        .jump_type(jump_type),
        .illegal_inst(illegal_inst)
    );

    imm_gen u_imm_gen(
        .inst(inst),
        .imm_sel(imm_sel),
        .imm(imm)

    );
    //rd inst[11:7]
    //rs1 inst[19:15]
    //rs2 inst[24:20]
    regfile u_regfile(
        .clk(clk),
        .rst_n(rst_n),
        .we(regfile_en),
        .waddr(inst[11:7]),
        .wdata(wb_data),
        .raddr1(inst[19:15]),
        .rdata1(rs1_data),
        .raddr2(inst[24:20]),
        .rdata2(rs2_data)
    );

    alu_B_mux u_alu_B_mux(
        .rs2_data(rs2_data),
        .imm(imm),
        .alu_src_b(alu_src_b),
        .alu_B_operator(alu_B_operator)
    );

    alu u_alu(
        .alu_a(rs1_data),
        .alu_b(alu_B_operator),
        .alu_op(alu_op),
        .alu_result(alu_result)
    );

    WB_mux u_WB_mux(
        .alu_result(alu_result),
        .ldata(ldata),
        .pc_plus4(pc_plus4),
        .imm(imm),
        .target_result(target_result),
        .wb_sel(wb_sel),
        .wb_data(wb_data)
    );

    branch_unit u_branch_unit(
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .branch_type(branch_type),
        .branch_taken(branch_taken)
    );

    pc_next_logic u_pc_next_logic(
        .pc_plus4(pc_plus4),
        .target_result(target_result),
        .branch_taken(branch_taken),
        .jump_type(jump_type),
        .pc_next(pc_next)
    );

    pc_plus4 u_pc_plus4(
        .pc_current(pc_current),
        .pc_plus4(pc_plus4)
    );

    target_adder u_target_adder(
        .target_A_operator(target_A_operator),
        .imm(imm),
        .target_result(target_result)
    );

    target_A_mux u_target_A_mux(
        .pc_current(pc_current),
        .rdata1(rs1_data),
        .jump_type(jump_type),
        .target_A_operator(target_A_operator)
    );

    data_memory u_data_memory(
        .clk(clk),
        .rst_n(rst_n),
        .addr(alu_result),
        .sdata(rs2_data),
        .mem_write(dmem_write_en),
        .mem_read(dmem_read_en),
        .mem_size(mem_size),
        .load_unsigned(load_unsigned),
        .ldata(ldata),
        .align_error(dmem_align_error),
        .addr_error(dmem_addr_error)
    );

    //异常处理逻辑

    // CPU Error Codes
    localparam [3:0]
        CPU_ERR_NONE         = 4'h0,
        CPU_ERR_FETCH        = 4'h1,
        CPU_ERR_ILLEGAL      = 4'h2,
        CPU_ERR_MEM_ADDR     = 4'h3,
        CPU_ERR_MEM_ALIGN    = 4'h4,
        CPU_ERR_TARGET_ALIGN = 4'h5;

    // CPU Exception Signals
    wire fault_fetch;
    wire fault_illegal;
    wire fault_mem_addr;
    wire fault_mem_align;
    wire fault_target_align;

    assign fault_fetch        = imem_addr_error;
    assign fault_illegal      = illegal_inst;
    assign fault_mem_addr     = dmem_addr_error;
    assign fault_mem_align    = dmem_align_error;
    assign fault_target_align = (branch_taken || jump_type) && (pc_next[1:0] != 2'b00);

    always@(*)begin
        case(1'b1)
            fault_fetch:
            begin
                fault_flag = 1'b1;
                fault_code = CPU_ERR_FETCH;
            end
            fault_illegal:
            begin

                fault_flag = 1'b1;
                fault_code = CPU_ERR_ILLEGAL;
            end
            fault_mem_addr:
            begin

                fault_flag = 1'b1;
                fault_code = CPU_ERR_MEM_ADDR;
            end
            fault_mem_align:
            begin

                fault_flag = 1'b1;
                fault_code = CPU_ERR_MEM_ALIGN;
            end
            fault_target_align:
            begin

                fault_flag = 1'b1;
                fault_code = CPU_ERR_TARGET_ALIGN;
            end
            default:
            begin
                fault_flag = 1'b0;
                fault_code = CPU_ERR_NONE;
            end
        endcase
    end
    //全局停机的实现
    //PC、RegFile、Data Memory
    wire execute_enable;
    assign execute_enable = !fault_flag && !halted;

    wire pc_en;
    wire regfile_en;
    wire dmem_write_en;
    wire dmem_read_en;

    assign pc_en = execute_enable;
    assign regfile_en = execute_enable && reg_write;
    assign dmem_write_en = mem_write && !halted
                        && !imem_addr_error && !illegal_inst;

    assign dmem_read_en  = mem_read && !halted
                        && !imem_addr_error && !illegal_inst;

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            halted <= 1'b0;
            cpu_error <= 4'b0000;
        end
        else begin
            if(fault_flag && !halted)begin
                halted <= 1'b1;
                cpu_error <= fault_code;
            end
        end
    end

endmodule
