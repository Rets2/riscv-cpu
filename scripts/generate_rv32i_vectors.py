"""Reproduce directed RV32I images and golden traces without extra packages.

This deliberately small assembler accepts only the explicit syntax in
sw/tests/rv32i_all.S. It is not a replacement for the installed GNU toolchain.
The separate reference execution decodes the encoded words (not the assembly
operands). Hand-written 'expect' comments are checked against its results.
No RTL, VCS, or hardware simulator is executed by this script.
"""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
MASK = 0xffffffff
R = {'add': (0, 0), 'sub': (0, 32), 'sll': (1, 0), 'slt': (2, 0),
     'sltu': (3, 0), 'xor': (4, 0), 'srl': (5, 0), 'sra': (5, 32),
     'or': (6, 0), 'and': (7, 0)}
I = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SHIFT = {'slli': (1, 0), 'srli': (5, 0), 'srai': (5, 32)}
LOAD = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
STORE = {'sb': 0, 'sh': 1, 'sw': 2}
BRANCH = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}
ALL = set(R) | set(I) | set(SHIFT) | set(LOAD) | set(STORE) | set(BRANCH) | {'lui', 'auipc', 'jal', 'jalr'}
assert len(ALL) == 37


def sext(value, bits):
    return (value & ((1 << (bits - 1)) - 1)) - (value & (1 << (bits - 1)))


def register(text):
    if not re.fullmatch(r'x(?:[0-9]|[12][0-9]|3[01])', text):
        raise ValueError('Bad register: ' + text)
    return int(text[1:])


def immediate(text, labels):
    if text.startswith('%lo(') and text.endswith(')'):
        return sext(immediate(text[4:-1], labels) & 0xfff, 12)
    try:
        return int(text, 0)
    except ValueError:
        match = re.fullmatch(r'([A-Za-z_]\w*)([+-]\d+)?', text)
        if not match or match[1] not in labels:
            raise ValueError('Bad immediate/label: ' + text)
        return labels[match[1]] + int(match[2] or '0')


def signed_field(value, bits, alignment=1):
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)) or value % alignment:
        raise ValueError('Immediate out of range/alignment: ' + str(value))
    return value & ((1 << bits) - 1)


def assemble(source):
    labels, entries = {}, []
    pc = 0
    for line_number, raw in enumerate(source.splitlines(), 1):
        body = raw.split('#', 1)[0].strip()
        if not body or body.startswith('.') or body.startswith('/*'):
            continue
        if body.endswith(':'):
            name = body[:-1]
            if name in labels:
                raise ValueError('Duplicate label: ' + name)
            labels[name] = pc
        else:
            entries.append((pc, body, raw, line_number))
            pc += 4
    words = []
    for pc, body, raw, line_number in entries:
        fields = re.split(r'[\s,]+', body.strip())
        fields = [field for field in fields if field]
        op, a = fields[0], fields[1:]
        if op in R:
            rd, rs1, rs2 = map(register, a)
            f3, f7 = R[op]
            word = f7 << 25 | rs2 << 20 | rs1 << 15 | f3 << 12 | rd << 7 | 0x33
        elif op in I or op in SHIFT:
            rd, rs1 = register(a[0]), register(a[1])
            imm = immediate(a[2], labels)
            if op in SHIFT:
                if not 0 <= imm < 32:
                    raise ValueError('Bad shift amount')
                f3, f7 = SHIFT[op]
                imm |= f7 << 5
            else:
                f3 = I[op]
                imm = signed_field(imm, 12)
            word = imm << 20 | rs1 << 15 | f3 << 12 | rd << 7 | 0x13
        elif op in LOAD or op == 'jalr':
            memory_operand = re.fullmatch(r'(.+)\((x\d+)\)', a[1])
            if memory_operand is None:
                raise ValueError('Bad memory operand: ' + body)
            rd, rs1 = register(a[0]), register(memory_operand[2])
            imm = signed_field(immediate(memory_operand[1], labels), 12)
            f3 = LOAD[op] if op in LOAD else 0
            word = imm << 20 | rs1 << 15 | f3 << 12 | rd << 7 | (0x03 if op in LOAD else 0x67)
        elif op in STORE:
            memory_operand = re.fullmatch(r'(.+)\((x\d+)\)', a[1])
            if memory_operand is None:
                raise ValueError('Bad memory operand: ' + body)
            rs2, rs1 = register(a[0]), register(memory_operand[2])
            imm = signed_field(immediate(memory_operand[1], labels), 12)
            word = (imm >> 5) << 25 | rs2 << 20 | rs1 << 15 | STORE[op] << 12 | (imm & 31) << 7 | 0x23
        elif op in BRANCH:
            rs1, rs2 = register(a[0]), register(a[1])
            imm = signed_field(immediate(a[2], labels) - pc, 13, 2)
            word = ((imm >> 12) & 1) << 31 | ((imm >> 5) & 63) << 25 | rs2 << 20 | rs1 << 15 | BRANCH[op] << 12 | ((imm >> 1) & 15) << 8 | ((imm >> 11) & 1) << 7 | 0x63
        elif op == 'jal':
            rd = register(a[0])
            imm = signed_field(immediate(a[1], labels) - pc, 21, 2)
            word = ((imm >> 20) & 1) << 31 | ((imm >> 1) & 1023) << 21 | ((imm >> 11) & 1) << 20 | ((imm >> 12) & 255) << 12 | rd << 7 | 0x6f
        elif op in ('lui', 'auipc'):
            rd, imm = register(a[0]), immediate(a[1], labels)
            if not 0 <= imm < (1 << 20):
                raise ValueError('Bad U immediate')
            word = imm << 12 | rd << 7 | (0x37 if op == 'lui' else 0x17)
        else:
            raise ValueError('Unsupported instruction: ' + body)
        words.append(word)
    return words, entries, labels


