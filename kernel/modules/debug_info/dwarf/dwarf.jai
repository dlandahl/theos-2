// parse_dwarf_debug_info() parses and combines the raw data of the various debug segments.
//
// The debug types are fully parsed but they are not yet converted into any data structures, only printed (if verbose = true).

Debug_Info :: struct {
    compilation_units: [..] Compilation_Unit;
}

Compilation_Unit :: struct {
    producer:       string;
    language:       u16;
    name:           string;
    statement_list: u64; // Could be removed. We only need it until we’ve parsed the line info.
    low_pc:         u64;
    high_pc:        u64;
    types:          [..] Debug_Type;
    line_info:      Line_Info;

    // @Incomplete: We’re parsing all the debug information, but we’re only keeping track the following things for now:
    subprograms:    Bucket_Array(Subprogram, 32);
    globals:        [..] Declaration;
}

Debug_Type :: struct {
    offset:    s64;
    tag:       Dwarf_Tag;
    name:      string;
    size:      u64;

    base_type: Dwarf_Base_Type;
}

Subprogram :: struct {
    name:               string;
    linkage_name:       string;
    external:           bool;
    decl_file_id:       Dwarf_File_Id;
    decl_line:          u32;
    type_id:            u32;
    is_main:            bool;
    calling_convention: u8; // @ToDO: Enumify?
    low_pc:             u64;
    high_pc:            u64;

    all_blocks:         Bucket_Array(Lexical_Block, 8); // Includes all nested blocks
    root_block:         *Lexical_Block;
}

Declaration :: struct {
    tag:          Dwarf_Tag;
    name:         string;
    decl_file_id: Dwarf_File_Id;
    decl_line:    u32;
    type_id:      u32;
    kind: enum {
        PARAMETER;
        VARIABLE;
    }
}

Lexical_Block :: struct {
    low_pc:       u64;
    high_pc:      u64;

    declarations: [..] Declaration;
    children:     [..] *Lexical_Block;
}

Frame_Common_Information_Entry :: struct {
    length:                  u64;
    id:                      u32;
    version:                 u8;
    augmentation:            string;
    eh_data:                 u64;
    code_alignment_factor:   u64;
    data_alignment_factor:   s64;
    return_address_register: u64;
    augmentation_data:       [] u8;
    initial_instructions:    [] Call_Frame_Address_Instruction;

    offset:                  u64;
}

Frame_Description_Entry :: struct {
    length:            u64;
    cie_offset:        u64;
    pc_begin:          u64;
    pc_range:          u64;
    augmentation_data: [] u8;
    instructions:      [] Call_Frame_Address_Instruction;
}

Call_Frame_Address_Instruction :: struct {
    type: Call_Frame_Address_Instruction_Type;
    arg1: Argument;
    arg2: Argument;

    Argument :: union {
        uvalue: u64;
        svalue: s64;
        // @ToDo: Dwarf expression block
    }
}


parse_dwarf_debug_info :: (debug_info_data: [] u8, abbrev: [] u8, line_programs: [] u8, debug_string_data: [] u8, verbose := false) -> Debug_Info, success: bool {
    parse_context: Parse_Context;
    parse_context.verbose = verbose;
    parse_context.debug_string_data = debug_string_data;

    cu_index := 0;
    offset := 0;
    while offset < debug_info_data.count {
        defer cu_index += 1;

        header := cast (*Compliation_Unit_Header_32) (debug_info_data.data + offset);
        if header.size == 0xffff_ffff {
            log_error("Compilation unit %: We dont support 64 bit DWARF format yet.", cu_index);
            return parse_context.debug_info, false;
        }

        cu_end := offset + size_of(type_of(header.size)) + header.size;
        if cu_end > debug_info_data.count {
            log_error("Compilation unit % has invalid size: %\n", cu_index, header.size);
            return parse_context.debug_info, false;
        }

        full_cu_data := array_view(debug_info_data, offset, cu_end - offset);

        defer offset = cu_end;

        if header.version == {
            case 4;
                cu, success := parse_compilation_unit_v4(*parse_context, cu_index, offset, full_cu_data, abbrev, line_programs);
                if !success return parse_context.debug_info, false;
                array_add(*parse_context.debug_info.compilation_units, cu);

            // case 5;
            //     log("Found Dwarf version 5, w");
            case;
                log_error("Compilation unit % has unsupported DWARF version %. Skipping...\n", cu_index, header.version);
                offset = cu_end;
                continue;
        }
    }

    // log("Found % compilation units", cu_index);

    return parse_context.debug_info, true;
}

