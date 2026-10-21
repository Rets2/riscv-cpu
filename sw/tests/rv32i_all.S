/* Directed tests for this project's 37-instruction RV32I subset. */
/* Each instruction is real (no li/la/nop pseudoinstructions). */
/* "expect" comments are independent, hand-written post-instruction checkpoints. */
.section .text
.option norvc
.globl _start
_start:
    addi x1, x0, 5                 # expect x1=5
    addi x2, x0, 10                # expect x2=10
    addi x3, x0, -1                # expect x3=0xffffffff
    lui x4, 0x80000                # expect x4=0x80000000
    addi x5, x4, -1                # expect x5=0x7fffffff
    addi x6, x0, 31
    addi x7, x0, 32
    addi x8, x0, 33

/* Register arithmetic, wraparound, Boolean operations and shift boundaries. */
    add x10, x1, x2                # expect x10=15
    add x11, x3, x1                # expect x11=4
    add x12, x5, x1                # expect x12=0x80000004
    sub x10, x1, x2                # expect x10=0xfffffffb
    sub x11, x0, x3                # expect x11=1
    and x10, x4, x5                # expect x10=0
    or x11, x4, x5                 # expect x11=0xffffffff
    xor x12, x3, x5                # expect x12=0x80000000
    sll x10, x1, x6                # expect x10=0x80000000
    sll x11, x1, x7                # expect x11=5
    sll x12, x1, x8                # expect x12=10
    srl x10, x4, x6                # expect x10=1
    srl x11, x4, x7                # expect x11=0x80000000
    sra x12, x4, x6                # expect x12=0xffffffff
    sra x13, x4, x7                # expect x13=0x80000000
    sra x14, x4, x8                # expect x14=0xc0000000
    slt x10, x3, x1                # expect x10=1
    slt x11, x5, x4                # expect x11=0
    slt x12, x1, x1                # expect x12=0
    sltu x13, x3, x1               # expect x13=0
    sltu x14, x1, x3               # expect x14=1
    sltu x15, x1, x1               # expect x15=0

/* Immediate extrema and signed-versus-unsigned interpretation. */
    addi x10, x0, -2048            # expect x10=0xfffff800
    addi x11, x0, 2047             # expect x11=2047
    slti x12, x3, 0                # expect x12=1
    slti x13, x1, -1               # expect x13=0
    sltiu x14, x1, -1              # expect x14=1
    sltiu x15, x3, 1               # expect x15=0
    xori x10, x4, -1               # expect x10=0x7fffffff
    ori x11, x4, 1                 # expect x11=0x80000001
    andi x12, x3, 0x7ff            # expect x12=2047
    slli x13, x1, 0                # expect x13=5
    slli x14, x1, 31               # expect x14=0x80000000
    srli x15, x4, 31               # expect x15=1
    srai x16, x4, 31               # expect x16=0xffffffff
    srai x17, x4, 1                # expect x17=0xc0000000
    addi x0, x3, 123               # expect x0=0
    add x0, x1, x2                 # expect x0=0

/* U-type writeback and PC-relative results. Trace checks AUIPC at nonzero PCs. */
    lui x18, 0x12345               # expect x18=0x12345000
    lui x19, 0xfffff               # expect x19=0xfffff000
    auipc x10, 0
    auipc x11, 0x80000
    auipc x12, 0xfffff
    lui x0, 0xfffff                # expect x0=0
    auipc x0, 1                    # expect x0=0

/* DMEM is 0x00010000..0x0001ffff. The suite uses its first 64 bytes. */
/* TB initializes DMEM to zero as a test fixture, not as CPU reset behavior. */
    lui x20, 0x10                 # expect x20=0x00010000
    lui x21, 0x80ff8
    addi x21, x21, -255            # expect x21=0x80ff7f01
    sw x21, 0(x20)                # expect m0=0x80ff7f01
    lw x10, 0(x20)                # expect x10=0x80ff7f01
    lb x11, 0(x20)                # expect x11=1
    lb x11, 1(x20)                # expect x11=127
    lb x11, 2(x20)                # expect x11=0xffffffff
    lb x11, 3(x20)                # expect x11=0xffffff80
    lbu x12, 0(x20)               # expect x12=1
    lbu x12, 1(x20)               # expect x12=127
    lbu x12, 2(x20)               # expect x12=255
    lbu x12, 3(x20)               # expect x12=128
    lh x13, 0(x20)                # expect x13=0x00007f01
    lh x13, 2(x20)                # expect x13=0xffff80ff
    lhu x14, 0(x20)               # expect x14=0x00007f01
    lhu x14, 2(x20)               # expect x14=0x000080ff

