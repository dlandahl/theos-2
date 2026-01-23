Elf :: struct {
    header: *Elf_Header_64;

    program_header_table: [] Elf_Program_Header_64;

    sections: [] Elf_Section_Header; // Section header table
    section_names: string;

    text_section: *Elf_Section_Header;

    debug_info_section_index: int; // Used in dump_binary_file for applying relocations?
    debug_line_section_index: int; // 
    
    debug_info_section:   *Elf_Section_Header;
    debug_abbrev_section: *Elf_Section_Header;
    debug_str_section:    *Elf_Section_Header;
    debug_line_section:   *Elf_Section_Header;
    debug_loc_section:    *Elf_Section_Header;
    debug_ranges_section: *Elf_Section_Header;
    
    text: [] u8;

    symbols: [] Elf_Symbol;
    symbol_names: string;

    dynamic_symbols: [] Elf_Symbol;
    dynamic_symbol_names: string;

    content: string; // The whole file content.
}

// @ToDo: Clean up on errors
parse_elf_file :: (path: string) -> success: bool, elf: Elf  {
    elf: Elf = ---;
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, elf;
    }

    success, elf = parse_elf(content);
    return success, elf;
}

is_elf :: (file_content: string) -> bool {
    if file_content.count < size_of(Elf_Header_64) return false;

    header := cast(*Elf_Header_64) file_content.data;
    return header.ident.magic == EXPECTED_MAGIC;
}