def execute(words, entries, labels):
    """Golden byte-addressed RV32I execution, independent of RTL internals."""
    regs, memory = [0] * 32, bytearray(64)
    pc, rows, coverage, outcomes, anchor_count = 0, [], Counter(), Counter(), 0
    for step in range(512):
        if pc % 4 or not 0 <= pc // 4 < len(words):
            raise ValueError('Reference fetch error: %08x' % pc)
        word = words[pc // 4]
        opcode, rd = word & 127, (word >> 7) & 31
        rs1, rs2 = (word >> 15) & 31, (word >> 20) & 31
        f3, f7 = (word >> 12) & 7, word >> 25
        # Capture OLD operand values before applying any writeback (JALR rd=rs1).
        a, b = regs[rs1], regs[rs2]
        next_pc, result, name = (pc + 4) & MASK, None, None
        if opcode == 0x33:
            name = next((n for n, fields in R.items() if fields == (f3, f7)), None)
            if name is None:
                raise ValueError('Illegal R encoding')
            result = {'add': lambda: a + b, 'sub': lambda: a - b,
                      'and': lambda: a & b, 'or': lambda: a | b, 'xor': lambda: a ^ b,
                      'sll': lambda: a << (b & 31), 'srl': lambda: a >> (b & 31),
                      'sra': lambda: sext(a, 32) >> (b & 31),
                      'slt': lambda: int(sext(a, 32) < sext(b, 32)),
                      'sltu': lambda: int(a < b)}[name]()
        elif opcode == 0x13:
            imm = sext(word >> 20, 12)
            if f3 in (1, 5):
                name = next((n for n, fields in SHIFT.items() if fields == (f3, f7)), None)
                if name is None:
                    raise ValueError('Illegal shift encoding')
                amount = (word >> 20) & 31
                result = a << amount if name == 'slli' else (sext(a, 32) >> amount if name == 'srai' else a >> amount)
            else:
                name = next(n for n, v in I.items() if v == f3)
                result = {'addi': lambda: a + imm, 'slti': lambda: int(sext(a, 32) < imm),
                          'sltiu': lambda: int(a < (imm & MASK)),
                          'xori': lambda: a ^ (imm & MASK), 'ori': lambda: a | (imm & MASK),
                          'andi': lambda: a & (imm & MASK)}[name]()
        elif opcode in (0x03, 0x23):
            table = LOAD if opcode == 3 else STORE
            name = next(n for n, v in table.items() if v == f3)
            encoded_imm = word >> 20 if opcode == 3 else ((word >> 25) << 5 | ((word >> 7) & 31))
            address = (a + sext(encoded_imm, 12)) & MASK
            width = {'lb': 1, 'lbu': 1, 'lh': 2, 'lhu': 2, 'lw': 4, 'sb': 1, 'sh': 2, 'sw': 4}[name]
            offset = address - 0x10000
            if address % width or not 0 <= offset <= len(memory) - width:
                raise ValueError('Reference DMEM error')
            if opcode == 3:
                value = int.from_bytes(memory[offset:offset + width], 'little')
                result = sext(value, width * 8) if name in ('lb', 'lh') else value
            else:
                memory[offset:offset + width] = (b & ((1 << (width * 8)) - 1)).to_bytes(width, 'little')
        elif opcode == 0x63:
            name = next(n for n, v in BRANCH.items() if v == f3)
            imm = ((word >> 31) << 12 | ((word >> 7) & 1) << 11 |
                   ((word >> 25) & 63) << 5 | ((word >> 8) & 15) << 1)
            taken = {'beq': a == b, 'bne': a != b,
                     'blt': sext(a, 32) < sext(b, 32), 'bge': sext(a, 32) >= sext(b, 32),
                     'bltu': a < b, 'bgeu': a >= b}[name]
            outcomes[name, taken] += 1
            if taken:
                next_pc = (pc + sext(imm, 13)) & MASK
        elif opcode == 0x6f:
            name = 'jal'
            imm = ((word >> 31) << 20 | ((word >> 12) & 255) << 12 |
                   ((word >> 20) & 1) << 11 | ((word >> 21) & 1023) << 1)
            result, next_pc = pc + 4, (pc + sext(imm, 21)) & MASK
        elif opcode == 0x67 and f3 == 0:
            name = 'jalr'
            result, next_pc = pc + 4, ((a + sext(word >> 20, 12)) & MASK) & ~1
        elif opcode in (0x37, 0x17):
            name = 'lui' if opcode == 0x37 else 'auipc'
            result = (word & 0xfffff000) + (pc if opcode == 0x17 else 0)
        else:
            raise ValueError('Unsupported encoding %08x' % word)
        if next_pc % 4:
            raise ValueError('Reference target alignment error')
        if result is not None and rd != 0:
            regs[rd] = result & MASK
        assert regs[0] == 0
        # Encode/decode agreement and independent hand-authored value anchors.
        assert name == entries[pc // 4][1].split()[0]
        for kind, index, value in re.findall(r'expect\s+([xm])(\d+)=(0x[0-9a-fA-F]+|\d+)', entries[pc // 4][2]):
            index, expected = int(index), int(value, 0)
            actual = regs[index] if kind == 'x' else int.from_bytes(memory[index * 4:index * 4 + 4], 'little')
            if actual != expected:
                raise ValueError('Hand checkpoint failed at PC=%08x: %s' % (pc, entries[pc // 4][2]))
            anchor_count += 1
        memory_words = [int.from_bytes(memory[i:i + 4], 'little') for i in range(0, 64, 4)]
        rows.append([pc, word, next_pc] + regs.copy() + memory_words)
        coverage[name] += 1
        if pc == labels['done']:
            assert next_pc == pc and name == 'jal'
            break
        pc = next_pc
    else:
        raise ValueError('Reference program did not terminate within 512 instructions')
    assert set(coverage) == ALL, 'Not all 37 instructions were executed'
    assert all(outcomes[n, True] and outcomes[n, False] for n in BRANCH)
    assert regs[31] == 0, 'A poison instruction was executed'
    return rows, coverage, outcomes, anchor_count


def check_gnu_disassembly(path, words, entries, labels):
    """Independently verify every encoding/operand using existing GNU objdump."""
    decoded = []
    for line in Path(path).read_text(encoding='ascii').splitlines():
        match = re.match(r'\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+(\S+)\s*(.*)', line)
        if match:
            decoded.append((int(match[1], 16), int(match[2], 16), match[3], match[4].split('#')[0].strip()))
    if len(decoded) != len(words):
        raise ValueError('GNU disassembly instruction count differs')
    for (address, encoded, actual_op, operands), word, (pc, body, raw, line_number) in zip(decoded, words, entries):
        parts = re.split(r'[\s,]+', body)
        op, args = parts[0], parts[1:]
        actual_args = operands.split(',')
        if (address, encoded, actual_op) != (pc, word, op):
            raise ValueError('GNU disassembly differs at source line %d' % line_number)
        if op in R:
            good = actual_args == args
        elif op in I or op in SHIFT:
            good = actual_args[:2] == args[:2] and int(actual_args[2], 0) == immediate(args[2], labels)
        elif op in LOAD or op in STORE or op == 'jalr':
            source_mem = re.fullmatch(r'(.+)\((x\d+)\)', args[1])
            actual_mem = re.fullmatch(r'(.+)\((x\d+)\)', actual_args[1])
            good = (actual_args[0] == args[0] and actual_mem is not None and
                    actual_mem[2] == source_mem[2] and
                    int(actual_mem[1], 0) == immediate(source_mem[1], labels))
        elif op in BRANCH:
            good = actual_args[:2] == args[:2] and int(actual_args[2], 16) == immediate(args[2], labels)
        elif op == 'jal':
            good = actual_args[0] == args[0] and int(actual_args[1], 16) == immediate(args[1], labels)
        else:
            good = actual_args[0] == args[0] and int(actual_args[1], 0) == immediate(args[1], labels)
        if not good:
            raise ValueError('GNU operands differ at PC=%08x: %s vs %s' % (pc, body, operands))
    print('GNU objdump cross-check: PASS (%d words, every register/immediate/target matched)' % len(words))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-objdump', help='Optionally cross-check an existing numeric/no-aliases GNU disassembly')
    args = parser.parse_args()
    source = ROOT / 'sw/tests/rv32i_all.S'
    words, entries, labels = assemble(source.read_text(encoding='utf-8'))
    assert words[:2] == [0x00500093, 0x00a00113]  # Previously verified encodings.
    assert len(words) <= 16384
    rows, coverage, outcomes, anchors = execute(words, entries, labels)
    image = ROOT / 'sw/images/rv32i_all.hex'
    expected = ROOT / 'sw/expected/rv32i_all.trace'
    listing = ROOT / 'sw/tests/rv32i_all.lst'
    report = ROOT / 'sw/tests/rv32i_all.coverage.txt'
    for path in [image, expected, listing, report]:
        path.parent.mkdir(parents=True, exist_ok=True)
    image.write_text(''.join('%08x\n' % word for word in words), encoding='ascii')
    header = [0x52563332, 1, len(rows), len(words)]
    expected.write_text(' '.join('%08x' % v for v in header) + '\n' + ''.join(' '.join('%08x' % v for v in row) + '\n' for row in rows), encoding='ascii')
    listing.write_text(''.join('%08x  %08x  %s\n' % (pc, word, body) for word, (pc, body, raw, line) in zip(words, entries)), encoding='ascii')
    lines = ['HOST REFERENCE RESULTS ONLY; VCS/RTL simulation has NOT been run.',
             'ISA kinds executed: %d/37' % len(coverage), 'Image words: %d' % len(words),
             'Executed instructions: %d' % len(rows), 'Hand-written checkpoints passed: %d' % anchors,
             'Expected end time: %d ns' % (16 + 10 * len(rows)),
             'Image SHA256: ' + hashlib.sha256(image.read_bytes()).hexdigest(), '', 'Instruction hits:']
    lines += ['%s %d' % (name.upper(), coverage[name]) for name in sorted(ALL)]
    lines += ['', 'Branch outcomes:']
    lines += ['%s taken=%d not_taken=%d' % (name.upper(), outcomes[name, True], outcomes[name, False]) for name in BRANCH]
    report.write_text('\n'.join(lines) + '\n', encoding='ascii')
    binary = ROOT / 'build/rv32i_vectors/rv32i_all.bin'
    binary.parent.mkdir(parents=True, exist_ok=True)
    binary.write_bytes(b''.join(word.to_bytes(4, 'little') for word in words))
    print('\n'.join(lines[:7]))
    if args.check_objdump:
        check_gnu_disassembly(args.check_objdump, words, entries, labels)


if __name__ == '__main__':
    main()
