// Official COFF / PE documentation:
// https://docs.microsoft.com/en-us/windows/win32/debug/pe-format#coff-file-header-object-and-image
//
// Documentation of .pdata / .xdata format:
// https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64

Coff :: struct {
    header:              *Coff_Header;
    optional_header:     Coff_Optional_Header;

    section_headers:     [] Coff_Section_Header;

    symbols:             [] Coff_Symbol;
    string_table:        [] u8;

    // The data of the corresponding sections, if they exist in section_headers:
    section_relocations: [][] Coff_Relocation;

    content:             string;
}

parse_coff_file :: (path: string) -> success: bool, Coff {
    coff: Coff = ---;
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, coff;
    }

    success, coff = parse_coff(content, path);
    return success, coff;
}

is_coff :: (file_content: string) -> bool {
    if file_content.count < size_of(Coff_Header) return false;

    header := cast(*Coff_Header) file_content.data;
    // @Incomplete: It could be a 32-bit x86 or ARM binary, but we don’t care about those atm.
    return header.machine == .AMD64 || header.machine == .ARM64;
}

parse_coff :: (file_content: string, path := "(unspecified file)", verbose := false, start_offset := 0) -> success: bool, Coff {
    check :: (condition: bool, message: string, args: .. Any) #expand {
        if !condition {
            log_error(message, ..args);
            `return false, coff;
        }
    } @PrintLike

    using coff: Coff;

    content = file_content;

    offset := start_offset;
    check(offset + size_of(Coff_Header) <= content.count, "File is too small to be a COFF binary: %", path);

    header = cast(*Coff_Header) (coff.content.data + offset);
    // log("COFF header: %\n", header.*);

    check(header.machine == .AMD64 || header.machine == .ARM64, "File does not appear to be a 64bit COFF binary: %", path);

    symbols_size := header.num_symbols * size_of(Coff_Symbol);
    if header.num_symbols {
        check(header.symbol_table_offset <= content.count, "Symbol table start is out of bounds: %", path);
        check(header.symbol_table_offset + symbols_size <= content.count, "Symbol table end is out of bounds: %", path);
        symbols.data = cast(*Coff_Symbol) (content.data + header.symbol_table_offset);
        symbols.count = header.num_symbols;

        string_table_size_offset := header.symbol_table_offset + symbols_size;
        // log("String table offset: 0x%", formatInt(string_table_size_offset, base = 16));
        string_table_size_end := string_table_size_offset + size_of(u32);
        check(string_table_size_end <= content.count, "String table start is out of bounds: %", path);
        string_table_size := (.*)(cast(*u32) (content.data + string_table_size_offset));
        check(string_table_size_offset >= size_of(u32), "String table size is invalid: %", path);
        check(string_table_size_offset + string_table_size <= content.count, "String table end is out of bounds: %", path);
        string_table.data = content.data + string_table_size_offset; // The symbol table starts at the length field for whatever reason...
        string_table.count = string_table_size + size_of(u32);
    }

    offset += size_of(Coff_Header);
    if header.optional_header_size {
        optional := cast(*Coff_Optional_Header_Pe32_Plus) (coff.content.data + offset);

        set_optional_header :: (sub_header: *$T, $Header_Type: Type, $Windows_Type: Type) -> bool #expand {
            sub_header.base = cast (*Header_Type) optional;

            windows_offset := offset + size_of(Header_Type);
            sub_header.windows = cast (*Windows_Type) (coff.content.data + windows_offset);

            dir_offset := windows_offset + size_of(Windows_Type);
            remainder := header.optional_header_size - size_of(Header_Type) - size_of(Windows_Type);
            if remainder % size_of(Coff_Data_Directory) != 0 {
                log_error("Unexpected remaining size after optional header fields: %", remainder);
                return false;
            }

            directories_count := remainder / size_of(Coff_Data_Directory);
            if sub_header.windows.number_of_rva_and_sizes != directories_count {
                // In theory it would be fine if number_of_rva_and_sizes is less than the computed count.
                // But we are strict for now until we see observe that this check fails somewhere.
                //  -rluba, 2023-09-01
                log_error("Unexpected number of data directory entries: % vs %", sub_header.windows.number_of_rva_and_sizes, directories_count);
                return false;
            }

            optional_header.data_directories.data = cast(*Coff_Data_Directory) (coff.content.data + dir_offset);
            optional_header.data_directories.count = directories_count;
            if verbose {
                log("Optional header: % / %", sub_header.base.*, sub_header.windows.*);
                log("Data directories:");
                for optional_header.data_directories {
                    log("%: 0x% size: 0x%", cast(Coff_Data_Directory_Index) it_index, formatHex(it.virtual_address), formatHex(it.size));
                }
            }

            return true;
        }

        header_success: bool;
        if optional.magic == {
            case .PE32;
                header_success = set_optional_header(*optional_header.pe32, Coff_Optional_Header_Pe32, Coff_Optional_Header_Windows_Specific_Pe32);
            case .PE32_PLUS;
                header_success = set_optional_header(*optional_header.pe32plus, Coff_Optional_Header_Pe32_Plus, Coff_Optional_Header_Windows_Specific_Pe32_Plus);
            case;
                check(false, "Unexpected optional header magic: 0x%", formatHex(cast(u16) optional.magic));
        }
        check(header_success, "Could not parse optional header");

        offset += header.optional_header_size;
    }

    sections_start := offset;
    sections_end := sections_start + header.num_sections * size_of(Coff_Section_Header);
    check(sections_start <= content.count, "Section start is out of bounds: %", path);
    check(sections_end <= content.count, "Section end is out of bounds: %", path);

    section_headers.data = xx (content.data + sections_start);
    section_headers.count = xx header.num_sections;

    section_relocations = NewArray(header.num_sections, [] Coff_Relocation);

    for section_headers {
        section_name := to_string(it.name.data);
        if verbose log("Section %: %, %", it_index, section_name, it);

        check(it.pointer_to_relocations <= coff.content.count, "Section % (%): relocations start out of bounds", it_index, section_name);

        relocations_size := it.number_of_relocations * size_of(Coff_Relocation);
        check(it.pointer_to_relocations + relocations_size <= coff.content.count, "Section % (%): relocations end out of bounds", it_index, section_name);
        relocations: [] Coff_Relocation;
        relocations.data = cast(*Coff_Relocation) (content.data + it.pointer_to_relocations);
        relocations.count = it.number_of_relocations;

        // Check for relocation overflow: If there are more than 65535 relocations, the real number is in the address field of the first relocation, which must be an "ABSOLUTE" relocation.
        if it.number_of_relocations {
            r := relocations[0];
            if r.type == .ABSOLUTE {
                check(r.symbol_index == 0, "Unexpected symbol index in overflow relocation: %", r);
                if  verbose log("Found overflow relocation for section %. Real relocation count: %", it_index, r.virtual_address);
                relocations.count = r.virtual_address;
            }
        }

        section_relocations[it_index] = relocations;

        if !(it.characteristics & .CNT_UNINITIALIZED_DATA) { // Don't check bss, since it's not actually part of this file.
            check(it.pointer_to_raw_data + it.size_of_raw_data <= coff.content.count, "Section % (%): raw data is out of bounds", it_index, section_name);
        }
    }

    if optional_header.data_directories.count > xx Coff_Data_Directory_Index.Debug {
        debug_data_directory := optional_header.data_directories[xx Coff_Data_Directory_Index.Debug];
        check(debug_data_directory.size % size_of(Coff_Debug_Directory_Entry) == 0, "Debug directory has unexpected size: %", debug_data_directory.size);

        for section, section_index: section_headers {
            if debug_data_directory.virtual_address >= section.virtual_address && debug_data_directory.virtual_address + debug_data_directory.size <= section.virtual_address + section.size_of_raw_data {
                raw_data := get_section_data(coff, section_index);
                start_offset := debug_data_directory.virtual_address - section.virtual_address;
                optional_header.debug_directory_entries.data = cast(*Coff_Debug_Directory_Entry) (raw_data.data + start_offset);
                optional_header.debug_directory_entries.count = debug_data_directory.size / size_of(Coff_Debug_Directory_Entry);
                break;
            }
        }
    }

    return true, coff;
}

get_section_data :: (coff: Coff, section_index: int) -> [] u8 {
    section := coff.section_headers[section_index];
    if section.characteristics & .CNT_UNINITIALIZED_DATA {
        // Don't try to fetch bss, since it's not actually part of this file.
        return .[];
    }

    assert(section.pointer_to_raw_data + section.size_of_raw_data <= coff.content.count, "Section raw data is out of bounds", section);

    result: [] u8 = ---;
    result.data = coff.content.data + section.pointer_to_raw_data;
    result.count = xx section.size_of_raw_data;
    return result;
}

// @Stability: Calling apply_relocations on the same data more than once will yield wrong results.
apply_relocations :: (coff: Coff, section_index: int, data: [] u8) {
    section := coff.section_headers[section_index];
    relocations := coff.section_relocations[section_index];
    for relocations {
        assert(it.virtual_address >= section.virtual_address);
        offset := it.virtual_address - section.virtual_address;
        symbol := coff.symbols[it.symbol_index];
        if it.type == {
            case .ABSOLUTE; // No-op

            case .SECTION;
                assert(offset + size_of(u16) <= data.count);
                target := cast(*u16) (data.data + offset);
                target.* += symbol.section_number;
            case .SECREL;
                assert(offset + size_of(u32) <= data.count);
                target := cast(*u32) (data.data + offset);
                target.* += symbol.value;
            case;
                log_error("@Incomplete: Applying relocations of type % is not yet implemented.", it.type);
        }
    }
}

get_symbol_name :: (using coff: Coff, symbol_index: int) -> string, bool {
    if symbol_index < 0 || symbol_index >= symbols.count {
        log_error("Error: Symbol index % is out of bounds.", symbol_index);
        return "", false;
    }

    symbol := *symbols[symbol_index];
    name: string;
    if symbol.name.long_name.zeroes == 0 {
        offset := symbol.name.long_name.offset;
        if offset < 4 || offset > string_table.count {
            log_error("Error: name offset for symbol % out of bounds: 0x%", symbol_index, formatInt(symbol.name.long_name.offset, base = 16));
            return "", false;
        } else {
            // name = tprint("Long name at offset 0x%", formatHex(symbol.name.long_name.offset));
            name = to_string(string_table.data + offset);
        }
    } else {
        name.data = symbol.name.short_name.data;
        name.count = 8;
        for i: 0..7 {
            if symbol.name.short_name[i] == 0 {
                name.count = i;
                break;
            }
        }
    }
    return name, true;
}

get_pdata :: (using coff: Coff, section_index: int) -> [] Pdata_Entry {
    section := section_headers[section_index];
    section_name := to_string(section.name.data);
    assert(section_name == ".pdata");
    if (section.size_of_raw_data % size_of(Pdata_Entry) != 0) {
        log_error("Section % (%) has unexpected size: %", section_index, section_name, section.size_of_raw_data);
        return .[];
    }

    raw_data := get_section_data(coff, section_index);
    assert(raw_data.count % size_of(Pdata_Entry) == 0);
    pdata: [] Pdata_Entry;
    pdata.data = cast(*Pdata_Entry) raw_data.data;
    pdata.count = raw_data.count / size_of(Pdata_Entry);
    return pdata;
}

get_xdata :: (using coff: Coff, section_index: int, offset: u64) -> success: bool, Unwind_Info {
    section := section_headers[section_index];
    section_name := to_string(section.name.data);
    assert(section_name == ".xdata");

    raw_data := get_section_data(coff, section_index);

    if offset > cast(u64) raw_data.count {
        log_error("Section % (%): xdata at % starts out of bounds.", section_index, section_name, offset);

    }
    if offset + size_of(Unwind_Info_Header) > cast(u64) raw_data.count {
        log_error("Section % (%): xdata at % ends out of bounds.", section_index, section_name, offset);
        return false, .{};
    }

    unwind_header := cast(*Unwind_Info_Header) (raw_data.data + offset);
    info: Unwind_Info;
    info.version = unwind_header.version_flags & 0x7;
    info.flags = cast(Unwind_Info_Flags) ((unwind_header.version_flags & 0xF8) >> 3);
    info.prolog_size = unwind_header.prolog_size;
    info.frame_register = unwind_header.frame_register & 0xF;
    info.scaled_frame_register_offset = (unwind_header.frame_register & 0xF0) >> 4;

    unwind_codes_offset := offset + size_of(Unwind_Info_Header);
    unwind_codes_end := unwind_codes_offset + unwind_header.num_unwind_codes * 2;
    if unwind_codes_offset > cast(u64) raw_data.count {
        log_error("Section % (%): unwind codes start is out of bounds", section_index, section_name);
        return false, .{};
    }
    if unwind_codes_end > cast(u64) raw_data.count {
        log_error("Section % (%): unwind codes end is out of bounds", section_index, section_name);
        return false, .{};
    }
    info.unwind_codes.data = cast(*u16) (raw_data.data + unwind_codes_offset);
    info.unwind_codes.count = unwind_header.num_unwind_codes;

    if (info.flags & .CHAININFO) {
        if (unwind_codes_end + size_of(Pdata_Entry) > cast(u64) raw_data.count) {
            log_error("Section % (%): chained unwind info is out of bounds", section_index, section_name);
            return false, .{};
        }
        info.extra.chained = cast (*Pdata_Entry) (raw_data.data + unwind_codes_end);
    } else if (info.flags & .EHANDLER || info.flags & .UHANDLER) {
        if (unwind_codes_end + size_of(Unwind_Info_Exception_Handler) > cast(u64) raw_data.count) {
            log_error("Section % (%): exception handler unwind info is out of bounds", section_index, section_name);
            return false, .{};
        }
        info.extra.handler = cast (*Unwind_Info_Exception_Handler) (raw_data.data + unwind_codes_end);
    }
    return true, info;
}

Coff_Header :: struct {
    machine:              Machine_Type;
    num_sections:         u16;
    timestamp:            u32;
    symbol_table_offset:  u32;
    num_symbols:          u32;
    optional_header_size: u16;
    characteristics:      Header_Characteristics;
}

Coff_Optional_Header :: struct {
    union {
        pe32: struct {
            base:    *Coff_Optional_Header_Pe32;
            windows: *Coff_Optional_Header_Windows_Specific_Pe32;
        }
        pe32plus:    struct {
            base:    *Coff_Optional_Header_Pe32_Plus;
            windows: *Coff_Optional_Header_Windows_Specific_Pe32_Plus;
        }
    };
    data_directories: [] Coff_Data_Directory;
    debug_directory_entries: [] Coff_Debug_Directory_Entry;
}

Coff_Optional_Header_Pe32_Plus :: struct {
    magic:                      Magic; // The unsigned integer that identifies the state of the image file. The most common number is 0x10B, which identifies it as a normal executable file. 0x107 identifies it as a ROM image, and 0x20B identifies it as a PE32+ executable.
    major_linker_version:       u8;    // The linker major version number.
    minor_linker_version:       u8;    // The linker minor version number.
    size_of_code:               u32;   // The size of the code (text) section, or the sum of all code sections if there are multiple sections.
    size_of_initialized_data:   u32;   // The size of the initialized data section, or the sum of all such sections if there are multiple data sections.
    size_of_uninitialized_data: u32;   // The size of the uninitialized data section (BSS), or the sum of all such sections if there are multiple BSS sections.
    address_of_entry_point:     u32;   // The address of the entry point relative to the image base when the executable file is loaded into memory. For program images, this is the starting address. For device drivers, this is the address of the initialization function. An entry point is optional for DLLs. When no entry point is present, this field must be zero.
    base_of_code:               u32;   // The address that is relative to the image base of the beginning-of-code section when it is loaded into memory.

    Magic :: enum u16 {
        PE32      :: 0x010b;
        PE32_PLUS :: 0x020b;
    }
}

Coff_Optional_Header_Pe32 :: struct {
    using base: Coff_Optional_Header_Pe32_Plus;

    base_of_data:               u32; // The address that is relative to the image base of the beginning-of-data section when it is loaded into memory.
}

Coff_Optional_Header_Windows_Specific :: struct (Size_Offset_Type: Type) {
    image_base:                     Size_Offset_Type;       // The preferred address of the first byte of image when loaded into memory; must be a multiple of 64 K. The default for DLLs is 0x10000000. The default for Windows CE EXEs is 0x00010000. The default for Windows NT, Windows 2000, Windows XP, Windows 95, Windows 98, and Windows Me is 0x00400000.
    section_alignment:              u32;                    // The alignment (in bytes) of sections when they are loaded into memory. It must be greater than or equal to FileAlignment. The default is the page size for the architecture.
    file_alignment:                 u32;                    // The alignment factor (in bytes) that is used to align the raw data of sections in the image file. The value should be a power of 2 between 512 and 64 K, inclusive. The default is 512. If the SectionAlignment is less than the architecture's page size, then FileAlignment must match SectionAlignment.
    major_operating_system_version: u16;                    // The major version number of the required operating system.
    minor_operating_system_version: u16;                    // The minor version number of the required operating system.
    major_image_version:            u16;                    // The major version number of the image.
    minor_image_version:            u16;                    // The minor version number of the image.
    major_subsystem_version:        u16;                    // The major version number of the subsystem.
    minor_subsystem_version:        u16;                    // The minor version number of the subsystem.
    win32_version_value:            u32;                    // Reserved, must be zero.
    size_of_image:                  u32;                    // The size (in bytes) of the image, including all headers, as the image is loaded in memory. It must be a multiple of SectionAlignment.
    size_of_headers:                u32;                    // The combined size of an MS-DOS stub, PE header, and section headers rounded up to a multiple of FileAlignment.
    check_sum:                      u32;                    // The image file checksum. The algorithm for computing the checksum is incorporated into IMAGHELP.DLL. The following are checked for validation at load time: all drivers, any DLL loaded at boot time, and any DLL that is loaded into a critical Windows process.
    subsystem:                      Windows_Subsystem_Type; // The subsystem that is required to run this image. For more information, see Windows Subsystem.
    dll_characteristics:            Windows_Dll_Characteristics; // For more information, see DLL Characteristics later in this specification.
    size_of_stack_reserve:          Size_Offset_Type;       // The size of the stack to reserve. Only SizeOfStackCommit is committed; the rest is made available one page at a time until the reserve size is reached.
    size_of_stack_commit:           Size_Offset_Type;       // The size of the stack to commit.
    size_of_heap_reserve:           Size_Offset_Type;       // The size of the local heap space to reserve. Only SizeOfHeapCommit is committed; the rest is made available one page at a time until the reserve size is reached.
    size_of_heap_commit:            Size_Offset_Type;       // The size of the local heap space to commit.
    loader_flags:                   u32;                    // Reserved, must be zero.
    number_of_rva_and_sizes:        u32;                    // The number of data-directory entries in the remainder of the optional header. Each describes a location and size.
}

Coff_Optional_Header_Windows_Specific_Pe32      :: Coff_Optional_Header_Windows_Specific(u32);
Coff_Optional_Header_Windows_Specific_Pe32_Plus :: Coff_Optional_Header_Windows_Specific(u64);

Coff_Data_Directory :: struct {
    virtual_address: u32;
    size: u32;
}

Coff_Data_Directory_Index :: enum {
    Export_Table            :: 0;  // The export table address and size. For more information see .edata Section (Image Only).
    Import_Table            :: 1;  // The import table address and size. For more information, see The .idata Section.
    Resource_Table          :: 2;  // The resource table address and size. For more information, see The .rsrc Section.
    Exception_Table         :: 3;  // The exception table address and size. For more information, see The .pdata Section.
    Certificate_Table       :: 4;  // The attribute certificate table address and size. For more information, see The Attribute Certificate Table (Image Only).
    Base_Relocation_Table   :: 5;  // The base relocation table address and size. For more information, see The .reloc Section (Image Only).
    Debug                   :: 6;  // The debug data starting address and size. For more information, see The .debug Section.
    Architecture            :: 7;  // Reserved, must be 0
    Global_Ptr              :: 8;  // The RVA of the value to be stored in the global pointer register. The size member of this structure must be set to zero.
    TLS_Table               :: 9;  // The thread local storage (TLS) table address and size. For more information, see The .tls Section.
    Load_Config_Table       :: 10; // The load configuration table address and size. For more information, see The Load Configuration Structure (Image Only).
    Bound_Import            :: 11; // The bound import table address and size.
    IAT                     :: 12; // The import address table address and size. For more information, see Import Address Table.
    Delay_Import_Descriptor :: 13; // The delay import descriptor address and size. For more information, see Delay-Load Import Tables (Image Only).
    CLR_Runtime_Header      :: 14; // The CLR runtime header address and size. For more information, see The .cormeta Section (Object Only).
    Reserved                :: 15; // must be zero
}

Coff_Debug_Directory_Entry :: struct {
    characteristics:     u32; // Reserved, must be zero.
    time_date_stamp:     u32; // The time and date that the debug data was created.
    major_version:       u16; // The major version number of the debug data format.
    minor_version:       u16; // The minor version number of the debug data format.
    type:                Coff_Debug_Type; // The format of debugging information. This field enables support of multiple debuggers. For more information, see Debug Type.
    size_of_data:        u32; // The size of the debug data (not including the debug directory itself).
    address_of_raw_data: u32; // The address of the debug data when loaded, relative to the image base.
    pointer_to_raw_data: u32; // The file pointer to the debug data.
}

Coff_Debug_Type :: enum u32 {
    TYPE_UNKNOWN               :: 0;  //  An unknown value that is ignored by all tools.
    TYPE_COFF                  :: 1;  //  The COFF debug information (line numbers, symbol table, and string table). This type of debug information is also pointed to by fields in the file headers.
    TYPE_CODEVIEW              :: 2;  //  The Visual C++ debug information.
    TYPE_FPO                   :: 3;  //  The frame pointer omission (FPO) information. This information tells the debugger how to interpret nonstandard stack frames, which use the EBP register for a purpose other than as a frame pointer.
    TYPE_MISC                  :: 4;  //  The location of DBG file.
    TYPE_EXCEPTION             :: 5;  //  A copy of .pdata section.
    TYPE_FIXUP                 :: 6;  //  Reserved.
    TYPE_OMAP_TO_SRC           :: 7;  //  The mapping from an RVA in image to an RVA in source image.
    TYPE_OMAP_FROM_SRC         :: 8;  //  The mapping from an RVA in source image to an RVA in image.
    TYPE_BORLAND               :: 9;  //  Reserved for Borland.
    TYPE_RESERVED10            :: 10; //  Reserved.
    TYPE_CLSID                 :: 11; //  Reserved.
    TYPE_REPRO                 :: 16; //  PE determinism or reproducibility.
    TYPE_EMBEDDED              :: 17; //  Debugging information is embedded in the PE file at location specified by PointerToRawData.
    TYPE_CRYPTO_HASH           :: 19; // Stores crypto hash for the content of the symbol file used to build the PE/COFF file.
    TYPE_EX_DLLCHARACTERISTICS :: 20; // Extended DLL characteristics bits.
}

Coff_Raw_Codeview_Info :: struct {
    rsds:     [4] u8;
    pdb_guid: Guid;
    pdb_age:  u32;
    // Followed by pdb_path string;
}

Coff_Codeview_Info :: struct {
    using base: Coff_Raw_Codeview_Info;
    pdb_path: string;
}

Coff_Section_Header :: struct {
    name:                    [8] u8; // Padded with zeros, but not necessarily zero-terminated!
    virtual_size:            u32;
    virtual_address:         u32;
    size_of_raw_data:        u32;
    pointer_to_raw_data:     u32;
    pointer_to_relocations:  u32;
    pointer_to_line_numbers: u32;
    number_of_relocations:   u16;
    number_of_line_numbers:  u16;
    characteristics:         Section_Characteristics;
}

get_section_name :: (header: Coff_Section_Header) -> string {
    return string_from_zero_padded_array(header.name);
}

Machine_Type :: enum u16 {
    UNKNOWN     :: 0x0 ; // The content of this field is assumed to be applicable to any machine type
    AM33        :: 0x1d3 ; // Matsushita AM33
    AMD64       :: 0x8664; // x64
    ARM         :: 0x1c0 ; // ARM little endian
    ARM64       :: 0xaa64; // ARM64 little endian
    ARMNT       :: 0x1c4 ; // ARM Thumb-2 little endian
    EBC         :: 0xebc ; // EFI byte code
    I386        :: 0x14c ; // Intel 386 or later processors and compatible processors
    IA64        :: 0x200 ; // Intel Itanium processor family
    LOONGARCH32 :: 0x6232; // LoongArch 32-bit processor family
    LOONGARCH64 :: 0x6264; // LoongArch 64-bit processor family
    M32R        :: 0x9041; // Mitsubishi M32R little endian
    MIPS16      :: 0x266 ; // MIPS16
    MIPSFPU     :: 0x366 ; // MIPS with FPU
    MIPSFPU16   :: 0x466 ; // MIPS16 with FPU
    POWERPC     :: 0x1f0 ; // Power PC little endian
    POWERPCFP   :: 0x1f1 ; // Power PC with floating point support
    R4000       :: 0x166 ; // MIPS little endian
    RISCV32     :: 0x5032; // RISC-V 32-bit address space
    RISCV64     :: 0x5064; // RISC-V 64-bit address space
    RISCV128    :: 0x5128; // RISC-V 128-bit address space
    SH3         :: 0x1a2 ; // Hitachi SH3
    SH3DSP      :: 0x1a3 ; // Hitachi SH3 DSP
    SH4         :: 0x1a6 ; // Hitachi SH4
    SH5         :: 0x1a8 ; // Hitachi SH5
    THUMB       :: 0x1c2 ; // Thumb
    WCEMIPSV2   :: 0x169 ; // MIPS little-endian WCE v2
}

Header_Characteristics :: enum_flags u16 {
    RELOCS_STRIPPED         :: 0x0001; // Image only, Windows CE, and Microsoft Windows NT and later. This indicates that the file does not contain base relocations and must therefore be loaded at its preferred base address. If the base address is not available, the loader reports an error. The default behavior of the linker is to strip base relocations from executable (EXE) files.
    EXECUTABLE_IMAGE        :: 0x0002; // Image only. This indicates that the image file is valid and can be run. If this flag is not set, it indicates a linker error.
    LINE_NUMS_STRIPPED      :: 0x0004; // COFF line numbers have been removed. This flag is deprecated and should be zero.
    LOCAL_SYMS_STRIPPED     :: 0x0008; // COFF symbol table entries for local symbols have been removed. This flag is deprecated and should be zero.
    AGGRESSIVE_WS_TRIM      :: 0x0010; // Obsolete. Aggressively trim working set. This flag is deprecated for Windows 2000 and later and must be zero.
    LARGE_ADDRESS_AWARE     :: 0x0020; // Application can handle > 2-GB addresses.
    // 0x0040 This flag is reserved for future use.
    BYTES_REVERSED_LO       :: 0x0080; // Little endian: the least significant bit (LSB) precedes the most significant bit (MSB) in memory. This flag is deprecated and should be zero.
    _32BIT_MACHINE          :: 0x0100; // Machine is based on a 32-bit-word architecture.
    DEBUG_STRIPPED          :: 0x0200; // Debugging information is removed from the image file.
    REMOVABLE_RUN_FROM_SWAP :: 0x0400; // If the image is on removable media, fully load it and copy it to the swap file.
    NET_RUN_FROM_SWAP       :: 0x0800; // If the image is on network media, fully load it and copy it to the swap file.
    SYSTEM                  :: 0x1000; // The image file is a system file, not a user program.
    DLL                     :: 0x2000; // The image file is a dynamic-link library (DLL). Such files are considered executable files for almost all purposes, although they cannot be directly run.
    UP_SYSTEM_ONLY          :: 0x4000; // The file should be run only on a uniprocessor machine.
    BYTES_REVERSED_HI       :: 0x8000; // Big endian: the MSB precedes the LSB in memory. This flag is deprecated and should be zero.
}

Windows_Subsystem_Type :: enum u16 {
    UNKNOWN                  :: 0;  // An unknown subsystem
    NATIVE                   :: 1;  // Device drivers and native Windows processes
    WINDOWS_GUI              :: 2;  // The Windows graphical user interface (GUI) subsystem
    WINDOWS_CUI              :: 3;  // The Windows character subsystem
    OS2_CUI                  :: 5;  // The OS/2 character subsystem
    POSIX_CUI                :: 7;  // The Posix character subsystem
    NATIVE_WINDOWS           :: 8;  // Native Win9x driver
    WINDOWS_CE_GUI           :: 9;  // Windows CE
    EFI_APPLICATION          :: 10; // An Extensible Firmware Interface (EFI) application
    EFI_BOOT_SERVICE_DRIVER  :: 11; // An EFI driver with boot services
    EFI_RUNTIME_DRIVER       :: 12; // An EFI driver with run-time services
    EFI_ROM                  :: 13; // An EFI ROM image
    XBOX                     :: 14; // XBOX
    WINDOWS_BOOT_APPLICATION :: 16; // Windows boot application.
}

Windows_Dll_Characteristics :: enum_flags u16 {
    HIGH_ENTROPY_VA       :: 0x0020; // Image can handle a high entropy 64-bit virtual address space.
    DYNAMIC_BASE          :: 0x0040; // DLL can be relocated at load time.
    FORCE_INTEGRITY       :: 0x0080; // Code Integrity checks are enforced.
    NX_COMPAT             :: 0x0100; // Image is NX compatible.
    NO_ISOLATION          :: 0x0200; // Isolation aware, but do not isolate the image.
    NO_SEH                :: 0x0400; // Does not use structured exception (SE) handling. No SE handler may be called in this image.
    NO_BIND               :: 0x0800; // Do not bind the image.
    APPCONTAINER          :: 0x1000; // Image must execute in an AppContainer.
    WDM_DRIVER            :: 0x2000; // A WDM driver.
    GUARD_CF              :: 0x4000; // Image supports Control Flow Guard.
    TERMINAL_SERVER_AWARE :: 0x8000; // Terminal Server aware.
}

Section_Characteristics :: enum_flags u32 {
    // 0x00000000 Reserved for future use.
    // 0x00000001 Reserved for future use.
    // 0x00000002 Reserved for future use.
    // 0x00000004 Reserved for future use.
    TYPE_NO_PAD            :: 0x00000008; // The section should not be padded to the next boundary. This flag is obsolete and is replaced by ALIGN_1BYTES. This is valid only for object files.
    // 0x00000010 Reserved for future use.
    CNT_CODE               :: 0x00000020; // The section contains executable code.
    CNT_INITIALIZED_DATA   :: 0x00000040; // The section contains initialized data.
    CNT_UNINITIALIZED_DATA :: 0x00000080; // The section contains uninitialized data.
    LNK_OTHER              :: 0x00000100; // Reserved for future use.
    LNK_INFO               :: 0x00000200; // The section contains comments or other information. The .drectve section has this type. This is valid for object files only.
    // 0x00000400 Reserved for future use.
    LNK_REMOVE             :: 0x00000800; // The section will not become part of the image. This is valid only for object files.
    LNK_COMDAT             :: 0x00001000; // The section contains COMDAT data. For more information, see COMDAT Sections (Object Only). This is valid only for object files.
    GPREL                  :: 0x00008000; // The section contains data referenced through the global pointer (GP).
    MEM_PURGEABLE          :: 0x00020000; // Reserved for future use.
    MEM_16BIT              :: 0x00020000; // Reserved for future use.
    MEM_LOCKED             :: 0x00040000; // Reserved for future use.
    MEM_PRELOAD            :: 0x00080000; // Reserved for future use.
    ALIGN_1BYTES           :: 0x00100000; // Align data on a 1-byte boundary. Valid only for object files.
    ALIGN_2BYTES           :: 0x00200000; // Align data on a 2-byte boundary. Valid only for object files.
    ALIGN_4BYTES           :: 0x00300000; // Align data on a 4-byte boundary. Valid only for object files.
    ALIGN_8BYTES           :: 0x00400000; // Align data on an 8-byte boundary. Valid only for object files.
    ALIGN_16BYTES          :: 0x00500000; // Align data on a 16-byte boundary. Valid only for object files.
    ALIGN_32BYTES          :: 0x00600000; // Align data on a 32-byte boundary. Valid only for object files.
    ALIGN_64BYTES          :: 0x00700000; // Align data on a 64-byte boundary. Valid only for object files.
    ALIGN_128BYTES         :: 0x00800000; // Align data on a 128-byte boundary. Valid only for object files.
    ALIGN_256BYTES         :: 0x00900000; // Align data on a 256-byte boundary. Valid only for object files.
    ALIGN_512BYTES         :: 0x00A00000; // Align data on a 512-byte boundary. Valid only for object files.
    ALIGN_1024BYTES        :: 0x00B00000; // Align data on a 1024-byte boundary. Valid only for object files.
    ALIGN_2048BYTES        :: 0x00C00000; // Align data on a 2048-byte boundary. Valid only for object files.
    ALIGN_4096BYTES        :: 0x00D00000; // Align data on a 4096-byte boundary. Valid only for object files.
    ALIGN_8192BYTES        :: 0x00E00000; // Align data on an 8192-byte boundary. Valid only for object files.
    LNK_NRELOC_OVFL        :: 0x01000000; // The section contains extended relocations.
    MEM_DISCARDABLE        :: 0x02000000; // The section can be discarded as needed.
    MEM_NOT_CACHED         :: 0x04000000; // The section cannot be cached.
    MEM_NOT_PAGED          :: 0x08000000; // The section is not pageable.
    MEM_SHARED             :: 0x10000000; // The section can be shared in memory.
    MEM_EXECUTE            :: 0x20000000; // The section can be executed as code.
    MEM_READ               :: 0x40000000; // The section can be read.
    MEM_WRITE              :: 0x80000000; // The section can be written to.
}

Pdata_Entry :: struct {
    begin_address:       u32;
    end_address:         u32;
    unwind_info_address: u32;
}

Coff_Relocation :: struct {
    virtual_address: u32;
    symbol_index:    u32;
    type:            Coff_Relocation_Type_x64;
} #no_padding;
#run assert(size_of(Coff_Relocation) == 10);

Coff_Relocation_Type_x64 :: enum u16 {
    ABSOLUTE :: 0x0000; // The relocation is ignored.
    ADDR64   :: 0x0001; // The 64-bit VA of the relocation target.
    ADDR32   :: 0x0002; // The 32-bit VA of the relocation target.
    ADDR32NB :: 0x0003; // The 32-bit address without an image base (RVA).
    REL32    :: 0x0004; // The 32-bit relative address from the byte following the relocation.
    REL32_1  :: 0x0005; // The 32-bit address relative to byte distance 1 from the relocation.
    REL32_2  :: 0x0006; // The 32-bit address relative to byte distance 2 from the relocation.
    REL32_3  :: 0x0007; // The 32-bit address relative to byte distance 3 from the relocation.
    REL32_4  :: 0x0008; // The 32-bit address relative to byte distance 4 from the relocation.
    REL32_5  :: 0x0009; // The 32-bit address relative to byte distance 5 from the relocation.
    SECTION  :: 0x000A; // The 16-bit section index of the section that contains the target. This is used to support debugging information.
    SECREL   :: 0x000B; // The 32-bit offset of the target from the beginning of its section. This is used to support debugging information and static thread local storage.
    SECREL7  :: 0x000C; // A 7-bit unsigned offset from the base of the section that contains the target.
    TOKEN    :: 0x000D; // CLR tokens.
    SREL32   :: 0x000E; // A 32-bit signed span-dependent value emitted into the object.
    PAIR     :: 0x000F; // A pair that must immediately follow every span-dependent value.
    SSPAN32  :: 0x0010; // A 32-bit signed span-dependent value that is applied at link time.
}

Coff_Symbol :: struct {
    name: union {
        short_name: [8] u8;
        long_name: struct {
            zeroes: u32;
            offset: u32;
        };
    };
    value:                 u32;
    section_number:        u16;
    type:                  u16;
    storage_class:         Coff_Symbol_Storage_Class;
    number_of_aux_symbols: u8;
} #no_padding;
#run assert(size_of(Coff_Symbol) == 18);

Coff_Symbol_Storage_Class :: enum u8 {
    END_OF_FUNCTION  :: 0xFF;// A special symbol that represents the end of function, for debugging purposes.
    NULL             :: 0;   // No assigned storage class.
    AUTOMATIC        :: 1;   // The automatic (stack) variable. The Value field specifies the stack frame offset.
    EXTERNAL         :: 2;   // A value that Microsoft tools use for external symbols. The Value field indicates the size if the section number is IMAGE_SYM_UNDEFINED (0). If the section number is not zero, then the Value field specifies the offset within the section.
    STATIC           :: 3;   // The offset of the symbol within the section. If the Value field is zero, then the symbol represents a section name.
    REGISTER         :: 4;   // A register variable. The Value field specifies the register number.
    EXTERNAL_DEF     :: 5;   // A symbol that is defined externally.
    LABEL            :: 6;   // A code label that is defined within the module. The Value field specifies the offset of the symbol within the section.
    UNDEFINED_LABEL  :: 7;   // A reference to a code label that is not defined.
    MEMBER_OF_STRUCT :: 8;   // The structure member. The Value field specifies the n th member.
    ARGUMENT         :: 9;   // A formal argument (parameter) of a function. The Value field specifies the n th argument.
    STRUCT_TAG       :: 10;  // The structure tag-name entry.
    MEMBER_OF_UNION  :: 11;  // A union member. The Value field specifies the n th member.
    UNION_TAG        :: 12;  // The Union tag-name entry.
    TYPE_DEFINITION  :: 13;  // A Typedef entry.
    UNDEFINED_STATIC :: 14;  // A static data declaration.
    ENUM_TAG         :: 15;  // An enumerated type tagname entry.
    MEMBER_OF_ENUM   :: 16;  // A member of an enumeration. The Value field specifies the n th member.
    REGISTER_PARAM   :: 17;  // A register parameter.
    BIT_FIELD        :: 18;  // A bit-field reference. The Value field specifies the n th bit in the bit field.
    BLOCK            :: 100; // A .bb (beginning of block) or .eb (end of block) record. The Value field is the relocatable address of the code location.
    FUNCTION         :: 101; // A value that Microsoft tools use for symbol records that define the extent of a function: begin function (.bf ), end function ( .ef ), and lines in function ( .lf ). For .lf records, the Value field gives the number of source lines in the function. For .ef records, the Value field gives the size of the function code.
    END_OF_STRUCT    :: 102; // An end-of-structure entry.
    FILE             :: 103; // A value that Microsoft tools, as well as traditional COFF format, use for the source-file symbol record. The symbol is followed by auxiliary records that name the file.
    SECTION          :: 104; // A definition of a section (Microsoft tools use STATIC storage class instead).
    WEAK_EXTERNAL    :: 105; // A weak external. For more information, see Auxiliary Format 3: Weak Externals.
    CLR_TOKEN        :: 107; // A CLR token symbol. The name is an ASCII string that consists of the hexadecimal value of the token. For more information, see CLR Token Definition (Object Only).
}

Unwind_Info_Header :: struct {
    version_flags: u8; // 3 bits version, 5 bits flags
    prolog_size: u8;
    num_unwind_codes: u8;
    frame_register: u8; // 4 bits register, 4 bits offset (scaled)
    // … followed by (num_unwind_codes * u16) unwind codes
    // … followed by either Unwind_Info_Exception_Handler or a Pdata_Entry (= chained unwind info), depending on the flags
}

// Decoded version of Unwind_Info_Header
Unwind_Info :: struct {
    version: u8;
    flags: Unwind_Info_Flags;
    prolog_size: u8;
    frame_register: u8;
    scaled_frame_register_offset: u8; // Actual value = <this field> * 16
    unwind_codes: [] u16; // Some of these are Unwind_Code, some are additional data for the preceeding code.
    extra: union {
        handler: *Unwind_Info_Exception_Handler;
        chained: *Pdata_Entry;
    }
}

Unwind_Info_Flags :: enum_flags u8 {
    NHANDLER  :: 0x0;
    EHANDLER  :: 0x1;
    UHANDLER  :: 0x2;
    CHAININFO :: 0x4;
}

Unwind_Info_Exception_Handler :: struct {
    address: u32;
    // + variable data
}

Unwind_Code :: struct {
    prolog_offset: u8;
    code_info: u8; // 4 bit Unwind_Operation_Code, 4 bit operation info
}

Unwind_Operation_Code :: enum u8 {
    PUSH_NONVOL          :: 0;
    ALLOC_LARGE     :: 1;
    ALLOC_SMALL     :: 2;
    SET_FPREG       :: 3;
    SAVE_NONVOL     :: 4;
    SAVE_NONVOL_FAR :: 5;

    SAVE_XMM128     :: 8;
    SAVE_XMM128_FAR :: 9;
    PUSH_MACHFRAME  :: 10;
}

Unwind_Operation_Info_Register :: enum {
    RAX :: 0;
    RCX :: 1;
    RDX :: 2;
    RBX :: 3;
    RSP :: 4;
    RBP :: 5;
    RSI :: 6;
    RDI :: 7;
    R8  :: 8;
    R9  :: 9;
    R10 :: 10;
    R11 :: 11;
    R12 :: 12;
    R13 :: 13;
    R14 :: 14;
    R15 :: 15;
}

#scope_module

#import "debug_info"; // For Guid