parse_elf :: (file_content: string, path := "(unspecified file)") -> success: bool, elf: Elf {
    check :: (condition: bool, message: string, args: .. Any) #expand {
        if !condition {
            log_error(message, ..args);
            `return false, elf;
        }
    } @PrintLike

    using elf: Elf = ---; // NOTE(Charles): Is it really worth doing this, then manually zeroing out a bunch of fields below? I fixed a bug caused by symbols/dynamic_symbols not being zeroed out, maybe there are more bugs waiting...
    elf.content = file_content;

    check(elf.content.count >= size_of(Elf_Header_64), "File is too small to be a ELF binary: %", path);

    elf.header = cast(*Elf_Header_64) elf.content.data;
    // log("ELF header: %\n", header.*);
    check(header.ident.magic == EXPECTED_MAGIC, "File does not appear to be a ELF binary: %", path);
    check(header.ident.class != ._32_BIT, "32-bit ELF is not yet supported"); // :ElfNo32
    check(header.ident.class == ._64_BIT, "Unsupported ELF class %", header.ident.class);
    check(header.ident.data  == .LSB, "Unsupported ELF endianness %", header.ident.data);
    check(header.ident.version == 1, "Unsupported ELF version %", header.ident.version);
    check(header.ident.os_abi == .SYSTEM_V || header.ident.os_abi == .LINUX || header.ident.os_abi == .FREEBSD, "Unsupported ELF OS ABI %", header.ident.os_abi);
    check(header.machine == .AMD_x64 || header.machine == .ARM_v8, "Unsupported ELF ISA 0x% (%)", formatInt(cast (int) header.machine, base = 16), header.machine);
    check(header.version == 1, "Unsupported ELF version %", header.version);
    check(header.ehsize == size_of(Elf_Header_64), "Unexpected header size: % (expected %)", header.ehsize, size_of(Elf_Header_64));

    PN_XNUM :: 0xffff;
    if header.type == .EXEC || header.type == .DYN {
        check(header.phnum != PN_XNUM, "Program header count too large to fit in phnum. This isn't handled yet!");
        check(header.phentsize == size_of(Elf_Program_Header_64), "Unexpected program header size: % (expected %)", header.phentsize, size_of(Elf_Program_Header_64));
        check(header.program_header_offset + header.phnum * header.phentsize <= cast(u64, elf.content.count), "Invalid program header offset: %", header.program_header_offset);
        program_header_table.data  = cast(*Elf_Program_Header_64, content.data + header.program_header_offset);
        program_header_table.count = header.phnum;
    } else {
        program_header_table = .[]; // Object files (.REL) don't have a program header table.
    }

    check(header.section_header_entry_size == size_of(Elf_Section_Header), "Unexpected section header size: % (expected %)", header.section_header_entry_size, size_of(Elf_Section_Header));
    check(header.section_header_offset + header.num_section_headers * header.section_header_entry_size <= cast (u64) elf.content.count, "Invalid section header offset: %", header.section_header_offset);

    elf.sections.data  = cast(*Elf_Section_Header) (elf.content.data + header.section_header_offset);
    elf.sections.count = header.num_section_headers;

    check(header.section_names_section_index < header.num_section_headers, "Invalid names section index: %", header.section_names_section_index);
    section_names_section := *elf.sections[header.section_names_section_index];
    check(section_names_section.type == .STRTAB, "String table section has an unexpected type: %", section_names_section.type);
    if !validate_section_header(section_names_section, elf.content.count)   return false, elf;
    elf.section_names = cast(string) get_section_data(elf, section_names_section);

    text_section = null;
    symbols         = .[];
    dynamic_symbols = .[];
    debug_info_section_index = 0;
    debug_line_section_index = 0;
    debug_info_section   = null;
    debug_abbrev_section = null;
    debug_str_section    = null;
    debug_line_section   = null;
    debug_loc_section    = null;
    debug_ranges_section = null;

    for * elf.sections {
        if !validate_section_header(it, elf.content.count)     return false, elf;

        success, section_name := get_string_from_table(it.name_offset, elf.section_names);
        check(success, "Invalid section name offset: %", it.name_offset);

        if my_strcmp(section_name, ".text") {
            check(it.type == .PROGBITS && (it.flags & .EXECINSTR), "Invalid text section at %: %", it_index, it.*);
            check(!elf.text_section, "Found another section % section at index %", section_name, it_index);
            elf.text_section = it;
            elf.text.data = elf.content.data + elf.text_section.offset;
            elf.text.count = cast (s64) elf.text_section.size;
        } else if my_strcmp(section_name, ".debug_info") {
            check(it.type == .PROGBITS, "Invalid type for section % (%). Expected PROGBITS", section_name, it_index);
            check(!elf.debug_info_section, "Found another section % section at index %", section_name, it_index);
            elf.debug_info_section_index = it_index;
            elf.debug_info_section = it;
        } else if my_strcmp(section_name, ".debug_abbrev") {
            check(it.type == .PROGBITS, "Invalid type for section % (%). Expected PROGBITS", section_name, it_index);
            check(!elf.debug_abbrev_section, "Found another section % section at index %", section_name, it_index);
            elf.debug_abbrev_section = it;
        } else if my_strcmp(section_name, ".debug_str") {
            check(it.type == .PROGBITS, "Invalid type for section % (%). Expected PROGBITS", section_name, it_index);
            check(!elf.debug_str_section, "Found another section % section at index %", section_name, it_index);
            elf.debug_str_section = it;
        } else if my_strcmp(section_name, ".debug_line") {
            check(it.type == .PROGBITS, "Invalid type for section % (%). Expected PROGBITS", section_name, it_index);
            check(!elf.debug_line_section, "Found another section % section at index %", section_name, it_index);
            elf.debug_line_section_index = it_index;
            elf.debug_line_section = it;
        } else if my_strcmp(section_name, ".debug_loc") {
            check(it.type == .PROGBITS, "Invalid type for section % (%). Expected PROGBITS", section_name, it_index);
            check(!elf.debug_loc_section, "Found another section % section at index %", section_name, it_index);
            elf.debug_loc_section = it;
        } else if my_strcmp(section_name, ".debug_ranges") {
            check(it.type == .PROGBITS, "Invalid type for section % (%). Expected PROGBITS", section_name, it_index);
            check(!elf.debug_ranges_section, "Found another section % section at index %", section_name, it_index);
            elf.debug_ranges_section = it;
        } else if it.type == {
          case .SYMTAB;
            check(elf.symbols.count == 0, "Found more than one symbol table. Second one is at %: %", it_index, it.*);
            section_data := get_section_data(elf, it);
            check(section_data.count % size_of(Elf_Symbol) == 0, "Unexpected symbol table size: % is not a multiple of %", section_data.count, size_of(Elf_Symbol));
            elf.symbols.data = cast(*Elf_Symbol) section_data.data;
            elf.symbols.count = section_data.count / size_of(Elf_Symbol);

            check(it.link < header.num_section_headers, "Invalid symbol name section index % in section %: %", it.link, it_index, it.*);
            symbol_names_section := *elf.sections[it.link];
            check(symbol_names_section.type == .STRTAB, "Symbol name section has an unexpected type: %", symbol_names_section.type);
            if !validate_section_header(symbol_names_section, elf.content.count)   return false, elf;
            elf.symbol_names = cast(string) get_section_data(elf, symbol_names_section);

            first_global_symbol := it.info;
            for elf.symbols {
                binding := get_binding(it);
                success, name := get_string_from_table(it.name_offset, elf.symbol_names);
                if it_index < first_global_symbol {
                    check(binding == .LOCAL, "Symbol % (%) is before the first global symbol index (%) but not local (%)", it_index, name, first_global_symbol, binding);
                } else {
                    check(binding != .LOCAL, "Symbol % (%) is after the first global symbol index (%) but local (%)", it_index, name, first_global_symbol, binding);
                }
            }

          case .DYNSYM;
            check(elf.dynamic_symbols.count == 0, "Found more than one dynamic symbol table. Second one is at %: %", it_index, it.*);
            section_data := get_section_data(elf, it);
            check(section_data.count % size_of(Elf_Symbol) == 0, "Unexpected dynamic symbol table size: % is not a multiple of %", section_data.count, size_of(Elf_Symbol));
            elf.dynamic_symbols.data = cast(*Elf_Symbol) section_data.data;
            elf.dynamic_symbols.count = section_data.count / size_of(Elf_Symbol);

            check(it.link < header.num_section_headers, "Invalid symbol name section index % in section %: %", it.link, it_index, it.*);
            symbol_names_section := *elf.sections[it.link];
            check(symbol_names_section.type == .STRTAB, "Symbol name section has an unexpected type: %", symbol_names_section.type);
            if !validate_section_header(symbol_names_section, elf.content.count)   return false, elf;
            elf.dynamic_symbol_names = cast(string) get_section_data(elf, symbol_names_section);
        }
    }

    // log("Text section: %\n", elf.text_section.*);
    // log("Debug line section: %\n", elf.debug_line_section.*);

    // ELF stubs don’t contain a text section
    // check(elf.text_section != null, "Could not find text section");

    return true, elf;
}

// @CopyPasta from parse_elf. When reading loaded segments at runtime we want more fine grained reading. This is the
// start of that. Maybe this gets factored and reused in parse elf.
parse_elf_header_and_program_header_table :: (data: string, path := "(unspecified file)") -> bool, *Elf_Header_64, [] Elf_Program_Header_64 {
    check :: (condition: bool, message: string, args: .. Any) #expand {
        if !condition {
            log_error(message, ..args);
            `return false, header, program_header_table;
        }
    } @PrintLike

    header: *Elf_Header_64;
    program_header_table: [] Elf_Program_Header_64;

    check(data.count >= size_of(Elf_Header_64), "File is too small to be a ELF binary: %", path);

    header = cast(*Elf_Header_64, data.data);
    // log("ELF header: %\n", header.*);

    check(header.ident.magic == EXPECTED_MAGIC, "File does not appear to be a ELF binary: %", path);
    check(header.ident.class != ._32_BIT, "32-bit ELF is not yet supported"); // :ElfNo32
    check(header.ident.class == ._64_BIT, "Unsupported ELF class %", header.ident.class);
    check(header.ident.data  == .LSB, "Unsupported ELF endianness %", header.ident.data);
    check(header.ident.version == 1, "Unsupported ELF version %", header.ident.version);
    check(header.ident.os_abi == .SYSTEM_V || header.ident.os_abi == .LINUX || header.ident.os_abi == .FREEBSD, "Unsupported ELF OS ABI %", header.ident.os_abi);
    check(header.machine == .AMD_x64 || header.machine == .ARM_v8, "Unsupported ELF ISA 0x% (%)", formatInt(cast (int) header.machine, base = 16), header.machine);
    check(header.version == 1, "Unsupported ELF version %", header.version);
    check(header.ehsize == size_of(Elf_Header_64), "Unexpected header size: % (expected %)", header.ehsize, size_of(Elf_Header_64));

    PN_XNUM :: 0xffff;
    check(header.phnum != PN_XNUM, "Program header count too large to fit in phnum. This isn't handled yet!");
    check(header.phentsize == size_of(Elf_Program_Header_64), "Unexpected program header size: % (expected %)", header.phentsize, size_of(Elf_Program_Header_64));
    check(header.program_header_offset + header.phnum * header.phentsize <= cast(u64, data.count), "Invalid program header offset: %", header.program_header_offset);
    program_header_table.data  = cast(*Elf_Program_Header_64, data.data + header.program_header_offset);
    program_header_table.count = header.phnum;

    return true, header, program_header_table;
}


