Mach_O :: struct {
    header: *Mach_Header;
    load_commands: [] *Load_Command;
    sections: [..] *Section_64;
    symbols: [..] Mach_Symbol;

    debug_info_section: *Section_64;
    debug_abbrev_section: *Section_64;
    debug_str_section: *Section_64;
    debug_line_section: *Section_64;

    content: string; // The whole file content.
}

parse_macho_file :: (path: string) -> success: bool, Mach_O {
    macho: Mach_O = ---;
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, macho;
    }

    success, macho = parse_macho(content);
    return success, macho;
}

is_macho :: (file_content: string) -> bool {
    if file_content.count < size_of(Mach_Header) return false;
    header := cast(*Mach_Header) file_content.data;
    // @Incomplete: It could be eg. an ARM binary, but we don’t care for those yet.
    return header.magic == MH_MAGIC_64;
}

parse_macho :: (file_content: string, path := "(unspecified file)") -> success: bool, Mach_O {
    check :: (condition: bool, message: string, args: .. Any) #expand {
        if !condition {
            log_error(message, ..args);
            `return false, macho;
        }
    } @PrintLike

    using macho: Mach_O;

    content = file_content;

    check(content.count >= size_of(Mach_Header), "File is too small to be a Mach-O binary: %", path);

    macho.header = cast(*Mach_Header) macho.content.data;
    // log("Mach-O header: %\n", header.*);

    check(header.magic == MH_MAGIC_64, "File does not appear to be a 64bit Mach-O binary: %", path);

    load_command_offset := size_of(Mach_Header);

    load_commands_end := load_command_offset + header.sizeofcmds;
    check(load_commands_end <= content.count, "Command size is out of bounds: %", header.sizeofcmds);

    load_commands = NewArray(header.ncmds, *Load_Command);
    for i: 0..header.ncmds-1 {
        check(load_command_offset + size_of(Load_Command) <= macho.content.count, "Unexpected end while parsing load command %", i);

        command := cast(*Load_Command) (macho.content.data + load_command_offset);
        // log("Command %: %", i, command.*);
        load_commands[i] = command;

        command_end := load_command_offset + command.cmdsize;
        check(command_end <= load_commands_end, "Command % extends beyond the size of all load commands indicated in the header: %", i, command.*);

        if command.cmd == {
            case .SEGMENT_64;
                check(command.cmdsize >= size_of(Segment_Command_64), "Unexpected size of command %: %", i, command.*);

                segment_command := cast(*Segment_Command_64) command;
                // log("Segment command: %", segment_command.*);
                check(segment_command.fileoff <= cast(u64) content.count, "Command %: Segment offset is out of bounds", i);

                segment_end := segment_command.fileoff + segment_command.filesize;
                check(segment_end <= cast(u64) content.count, "Command %: Segment size is out of bounds", i);

                // @ToDo: check sizeof(segment_command_64 + (sizeof(section_64) * segment->nsect))).

                section_offset := cast(u64) (load_command_offset + size_of(Segment_Command_64));
                for s: 0..cast(s64)segment_command.nsects-1 {
                    section_end := section_offset + size_of(Section_64);
                    check(section_end <= cast(u64) command_end, "Unexpected end while parsing section % of segment %: % vs %", s, i, section_end, command_end);

                    section := cast(*Section_64) (content.data + section_offset);
                    section_offset += size_of(Section_64);

                    check(section_offset <= cast(u64) command_end, "Section % of segment % is out of bounds", s, i);
                    // log("Section: %", section).*;

                    array_add(*sections, section);

                    maybe_set_debug_section :: (index: int, section: *Section_64, name: string, target: **Section_64) -> bool {
                        section_name := to_string(section.sectname.data);
                        if section_name != name then return true;

                        // if section.flags & .ATTR_DEBUG == 0 {
                        //     log_error("% section at % is not flagged as a debug section: %", name, index, formatStruct(section.*, use_long_form_if_more_than_this_many_members = 0));
                        //     return false;
                        // }
                        if target.* {
                            log_error("Found another % section at %", name, index);
                            return false;
                        }

                        target.* = section;
                        return true;
                    }

                    if !maybe_set_debug_section(s, section, "__debug_info",   *macho.debug_info_section) then return false, macho;
                    if !maybe_set_debug_section(s, section, "__debug_abbrev", *macho.debug_abbrev_section) then return false, macho;
                    if !maybe_set_debug_section(s, section, "__debug_line",   *macho.debug_line_section) then return false, macho;
                    if !maybe_set_debug_section(s, section, "__debug_str",    *macho.debug_str_section) then return false, macho;
                }
            case .SYMTAB;
                check(command.cmdsize >= size_of(Symtab_Command), "Unexpected size of command %: %", i, command.*);
                symtab_command := cast(*Symtab_Command) command;
                check(symtab_command.symoff <= content.count, "Command %: Symbol table offset is out of bounds", i);
                symbol_end := symtab_command.symoff + (symtab_command.nsyms * size_of(nlist_64));
                check(symbol_end <= content.count, "Command %: Symbol table end is out of bounds", i);
                check(symtab_command.stroff <= content.count, "Command %: String table offset is out of bounds", i);
                check(symtab_command.stroff + symtab_command.strsize <= content.count, "Command %: String table end is out of bounds", i);

                raw_symbols: [] nlist_64;
                raw_symbols.data = cast(*nlist_64)(macho.content.data + symtab_command.symoff);
                raw_symbols.count = symtab_command.nsyms;
                string_table: *u8 = macho.content.data + symtab_command.stroff;
                array_reserve(*symbols, symbols.count + raw_symbols.count);
                for raw_symbols {
                    s: Mach_Symbol;
                    string_index := it.n_un.n_strx;
                    if string_index {
                        check(string_index < symtab_command.strsize, "Command %: String offset % is out of bounds", i, string_index);
                        s.name = to_string(string_table + string_index);
                        check(string_index + s.name.count < symtab_command.strsize, "Command %: String at offset % is out of bounds", i, string_index);
                    }

                    stab := it.n_type & N_STAB;
                    if stab {
                        s.flags |= .SYMBOLIC;
                        s.type.symbolic_type = xx it.n_type;
                    } else {
                        is_external         := it.n_type & N_EXT;
                        is_private_external := it.n_type & N_PEXT;
                        if is_external         s.flags |= .EXTERNAL;
                        if is_private_external s.flags |= .PRIVATE_EXTERNAL;
                        s.type.type          = xx (it.n_type & N_TYPE);
                    }

                    s.description = it.n_desc;
                    s.value = it.n_value;
                    s.section = it.n_sect;

                    array_add(*symbols, s);
                }
        }

        load_command_offset += command.cmdsize;

        check(load_command_offset <= macho.content.count, "Command % is out of bounds", i);
    }

    return true, macho;
}

get_section_data :: (macho: Mach_O, section: *Section_64) -> [] u8 {
    if !section                   return .[];
    if section.flags & .ZEROFILL && section.offset == 0 {
        // Don’t try to lookup ZEROFILL sections without offsets (BSS)
        // Unfortunately, some sections are flagged as ZEROFILL
        // despite containing data (eg. eh_frame when emitted by LLVM on macOS),
        // so we can’t just use the ZEROFILL flag and have to hope that all truly empty sections
        // have an offset of 0.
        // -rluba, 2023-10-16
        return .[];
    }

    assert(section.offset + section.size <= xx macho.content.count);
    result: [] u8 = ---;
    result.data = macho.content.data + section.offset;
    result.count = xx section.size;
    return result;
}

Mach_Header :: struct {
    magic:      u32;
    cputype:    Cpu_Type;
    cpusubtype: Cpu_Subtype;
    filetype:   u32;
    ncmds:      u32;
    sizeofcmds: u32;
    flags:      Mach_Header_Flags;
    reserved:   u32;
}

Mach_Symbol :: struct {
    name:    string;
    type: union {
        symbolic_type: Mach_Symbolic_Symbol_Type; // if flags & .SYMBOLIC
        type:    Mach_Symbol_Type;
    }
    flags:   Mach_Symbol_Flags;
    description: u16;
    value:   u64;
    section: u8;
}

Mach_Symbol_Type :: enum u8 {
    UNDEFINED        :: N_UNDF;
    ABSOLUTE         :: N_ABS;
    SECTION          :: N_SECT;
    PREBOUND         :: N_PBUD;
    INDIRECT         :: N_INDR;
}

Mach_Symbolic_Symbol_Type :: enum u8 {
                                 // .stabs "n_name", n_type, n_sect, n_desc, n_value
    GLOBAL           :: N_GSYM;  /* global symbol */
    F77_NAME         :: N_FNAME; /* F77 function name */
    PROC_NAME        :: N_FUN;   /* procedure: name,,n_sect,linenumber,address */
    DATA_VAR         :: N_STSYM; /* data segment variable */
    BSS_VAR          :: N_LCSYM; /* bss segment variable */
    BEGIN_NSECT      :: N_BNSYM; /* begin nsect sym: 0,,n_sect,0,address */
    AST              :: N_AST;   /* AST file path: name,,NO_SECT,0,0 */
    GCC_OPT          :: N_OPT;   /* emitted with gcc2_compiled and in gcc source */
    REGISTER         :: N_RSYM;  /* register sym: name,,NO_SECT,type,register */
    SRC_LINE         :: N_SLINE; /* src line: 0,,n_sect,linenumber,address */
    END_NSECT        :: N_ENSYM; /* end nsect sym: 0,,n_sect,0,address */
    STRUCT           :: N_SSYM;  /* structure elt: name,,NO_SECT,type,struct_offset */
    SOURCE_FILE      :: N_SO;    /* source file name: name,,n_sect,0,address */
    OBJECT_FILE      :: N_OSO;   /* object file name: name,,(see below),0,st_mtime */
                                 /*   historically N_OSO set n_sect to 0. The N_OSO
                                  *   n_sect may instead hold the low byte of the
                                  *   cpusubtype value from the Mach-O header. */
    LOCAL            :: N_LSYM;  /* local sym: name,,NO_SECT,type,offset */
// #define N_BINCL    0x82    /* include file beginning: name,,NO_SECT,0,sum */
// #define    N_SOL    0x84    /* #included file name: name,,n_sect,0,address */
// #define    N_PARAMS  0x86    /* compiler parameters: name,,NO_SECT,0,0 */
// #define    N_VERSION 0x88    /* compiler version: name,,NO_SECT,0,0 */
// #define    N_OLEVEL  0x8A    /* compiler -O level: name,,NO_SECT,0,0 */
// #define    N_PSYM    0xa0    /* parameter: name,,NO_SECT,type,offset */
// #define N_EINCL    0xa2    /* include file end: name,,NO_SECT,0,0 */
// #define    N_ENTRY    0xa4    /* alternate entry: name,,n_sect,linenumber,address */
// #define    N_LBRAC    0xc0    /* left bracket: 0,,NO_SECT,nesting level,address */
// #define N_EXCL    0xc2    /* deleted include file: name,,NO_SECT,0,sum */
// #define    N_RBRAC    0xe0    /* right bracket: 0,,NO_SECT,nesting level,address */
    BEGIN_COMMON     :: N_BCOMM; /* begin common: name,,NO_SECT,0,0 */
    END_COMMON       :: N_ECOMM; /* end common: name,,n_sect,0,0 */
    END_COMMON_LOCAL :: N_ECOML; /* end common (local name): 0,,n_sect,0,address */
    LENGTH           :: N_LENG;  /* second stab entry with length information */
}

Mach_Symbol_Flags :: enum_flags u8 {
    EXTERNAL;
    PRIVATE_EXTERNAL;
    SYMBOLIC;
}

Load_Command :: struct {
    cmd:     Load_Command_Type;
    cmdsize: u32; /* total size of command in bytes */
}

Segment_Command_64 :: struct {
    using base: Load_Command;
    segname:  [16] u8; /* segment name */ // Padded with zeros, but not necessarily zero-terminated!
    vmaddr:   u64; /* memory address of this segment */
    vmsize:   u64; /* memory size of this segment */
    fileoff:  u64; /* file offset of this segment */
    filesize: u64; /* amount to map from the file */
    maxprot:  vm_prot_t; /* maximum VM protection */
    initprot: vm_prot_t; /* initial VM protection */
    nsects:   u32; /* number of sections in segment */
    flags:    Segment_Flags;
}

Section_64 :: struct {
    sectname:  [16] u8; /* name of this section */         // Padded with zeros, but not necessarily zero-terminated!
    segname:   [16] u8; /* segment this section goes in */ // Padded with zeros, but not necessarily zero-terminated!
    addr:      u64;     /* memory address of this section */
    size:      u64; /* size in bytes of this section */
    offset:    u32; /* file offset of this section */
    align:     u32; /* section alignment (power of 2) */
    reloff:    u32; /* file offset of relocation entries */
    nreloc:    u32; /* number of relocation entries */
    flags:     Section_Flags; /* flags (section type and attributes)*/
    reserved1: u32; /* reserved (for offset or index) */
    reserved2: u32; /* reserved (for count or sizeof) */
    reserved3: u32; /* reserved */
}

get_section_name :: (section: Section_64) -> string {
    return string_from_zero_padded_array(section.sectname);
}

get_segment_name :: (section: Section_64) -> string {
    return string_from_zero_padded_array(section.segname);
}

Symtab_Command :: struct {
    using base: Load_Command;
    symoff:  u32; /* symbol table offset */
    nsyms:   u32; /* number of symbol table entries */
    stroff:  u32; /* string table offset */
    strsize: u32; /* string table size in bytes */
}

Mach_Header_Flags :: enum_flags u32 {
    NOUNDEFS                      :: 0x1;
    INCRLINK                      :: 0x2;
    DYLDLINK                      :: 0x4;
    BINDATLOAD                    :: 0x8;
    PREBOUND                      :: 0x10;
    SPLIT_SEGS                    :: 0x20;
    LAZY_INIT                     :: 0x40;
    TWOLEVEL                      :: 0x80;
    FORCE_FLAT                    :: 0x100;
    NOMULTIDEFS                   :: 0x200;
    NOFIXPREBINDING               :: 0x400;
    PREBINDABLE                   :: 0x800;
    ALLMODSBOUND                  :: 0x1000;
    SUBSECTIONS_VIA_SYMBOLS       :: 0x2000;
    CANONICAL                     :: 0x4000;
    WEAK_DEFINES                  :: 0x8000;
    BINDS_TO_WEAK                 :: 0x10000;
    ALLOW_STACK_EXECUTION         :: 0x20000;
    ROOT_SAFE                     :: 0x40000;
    SETUID_SAFE                   :: 0x80000;
    NO_REEXPORTED_DYLIBS          :: 0x100000;
    PIE                           :: 0x200000;
    DEAD_STRIPPABLE_DYLIB         :: 0x400000;
    HAS_TLV_DESCRIPTORS           :: 0x800000;
    NO_HEAP_EXECUTION             :: 0x1000000;
    NLIST_OUTOFSYNC_WITH_DYLDINFO :: 0x04000000;
    SIM_SUPPORT                   :: 0x08000000;
    DYLIB_IN_CACHE                :: 0x80000000;
}

#load "bindings/macho.jai";

