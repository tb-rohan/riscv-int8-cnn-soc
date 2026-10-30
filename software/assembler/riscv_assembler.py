
"""
RISC-V RV32I Assembler
Encodes standard RV32I assembly instructions and pseudoinstructions into
binary machine code and Verilog $readmemh hex files.
"""

import sys 
import re 
from pathlib import Path 
from typing import Dict ,List ,Tuple 

REGISTERS ={

"zero":0 ,"ra":1 ,"sp":2 ,"gp":3 ,"tp":4 ,
"t0":5 ,"t1":6 ,"t2":7 ,"s0":8 ,"fp":8 ,"s1":9 ,
"a0":10 ,"a1":11 ,"a2":12 ,"a3":13 ,"a4":14 ,"a5":15 ,"a6":16 ,"a7":17 ,
"s2":18 ,"s3":19 ,"s4":20 ,"s5":21 ,"s6":22 ,"s7":23 ,
"s8":24 ,"s9":25 ,"s10":26 ,"s11":27 ,"t3":28 ,"t4":29 ,"t5":30 ,"t6":31 ,
}

for i in range (32 ):
    REGISTERS [f"x{i }"]=i 


def parse_reg (token :str )->int :
    token =token .strip ().rstrip (",").lower ()
    if token in REGISTERS :
        return REGISTERS [token ]
    raise ValueError (f"Unknown register '{token }'")


def parse_imm (val_str :str ,labels :Dict [str ,int ]=None ,current_pc :int =0 )->int :
    val_str =val_str .strip ().rstrip (",")

    if labels and val_str in labels :
        return labels [val_str ]

    hi_match =re .match (r"%hi\((.*?)\)",val_str )
    if hi_match :
        target =hi_match .group (1 )
        addr =parse_imm (target ,labels ,current_pc )

        return ((addr +0x800 )>>12 )&0xFFFFF 
    lo_match =re .match (r"%lo\((.*?)\)",val_str )
    if lo_match :
        target =lo_match .group (1 )
        addr =parse_imm (target ,labels ,current_pc )
        return addr &0xFFF 

    if val_str .startswith ("0x")or val_str .startswith ("0X"):
        return int (val_str ,16 )
    if val_str .startswith ("0b")or val_str .startswith ("0B"):
        return int (val_str ,2 )
    return int (val_str )


def parse_mem_operand (op :str )->Tuple [int ,str ]:
    """Parses offset(rs1) e.g., 8(sp), %lo(var)(t0), (a0)"""
    op =op .strip ().rstrip (",")
    m =re .match (r"^(.*?)\((.*?)\)$",op )
    if not m :
        raise ValueError (f"Invalid memory operand '{op }'")
    offset_str =m .group (1 ).strip ()
    if not offset_str :
        offset_str ="0"
    reg_str =m .group (2 ).strip ()
    rs1 =parse_reg (reg_str )
    return rs1 ,offset_str 



def encode_r (opcode :int ,funct3 :int ,funct7 :int ,rd :int ,rs1 :int ,rs2 :int )->int :
    return (
    ((funct7 &0x7F )<<25 )
    |((rs2 &0x1F )<<20 )
    |((rs1 &0x1F )<<15 )
    |((funct3 &0x07 )<<12 )
    |((rd &0x1F )<<7 )
    |(opcode &0x7F )
    )


def encode_i (opcode :int ,funct3 :int ,rd :int ,rs1 :int ,imm :int )->int :
    return (
    ((imm &0xFFF )<<20 )
    |((rs1 &0x1F )<<15 )
    |((funct3 &0x07 )<<12 )
    |((rd &0x1F )<<7 )
    |(opcode &0x7F )
    )


def encode_s (opcode :int ,funct3 :int ,rs1 :int ,rs2 :int ,imm :int )->int :
    imm11_5 =(imm >>5 )&0x7F 
    imm4_0 =imm &0x1F 
    return (
    (imm11_5 <<25 )
    |((rs2 &0x1F )<<20 )
    |((rs1 &0x1F )<<15 )
    |((funct3 &0x07 )<<12 )
    |(imm4_0 <<7 )
    |(opcode &0x7F )
    )


def encode_b (opcode :int ,funct3 :int ,rs1 :int ,rs2 :int ,offset :int )->int :

    imm12 =(offset >>12 )&0x01 
    imm10_5 =(offset >>5 )&0x3F 
    imm4_1 =(offset >>1 )&0x0F 
    imm11 =(offset >>11 )&0x01 
    return (
    (imm12 <<31 )
    |(imm10_5 <<25 )
    |((rs2 &0x1F )<<20 )
    |((rs1 &0x1F )<<15 )
    |((funct3 &0x07 )<<12 )
    |(imm4_1 <<8 )
    |(imm11 <<7 )
    |(opcode &0x7F )
    )


