import argparse
import subprocess as sp
import os, time, re, sys, json
import binascii as ba


OTBN_CFG_DIR = os.path.dirname(os.path.realpath(__file__))
TMP_DIR = "/".join(OTBN_CFG_DIR.split("/")[:-2]) + "/tmp"
# parsed automatically
ASM_CMD = None
OBJDUMP_CMD = None
RV_OBJDUMP_CMD = None
INSTR_LIMIT = None
VERILATOR_AT_LEAST_4_200 = False


def check_file_exists(file_path):
    if file_path == None: return None
    if not os.path.isfile(file_path):
        raise argparse.ArgumentTypeError("File '%s' does not exist" % file_path)
    return file_path


def check_dir_exists(dir_path):
    if not os.path.isdir(dir_path):
        print("ERROR: Directory %s does not exist" % dir_path)


try:
    with open("config.json", "r") as f:
        opts = json.load(f)
        ASM_CMD = opts.get("asm")
        OBJDUMP_CMD = opts.get("objdump")
        RV_OBJDUMP_CMD = opts.get("rv_objdump")
        VERILATOR_AT_LEAST_4_200 = opts.get("verilator_at_least_4_200", False)
except FileNotFoundError as e:
    print(e)


if not isinstance(ASM_CMD, str) or not isinstance(OBJDUMP_CMD, str) or not isinstance(RV_OBJDUMP_CMD, str):
    print("Invalid config.json file contents")
    sys.exit(1)


ASM_CMD = ASM_CMD.split()
OBJDUMP_CMD = OBJDUMP_CMD.split()
RV_OBJDUMP_CMD = RV_OBJDUMP_CMD.split()
check_file_exists(ASM_CMD[0])
check_file_exists(OBJDUMP_CMD[0])
check_file_exists(RV_OBJDUMP_CMD[0])


def parse_arguments():
    global INSTR_LIMIT
    parser = argparse.ArgumentParser(description="Assemble.py for otbn")
    parser.add_argument("--program", dest="program_path", required=True)
    # parser.add_argument('--init-file', dest='init_file_path', required=False, default=None)
    parser.add_argument("--build-dir", dest="build_dir_path", required=False, default=TMP_DIR)
    parser.add_argument("--netlist", dest="netlist_path", required=True)
    args = parser.parse_args()
    check_file_exists(args.program_path)
    # check_file_exists(args.init_file_path)
    check_dir_exists(args.build_dir_path)
    check_file_exists(args.netlist_path)

    with open(args.netlist_path, "r") as f:
        verilog_txt = f.read()
        rax = re.compile("u_imem.mem\[([0-9]+)\]")
        INSTR_LIMIT = max([int(x) for x in rax.findall(verilog_txt)]) + 1
        print("INSTR_LIMIT = ", INSTR_LIMIT)

    return args


def xor_all_bits(num):
    output = 0
    while num > 0:
        output = output ^ (num & 1)
        num = num >> 1
    return output


# extend 32-bit instruction to a 39-bit value
# see enc_secded_inv_39_32() function in secded_enc.c in opentitan
def secded_extend_39_32(num):
    num = num | ((xor_all_bits(num & 0x2606bd25) ^ 0) << 32)
    num = num | ((xor_all_bits(num & 0xdeba8050) ^ 1) << 33)
    num = num | ((xor_all_bits(num & 0x413d89aa) ^ 0) << 34)
    num = num | ((xor_all_bits(num & 0x31234ed1) ^ 1) << 35)
    num = num | ((xor_all_bits(num & 0xc2c1323b) ^ 0) << 36)
    num = num | ((xor_all_bits(num & 0x2dcc624c) ^ 1) << 37)
    num = num | ((xor_all_bits(num & 0x98505586) ^ 0) << 38)
    return num