parse_compilation_unit_v4 :: (using parse_context: *Parse_Context, cu_index: int, offset: int, full_cu_data: [] u8, abbrev: [] u8, line_programs: [] u8) -> Compilation_Unit, success: bool {
    cu: Compilation_Unit = ---;
    Initialize(*cu.globals);
    current_compilation_unit = *cu;
    defer current_compilation_unit = null;

    header := cast (*Compliation_Unit_Header_32) full_cu_data.data;
    if header.address_size != 8 {
        log_error("Compilation unit % has unexpected address_size: %\n", cu_index, header.address_size);
        return cu, false;
    }

    // log("Compilation unit header: %\n", header.*);
    abbreviations, success := parse_abbreviations(abbrev, header.debug_abbrev_offset);
    if !success     return cu, false;

    cu_start := size_of(Compliation_Unit_Header_32);
    cu_data := array_view(full_cu_data, cu_start, full_cu_data.count - cu_start);
    cu, success = parse_compilation_unit_content_v4(parse_context, offset, cu_data, abbreviations);
    if !success     return cu, false;

    statement_list_data := array_view(line_programs, xx cu.statement_list);
    cu.line_info, success = decode_line_info(statement_list_data);
    if !success     return cu, false;

    if !cu.low_pc && cu.line_info.sequences.count {
        first := cu.line_info.sequences[0];
        last := cu.line_info.sequences[cu.line_info.sequences.count - 1];
        cu.low_pc = first.addresses[0];
        cu.high_pc = last.addresses[last.addresses.count - 1];
    }

    return cu, true;
}

get_type :: (cu: Compilation_Unit, type: u32) -> *Debug_Type {
    for * cu.types {
        if it.offset == type return it;
    }
    return null;
}

parse_common_information_entry :: (data: [] u8, offset_in: s64) -> success: bool, Frame_Common_Information_Entry, offset: s64 {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false, `cie, `offset;
        }
    }

    offset := offset_in;
    success: bool;

    cie: Frame_Common_Information_Entry;
    cie.offset = cast(u64) offset_in;

    cie.length, offset, success = parse_integer(data, offset, u32);
    if success && cie.length == 0xFFFF_FFFF {
        cie.length, offset, success = parse_integer(data, offset, u64);
    }
    check(success, "Could not parse CIE length");

    if cie.length == 0 return true, cie, offset;

    start := offset;
    end := offset + cast(s64) cie.length;
    check(end <= data.count, "Invalid CIE length: %", cie.length);

    cie.id, offset, success = parse_integer(data, offset, u32);
    check(success, "Could not parse CIE ID");
    check(cie.id == 0, "Unexpected CIE ID: %", cie.id);
    cie.version, offset, success = parse_integer(data, offset, u8);
    check(success, "Could not parse CIE version");
    check(cie.version == 1, "Unexpected CIE version: %", cie.version);

    cie.augmentation, success = get_c_string_from_data(data, offset);
    check(success, "Could not parse CIE augmentation string");
    offset += cie.augmentation.count + 1;

    if find_index_from_left(cie.augmentation, "eh") != -1 {
        cie.eh_data, offset, success = parse_uleb128(data, offset);
        check(success, "Could not parse CIE EH data");
    }

    cie.code_alignment_factor, offset, success = parse_uleb128(data, offset);
    check(success, "Could not parse CIE code alignment factor");
    cie.data_alignment_factor, offset, success = parse_sleb128(data, offset);
    check(success, "Could not parse CIE data alignment factor");
    cie.return_address_register, offset, success = parse_uleb128(data, offset);
    check(success, "Could not parse CIE return address register");

    if begins_with(cie.augmentation, "z") {
        count: u64;
        count, offset, success = parse_uleb128(data, offset);
        check(success, "Could not parse CIE agumentation data length");
        cie.augmentation_data.count = cast(s64) count;
        cie.augmentation_data.data = data.data + offset;
        offset += cie.augmentation_data.count;
    }

    check(offset <= end, "CIE went past its supposed length: % vs %", offset, end);
    remaining := end - offset;
    instruction_data: [] u8;
    instruction_data.count = remaining;
    instruction_data.data = data.data + offset;
    offset += remaining;

    cie.initial_instructions, success = decode_cfa_instructions(instruction_data);

    return success, cie, offset;
}