Elf_Header :: struct (Offset_Type: Type) {
    ident: struct {
        magic:       u32;
        class:       Elf_Class;
        data:        Elf_Endianness;
        version:     u8;
        os_abi:      Elf_Abi;
        abi_version: u8;
        pad:         [7] u8;
    }

    type:                        Elf_Type;
    machine:                     Elf_Machine;
    version:                     u32;
    entry:                       Offset_Type;
    program_header_offset:       Offset_Type; // phoff
    section_header_offset:       Offset_Type; // shoff
    flags:                       u32;
    ehsize:                      u16;
    phentsize:                   u16;
    phnum:                       u16;
    section_header_entry_size:   u16; // shentsize
    num_section_headers:         u16; // shnum
    section_names_section_index: u16; // shstrndx
}

Elf_Header_64 :: Elf_Header(u64);
Elf_Header_32 :: Elf_Header(u32);

Elf_Class :: enum u8 {
    _32_BIT :: 1;
    _64_BIT :: 2;
}

Elf_Endianness :: enum u8 {
    LSB :: 1;
    MSB :: 1;
}

Elf_Abi :: enum u8 {
    SYSTEM_V :: 0x00;
    LINUX    :: 0x03;
    FREEBSD  :: 0x09;
    // We don’t care about the rest for the moment
}

