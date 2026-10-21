`default_nettype none

// RV32I single-cycle CPU instruction decoder (37 regular instructions).

// Not implemented in this version: FENCE, ECALL, EBREAK, CSR/other extensions.

// No architectural trap handling is implemented here.

// ============================================================================
// Decoder - RV32I 单周期 CPU 指令译码器 (37 条常规指令)
//
// 输入  : inst[31:0]，来自 Instruction Memory 的当前指令
// 输出  : 纯组合控制信号，分别送至 ALU、ImmGen、RegFile、访存逻辑、
//         Branch Unit、PC_next / 目标加法器输入选择、WriteBack MUX。
//
// 重要约定：
// 1. Decoder 不直接输出 rs1/rs2/rd 地址，CPU Top 直接取 inst[19:15]、
//    inst[24:20]、inst[11:7] 连接寄存器堆。
// 2. Decoder 仅判断指令编码是否合法；地址越界/未对齐由其他模块检查。
// 3. 非法指令使 illegal_inst=1，默认禁止寄存器及存储器写入等副作用。
//    CPU Top 仍须处理停机、访存错误和全局写使能抑制。
// 4. 这是信号注释版：保持原译码逻辑、各编码和值不变；尚未功能验证。
// ============================================================================
module decoder (

    // 当前 32-bit 指令；由 Instruction Memory 输出

    input  wire [31:0] inst,
    // ALU 运算选择：ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU；连接 ALU.alu_op
    output reg  [3:0]  alu_op,
    // ALU B 端 MUX：0=RegFile.rs2_data，1=ImmGen.imm；连接 ALU B MUX
    output reg         alu_src_b,
    // 立即数格式选择：I/S/B/U/J；连接 ImmGen.imm_sel
    output reg  [2:0]  imm_sel,
    // 寄存器写回请求：1=本条指令写 rd；接 RegFile.we（顶层还需错误/停机门控）
    output reg         reg_write,
    // WriteBack MUX 选择：ALU/LOAD/PC+4/IMM/TARGET；连接写回数据选择器
    output reg  [2:0]  wb_sel,
    // Store 请求：1=将 rs2 的部分/全部数据写入 RAM/MMIO；顶层需进行地址译码
    output reg         mem_write,
    // Load 请求：1=从 RAM/MMIO 读取并送回 rd；顶层需进行地址译码
    output reg         mem_read,
    // 访存宽度：00=Byte(8b)、01=Half(16b)、10=Word(32b)，11=保留
    output reg  [1:0]  mem_size,
    // Load 扩展方式：0=符号扩展(LB/LH)，1=零扩展(LBU/LHU)；LW 不受影响
    output reg         load_unsigned,
    // 条件分支种类：NONE/BEQ/BNE/BLT/BGE/BLTU/BGEU；接 Branch Unit
    output reg  [2:0]  branch_type,
    // 跳转控制：NONE/JAL/JALR；接 PC_next，并供目标加法器输入选择
    output reg  [1:0]  jump_type,
    // 非法/未支持指令标志：1=非法；顶层应禁止状态更新并决定如何停机
    output reg         illegal_inst
);

    wire [6:0] opcode;

    wire [2:0] funct3;

    wire [6:0] funct7;

    assign opcode = inst[6:0];

    assign funct3 = inst[14:12];

    assign funct7 = inst[31:25];

    // opcode[6:0] 指令大类，由 RISC-V 编码规定；不同 OP_* 进入不同译码分支
    // Opcode fields

    localparam [6:0] OP_LOAD   = 7'b0000011;

    localparam [6:0] OP_OPIMM  = 7'b0010011;

    localparam [6:0] OP_AUIPC  = 7'b0010111;

    localparam [6:0] OP_STORE  = 7'b0100011;

    localparam [6:0] OP_OP     = 7'b0110011;

    localparam [6:0] OP_LUI    = 7'b0110111;

    localparam [6:0] OP_BRANCH = 7'b1100011;

    localparam [6:0] OP_JALR   = 7'b1100111;

    localparam [6:0] OP_JAL    = 7'b1101111;

    // alu_op[3:0]：要与 ALU 模块的运算编码严格一致。
    // 例：ADD=0000、SUB=0001；Decoder 只生成控制码，不执行实际运算。
    // Must match existing ALU alu_op encoding

    localparam [3:0] ALU_ADD  = 4'b0000;

    localparam [3:0] ALU_SUB  = 4'b0001;

    localparam [3:0] ALU_AND  = 4'b0010;

    localparam [3:0] ALU_OR   = 4'b0011;

    localparam [3:0] ALU_XOR  = 4'b0100;

    localparam [3:0] ALU_SLL  = 4'b0101;

    localparam [3:0] ALU_SRL  = 4'b0110;

    localparam [3:0] ALU_SRA  = 4'b0111;

    localparam [3:0] ALU_SLT  = 4'b1000;

    localparam [3:0] ALU_SLTU = 4'b1001;

    // imm_sel[2:0]：选择 ImmGen 生成哪一种立即数。
    // IMM_I=000 不是 NONE；R型/其他不使用立即数的指令也可以保留默认 IMM_I。
    // Must match existing ImmGen imm_sel encoding

    localparam [2:0] IMM_I = 3'b000;

    localparam [2:0] IMM_S = 3'b001;

    localparam [2:0] IMM_B = 3'b010;

    localparam [2:0] IMM_U = 3'b011;

    localparam [2:0] IMM_J = 3'b100;

    // wb_sel[2:0] 写回数据源选择，连接 CPU Top 的 WriteBack MUX。
    // WB_ALU    (000)：ALU result，供 R/I 型算术指令写回。
    // WB_LOAD   (001)：Data Memory/MMIO 读取并扩展后的 Load Data。
    // WB_PC4    (010)：PC+4，用于 JAL/JALR 保存返回地址。
    // WB_IMM    (011)：ImmGen 立即数，用于 LUI。
    // WB_TARGET (100)：目标地址加法器 *原始输出*，用于 AUIPC (PC+U-imm)。
    // Datapath interface conventions

    localparam [2:0] WB_ALU    = 3'b000;

    localparam [2:0] WB_LOAD   = 3'b001;

    localparam [2:0] WB_PC4    = 3'b010;

    localparam [2:0] WB_IMM    = 3'b011;

    localparam [2:0] WB_TARGET = 3'b100; // Raw target-adder result (PC + U-imm for AUIPC)

    // mem_size[1:0]：仅说明访存字节数；字节偏移取 addr[1:0]。
    // 对齐与地址合法性不是 Decoder 职责，由 Data Memory/MMIO 控制检测。
    localparam [1:0] MEM_BYTE = 2'b00;

    localparam [1:0] MEM_HALF = 2'b01;

    localparam [1:0] MEM_WORD = 2'b10;

    // branch_type[2:0]：供独立 Branch Unit 进行 rs1/rs2 比较。
    // 分支目标地址另由 Target Adder(PC + B-imm)计算；是否采用由 branch_taken 决定。
    localparam [2:0] BR_NONE = 3'b000;

    localparam [2:0] BR_BEQ  = 3'b001;

    localparam [2:0] BR_BNE  = 3'b010;

    localparam [2:0] BR_BLT  = 3'b011;

    localparam [2:0] BR_BGE  = 3'b100;

    localparam [2:0] BR_BLTU = 3'b101;

    localparam [2:0] BR_BGEU = 3'b110;

    // jump_type[1:0]：供 PC_next Logic 选择 JAL/JALR 跳转路径。
    // JAL 目标 = PC + J-imm；JALR 目标 = (rs1 + I-imm) & ~32'h1。
    // JALR 的 bit0 清零由 PC_next 实现，不能误将 bit1 一并清零。
    localparam [1:0] JMP_NONE = 2'b00;

    localparam [1:0] JMP_JAL  = 2'b01;

    localparam [1:0] JMP_JALR = 2'b10;

    // 仅供 Decoder 内部使用：识别到本版本支持的合法指令时置 1。
    // 最终 illegal_inst = ~decoded_legal，不属于外部数据通路输入。
    reg decoded_legal;

    always @(*) begin

        // 默认不给任何架构状态施加写副作用：未知指令只置 illegal_inst。
        // 这些默认值仅是组合译码输出的安全值，并非代表执行了 ADD/LW 等操作。
        // Safe defaults. Unrecognized encodings must not modify architectural state.

        alu_op        = ALU_ADD;  // 非ALU类指令的无关默认值

        alu_src_b     = 1'b0;      // 0: RegFile.rdata2; 1: ImmGen output

        imm_sel       = IMM_I;     // IMM_I is NOT a special 'NONE' encoding

        reg_write     = 1'b0;    // 默认禁止写通用寄存器

        wb_sel        = WB_ALU;

        mem_write     = 1'b0;    // 默认禁止 Store

        mem_read      = 1'b0;    // 默认禁止 Load

        mem_size      = MEM_WORD;

        load_unsigned = 1'b0;

        branch_type   = BR_NONE; // 默认不执行条件分支

        jump_type     = JMP_NONE; // 默认不执行跳转

        decoded_legal = 1'b0;

        illegal_inst  = 1'b1;   // 默认非法，只有确认为合法才清除

        case (opcode)

            // R型：ALU.A=rs1，ALU.B=rs2；写回 ALU result 到 rd。
            // Register-register integer operations (R-type)

            OP_OP: begin

                case ({funct7, funct3})

                    10'b0000000_000: begin alu_op = ALU_ADD;  decoded_legal = 1'b1; end // ADD

                    10'b0100000_000: begin alu_op = ALU_SUB;  decoded_legal = 1'b1; end // SUB

                    10'b0000000_001: begin alu_op = ALU_SLL;  decoded_legal = 1'b1; end // SLL

                    10'b0000000_010: begin alu_op = ALU_SLT;  decoded_legal = 1'b1; end // SLT

                    10'b0000000_011: begin alu_op = ALU_SLTU; decoded_legal = 1'b1; end // SLTU

                    10'b0000000_100: begin alu_op = ALU_XOR;  decoded_legal = 1'b1; end // XOR

                    10'b0000000_101: begin alu_op = ALU_SRL;  decoded_legal = 1'b1; end // SRL

                    10'b0100000_101: begin alu_op = ALU_SRA;  decoded_legal = 1'b1; end // SRA

                    10'b0000000_110: begin alu_op = ALU_OR;   decoded_legal = 1'b1; end // OR

                    10'b0000000_111: begin alu_op = ALU_AND;  decoded_legal = 1'b1; end // AND

                    default: ;

                endcase

                if (decoded_legal) begin

                    reg_write = 1'b1;

                    wb_sel    = WB_ALU;

                end

            end

            // I型算术：ALU.A=rs1，ALU.B=I-imm；写回 ALU result 到 rd。
            // Register-immediate integer operations (I-type)

            OP_OPIMM: begin

                alu_src_b = 1'b1;

                imm_sel   = IMM_I;

                case (funct3)

                    3'b000: begin alu_op = ALU_ADD;  decoded_legal = 1'b1; end // ADDI

                    3'b010: begin alu_op = ALU_SLT;  decoded_legal = 1'b1; end // SLTI

                    3'b011: begin alu_op = ALU_SLTU; decoded_legal = 1'b1; end // SLTIU

                    3'b100: begin alu_op = ALU_XOR;  decoded_legal = 1'b1; end // XORI

                    3'b110: begin alu_op = ALU_OR;   decoded_legal = 1'b1; end // ORI

                    3'b111: begin alu_op = ALU_AND;  decoded_legal = 1'b1; end // ANDI

                    3'b001: begin

                        if (funct7 == 7'b0000000) begin

                            alu_op = ALU_SLL;

                            decoded_legal = 1'b1; // SLLI

                        end

                    end

                    3'b101: begin

                        case (funct7)

                            7'b0000000: begin alu_op = ALU_SRL; decoded_legal = 1'b1; end // SRLI

                            7'b0100000: begin alu_op = ALU_SRA; decoded_legal = 1'b1; end // SRAI

                            default: ;

                        endcase

                    end

                    default: ;

                endcase

                if (decoded_legal) begin

                    reg_write = 1'b1;

                    wb_sel    = WB_ALU;

                end

            end

            // Load：ALU.ADD 求有效地址；mem_read=1；wb_sel=WB_LOAD；写 rd。
            // mem_size + load_unsigned 决定 LB/LH/LW/LBU/LHU 的选择与扩展。
            // Loads: use ALU for effective address = rs1 + I-immediate

            OP_LOAD: begin

                alu_op    = ALU_ADD;

                alu_src_b = 1'b1;

                imm_sel   = IMM_I;

                case (funct3)

                    3'b000: begin mem_size = MEM_BYTE; decoded_legal = 1'b1; end // LB

                    3'b001: begin mem_size = MEM_HALF; decoded_legal = 1'b1; end // LH

                    3'b010: begin mem_size = MEM_WORD; decoded_legal = 1'b1; end // LW

                    3'b100: begin mem_size = MEM_BYTE; load_unsigned = 1'b1; decoded_legal = 1'b1; end // LBU

                    3'b101: begin mem_size = MEM_HALF; load_unsigned = 1'b1; decoded_legal = 1'b1; end // LHU

                    default: ;

                endcase

                if (decoded_legal) begin

                    mem_read  = 1'b1;

                    reg_write = 1'b1;

                    wb_sel    = WB_LOAD;

                end

            end

            // Store：ALU.ADD 求有效地址；mem_write=1；数据来自 RegFile.rs2。
            // SB/SH/SW 宽度由 mem_size 表示；不写 RegFile。
            // Stores: use ALU for effective address = rs1 + S-immediate

            OP_STORE: begin

                alu_op    = ALU_ADD;

                alu_src_b = 1'b1;

                imm_sel   = IMM_S;

                case (funct3)

                    3'b000: begin mem_size = MEM_BYTE; decoded_legal = 1'b1; end // SB

                    3'b001: begin mem_size = MEM_HALF; decoded_legal = 1'b1; end // SH

                    3'b010: begin mem_size = MEM_WORD; decoded_legal = 1'b1; end // SW

                    default: ;

                endcase

                if (decoded_legal)

                    mem_write = 1'b1;

            end

            // 条件分支：branch_type 指示比较类型；Branch Unit 输出 branch_taken。
            // Target Adder 用 PC+B-imm 求分支目标；branch_taken 决定 PC 是否跳转。
            // Conditional branches: separate Branch Unit compares rs1_data and rs2_data

            OP_BRANCH: begin

                imm_sel = IMM_B;

                case (funct3)

                    3'b000: begin branch_type = BR_BEQ;  decoded_legal = 1'b1; end

                    3'b001: begin branch_type = BR_BNE;  decoded_legal = 1'b1; end

                    3'b100: begin branch_type = BR_BLT;  decoded_legal = 1'b1; end

                    3'b101: begin branch_type = BR_BGE;  decoded_legal = 1'b1; end

                    3'b110: begin branch_type = BR_BLTU; decoded_legal = 1'b1; end

                    3'b111: begin branch_type = BR_BGEU; decoded_legal = 1'b1; end

                    default: ;

                endcase

            end

            // JAL：PC_next 取 PC+J-imm；WriteBack 选 PC+4 写 rd。
            // JAL: PC target = PC + J-immediate; rd = PC + 4

            OP_JAL: begin

                imm_sel       = IMM_J;

                jump_type     = JMP_JAL;

                wb_sel        = WB_PC4;

                reg_write     = 1'b1;

                decoded_legal = 1'b1;

            end

            // JALR：Target Adder 以 rs1+I-imm 计算原始目标，PC_next 清 bit0。
            // WriteBack 选 PC+4 写 rd；只有 funct3=000 是合法 JALR。
            // JALR: PC target = (rs1 + I-immediate) & ~1; rd = PC + 4

            OP_JALR: begin

                if (funct3 == 3'b000) begin

                    imm_sel       = IMM_I;

                    jump_type     = JMP_JALR;

                    wb_sel        = WB_PC4;

                    reg_write     = 1'b1;

                    decoded_legal = 1'b1;

                end

            end

            // LUI：无需 ALU，WriteBack 直接选择 ImmGen 输出的 U-imm。
            // LUI: rd = U-immediate

            OP_LUI: begin

                imm_sel       = IMM_U;

                wb_sel        = WB_IMM;

                reg_write     = 1'b1;

                decoded_legal = 1'b1;

            end

            // AUIPC：Target Adder 以 PC+U-imm 计算；WriteBack 选择 WB_TARGET。
            // 不能误用 PC_next 对 JALR 的 bit0 清零处理。
            // AUIPC: rd = PC + U-immediate (raw target-adder result)

            OP_AUIPC: begin

                imm_sel       = IMM_U;

                wb_sel        = WB_TARGET;

                reg_write     = 1'b1;

                decoded_legal = 1'b1;

            end

            default: ; // FENCE, ECALL, EBREAK and other unsupported encodings

        endcase

        illegal_inst = ~decoded_legal;

    end

endmodule

`default_nettype wire