parse_frame_description_entry :: (cie: Frame_Common_Information_Entry, frame_section_address: u64, data: [] u8, offset_in: s64) -> success: bool, Frame_Description_Entry, offset: s64 {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false, `fde, `offset;
        }
    }

    offset := offset_in;
    success: bool;

    fde: Frame_Description_Entry;

    fde.length, offset, success = parse_integer(data, offset, u32);
    if success && fde.length == 0xFFFF_FFFF {
        fde.length, offset, success = parse_integer(data, offset, u64);
    }
    check(success, "Could not parse FDE length");

    if fde.length == 0 return true, fde, offset;

    start := offset;
    end := offset + cast(s64) fde.length;
    check(end <= data.count, "Invalid FDE length: %", fde.length);

    cie_pointer_offset := offset;
    cie_pointer: u32;
    cie_pointer, offset, success = parse_integer(data, offset, u32);
    check(success, "Could not parse FDE CIE pointer");
    if cie_pointer == 0 {
        // This looks like a CIE record’s ID field, so we’re parsing a CIE, not an FDE. There seems to be no other way to detect that without looking at .eh_frame_hdr, which might not be present?
        return true, .{}, offset_in; // Pretend we’ve hit an end record
    }

    check(cie_pointer_offset >= cie_pointer, "Invalid FDE CIE pointer: %. FDE started at %", cie_pointer, cie_pointer_offset);
    fde.cie_offset = cast(u64) (cie_pointer_offset - cie_pointer);
    check(fde.cie_offset == cie.offset, "Unexpected FDE CIE pointer % vs % (delta was %)", fde.cie_offset, cie.offset, cie_pointer);

    address_config: u8;
    if find_index_from_left(cie.augmentation, #char "R") != -1 {
        check(cie.augmentation_data.count == 1, "Unsupported CIE augmentation data: %", cie.augmentation_data);
        address_config = cie.augmentation_data[0];
    }

    address_address := frame_section_address + cast(u64) offset;
    pc_delta: s64;
    if address_config & 0xF == {
        case 0x0; pc_delta, offset, success = parse_integer(data, offset, s64);
        case 0xb; pc_delta, offset, success = parse_integer(data, offset, s32);
        case;     check(false, "Unsupported address pointer encoding: 0x%", formatInt(address_config, base = 16, minimum_digits = 2));
    }
    check(success, "Could not parse FDE PC begin");

    if (address_config & 0xF0) == {
        case 0x00;
            fde.pc_begin = cast,no_check(u64) pc_delta;
        case 0x10;
            check(pc_delta > 0 || cast(u64)-pc_delta <= address_address, "Inavlid PC delta: %", pc_delta);
            fde.pc_begin = address_address + cast,no_check(u64) pc_delta;
        case;     check(false, "Unsupported address pointer encoding: 0x%", formatInt(address_config, base = 16, minimum_digits = 2));
    }

    if address_config & 0xF == {
        case 0x0; fde.pc_range, offset, success = parse_integer(data, offset, u64);
        case 0xb; fde.pc_range, offset, success = parse_integer(data, offset, u32);
        case;     check(false, "Unsupported address pointer encoding: 0x%", formatInt(address_config, base = 16, minimum_digits = 2));
    }
    check(success, "Could not parse FDE PC range");

    if begins_with(cie.augmentation, "z") {
        count: u64;
        count, offset, success = parse_uleb128(data, offset);
        check(success, "Could not parse FDE agumentation data length");
        fde.augmentation_data.count = cast(s64) count;
        fde.augmentation_data.data = data.data + offset;
        offset += fde.augmentation_data.count;
    }

    check(offset <= end, "FDE went past its supposed length: % vs %", offset, end);

    remaining := end - offset;
    instruction_data: [] u8;
    instruction_data.count = remaining;
    instruction_data.data = data.data + offset;
    offset += remaining;

    fde.instructions, success = decode_cfa_instructions(instruction_data);

    return success, fde, offset;
}

decode_cfa_instructions :: (data: [] u8) -> [] Call_Frame_Address_Instruction, success: bool {
    instructions: [..] Call_Frame_Address_Instruction;
    offset := 0;
    success := true;
    while success && offset < data.count {
        instruction_byte := data[offset];
        offset += 1;
        i: Call_Frame_Address_Instruction;
        i.type = cast(Call_Frame_Address_Instruction_Type) (instruction_byte & 0xC0);
        low  := instruction_byte & 0x3F;
        if i.type == {
            case .ADVANCE_LOC;
                i.arg1.uvalue = low;
            case .OFFSET;
                i.arg1.uvalue = low;
                i.arg2.uvalue, offset, success = parse_uleb128(data, offset);
                if !success return .[], false;
            case .RESTORE;
                i.arg1.uvalue = low;
            case;
                i.type = cast(Call_Frame_Address_Instruction_Type) low;
                if i.type == {
                    case .NOP;            // no args
                    case .REMEMBER_STATE; // no args
                    case .RESTORE_STATE;  // no args

                    case .RESTORE_EXTENDED; #through;
                    case .UNDEFINED;        #through;
                    case .SAME_VALUE;       #through;
                    case .DEF_CFA_REGISTER; #through;
                    case .DEF_CFA_OFFSET;
                        i.arg1.uvalue, offset, success = parse_uleb128(data, offset);
                        if !success return .[], false;

                    case .OFFSET_EXTENDED; #through;
                    case .DEF_CFA;         #through;
                    case .VAL_OFFSET;
                        i.arg1.uvalue, offset, success = parse_uleb128(data, offset);
                        if !success return .[], false;
                        i.arg2.uvalue, offset, success = parse_uleb128(data, offset);
                        if !success return .[], false;

                    case .OFFSET_EXTENDED_SF; #through;
                    case .DEF_CFA_SF;         #through;
                    case .VAL_OFFSET_SF;
                        i.arg1.uvalue, offset, success = parse_uleb128(data, offset);
                        if !success return .[], false;
                        i.arg2.svalue, offset, success = parse_sleb128(data, offset);
                        if !success return .[], false;

                    case .DEF_CFA_OFFSET_SF;
                        i.arg1.svalue, offset, success = parse_sleb128(data, offset);
                        if !success return .[], false;

                    case .ADVANCE_LOC1;
                        i.arg1.uvalue, offset, success = parse_integer(data, offset, u8);
                        if !success return .[], false;
                    case .ADVANCE_LOC2;
                        i.arg1.uvalue, offset, success = parse_integer(data, offset, u16);
                        if !success return .[], false;
                    case .ADVANCE_LOC4;
                        i.arg1.uvalue, offset, success = parse_integer(data, offset, u32);
                        if !success return .[], false;

                    case;
                        // @Incomplete
                        log_error("Unhandled instruction type %", i.type);
                        return .[], false;
                }
        }

        array_add(*instructions, i);
    }

    while instructions.count && instructions[instructions.count - 1].type == .NOP {
        instructions.count -= 1;
    }

    return instructions, success;
}