def encode_u (opcode :int ,rd :int ,imm :int )->int :
    return ((imm &0xFFFFF )<<12 )|((rd &0x1F )<<7 )|(opcode &0x7F )


def encode_j (opcode :int ,rd :int ,offset :int )->int :

    imm20 =(offset >>20 )&0x01 
    imm10_1 =(offset >>1 )&0x3FF 
    imm11 =(offset >>11 )&0x01 
    imm19_12 =(offset >>12 )&0xFF 
    return (
    (imm20 <<31 )
    |(imm10_1 <<21 )
    |(imm11 <<20 )
    |(imm19_12 <<12 )
    |((rd &0x1F )<<7 )
    |(opcode &0x7F )
    )


class Assembler :
    def __init__ (self ):
        self .labels :Dict [str ,int ]={}
        self .constants :Dict [str ,int ]={}

    def expand_pseudoinstructions (self ,lines :List [Tuple [int ,str ]])->List [Tuple [int ,str ]]:
        expanded =[]
        for line_no ,raw in lines :
            line =raw .strip ()
            if not line or line .startswith ("#")or line .startswith ("//"):
                continue 


            line =re .sub (r"(#|//).*$","",line ).strip ()
            if not line :
                continue 


            if ":"in line :
                parts =line .split (":",1 )
                label =parts [0 ].strip ()
                expanded .append ((line_no ,f"{label }:"))
                line =parts [1 ].strip ()
                if not line :
                    continue 

            tokens =line .split (None ,1 )
            mnemonic =tokens [0 ].lower ()
            args_str =tokens [1 ].strip ()if len (tokens )>1 else ""
            args =[a .strip ()for a in args_str .split (",")if a .strip ()]


            if mnemonic =="nop":
                expanded .append ((line_no ,"addi x0, x0, 0"))
            elif mnemonic =="li":

                rd =args [0 ]
                val_str =args [1 ]
                try :
                    val =parse_imm (val_str ,self .constants )
                    if -2048 <=val <=2047 :
                        expanded .append ((line_no ,f"addi {rd }, x0, {val }"))
                    else :
                        hi =((val +0x800 )>>12 )&0xFFFFF 
                        lo =val -(hi <<12 )
                        expanded .append ((line_no ,f"lui {rd }, {hi }"))
                        if lo !=0 :
                            expanded .append ((line_no ,f"addi {rd }, {rd }, {lo }"))
                except Exception :

                    expanded .append ((line_no ,f"lui {rd }, %hi({val_str })"))
                    expanded .append ((line_no ,f"addi {rd }, {rd }, %lo({val_str })"))
            elif mnemonic =="la":
                rd =args [0 ]
                sym =args [1 ]
                expanded .append ((line_no ,f"lui {rd }, %hi({sym })"))
                expanded .append ((line_no ,f"addi {rd }, {rd }, %lo({sym })"))
            elif mnemonic =="mv":
                expanded .append ((line_no ,f"addi {args [0 ]}, {args [1 ]}, 0"))
            elif mnemonic =="not":
                expanded .append ((line_no ,f"xori {args [0 ]}, {args [1 ]}, -1"))
            elif mnemonic =="neg":
                expanded .append ((line_no ,f"sub {args [0 ]}, x0, {args [1 ]}"))
            elif mnemonic =="j":
                expanded .append ((line_no ,f"jal x0, {args [0 ]}"))
            elif mnemonic =="jr":
                expanded .append ((line_no ,f"jalr x0, {args [0 ]}, 0"))
            elif mnemonic =="ret":
                expanded .append ((line_no ,"jalr x0, ra, 0"))
            elif mnemonic =="call":
                expanded .append ((line_no ,f"jal ra, {args [0 ]}"))
            elif mnemonic =="bgt":
                expanded .append ((line_no ,f"blt {args [1 ]}, {args [0 ]}, {args [2 ]}"))
            elif mnemonic =="ble":
                expanded .append ((line_no ,f"bge {args [1 ]}, {args [0 ]}, {args [2 ]}"))
            elif mnemonic =="bgtu":
                expanded .append ((line_no ,f"bltu {args [1 ]}, {args [0 ]}, {args [2 ]}"))
            elif mnemonic =="bleu":
                expanded .append ((line_no ,f"bgeu {args [1 ]}, {args [0 ]}, {args [2 ]}"))
            elif mnemonic =="beqz":
                expanded .append ((line_no ,f"beq {args [0 ]}, x0, {args [1 ]}"))
            elif mnemonic =="bnez":
                expanded .append ((line_no ,f"bne {args [0 ]}, x0, {args [1 ]}"))
            elif mnemonic =="bgez":
                expanded .append ((line_no ,f"bge {args [0 ]}, x0, {args [1 ]}"))
            elif mnemonic =="bltz":
                expanded .append ((line_no ,f"blt {args [0 ]}, x0, {args [1 ]}"))
            elif mnemonic =="blez":
                expanded .append ((line_no ,f"bge x0, {args [0 ]}, {args [1 ]}"))
            elif mnemonic =="bgtz":
                expanded .append ((line_no ,f"blt x0, {args [0 ]}, {args [1 ]}"))
            elif mnemonic =="seqz":
                expanded .append ((line_no ,f"sltiu {args [0 ]}, {args [1 ]}, 1"))
            elif mnemonic =="snez":
                expanded .append ((line_no ,f"sltu {args [0 ]}, x0, {args [1 ]}"))
            elif mnemonic =="sltz":
                expanded .append ((line_no ,f"slt {args [0 ]}, {args [1 ]}, x0"))
            elif mnemonic =="sgtz":
                expanded .append ((line_no ,f"slt {args [0 ]}, x0, {args [1 ]}"))
            else :
                expanded .append ((line_no ,line ))
        return expanded 

    def assemble (self ,source_text :str )->List [int ]:
        raw_lines =[(i +1 ,l )for i ,l in enumerate (source_text .splitlines ())]
        lines =self .expand_pseudoinstructions (raw_lines )


        pc =0 
        instructions =[]
        for line_no ,line in lines :
            line =line .strip ()
            if not line :
                continue 
            if line .endswith (":"):
                lbl =line [:-1 ].strip ()
                self .labels [lbl ]=pc 
                continue 
            if line .startswith ("."):

                parts =line .split (None ,1 )
                directive =parts [0 ].lower ()
                arg =parts [1 ].strip ()if len (parts )>1 else ""
                if directive ==".equ":
                    eq_parts =[p .strip ()for p in arg .split (",",1 )]
                    val =parse_imm (eq_parts [1 ],self .constants )
                    self .constants [eq_parts [0 ]]=val 
                    self .labels [eq_parts [0 ]]=val 
                elif directive in (".word",".byte",".string",".ascii"):
                    pass 
                continue 

            instructions .append ((pc ,line_no ,line ))
            pc +=4 


        machine_words =[]
        for curr_pc ,line_no ,line in instructions :
            tokens =line .split (None ,1 )
            mnemonic =tokens [0 ].lower ()
            args_str =tokens [1 ].strip ()if len (tokens )>1 else ""
            args =[a .strip ()for a in args_str .split (",")if a .strip ()]

            word =self .encode_instruction (mnemonic ,args ,curr_pc )
            machine_words .append (word )

        return machine_words 

    def encode_instruction (self ,mnemonic :str ,args :List [str ],pc :int )->int :
        labels ={**self .constants ,**self .labels }


        r_ops ={
        "add":(0x33 ,0x0 ,0x00 ),"sub":(0x33 ,0x0 ,0x20 ),
        "sll":(0x33 ,0x1 ,0x00 ),"slt":(0x33 ,0x2 ,0x00 ),
        "sltu":(0x33 ,0x3 ,0x00 ),"xor":(0x33 ,0x4 ,0x00 ),
        "srl":(0x33 ,0x5 ,0x00 ),"sra":(0x33 ,0x5 ,0x20 ),
        "or":(0x33 ,0x6 ,0x00 ),"and":(0x33 ,0x7 ,0x00 ),
        }
        if mnemonic in r_ops :
            opcode ,f3 ,f7 =r_ops [mnemonic ]
            return encode_r (opcode ,f3 ,f7 ,parse_reg (args [0 ]),parse_reg (args [1 ]),parse_reg (args [2 ]))


        i_ops ={
        "addi":(0x13 ,0x0 ),"slti":(0x13 ,0x2 ),"sltiu":(0x13 ,0x3 ),
        "xori":(0x13 ,0x4 ),"ori":(0x13 ,0x6 ),"andi":(0x13 ,0x7 ),
        "slli":(0x13 ,0x1 ),"srli":(0x13 ,0x5 ),"srai":(0x13 ,0x5 ),
        }
        if mnemonic in i_ops :
            opcode ,f3 =i_ops [mnemonic ]
            rd =parse_reg (args [0 ])
            rs1 =parse_reg (args [1 ])
            imm =parse_imm (args [2 ],labels ,pc )
            if mnemonic =="srai":
                imm =(imm &0x1F )|0x400 
            elif mnemonic in ("slli","srli"):
                imm =imm &0x1F 
            return encode_i (opcode ,f3 ,rd ,rs1 ,imm )


        load_ops ={
        "lb":(0x03 ,0x0 ),"lh":(0x03 ,0x1 ),"lw":(0x03 ,0x2 ),
        "lbu":(0x03 ,0x4 ),"lhu":(0x03 ,0x5 ),
        }
        if mnemonic in load_ops :
            opcode ,f3 =load_ops [mnemonic ]
            rd =parse_reg (args [0 ])
            rs1 ,offset_str =parse_mem_operand (args [1 ])
            offset =parse_imm (offset_str ,labels ,pc )
            return encode_i (opcode ,f3 ,rd ,rs1 ,offset )


        store_ops ={
        "sb":(0x23 ,0x0 ),"sh":(0x23 ,0x1 ),"sw":(0x23 ,0x2 ),
        }
        if mnemonic in store_ops :
            opcode ,f3 =store_ops [mnemonic ]
            rs2 =parse_reg (args [0 ])
            rs1 ,offset_str =parse_mem_operand (args [1 ])
            offset =parse_imm (offset_str ,labels ,pc )
            return encode_s (opcode ,f3 ,rs1 ,rs2 ,offset )


        branch_ops ={
        "beq":(0x63 ,0x0 ),"bne":(0x63 ,0x1 ),
        "blt":(0x63 ,0x4 ),"bge":(0x63 ,0x5 ),
        "bltu":(0x63 ,0x6 ),"bgeu":(0x63 ,0x7 ),
        }
        if mnemonic in branch_ops :
            opcode ,f3 =branch_ops [mnemonic ]
            rs1 =parse_reg (args [0 ])
            rs2 =parse_reg (args [1 ])
            target =parse_imm (args [2 ],labels ,pc )
            offset =target -pc 
            return encode_b (opcode ,f3 ,rs1 ,rs2 ,offset )


        if mnemonic =="lui":
            rd =parse_reg (args [0 ])
            imm =parse_imm (args [1 ],labels ,pc )
            return encode_u (0x37 ,rd ,imm )
        if mnemonic =="auipc":
            rd =parse_reg (args [0 ])
            imm =parse_imm (args [1 ],labels ,pc )
            return encode_u (0x17 ,rd ,imm )


        if mnemonic =="jal":
            if len (args )==1 :
                rd =1 
                target =parse_imm (args [0 ],labels ,pc )
            else :
                rd =parse_reg (args [0 ])
                target =parse_imm (args [1 ],labels ,pc )
            offset =target -pc 
            return encode_j (0x6F ,rd ,offset )

        if mnemonic =="jalr":
            rd =parse_reg (args [0 ])
            if len (args )==2 :

                if "("in args [1 ]:
                    rs1 ,offset_str =parse_mem_operand (args [1 ])
                    imm =parse_imm (offset_str ,labels ,pc )
                else :
                    rs1 =parse_reg (args [1 ])
                    imm =0 
            else :

                rs1 =parse_reg (args [1 ])
                imm =parse_imm (args [2 ],labels ,pc )
            return encode_i (0x67 ,0x0 ,rd ,rs1 ,imm )


        if mnemonic =="ecall":
            return 0x00000073 
        if mnemonic =="ebreak":
            return 0x00100073 
        if mnemonic =="fence":
            return 0x0FF0000F 

        raise ValueError (f"Unsupported instruction '{mnemonic }'")