/* Byte write enables: preserve all bytes not selected by SB. */
    lui x22, 0x12345
    addi x22, x22, 0x678          # expect x22=0x12345678
    sw x22, 4(x20)                # expect m1=0x12345678
    sb x3, 4(x20)                 # expect m1=0x123456ff
    sb x1, 5(x20)                 # expect m1=0x123405ff
    sb x2, 6(x20)                 # expect m1=0x120a05ff
    addi x22, x0, 128
    sb x22, 7(x20)                # expect m1=0x800a05ff
    lw x15, 4(x20)                # expect x15=0x800a05ff

/* Both halfword lanes, sign extension and low-16-bit store truncation. */
    sh x3, 8(x20)                 # expect m2=0x0000ffff
    lui x22, 8
    addi x22, x22, 170            # expect x22=0x000080aa
    sh x22, 10(x20)               # expect m2=0x80aaffff
    lh x16, 8(x20)                # expect x16=0xffffffff
    lh x16, 10(x20)               # expect x16=0xffff80aa
    lhu x17, 10(x20)              # expect x17=0x000080aa
    addi x23, x20, 16
    sw x21, -4(x23)               # expect m3=0x80ff7f01
    lw x24, -4(x23)               # expect x24=0x80ff7f01
    addi x25, x24, 1              # expect x25=0x80ff7f02
    lw x0, 0(x20)                 # expect x0=0
    sw x3, 16(x20)                # expect m4=0xffffffff
    sw x0, 16(x20)                # expect m4=0

/* Each branch executes both taken and not-taken paths. */
/* The skipped x31 writes are poison instructions; x31 must remain zero. */
    beq x1, x1, beq_taken
    addi x31, x0, 0x111
beq_taken:
    beq x1, x2, beq_not_taken
    addi x30, x30, 1
beq_not_taken:
    bne x1, x2, bne_taken
    addi x31, x0, 0x112
bne_taken:
    bne x1, x1, bne_not_taken
    addi x30, x30, 1
bne_not_taken:
    blt x3, x1, blt_taken
    addi x31, x0, 0x113
blt_taken:
    blt x1, x3, blt_not_taken
    addi x30, x30, 1
blt_not_taken:
    bge x1, x3, bge_taken
    addi x31, x0, 0x114
bge_taken:
    bge x3, x1, bge_not_taken
    addi x30, x30, 1
bge_not_taken:
    bltu x1, x3, bltu_taken
    addi x31, x0, 0x115
bltu_taken:
    bltu x3, x1, bltu_not_taken
    addi x30, x30, 1
bltu_not_taken:
    bgeu x3, x1, bgeu_taken
    addi x31, x0, 0x116
bgeu_taken:
    bgeu x1, x3, bgeu_not_taken
    addi x30, x30, 1
bgeu_not_taken:
    addi x29, x0, 6               # expect x30=6

/* Equality boundaries and a not-taken branch with a misaligned candidate. */
    blt x1, x1, signed_equal_done
    addi x29, x29, 1
signed_equal_done:
    bge x1, x1, signed_ge_done
    addi x31, x0, 0x117
signed_ge_done:
    bltu x1, x1, unsigned_equal_done
    addi x29, x29, 1
unsigned_equal_done:
    bgeu x1, x1, unsigned_ge_done
    addi x31, x0, 0x118
unsigned_ge_done:
misaligned_not_taken:
    beq x1, x2, misaligned_not_taken+2
    addi x26, x0, 3
backward_loop:
    addi x26, x26, -1
    bne x26, x0, backward_loop
    addi x29, x29, 1              # expect x26=0

/* JAL forward call, JALR return, discarded link and negative JAL offset. */
    jal x27, subroutine
return_point:
    addi x30, x30, 1
    jal x0, after_subroutine
subroutine:
    addi x29, x29, 1
    jalr x0, 0(x27)
after_subroutine:
    jal x0, forward_entry
backward_target:
    addi x30, x30, 1
    jal x0, after_backward_jump
forward_entry:
    jal x27, backward_target
    addi x31, x0, 0x119
after_backward_jump:

/* JALR rd=rs1 must use the OLD rs1 value; also clear an odd target's bit 0. */
    addi x28, x0, %lo(same_register_target+1)
    jalr x28, 0(x28)
    addi x31, x0, 0x11a
same_register_target:
    addi x29, x29, 1
    addi x28, x0, %lo(negative_jalr_target+5)
    jalr x27, -4(x28)
    addi x31, x0, 0x11b
negative_jalr_target:
    addi x29, x29, 1              # expect x31=0
    addi x0, x0, 0
    addi x0, x0, 0
done:
    jal x0, done