#load "dwarf_enums.jai";
#load "line_program.jai";

#scope_module

Parse_Context :: struct {
    debug_info:        Debug_Info;
    debug_string_data: [] u8;
    depth:             int;
    verbose:           bool;

    current_compilation_unit: *Compilation_Unit;
    subprogram_stack:  [..] *Subprogram;
    block_stack:       [..] *Lexical_Block;
}

Dwarf_Abbreviation_List :: struct {
    ids:    [..] u64;
    values: [..] Dwarf_Abbreviation;
}

Dwarf_Abbreviation :: struct {
    tag:          Dwarf_Tag;
    has_children: bool;
    attributes:   [..] Dwarf_Attribute;
}

Dwarf_Attribute :: struct {
    type:   Dwarf_Attribute_Type;
    format: Dwarf_Attribute_Format;
}

parse_abbreviations :: (abbrev_data: [] u8, offset_in: u64) -> Dwarf_Abbreviation_List, success: bool {
    abbreviations: Dwarf_Abbreviation_List;
    offset := cast(s64) offset_in;
    while offset < abbrev_data.count {
        id: u64 = ---;
        success: bool = ---;
        id, offset, success = parse_uleb128(abbrev_data, offset);
        if !success     return .{}, false;
        if id == 0 {
            break;
        }

        tag: u64 = ---;
        tag, offset, success = parse_uleb128(abbrev_data, offset);
        if !success     return .{}, false;

        abbrev: Dwarf_Abbreviation;
        abbrev.tag = xx tag;
        if offset >= abbrev_data.count  return .{}, false;
        abbrev.has_children = (abbrev_data[offset] > 0);
        offset += 1;

        while true {
            type: u64 = ---;
            format: u64 = ---;
            type, offset, success = parse_uleb128(abbrev_data, offset);
            if !success     return .{}, false;

            format, offset, success = parse_uleb128(abbrev_data, offset);
            if !success     return .{}, false;

            if type == 0 && format == 0   break;

            attribute: Dwarf_Attribute;
            attribute.type = xx type;
            attribute.format = xx format;
            // log("Found attribute %\n", attribute);
            array_add(*abbrev.attributes, attribute);
        }

        // log("Abbreviation %: %\n", id, abbrev);

        array_add(*abbreviations.ids, id);
        array_add(*abbreviations.values, abbrev);
    }
    // log("Found % abbreviations\n", abbreviations.ids.count);

    return abbreviations, true;
}

Compliation_Unit_Header_32 :: struct {
    size:                u32;
    version:             u16;
    debug_abbrev_offset: u32 #align 2;
    address_size:        u8;
} #no_padding;
#run assert(size_of(Compliation_Unit_Header_32) == 11, "Invalid compilation unit header size");

Compliation_Unit_Header_64 :: struct {
    size32:              u32;
    size64:              u64 #align 4;
    version:             u16;
    debug_abbrev_offset: u64 #align 2;
    address_size:        u8;
} #no_padding;
#run assert(size_of(Compliation_Unit_Header_64) == 23, "Invalid compilation unit header size");