def create_raminit_header(args):

    # program.S -> program.o
    cmd = ASM_CMD + ["-o", args.program_path[:-2] + ".o", args.program_path]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

    # program.o -> program.elf
    cmd = OBJDUMP_CMD + ["-o", args.program_path[:-2] + ".elf", args.program_path[:-2] + ".o"]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

    # retrieve .text section from program.elf
    cmd = RV_OBJDUMP_CMD + ["-s", "-j", ".text", args.program_path[:-2] + ".elf"]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    data = p.stdout.read().decode("ascii").strip().split("\n")

    # strip instructions from .text section
    curr = 1
    while("section" not in data[curr - 1]): curr += 1
    data = [d.strip()[:d.find("  ")].split()[1:] for d in data[curr:]]
    data = "".join(["".join(d) for d in data])
    code = ba.unhexlify(data)

    # check .text section size
    MEM_WIDTH = 4
    if len(code) > INSTR_LIMIT * MEM_WIDTH:
        print(".text section is too large (> %d bytes)" % (INSTR_LIMIT * MEM_WIDTH))
        sys.exit(-1)

    # create ram_init.h file
    header = open(args.build_dir_path + "/ram_init.h", "w")
    header.write("void load_prog(Testbench<Vcircuit>* tb) {\n")

    # append secded extended instructions to the ram_init.h file
    for i in range(0, len(code), MEM_WIDTH):
        x = "0x" + ba.hexlify(code[i:i+MEM_WIDTH][::-1]).decode("ascii")
        x = hex(secded_extend_39_32(int(x, 0)))
        signal_name = "02Emem__05B%d__05D" % (i // MEM_WIDTH)
        if VERILATOR_AT_LEAST_4_200:
            signal_name = signal_name.lower()
        signal_name = "otbn_top_coco__DOT__u_imem__" + signal_name
        header.write("  tb->m_core->%s = %s;\n" % (signal_name, x))

    # # parse data init file with format addr/reg ; value
    # reg, mem = [], []
    # if args.init_file_path is not None:
    #     data = None
    #     with open(args.init_file_path, "r") as f:
    #         data = f.read().strip().split("\n")
    #     data = [d.split(";") for d in data]
    #     reg = [d for d in data if d[0].startswith("x")]
    #     mem = [d for d in data if not d[0].startswith("x")]

    # for m in mem:
    #     addr, val = int(m[0], 0) // MEM_WIDTH, m[1]
    #     signal_name = "02Emem__05B%d__05D" % addr
    #     if VERILATOR_AT_LEAST_4_200:
    #         signal_name = signal_name.lower()
    #     signal_name = "ibex_top__DOT__u_ram__" + signal_name
    #     header.write("  tb->m_core->%s = %s;\n" % (signal_name, val))

    header.write("  tb->reset();\n")

    # for r in reg:
    #     addr, val = r[0][1:], r[1]
    #     signal_name = "02Eregister_file_i__02Erf_reg_tmp__05B%d__05D" % addr
    #     if VERILATOR_AT_LEAST_4_200:
    #         signal_name = signal_name.lower()
    #     signal_name = "ibex_top__DOT__u_core__" + signal_name
    #     header.write("  tb->m_core->%s = %s;\n" % (signal_name, val))

    header.write("}\n")
    header.close()


def create_verilator_testbench(args):
    with open(OTBN_CFG_DIR + "/verilator_tb_template.txt", "r") as f:
        template = f.read()

    tb_path = args.build_dir_path + "/verilator_tb.c"
    vcd_path = args.build_dir_path + "/circuit.vcd"

    template = template.replace("{VCD_PATH}", vcd_path)
    with open(tb_path, "w+") as f: f.write(template)

    print("Wrote verilator testbench to %s" % tb_path)
    print("It produces output VCD at %s" % vcd_path)


def main():
    args = parse_arguments()
    print("Using program file: ", args.program_path)
    # print("Using initialization file: ", args.init_file_path)
    print("Using build directory: %s" % args.build_dir_path)
    print("Using netlist path: %s" % args.netlist_path)

    # Create raminit.h
    create_raminit_header(args)

    # Create verilator testbench
    create_verilator_testbench(args)


if __name__ == "__main__":
    main()