Elf_Type :: enum u16 {
    NONE   :: 0x00;
    REL    :: 0x01;
    EXEC   :: 0x02;
    DYN    :: 0x03;
    CORE   :: 0x04;
    LOOS   :: 0xFE00;
    HIOS   :: 0xFEFF;
    LOPROC :: 0xFF00;
    HIPROC :: 0xFFFF;
}

Elf_Machine :: enum u16 {
    AMD_x64 :: 0x3E;
    ARM_v8  :: 0xB7;
    // We don’t care about the rest for the moment
}

// NOTE(Charles): This is the 64 bit version (Elf64_Shdr)! Elf_Header is polymorphed for 32/64 but this isn't. 
// We want to be able to tell if an elf file is 32 bit, but don't actually care about reading it beyond that :ElfNo32.
Elf_Section_Header :: struct {
    name_offset: u32;
    type:        Elf_Section_Type;
    flags:       Elf_Section_Flags;
    address:     u64;
    offset:      u64;
    size:        u64;
    link:        u32;
    info:        u32;
    addralign:   u64;
    entsize:     u64;
}

Elf_Section_Type :: enum u32 {
    NULL          :: 0x00;
    PROGBITS      :: 0x01;
    SYMTAB        :: 0x02;
    STRTAB        :: 0x03;
    RELA          :: 0x04;
    HASH          :: 0x05;
    DYNAMIC       :: 0x06;
    NOTE          :: 0x07;
    NOBITS        :: 0x08; // Program space with no data (bss)
    REL           :: 0x09; // Relocation entries, no addends
    SHLIB         :: 0x0A; // Reserved
    DYNSYM        :: 0x0B; // Dynamic linker symbol table
    INIT_ARRAY    :: 0x0E; // Array of constructors
    FINI_ARRAY    :: 0x0F; // Array of destructors
    PREINIT_ARRAY :: 0x10; // Array of pre-constructors
    GROUP         :: 0x11; // Section group
    SYMTAB_SHNDX  :: 0x12; // Extended section indices
    NUM           :: 0x13; // Number of defined types.

    LOOS          :: 0x60000000; // Start OS-specific

    // LLVM extensions
    LLVM_ADDRSIG  :: 0x6FFF4C03; // mark symbols as address-significant
}

Elf_Section_Flags :: enum_flags u64 {
    WRITE            :: 0x01;   //  Writable
    ALLOC            :: 0x02;   //  Occupies memory during execution
    EXECINSTR        :: 0x04;   //  Executable
    MERGE            :: 0x10;   //  Might be merged
    STRINGS          :: 0x20;   //  Contains null-terminated strings
    INFO_LINK        :: 0x40;   //  'sh_info' contains SHT index
    LINK_ORDER       :: 0x80;   //  Preserve order after combining
    OS_NONCONFORMING :: 0x0100; // Non-standard OS specific handling required
    GROUP            :: 0x0200; //  Section is member of a group
    TLS              :: 0x0400; //  Section hold thread-local data
    MASKOS           :: 0x0ff00000; // OS-specific
    MASKPROC         :: 0xf0000000; //  Processor-specific
    ORDERED          :: 0x4000000;  // Special ordering requirement (Solaris)
    EXCLUDE          :: 0x8000000;  //   Section is excluded unless referenced or allocated (Solaris
}

