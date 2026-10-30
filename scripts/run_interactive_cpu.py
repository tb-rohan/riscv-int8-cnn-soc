
"""
RISC-V Interactive CPU Terminal Interface
Allows interactive calculation, custom program execution, and verification
against an independent Python reference model running on the real RV32I RTL datapath.
"""

import sys 
import os 
import subprocess 
import random 
import argparse 
from pathlib import Path 

ROOT =Path (__file__ ).resolve ().parents [1 ]
ASM_DIR =ROOT /"software"/"asm"
TB_DIR =ROOT /"tb"/"cpu"
RTL_DIR =ROOT /"rtl"
BIN_VVP =ROOT /"bin_cpu_interactive.vvp"

OP_NAMES ={
1 :"Addition",
2 :"Subtraction",
3 :"Multiplication",
4 :"Division",
5 :"Bitwise AND",
6 :"Bitwise OR",
7 :"Bitwise XOR",
8 :"Bitwise NOT",
9 :"Left shift",
10 :"Logical right shift",
11 :"Arithmetic right shift",
12 :"Signed comparison",
13 :"Unsigned comparison",
14 :"Full RV32I ISA Verification (37 Instructions)",
}


def python_reference (cmd :int ,a :int ,b :int ):
    """Independent Python golden model for arithmetic operations."""

    a_u32 =a &0xFFFFFFFF 
    b_u32 =b &0xFFFFFFFF 
    a_s32 =a_u32 if a_u32 <0x80000000 else a_u32 -0x100000000 
    b_s32 =b_u32 if b_u32 <0x80000000 else b_u32 -0x100000000 

    if cmd ==1 :
        res =(a_s32 +b_s32 )&0xFFFFFFFF 
        res_s =res if res <0x80000000 else res -0x100000000 
        return res_s ,0 
    elif cmd ==2 :
        res =(a_s32 -b_s32 )&0xFFFFFFFF 
        res_s =res if res <0x80000000 else res -0x100000000 
        return res_s ,0 
    elif cmd ==3 :
        prod =a_s32 *b_s32 
        lo =prod &0xFFFFFFFF 
        lo_s =lo if lo <0x80000000 else lo -0x100000000 
        hi =(prod >>32 )&0xFFFFFFFF 
        hi_s =hi if hi <0x80000000 else hi -0x100000000 
        return lo_s ,hi_s 
    elif cmd ==4 :
        if b_s32 ==0 :
            return -1 ,a_s32 
        elif a_s32 ==-2147483648 and b_s32 ==-1 :
            return -2147483648 ,0 
        else :

            q =int (abs (a_s32 )//abs (b_s32 ))
            if (a_s32 <0 )^(b_s32 <0 ):
                q =-q 
            r =a_s32 -q *b_s32 
            return q ,r 
    elif cmd ==5 :
        return a_s32 &b_s32 ,0 
    elif cmd ==6 :
        return a_s32 |b_s32 ,0 
    elif cmd ==7 :
        return a_s32 ^b_s32 ,0 
    elif cmd ==8 :
        res =(~a_u32 )&0xFFFFFFFF 
        res_s =res if res <0x80000000 else res -0x100000000 
        return res_s ,0 
    elif cmd ==9 :
        shamt =b_u32 &0x1F 
        res =(a_u32 <<shamt )&0xFFFFFFFF 
        res_s =res if res <0x80000000 else res -0x100000000 
        return res_s ,0 
    elif cmd ==10 :
        shamt =b_u32 &0x1F 
        res =(a_u32 >>shamt )&0xFFFFFFFF 
        res_s =res if res <0x80000000 else res -0x100000000 
        return res_s ,0 
    elif cmd ==11 :
        shamt =b_u32 &0x1F 
        res =(a_s32 >>shamt )&0xFFFFFFFF 
        res_s =res if res <0x80000000 else res -0x100000000 
        return res_s ,0 
    elif cmd ==12 :
        return 1 if a_s32 <b_s32 else 0 ,0 
    elif cmd ==13 :
        return 1 if a_u32 <b_u32 else 0 ,0 
    elif cmd ==14 :
        return 37 ,0x50415353 
    else :
        return 0 ,0 


def ensure_compiled ():
    """Compiles the standalone CPU simulation binary if needed."""
    hex_path =ASM_DIR /"interactive_cpu.hex"
    asm_path =ASM_DIR /"interactive_cpu.s"

    if not hex_path .exists ()or asm_path .stat ().st_mtime >hex_path .stat ().st_mtime :
        print ("[INFO] Assembling interactive_cpu.s...")
        cmd_asm =[sys .executable ,str (ROOT /"software"/"assembler"/"riscv_assembler.py"),str (asm_path ),str (hex_path )]
        subprocess .run (cmd_asm ,check =True )

    sources =[
    "rtl/core/riscv_pkg.sv",
    "rtl/core/alu.sv",
    "rtl/core/regfile.sv",
    "rtl/core/imm_gen.sv",
    "rtl/core/decoder.sv",
    "rtl/core/branch_unit.sv",
    "rtl/core/forwarding_unit.sv",
    "rtl/core/hazard_unit.sv",
    "rtl/core/pipe_reg_if_id.sv",
    "rtl/core/pipe_reg_id_ex.sv",
    "rtl/core/pipe_reg_ex_mem.sv",
    "rtl/core/pipe_reg_mem_wb.sv",
    "rtl/core/load_store_unit.sv",
    "rtl/core/rv32i_core.sv",
    "rtl/memory/ram_sync.sv",
    "rtl/memory/imem.sv",
    "rtl/memory/dmem.sv",
    "rtl/peripherals/host_interface.sv",
    "rtl/peripherals/timer.sv",
    "rtl/peripherals/uart_lite.sv",
    "rtl/interconnect/bus_interconnect.sv",
    "rtl/soc/cpu_standalone_top.sv",
    "tb/cpu/tb_cpu_interactive.sv"
    ]

    rebuild =False 
    if not BIN_VVP .exists ():
        rebuild =True 
    else :
        vvp_mtime =BIN_VVP .stat ().st_mtime 
        for s in sources :
            p =ROOT /s 
            if p .exists ()and p .stat ().st_mtime >vvp_mtime :
                rebuild =True 
                break 

    if rebuild :
        print ("[INFO] Compiling Standalone CPU with iverilog...")
        compile_args =["iverilog","-g2012","-s","tb_cpu_interactive","-o",str (BIN_VVP )]+[str (ROOT /s )for s in sources ]
        res =subprocess .run (compile_args ,cwd =str (ROOT ),capture_output =True ,text =True )
        if res .returncode !=0 :
            print ("[ERROR] iverilog compilation failed:\n",res .stderr )
            sys .exit (res .returncode )


def execute_cpu (cmd :int ,a :int ,b :int ,hex_file :str =None ,vcd_file :str =None ):
    """Executes operation on the simulated RV32I CPU and returns results."""
    ensure_compiled ()
    args =["vvp",str (BIN_VVP ),f"+CMD={cmd }",f"+OP_A={a }",f"+OP_B={b }"]
    if hex_file :
        args .append (f"+HEX={hex_file }")
    if vcd_file :
        args .append (f"+VCD={vcd_file }")

    res =subprocess .run (args ,cwd =str (ROOT ),capture_output =True ,text =True )
    if res .returncode !=0 :
        print ("[ERROR] Simulation failed:\n",res .stderr )
        return None 

    out ={}
    for line in res .stdout .splitlines ():
        line =line .strip ()
        if "="in line :
            k ,v =line .split ("=",1 )
            out [k ]=v 

    if "CPU_RESULT_DEC"not in out :
        print ("[ERROR] Simulation output malformed:\n",res .stdout )
        return None 

    cpu_res =int (out ["CPU_RESULT_DEC"])
    cpu_res_hi =int (out .get ("CPU_RESULT_HI_DEC",0 ))
    cycles =int (out .get ("CPU_CYCLES",0 ))
    status =out .get ("CPU_STATUS","FAIL")

    return {
    "result":cpu_res ,
    "result_hi":cpu_res_hi ,
    "cycles":cycles ,
    "status":status ,
    "raw_output":res .stdout 
    }


def print_menu ():
    print ("========================================")
    print ("RISC-V INTERACTIVE CPU")
    print ("========================================")
    for i in range (1 ,14 ):
        print (f"{i :2d}. {OP_NAMES [i ]}")
    print ("14. Run custom RISC-V program")
    print ("15. Inspect CPU state / Register test")
    print ("16. Run randomized CPU tests")
    print ("17. Exit")
    print ("========================================")


def parse_int_input (prompt :str )->int :
    while True :
        try :
            val_str =input (prompt ).strip ()
            if val_str .lower ().startswith ("0x"):
                return int (val_str ,16 )
            return int (val_str )
        except ValueError :
            print ("Invalid integer. Please enter a valid decimal (e.g. 42, -15) or hex (e.g. 0x2A).")


def run_random_suite (count :int =100 ,seed :int =42 ):
    print (f"\n[RANDOM TEST] Running {count } randomized CPU operations (Seed={seed })...")
    random .seed (seed )
    passed =0 
    failed =0 

    edge_values =[
    0 ,1 ,-1 ,2 ,-2 ,7 ,-7 ,15 ,-15 ,31 ,32 ,
    127 ,-128 ,255 ,-256 ,32767 ,-32768 ,65535 ,
    2147483647 ,-2147483648 ,0x55555555 ,0xAAAAAAAA ,0xFFFFFFFF 
    ]

    for i in range (count ):
        cmd =random .randint (1 ,13 )
        if random .random ()<0.4 :
            a =random .choice (edge_values )
            b =random .choice (edge_values )
        else :
            a =random .randint (-2147483648 ,2147483647 )
            b =random .randint (-2147483648 ,2147483647 )


        if cmd in (9 ,10 ,11 ):
            b =b &0x1F 

        exp_lo ,exp_hi =python_reference (cmd ,a ,b )
        dut_res =execute_cpu (cmd ,a ,b )

        if not dut_res or dut_res ["status"]!="PASS":
            print (f"[FAIL] Test {i +1 }: CMD={cmd } ({OP_NAMES [cmd ]}), A={a }, B={b } -> Execution Failed")
            failed +=1 
            continue 

        match =(dut_res ["result"]==exp_lo )
        if cmd in (3 ,4 ):
            if dut_res ["result_hi"]!=exp_hi :
                match =False 

        if match :
            passed +=1 
        else :
            print (f"[FAIL] Test {i +1 }: CMD={cmd } ({OP_NAMES [cmd ]}), A={a }, B={b }")
            print (f"       DUT : Res={dut_res ['result']} (0x{dut_res ['result']&0xFFFFFFFF :08x}), ResHi={dut_res ['result_hi']}")
            print (f"       GOLD: Res={exp_lo } (0x{exp_lo &0xFFFFFFFF :08x}), ResHi={exp_hi }")
            failed +=1 

    print (f"\nRandomized Test Summary: {passed }/{count } PASSED ({failed } failed)\n")
    return failed ==0 


def interactive_loop ():
    while True :
        print_menu ()
        choice_str =input ("Select operation (1-17): ").strip ()
        if not choice_str .isdigit ():
            print ("Please enter a valid numeric choice.")
            continue 
        choice =int (choice_str )

        if choice ==17 :
            print ("Exiting interactive CPU. Goodbye!")
            break 
        elif 1 <=choice <=13 :
            op_name =OP_NAMES [choice ]
            print (f"\n--- {op_name } ---")
            a =parse_int_input ("Enter Operand A: ")
            if choice ==8 :
                b =0 
            else :
                b =parse_int_input ("Enter Operand B: ")

            print (f"\n[CPU] Executing {op_name }: A = {a }, B = {b }...")
            res =execute_cpu (choice ,a ,b )
            if res :
                exp_lo ,exp_hi =python_reference (choice ,a ,b )
                match =(res ["result"]==exp_lo )
                if choice in (3 ,4 ):
                    match =match and (res ["result_hi"]==exp_hi )

                print ("\n================ OUTPUT ================")
                print (f"Operation        : {op_name }")
                print (f"Operand A        : {a } (0x{a &0xFFFFFFFF :08x})")
                if choice !=8 :
                    print (f"Operand B        : {b } (0x{b &0xFFFFFFFF :08x})")
                print (f"CPU Result       : {res ['result']} (0x{res ['result']&0xFFFFFFFF :08x})")
                if choice ==3 :
                    print (f"CPU Product High : {res ['result_hi']} (0x{res ['result_hi']&0xFFFFFFFF :08x})")
                elif choice ==4 :
                    print (f"CPU Remainder    : {res ['result_hi']} (0x{res ['result_hi']&0xFFFFFFFF :08x})")
                print (f"Reference Result : {exp_lo } (0x{exp_lo &0xFFFFFFFF :08x})")
                print (f"CPU Cycles       : {res ['cycles']}")
                print (f"CPU verification : {'PASS'if match else 'FAIL'}")
                print ("========================================\n")
            else :
                print ("[ERROR] CPU execution failed.")

        elif choice ==14 :
            print ("\n--- Run Custom RISC-V Program ---")
            asm_file =input ("Enter path to assembly (.s) or hex (.hex) file: ").strip ()
            path =Path (asm_file ).resolve ()
            if not path .is_file ():
                print (f"File not found: {path }")
                continue 
            if path .suffix ==".s":
                hex_target =path .with_suffix (".hex")
                print (f"Assembling {path } -> {hex_target }...")
                subprocess .run ([sys .executable ,str (ROOT /"software"/"assembler"/"riscv_assembler.py"),str (path ),str (hex_target )],check =True )
                path =hex_target 
            print (f"Running {path } on simulated RISC-V core...")
            res =execute_cpu (1 ,0 ,0 ,hex_file =str (path ).replace ("\\","/"))
            if res :
                print ("\n================ OUTPUT ================")
                print (f"Result           : {res ['result']} (0x{res ['result']&0xFFFFFFFF :08x})")
                print (f"Cycles           : {res ['cycles']}")
                print (f"Status           : {res ['status']}")
                print ("========================================\n")

        elif choice ==15 :
            print ("\n--- Inspect CPU State ---")
            res =execute_cpu (1 ,0 ,0 )
            if res :
                print (f"Core Status      : Operational (RV32I 5-stage pipeline)")
                print (f"Reset Vector     : 0x00000000")
                print (f"Host Interface   : 0x80000000 (Active)")
                print (f"Instruction RAM  : 16 KB (0x00000000 - 0x00003FFF)")
                print (f"Data RAM         : 16 KB (0x00004000 - 0x00007FFF)")
                print (f"Cycles Elapsed   : {res ['cycles']}")
                print (f"Status           : READY\n")

        elif choice ==16 :
            cnt_str =input ("Enter number of tests (default 50): ").strip ()
            cnt =int (cnt_str )if cnt_str .isdigit ()else 50 
            seed_str =input ("Enter random seed (default 42): ").strip ()
            seed =int (seed_str )if seed_str .isdigit ()else 42 
            run_random_suite (count =cnt ,seed =seed )


def main ():
    parser =argparse .ArgumentParser (description ="RISC-V Interactive CPU & Verification Suite")
    parser .add_argument ("--cmd",type =int ,choices =range (1 ,15 ),help ="Operation opcode (1..14)")
    parser .add_argument ("--op_a",type =int ,default =0 ,help ="Operand A")
    parser .add_argument ("--op_b",type =int ,default =0 ,help ="Operand B")
    parser .add_argument ("--random",action ="store_true",help ="Run randomized verification suite")
    parser .add_argument ("--count",type =int ,default =100 ,help ="Number of random tests")
    parser .add_argument ("--seed",type =int ,default =42 ,help ="Random seed")
    parser .add_argument ("--vcd",type =str ,help ="Generate VCD waveform file")
    args =parser .parse_args ()

    if args .random :
        success =run_random_suite (count =args .count ,seed =args .seed )
        sys .exit (0 if success else 1 )

    if args .cmd is not None :
        res =execute_cpu (args .cmd ,args .op_a ,args .op_b ,vcd_file =args .vcd )
        if not res :
            sys .exit (1 )
        exp_lo ,exp_hi =python_reference (args .cmd ,args .op_a ,args .op_b )
        match =(res ["result"]==exp_lo )
        if args .cmd in (3 ,4 ,14 ):
            match =match and (res ["result_hi"]==exp_hi )
        print (f"Result = {res ['result']}")
        print (f"CPU verification = {'PASS'if match else 'FAIL'}")
        sys .exit (0 if match else 1 )


    interactive_loop ()


if __name__ =="__main__":
    main ()