def self_test ():
    """Validates assembler output against known RV32I encodings."""
    asm =Assembler ()
    tests =[
    ("addi x1, x0, 42",0x02A00093 ),
    ("add x3, x1, x2",0x002081B3 ),
    ("sub x4, x3, x1",0x40118233 ),
    ("lui x5, 0x12345",0x123452B7 ),
    ("lw x6, 8(x2)",0x00812303 ),
    ("sw x6, 12(x2)",0x00612623 ),
    ("srai x7, x7, 4",0x4043D393 ),
    ("jal x0, 0",0x0000006F ),
    ]
    for code ,expected in tests :
        res =asm .assemble (code )[0 ]
        assert res ==expected ,f"Failed {code }: got 0x{res :08x}, expected 0x{expected :08x}"
    print ("Assembler self-test PASSED!")


def main ():
    if len (sys .argv )<2 :
        print ("Running self-test...")
        self_test ()
        sys .exit (0 )

    in_path =Path (sys .argv [1 ])
    out_path =Path (sys .argv [2 ])if len (sys .argv )>2 else in_path .with_suffix (".hex")

    with open (in_path ,"r",encoding ="utf-8")as f :
        src =f .read ()

    assembler =Assembler ()
    words =assembler .assemble (src )

    with open (out_path ,"w",encoding ="ascii")as f :
        for w in words :
            f .write (f"{w :08x}\n")

    print (f"Assembled {len (words )} instructions -> {out_path }")


if __name__ =="__main__":
    main ()