Elf_Segment_Type :: enum u32 {
    NULL         :: 0;           /* Program header table entry unused */
    LOAD         :: 1;           /* Loadable program segment */
    DYNAMIC      :: 2;           /* Dynamic linking information */
    INTERP       :: 3;           /* Program interpreter */
    NOTE         :: 4;           /* Auxiliary information */
    SHLIB        :: 5;           /* Reserved */
    PHDR         :: 6;           /* Entry for header table itself */
    TLS          :: 7;           /* Thread-local storage segment */
    NUM          :: 8;           /* Number of defined types */

    LOOS         :: 0x60000000;  /* Start of OS-specific */
    GNU_EH_FRAME :: 0x6474e550;  /* GCC .eh_frame_hdr segment */
    GNU_STACK    :: 0x6474e551;  /* Indicates stack executability */
    GNU_RELRO    :: 0x6474e552;  /* Read-only after relocation */
    GNU_PROPERTY :: 0x6474e553;  /* GNU property */
    LOSUNW       :: 0x6ffffffa;
    SUNWBSS      :: 0x6ffffffa;  /* Sun Specific segment */
    SUNWSTACK    :: 0x6ffffffb;  /* Stack segment */
    HISUNW       :: 0x6fffffff;
    HIOS         :: 0x6fffffff;  /* End of OS-specific */
    
    LOPROC       :: 0x70000000;  /* Start of processor-specific */
    HIPROC       :: 0x7fffffff;  /* End of processor-specific */
}

Elf_Segment_Flags :: enum_flags u32 {
    EXEC  :: (1 << 0);
    WRITE :: (1 << 1);
    READ  :: (1 << 2);

    MASKOS   :: 0x0ff00000;  /* OS-specific */
    MASKPROC :: 0xf0000000;  /* Processor-specific */
}

Elf_Program_Header :: struct(Size_Type: Type) {
    #assert Size_Type == u64 || Size_Type == u32;

    type: Elf_Segment_Type;

    #if Size_Type == u64  flags: Elf_Segment_Flags;

    offset: Size_Type;
    vaddr:  Size_Type;
    paddr:  Size_Type;
    filesz: Size_Type;
    memsz:  Size_Type;

    #if Size_Type == u32  flags: Elf_Segment_Flags;

    align: Size_Type;
}

// NOTE(Charles): I did this polymoprh before realising 32 bit is not supported :ElfNo32.
Elf_Program_Header_64 :: Elf_Program_Header(u64);
Elf_Program_Header_32 :: Elf_Program_Header(u32);

Elf_Symbol :: struct {
    name_offset:   u32; // Symbol name (string tbl index)
    info:          u8;  // Symbol type and binding
    other:         u8;  // Symbol visibility
    section_index: u16;
    value:         u64;
    size:          u64;
}

get_type :: (symbol: Elf_Symbol) -> Elf_Symbol_Type {
    return xx (symbol.info & 0xf);
}

get_binding :: (symbol: Elf_Symbol) -> Elf_Symbol_Binding {
    return xx (symbol.info >> 4);
}

get_visibility :: (symbol: Elf_Symbol) -> Elf_Symbol_Visibility {
    return xx (symbol.other & 0x3);
}

Elf_Symbol_Binding :: enum {
    LOCAL      :: 0;               // Local symbol
    GLOBAL     :: 1;               // Global symbol
    WEAK       :: 2;               // Weak symbol
    NUM        :: 3;               // Number of defined types.
    // LOOS       :: 10;              // Start of OS-specific
    GNU_UNIQUE :: 10;              // Unique symbol.
    // HIOS       :: 12;              // End of OS-specific
    // LOPROC     :: 13;              // Start of processor-specific
    // HIPROC     :: 15;              // End of processor-specific
}

Elf_Symbol_Type :: enum {
    NOTYPE    :: 0;               // Symbol type is unspecified
    OBJECT    :: 1;               // Symbol is a data object
    FUNC      :: 2;               // Symbol is a code object
    SECTION   :: 3;               // Symbol associated with a section
    FILE      :: 4;               // Symbol's name is file name
    COMMON    :: 5;               // Symbol is a common data object
    TLS       :: 6;               // Symbol is thread-local data object
    NUM       :: 7;               // Number of defined types.
    // LOOS      :: 10;              // Start of OS-specific
    GNU_IFUNC :: 10;              // Symbol is indirect code object
    // HIOS      :: 12;              // End of OS-specific
    // LOPROC    :: 13;              // Start of processor-specific
    // HIPROC    :: 15;              // End of processor-specific
}

Elf_Symbol_Visibility :: enum u8 {
    DEFAULT   :: 0;               // Default symbol visibility rules
    INTERNAL  :: 1;               // Processor specific hidden class
    HIDDEN    :: 2;               // Sym unavailable in other modules
    PROTECTED :: 3;               // Not preemptible, not exported
}