parse_compilation_unit_content_v4 :: (using parse_context: *Parse_Context, base_offset: s64, data: [] u8, abbrevs: Dwarf_Abbreviation_List) -> Compilation_Unit, success: bool {
    offset := 0;
    cu: Compilation_Unit;
    abbrev_id: u64 = ---;
    success: bool = ---;
    abbrev_id, offset, success = parse_uleb128(data, offset);
    if !success     return cu, false;

    abbrev := find_abbrev(abbrevs, abbrev_id);
    if !abbrev  return cu, false;

    if abbrev.tag != .COMPILE_UNIT {
        log_error("Unexpected abbreviation: %\n", abbrev.*);
        return cu, false;
    }

    if !abbrev.has_children {
        log_error("Unexpected compile unit without children: %\n", abbrev.*);
        return cu, false;
    }

    if verbose then log("CU abbrev: % starting at 0x%\n", abbrev.*, formatHex(base_offset));

    high_pc_is_relative := false;
    for abbrev.attributes {
        if it.type == {
            case .PRODUCER;
                cu.producer, offset, success = parse_string_attribute(it.format, data, offset, debug_string_data);
                if !success     return cu, false;
            case .LANGUAGE;
                value: u64;
                value, offset, success = parse_unsigned_int_attribute(it.format, data, offset);
                if !success     return cu, false;
                Reflection.range_check_and_store(value, type_info(type_of(cu.language)), *cu.language);
            case .NAME;
                cu.name, offset, success = parse_string_attribute(it.format, data, offset, debug_string_data);
                if !success     return cu, false;
            case .STMT_LIST;
                cu.statement_list, offset, success = parse_unsigned_int_attribute(it.format, data, offset);
                if !success     return cu, false;
            case .LOW_PC;
                cu.low_pc, offset, success = parse_unsigned_int_attribute(it.format, data, offset);
                if !success     return cu, false;
            case .HIGH_PC;
                cu.high_pc, offset, success = parse_unsigned_int_attribute(it.format, data, offset);
                if !success     return cu, false;
                if it.format != .ADDR {
                    high_pc_is_relative = true;
                }
            case;
                offset, success = skip_attribute(parse_context, it, data, offset);
                if !success     return cu, false;
        }
    }

    if high_pc_is_relative {
        cu.high_pc += cu.low_pc;
    }

    done := false;
    while !done {
        debug_info_base_offset := size_of(Compliation_Unit_Header_32);
        done, offset, success = parse_debug_info_entry(parse_context, *cu, debug_info_base_offset, data, offset, abbrevs);
        if !success     return cu, false;
    }

    if offset != data.count {
        remainder := array_view(data, offset);
        log_error("Unexpected additional data after parsing the compilation unit. Offset was % of %. Remainder:\n%\n", offset, data.count, remainder);
        return cu, false;
    }

    if verbose then log("Compilation unit: %\n", cu);

    return cu, true;
}

