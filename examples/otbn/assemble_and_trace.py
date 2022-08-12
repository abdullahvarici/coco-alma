import argparse
import subprocess as sp
import os, time, re, sys, json
import binascii as ba

OTBN_CFG_DIR = os.path.dirname(os.path.realpath(__file__))
TMP_DIR = "/".join(OTBN_CFG_DIR.split("/")[:-2]) + "/tmp"
ASM_CMD = None
OBJDUMP_CMD = None
OPENTITAN_DIR = None
VERILATED_CMD = None

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
        OBJDUMP_CMD = opts.get("objdump")
        ASM_CMD = opts.get("asm")
        OPENTITAN_DIR = opts.get("opentitan_dir")
        VERILATED_CMD = opts.get("verilated_dir")
        VERILATOR_AT_LEAST_4_200 = opts.get("verilator_at_least_4_200", False)
except FileNotFoundError as e:
    print(e)

if not isinstance(ASM_CMD, str) or not isinstance(OBJDUMP_CMD, str):
    print("Invalid config.json file contents")
    sys.exit(1)

ASM_CMD = ASM_CMD.split()
OBJDUMP_CMD = OBJDUMP_CMD.split()
VERILATED_CMD = VERILATED_CMD.split()
check_file_exists(ASM_CMD[0])
check_file_exists(OBJDUMP_CMD[0])

def parse_arguments():
    parser = argparse.ArgumentParser(description="Assemble.py for ibex")
    parser.add_argument("--program", dest="program_path", required=True)
    parser.add_argument("--verilate", dest="verilate", required=True)
    args = parser.parse_args()
    check_file_exists(args.program_path)
    return args

def assemble_and_link(args):
    print("Generating otbn binary using program file: ", args.program_path)

    cmd = ASM_CMD + ["-o", args.program_path[:-2] + ".o", args.program_path]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

    cmd = OBJDUMP_CMD + ["-o", args.program_path[:-2] + ".elf", args.program_path[:-2] + ".o"]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

def verilate_otbn(args):
    if args.verilate == "true":
        print("Verilating...")

        retval = os.getcwd()
        os.chdir(OPENTITAN_DIR)

        bashCommand = "fusesoc --cores-root=. run --target=sim --setup --build lowrisc:ip:otbn_top_sim"
        p = sp.Popen(bashCommand.split(), stdout=sp.PIPE, stderr=sp.PIPE)
        p.wait()
        output = (p.stdout.read() + p.stderr.read()).decode("ascii")
        print(output)

        os.chdir(retval)
    
def gen_trace(args):
    print("Generating trace...")

    cmd = VERILATED_CMD + ["--load-elf", args.program_path[:-2] + ".elf", "-t"]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

    cmd = ["fst2vcd", "-f", "sim.fst", "-o", "../../tmp/circuit.vcd"]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

    cmd = ["rm", "sim.fst"]
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    output = (p.stdout.read() + p.stderr.read()).decode("ascii")
    print(output)

def main():
    args = parse_arguments()
    assemble_and_link(args)
    verilate_otbn(args)
    gen_trace(args)

if __name__ == "__main__":
    main()