Elf_Special_Section_Indices :: enum u16 {
    UNDEF     :: 0;               // Undefined section
    // LORESERVE :: 0xff00;          // Start of reserved indices
    // LOPROC    :: 0xff00;          // Start of processor-specific
    BEFORE    :: 0xff00;          // Order section before all others (Solaris).
    AFTER     :: 0xff01;          // Order section after all others (Solaris).
    // HIPROC    :: 0xff1f;          // End of processor-specific
    // LOOS      :: 0xff20;          // Start of OS-specific
    // HIOS      :: 0xff3f;          // End of OS-specific
    ABS       :: 0xfff1;          // Associated symbol is absolute
    COMMON    :: 0xfff2;          // Associated symbol is common
    XINDEX    :: 0xffff;          // Index is in extra table.
    // HIRESERVE :: 0x10000;          // End of reserved indices
}

// This is Elf64_Rela, relocation table entry for sections of type .RELA. What about REL sections?
Elf_Relocation :: struct {
    address:   u64;
    type:      Elf_Relocation_Type; // r_info low  u32
    symbol_id: Elf_Symbol_Id;       // r_info high u32
    addend:    s64;
}

Elf_Symbol_Id :: #type,isa u32;

Elf_Relocation_Type :: enum u32 {
    // X64. See https://docs.oracle.com/en/operating-systems/solaris/oracle-solaris/11.4/linkers-libraries/x64-relocation-types.html
    AMD64_64        :: 1;  // S + A
    AMD64_PC32      :: 2;  // S + A - P
    AMD64_PLT32     :: 4;  // L + A - P
    AMD64_JUMP_SLOT :: 7;  // S
    AMD64_RELATIVE  :: 8;  // B + A
    AMD64_GOTPCREL  :: 9;  // G + GOT + A - P
    AMD64_32        :: 10; // S + A, truncated, zero-extends to the original 64bit value
    AMD64_32S       :: 11; // S + A, truncated, sign-extends to the original 64bit value

    X86_64_ORBIS_GOTPCREL_LOAD :: 0x28;

    // Arm64. See https://github.com/ARM-software/abi-aa/blob/main/aaelf64/aaelf64.rst#relocation
    AARCH64_ABS64     :: 257;  // S + A
    AARCH64_ABS32     :: 258;  // S + A (overflow check: -2^31 <= X <= 2^32)
    AARCH64_ABS16     :: 259;  // S + A (overflow check: -2^15 <= X <= 2^16)
    AARCH64_PREL64    :: 260;  // S + A - P
    AARCH64_PREL32    :: 261;  // S + A - P (overflow check: -2^31 <= X <= 2^32)
    AARCH64_PREL16    :: 262;  // S + A - P (overflow check: -2^15 <= X <= 2^16)
    AARCH64_PLT32     :: 314;  // L + A - P (overflow check: -2^31 <= X <= 2^32)
    AARCH64_GLOB_DAT  :: 1025; // S + A
    AARCH64_JUMP_SLOT :: 1026; // S + A
    AARCH64_RELATIVE  :: 1027; // Delta(S) + A
    // Very @Incomplete!

}

// An entry in the .dynamic section
Elf_Dynamic_64 :: struct {
    tag:   Elf_Dynamic_Tag;
    value: u64; // This is a union in c headers, but the union members are both u64...
}