parse_debug_info_entry :: (using parse_context: *Parse_Context, cu: *Compilation_Unit, base_offset: s64, data: [] u8, offset_in: s64, abbrevs: Dwarf_Abbreviation_List) -> done: bool, offset: s64, success: bool {
    id := base_offset + offset_in;
    abbrev_id, offset, success := parse_uleb128(data, offset_in);
    if !success     return false, offset, false;

    if abbrev_id == 0   return true, offset, true;

    abbrev := find_abbrev(abbrevs, abbrev_id);
    if !abbrev  return false, offset, false;

    if verbose {
        print_indentation(depth);
        log("Parsing abbrev 0x%: %", formatHex(id), abbrev.*);
    }

    pop_subprogram := false;
    pop_block := false;

    type: *Debug_Type;
    if abbrev.tag == {
        case .TYPEDEF;          #through;
        case .BASE_TYPE;        #through;
        case .UNSPECIFIED_TYPE; #through;
        case .REFERENCE_TYPE;   #through;
        case .STRUCTURE_TYPE;
            type = array_add(*cu.types);
            type.tag = abbrev.tag;
            type.offset = id;
            for abbrev.attributes {
                offset, success = parse_type_attribute(parse_context, it, type, data, offset);
                if !success     return false, offset, false;
            }
            if verbose {
                print_indentation(depth + 1);
                log("Parsed type: %", type);
            }

        case .SUBPROGRAM;
            subprogram: Subprogram;
            high_pc_is_relative := false;
            for abbrev.attributes {
                if it.type == {
                    case .EXTERNAL;
                        subprogram.external, offset, success = parse_unsigned_int_attribute(it.format, data, offset, bool);
                    case .NAME;
                        subprogram.name, offset, success = parse_string_attribute(it.format, data, offset, debug_string_data);
                    case .LINKAGE_NAME;
                        subprogram.linkage_name, offset, success = parse_string_attribute(it.format, data, offset, debug_string_data);
                    case .DECL_FILE;
                        subprogram.decl_file_id, offset, success = parse_unsigned_int_attribute(it.format, data, offset, Dwarf_File_Id);
                    case .DECL_LINE;
                        subprogram.decl_line, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u32);
                    case .TYPE;
                        subprogram.type_id, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u32);
                    case .MAIN_SUBPROGRAM;
                        subprogram.is_main, offset, success = parse_unsigned_int_attribute(it.format, data, offset, bool);
                    case .CALLING_CONVENTION;
                        subprogram.calling_convention, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u8);
                    case .LOW_PC;
                        subprogram.low_pc, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u64);
                    case .HIGH_PC;
                        subprogram.high_pc, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u64);
                        if it.format != .ADDR {
                            high_pc_is_relative = true;
                        }
                    case;
                        offset, success = skip_attribute(parse_context, it, data, offset);
                }
                if !success     return false, offset, false;
            }

            if high_pc_is_relative {
                subprogram.high_pc += subprogram.low_pc;
            }

            if verbose {
                print_indentation(depth + 1);
                log("Parsed subprogram: %", subprogram);
            }
            _, sub_pointer := bucket_array_add(*cu.subprograms, subprogram);
            array_add(*subprogram_stack, sub_pointer);
            pop_subprogram = true;

            block: Lexical_Block;
            block.low_pc  = subprogram.low_pc;
            block.high_pc = subprogram.high_pc;
            _, root_block_pointer := bucket_array_add(*sub_pointer.all_blocks, block);
            sub_pointer.root_block = root_block_pointer;
            array_add(*block_stack, root_block_pointer);
            pop_block = true;

        case .INLINED_SUBROUTINE; #through; // Treat inlined subroutines like lexcial blocks until we’re interested in more information about them
        case .LEXICAL_BLOCK;
            block: Lexical_Block;
            high_pc_is_relative := false;
            for abbrev.attributes {
                if it.type == {
                    case .LOW_PC;
                        block.low_pc, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u64);
                    case .HIGH_PC;
                        block.high_pc, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u64);
                        if it.format != .ADDR {
                            high_pc_is_relative = true;
                        }
                    case;
                        offset, success = skip_attribute(parse_context, it, data, offset);
                }
                if !success     return false, offset, false;
            }

            if high_pc_is_relative {
                block.high_pc += block.low_pc;
            }

            if verbose {
                print_indentation(depth + 1);
                log("Parsed %: % (address range: 0x%-0x%)", abbrev.tag, block, formatHex(block.low_pc), formatHex(block.high_pc));
            }

            if !subprogram_stack.count {
                log_error("Found % outside a subprogram at offset 0x%: %", abbrev.tag, formatHex(offset_in), block);
                return false, offset, false;
            }

            subprogram := subprogram_stack[subprogram_stack.count - 1];
            _, block_pointer := bucket_array_add(*subprogram.all_blocks, block);
            assert(block_stack.count > 0);
            parent := block_stack[block_stack.count - 1];
            array_add(*parent.children, block_pointer);

            array_add(*block_stack, block_pointer);
            pop_block = true;

        case .FORMAL_PARAMETER;
            declaration:, offset, success = parse_declaration(parse_context, abbrev, data, offset);
            if !success return false, offset, false;

            declaration.kind = .PARAMETER;

            if subprogram_stack.count {
                block := block_stack[block_stack.count - 1];
                array_add(*block.declarations, declaration);
            } else {
                // FORMAL_PARAMETER is also used inside SUBROUTINE_TYPE to define the type’s parameters
                // But we’re not interested in these right now, so we don't keep track of them.
            }

        case .VARIABLE;
            declaration:, offset, success = parse_declaration(parse_context, abbrev, data, offset);
            if !success return false, offset, false;

            declaration.kind = .VARIABLE;

            if block_stack.count {
                block := block_stack[block_stack.count - 1];
                array_add(*block.declarations, declaration);
            } else {
                assert(!subprogram_stack.count);
                assert(current_compilation_unit != null);
                array_add(*current_compilation_unit.globals, declaration);
            }

        case;
            for abbrev.attributes {
                offset, success = skip_attribute(parse_context, it, data, offset);
                if !success     return false, offset, false;
            }
    }

    if abbrev.has_children {
        if verbose {
            print_indentation(depth);
            log("Parsing children:");
        }
        done := false;
        while !done {
            depth += 1;
            done, offset, success = parse_debug_info_entry(parse_context, cu, base_offset, data, offset, abbrevs);
            depth -= 1;
            if !success     return false, offset, false;
        }
        if verbose {
            print_indentation(depth);
            log("Done parsing children");
        }
    }

    if pop_subprogram pop(*parse_context.subprogram_stack);
    if pop_block      pop(*parse_context.block_stack);

    return false, offset, true;
}

parse_declaration :: (using parse_context: *Parse_Context, abbrev: *Dwarf_Abbreviation, data: [] u8, offset_in: s64) -> Declaration, offset: s64, success: bool {
    offset := offset_in;
    success: bool;

    declaration: Declaration;
    declaration.tag = abbrev.tag;
    for abbrev.attributes {
        if it.type == {
            case .NAME;
                declaration.name, offset, success = parse_string_attribute(it.format, data, offset, debug_string_data);
            case .DECL_FILE;
                declaration.decl_file_id, offset, success = parse_unsigned_int_attribute(it.format, data, offset, Dwarf_File_Id);
            case .DECL_LINE;
                declaration.decl_line, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u32);
            case .TYPE;
                declaration.type_id, offset, success = parse_unsigned_int_attribute(it.format, data, offset, u32);
            case;
                offset, success = skip_attribute(parse_context, it, data, offset);
        }
        if !success     return declaration, offset, false;
    }

    if verbose {
        print_indentation(depth + 1);
        log("Parsed %: %", abbrev.tag, declaration);
    }
    return declaration, offset, true;
}