Elf_Dynamic_Tag :: enum s64 {
    NULL     :: 0;       // Marks end of dynamic section
    NEEDED   :: 1;       // Name of needed library
    PLTRELSZ :: 2;       // Size in bytes of PLT relocs
    PLTGOT   :: 3;       // Processor defined value
    HASH     :: 4;       // Address of symbol hash table
    STRTAB   :: 5;       // Address of string table
    SYMTAB   :: 6;       // Address of symbol table. NOTE(Charles): This is the _dynamic_ symbol table. Bit confusing with Elf_Section_Type.SYMTAB!
    RELA     :: 7;       // Address of Rela relocs
    RELASZ   :: 8;       // Total size of Rela relocs
    RELAENT  :: 9;       // Size of one Rela reloc
    STRSZ    :: 10;      // Size of string table
    SYMENT   :: 11;      // Size of one symbol table entry
    INIT     :: 12;      // Address of init function
    FINI     :: 13;      // Address of termination function
    SONAME   :: 14;      // Name of shared object
    RPATH    :: 15;      // Library search path (deprecated)
    SYMBOLIC :: 16;      // Start symbol search here
    REL      :: 17;      // Address of Rel relocs
    RELSZ    :: 18;      // Total size of Rel relocs
    RELENT   :: 19;      // Size of one Rel reloc
    PLTREL   :: 20;      // Type of reloc in PLT
    DEBUG    :: 21;      // For debugging; unspecified
    TEXTREL  :: 22;      // Reloc might modify .text
    JMPREL   :: 23;      // Address of PLT relocs
    BIND_NOW :: 24;      // Process relocations of object
    INIT_ARRAY   :: 25;      // Array with addresses of init fct
    FINI_ARRAY   :: 26;      // Array with addresses of fini fct
    INIT_ARRAYSZ :: 27;      // Size in bytes of DT_INIT_ARRAY
    FINI_ARRAYSZ :: 28;      // Size in bytes of DT_FINI_ARRAY
    RUNPATH  :: 29;      // Library search path
    FLAGS    :: 30;      // Flags for the object being loaded
    ENCODING :: 32;      // Start of encoded range
    PREINIT_ARRAY :: 32;     // Array with addresses of preinit fc
    PREINIT_ARRAYSZ :: 33;       // size in bytes of DT_PREINIT_ARRAY
    SYMTAB_SHNDX :: 34;      // Address of SYMTAB_SHNDX section
    RELRSZ   :: 35;      // Total size of RELR relative relocations
    RELR     :: 36;      // Address of RELR relative relocations
    RELRENT  :: 37;      // Size of one RELR relative relocaction
    NUM      :: 38;      // Number used

    LOOS     :: 0x6000000d;  // Start of OS-specific
    HIOS     :: 0x6ffff000;  // End of OS-specific

    LOPROC   :: 0x70000000;  // Start of processor-specific
    HIPROC   :: 0x7fffffff;  // End of processor-specific

    // PROCNUM  :: DT_MIPS_NUM; // Most used by any processor

    // @Incomplete: There are more DT_* defines for os/processor specific stuff. I have only added ones that I see in jai binaries so far.

    GNU_HASH :: 0x6ffffef5; // GNU-style hash table.

    VERSYM     :: 0x6ffffff0;
    RELACOUNT  :: 0x6ffffff9; // The number of relative relocations in .rela.dyn
    VERNEED    :: 0x6ffffffe; // Address of table with needed versions
    VERNEEDNUM :: 0x6fffffff; // Number of needed versions
}

// Possible values of Elf_Dynamic_Tag.FLAGS entry value.
Elf_Dynamic_Flags :: enum_flags u64 {
    ORIGIN     :: 0x00000001;  // Object may use DF_ORIGIN
    SYMBOLIC   :: 0x00000002;  // Symbol resolutions starts here
    TEXTREL    :: 0x00000004;  // Object contains text relocations
    BIND_NOW   :: 0x00000008;  // No lazy binding for this object
    STATIC_TLS :: 0x00000010;  // Module uses the static TLS model
}

validate_section_header :: (section_header: *Elf_Section_Header, file_size: s64) -> success: bool {
    if section_header.type != .NOBITS && section_header.offset + section_header.size > cast(u64) file_size {
        log_error("Section data is out of bounds: % + % vs %\n", section_header.offset, section_header.size, file_size);
        return false;
    }

    return true;
}

get_section_data :: (elf: Elf, section: *Elf_Section_Header) -> [] u8 {
    if !section                 return .[];
    if section.type == .NOBITS  return .[];

    result: [] u8 = ---;
    result.data = elf.content.data + section.offset;
    result.count = xx section.size;
    return result;
}

get_relocations :: (elf: Elf, section_index: int) -> [] Elf_Relocation, bool {
    section: *Elf_Section_Header;
    for * elf.sections {
        if it.type == .RELA  && it.info == section_index {
            section = it;
            break;
        }
    }
    if !section return .[], true; // No relocation section for this section

    section_data := get_section_data(elf, section);
    if section_data.count % size_of(Elf_Relocation) != 0 {
        log_error("Relocation section for section % has unexpected size: 0x%", section_index, formatInt(section_data.count, base = 16));
        return .[], false;
    }

    relocations: [] Elf_Relocation;
    relocations.data = cast(*Elf_Relocation) section_data.data;
    relocations.count = section_data.count / size_of(Elf_Relocation);

    return relocations, true;
}