print_indentation :: (depth: int) {
    for 0..depth - 1 {
        print("    ");
    }
}

find_abbrev :: (abbrevs: Dwarf_Abbreviation_List, id: u64) -> *Dwarf_Abbreviation {
    for abbrevs.ids {
        if it == id   {
            return *abbrevs.values[it_index];
        }
    }

    log_error("Could not find abbreviation %\n", id);
    return null;
}

parse_uleb128 :: (data: [] u8, offset_in: s64, $ParseType := u64) -> value: ParseType, len: int, success: bool {
    value: u64;
    shift := 0;

    offset := offset_in;
    while true {
        if offset == data.count {
            #import "Debug";
            breakpoint();
            log_error("Unexpected end at offset % (0x%) while decoding a ULEB128 value\n", offset, formatInt(offset, base = 16));
            return 0, 0, false;
        }

        byte := data[offset];
        value |= ((cast(u64) byte & 0x7F) << shift);
        offset += 1;
        if !(byte & 0x80)  break;
        shift += 7;
    }


    result := cast(ParseType) value;
    return result, offset, true;
}

parse_sleb128 :: (data: [] u8, offset_in: s64) -> value: s64, len: int, success: bool {
    result: s64;
    shift := 0;

    offset := offset_in;
    while true {
        if offset == data.count {
            log_error("Unexpected end at offset % while decoding a ULEB128 value\n", offset);
            return 0, 0, false;
        }

        byte := data[offset];
        result |= ((cast(s64) byte & 0x7F) << shift);
        offset += 1;
        shift += 7;
        if !(byte & 0x80) {
            if shift < size_of(s64) * 8 && (byte & 0x40) {
                // sign extend
                extension := - (1 << shift);
                result |= extension;
            }
            break;
        }
    }

    return result, offset, true;
}

parse_string_attribute :: (format: Dwarf_Attribute_Format, data: [] u8, offset: s64, debug_string_data: [] u8) -> result: string, offset: s64, success: bool {
    if format == {
        case .STRING;
            str, success := get_c_string_from_data(data, offset);
            if !success return "", offset, false;

            return str, offset + str.count + 1, true;

        case .STRP;
            str_offset, end_offset, success := parse_integer(data, offset, u32);
            if !success     return "", offset, false;

            str: string = ---;
            str, success = get_debug_string(str_offset, debug_string_data);
            return str, end_offset, success;

        case;
            log_error("Unsupported string attribute format: %\n", format);
            return "", offset, false;
    }

}

parse_unsigned_int_attribute :: (format: Dwarf_Attribute_Format, data: [] u8, offset: s64, $T := u64) -> result: T, offset: s64, success: bool {
    if format == {
        case .REF1; #through;
        case .DATA1;
            result, end_offset, success := parse_integer(data, offset, u8);
            return xx result, end_offset, success;

        case .REF2; #through;
        case .DATA2;
            result, end_offset, success := parse_integer(data, offset, u16);
            return xx result, end_offset, success;

        case .REF4; #through;
        case .REF_ADDR; #through; // @Incomplete: Size actually depends on dwarf format size :Dwarf64bit
        case .DATA4;
            result, end_offset, success := parse_integer(data, offset, u32);
            return xx result, end_offset, success;

        case .REF8; #through;
        case .DATA8;
            result, end_offset, success := parse_integer(data, offset, u64);
            return xx result, end_offset, success;

        case .REF_UDATA; #through;
        case .UDATA;
            result, end_offset, success := parse_uleb128(data, offset);
            return xx result, end_offset, success;

        case .SEC_OFFSET;
            // @ToDo: Depends on whether its dwarf 32 or 64.
            result, end_offset, success := parse_integer(data, offset, u32);
            return xx result, end_offset, success;

        case .ADDR;
            result, end_offset, success := parse_integer(data, offset, u64);
            return xx result, end_offset, success;

        case .FLAG;
            result, end_offset, success := parse_integer(data, offset, u8);
            return xx result, end_offset, success;
        case .FLAG_PRESENT;
            return xx 1, offset, true;

        case;
            log_error("Unsupported data attribute format: %\n", format);
            return xx 0, offset, false;
    }
}

parse_signed_int_attribute :: (format: Dwarf_Attribute_Format, data: [] u8, offset: s64) -> result: s64, offset: s64, success: bool {
    if format == {
        case .SDATA;
            result, end_offset, success := parse_sleb128(data, offset);
            return result, end_offset, success;
        case;
            log_error("Unsupported data attribute format: %\n", format);
            return 0, offset, false;
    }
}