apply_relocations :: (elf: Elf, section_index: int, data: [] u8) -> bool {
    relocations, success := get_relocations(elf, section_index);
    if !success return false;

    for relocations {
        // log("Relocation: %", it);
        symbol := get_symbol(elf, it.symbol_id);
        if !symbol continue;

        offset := it.address;
        symbol_address := symbol.value; // @ToDo: Take symbol's section address into account

        if it.type == {
            case .AMD64_64; #through;
            case .AARCH64_ABS64;
                assert(offset + size_of(s64) <= cast(u64) data.count);
                value := cast(s64) symbol_address + it.addend;
                // @Incomplete: Allowing u64 values for .AARCH64_ABS64
                target := cast(*s64) (data.data + offset);
                target.* = value;

            case .AMD64_32; #through;
            case .AARCH64_ABS32;
                assert(offset + size_of(s32) <= cast(u64) data.count);
                value := (cast(s64) symbol_address + it.addend);
                // @Incomplete: Overflow check and allowing u32 values for .AARCH64_ABS32
                target := cast(*s32) (data.data + offset);
                target.* = cast(s32) value;

            case .AARCH64_ABS16;
                assert(offset + size_of(s16) <= cast(u64) data.count);
                value := (cast(s64) symbol_address + it.addend);
                // @Incomplete: Overflow check and allowing u16 values for .AARCH64_ABS16
                target := cast(*s16) (data.data + offset);
                target.* = cast(s16) value;

            case .AARCH64_PREL64;
                assert(offset + size_of(s64) <= cast(u64) data.count);
                // @Incomplete: Allowing u64 values
                offset_address := offset; // @ToDo: Take this section's address into account
                value := (cast(s64) (symbol_address + cast(u64) it.addend - offset_address));
                target := cast(*s64) (data.data + offset);
                target.* = value;

            case .AMD64_PC32; #through;
            case .AARCH64_PREL32;
                assert(offset + size_of(s32) <= cast(u64) data.count);
                offset_address := offset; // @ToDo: Take this section's address into account
                // @Incomplete: Overflow check and allowing u32 values for .AARCH64_PREL32
                value := (cast(s64) (symbol_address + cast(u64) it.addend - offset_address));
                target := cast(*s32) (data.data + offset);
                target.* = cast(s32) value;

            case;
                log_error("@Incomplete: Applying relocations of type % is not yet implemented.", it.type);
        }
    }

    return true;
}

get_symbol :: (elf: Elf, symbol_id: Elf_Symbol_Id) -> *Elf_Symbol {
    if cast(s64) symbol_id >= elf.symbols.count {
        log_error("Invalid symbol id %", symbol_id);
        return null;
    }

    return *elf.symbols[cast(s64) symbol_id];
}

get_symbol_type_and_name :: (elf: Elf, symbol: Elf_Symbol, symbol_names: string) -> Elf_Symbol_Type, name: string, success: bool {
    symbol_type := get_type(symbol);
    success: bool;
    symbol_name: string;
    if symbol_type == {
        case .SECTION;
            symbol_section := elf.sections[symbol.section_index];
            symbol_name, success = get_section_name(elf, symbol_section);
        case;
            success, symbol_name = get_string_from_table(symbol.name_offset, symbol_names);
    }

    return symbol_type, symbol_name, success;
}

get_section_name :: (elf: Elf, section: Elf_Section_Header) -> string, success: bool {
    success, section_name := get_string_from_table(section.name_offset, elf.section_names);
    return section_name, success;
}

get_string_from_table :: (index: int, table: string) -> success: bool, string {
    if index >= table.count {
        log_error("Invalid string table index: % / %", index, table.count);
        return false, "";
    }

    start := table.data + index;
    length := 0;
    while start[length] != 0 && index + length < table.count {
        length += 1;
    }
    if length == table.count {
        log_error("String at index % overflows the string table", index);
        return false, "";
    }

    result: string;
    result.data = start;
    result.count = length;
    return true, result;
}

#scope_file

EXPECTED_MAGIC :: 0x464c457F;






my_strcmp :: (a: string, b: string) -> bool {
    if a.count != b.count return false;

    return _memcmp(a.data, b.data, cast(u64)a.count) == 0;
}


// For some reason the function interposition trick doesn't work with memcmp, even though it works with memset and memcpy.
_memcmp :: (a: *void, b: *void, count: u64) -> s16 #c_call {
    for 0..count-1 {
        if a.(*u8)[it] != b.(*u8)[it] return -1;
    }

    return 0;

    /*
    start := a;

    #asm {
        cld;
        
        count === c;
        a     === si;
        b     === di;
        repe_cmps.b b, a, count;
    }

    if start + count == a {
        return 0;
    }

    return cast(s16) (*(a-1) - *(b-1));
    */
}