parse_length_block :: (format: Dwarf_Attribute_Format, data: [] u8, offset_in: s64) -> result: [] u8, offset: s64, success: bool {
    length: u64 = ---;
    offset: s64 = ---;
    success: bool = ---;
    if format == {
        case .BLOCK1;
            length, offset, success = parse_integer(data, offset_in, u8);
        case .BLOCK2;
            length, offset, success = parse_integer(data, offset_in, u16);
        case .BLOCK4;
            length, offset, success = parse_integer(data, offset_in, u32);
        case .EXPRLOC; #through;
        case .BLOCK;
            length, offset, success = parse_uleb128(data, offset_in);
    }

    end := offset + cast (s64) length;
    if end > data.count {
        log_error("Block length went out of bounds: %\n", length);
        return .[], offset, false;
    }

    return array_view(data, offset, xx length), end, true;
}

parse_integer :: (data: [] u8, offset: s64, $T: Type) -> value: T, offset: s64, success: bool {
    end_offset := offset + size_of(T);
    if end_offset > data.count  {
        log_error("Unexpected end of data while parsing %\n", T);
        return 0, offset, false;
    }
    value := (.*)(cast(*T) (data.data + offset));
    return value, end_offset, true;
}

parse_type_attribute :: (using parse_context: *Parse_Context, using attribute: Dwarf_Attribute, debug_type: *Debug_Type, data: [] u8, offset_in: s64) -> offset: s64, success: bool {
    skip_attribute :: () #expand {
        offset, success = skip_attribute(parse_context, attribute, data, offset_in);
    }

    offset: s64;
    success: bool;
    if attribute.type == {
        case .NAME;
            debug_type.name, offset, success = parse_string_attribute(format, data, offset_in, debug_string_data);
            return offset, success;
        case .BYTE_SIZE;
            debug_type.size, offset, success = parse_unsigned_int_attribute(format, data, offset_in);
        case .TYPE;
            if debug_type.tag == .TYPEDEF {
                // @ToDo: validate?
                debug_type.base_type, offset, success = parse_unsigned_int_attribute(format, data, offset_in, Dwarf_Base_Type);
            } else {
                skip_attribute();
            }

        case .ENCODING;
            if debug_type.tag == .BASE_TYPE {
                // @ToDo: validate?
                debug_type.base_type, offset, success = parse_unsigned_int_attribute(format, data, offset_in, Dwarf_Base_Type);
            } else {
                skip_attribute();
            }
        case;
            skip_attribute();
    }

    return offset, success;
}

skip_attribute :: (using parse_context: *Parse_Context, using attribute: Dwarf_Attribute, data: [] u8, offset_in: s64) -> offset: s64, success: bool {
    if verbose then print_indentation(depth + 1);
    if format == {
        case .STRING; #through;
        case .STRP;
            str, offset, success := parse_string_attribute(format, data, offset_in, debug_string_data);
            if verbose then log("Attribute % (%): %", type, format, str);
            return offset, success;
        case .DATA1; #through;
        case .DATA2; #through;
        case .DATA4; #through;
        case .DATA8; #through;
        case .UDATA; #through;
        case .REF1; #through;
        case .REF2; #through;
        case .REF4; #through;
        case .REF_ADDR; #through;
        case .REF8; #through;
        case .REF_UDATA; #through;
        case .SEC_OFFSET; #through;
        case .ADDR; #through;
        case .FLAG; #through;
        case .FLAG_PRESENT;
            value, offset, success := parse_unsigned_int_attribute(format, data, offset_in);
            if verbose then log("Attribute % (%): % (0x%)", type, format, value, formatHex(value));
            return offset, success;
        case .SDATA;
            value, offset, success := parse_signed_int_attribute(format, data, offset_in);
            if verbose then log("Attribute % (%): % (0x%)", type, format, value, formatHex(value));
            return offset, success;
        case .BLOCK1; #through;
        case .BLOCK2; #through;
        case .BLOCK4; #through;
        case .BLOCK; #through;
        case .EXPRLOC;
            value, offset, success := parse_length_block(format, data, offset_in);
            if verbose then log("Attribute % (%): %", type, format, as_hex_string(value));
            return offset, success;
        case;
            log_error("Couldn’t skip over unsupported attribute format: %\n", format);
            return offset_in, false;
    }
}

get_debug_string :: (offset: u64, debug_string_data: [] u8) -> result: string, success: bool {
    if !debug_string_data.count                   return "", false;

    if offset >= xx debug_string_data.count {
        log_error("Debug string offset % is out of bounds\n", offset);
        return "", false;
    }

    result, success := get_c_string_from_data(debug_string_data, xx offset);
    return result, success;
}

as_hex_string :: (value: [] u8) -> string {
    builder: String_Builder;
    for value {
        if it_index append(*builder, " ");
        print_to_builder(*builder, "%", formatHex(it));
    }
    return builder_to_string(*builder);
}

#import "Basic";
#import "Bucket_Array";
Reflection :: #import "Reflection";
