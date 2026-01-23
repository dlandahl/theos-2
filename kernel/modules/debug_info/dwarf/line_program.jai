Dwarf_File_Id :: #type,isa u32;

Line_Info :: struct {
    dirs: [..] string;
    files: [..] File_Info;
    sequences: [..] Line_Info_Sequence;
}

// Within a sequence, addresses are strictly increasing, so you can do a binary search
Line_Info_Sequence :: struct {
    addresses: [..] u64;
    mappings: [..] Line_Mapping;
}

File_Info :: struct {
    dir_id: u64;
    path: string;
}

Line_Mapping :: struct {
    file_id: Dwarf_File_Id;
    line: u32;
    column: u32;
    is_end: bool;

    flags: Flags;

    Flags :: enum_flags {
        STATEMENT;
        BASIC_BLOCK;
        PROLOGUE_END;
        EPILOGUE_BEGIN;
    }
}

Line_Program_Header :: struct {
    size: u32;
    version: u16;
    header_length: u32 #align 2;
    minimum_instruction_length: u8;
    maximum_operations_per_instruction: u8;
    default_is_stmt: bool;
    line_base: s8;
    line_range: u8;
    opcode_base: u8;
} #no_padding;


get_filename_for_file_id :: (info: Line_Info, file_id: Dwarf_File_Id) -> string {
    if !file_id then return "";

    file_info := info.files[file_id - 1];
    return get_filename(info, file_info);
}

get_filename :: (info: Line_Info, file_info: File_Info) -> string {
    if file_info.dir_id > 0 {
        return tprint("%/%", info.dirs[file_info.dir_id - 1], file_info.path);
    } else {
        return file_info.path;
    }
}

get_line_mapping_for_address :: (info: Line_Info, address: u64) -> Line_Mapping, success: bool {
    for seq: info.sequences {
        for seq.addresses {
            if it <= address && (it_index == seq.addresses.count - 1 || seq.addresses[it_index + 1] > address) {
                return seq.mappings[it_index], true;
            }
        }
    }
    return .{}, false;
}

get_line_mappings_for_address_range :: (info: Line_Info, start: u64, end_exclusive: u64) -> [] Line_Mapping, success: bool {
    first_mapping_index := -1;
    last_mapping_index  := -1;
    for seq: info.sequences {
        for seq.addresses {
            if it <= start && (it_index == seq.addresses.count - 1 || seq.addresses[it_index + 1] > start) {
                first_mapping_index = it_index;
            } else if first_mapping_index != -1 && it >= end_exclusive && last_mapping_index == -1 {
                last_mapping_index = it_index - 1;
            }
        }

        if first_mapping_index != -1 {
            if last_mapping_index == -1 {
                last_mapping_index = seq.addresses.count - 1;
            }

            return array_view(seq.mappings, first_mapping_index, last_mapping_index - first_mapping_index + 1), true;
        }
    }

    return .[], false;
}

#scope_module

decode_line_info :: (data: [] u8) -> Line_Info, success: bool {
    info: Line_Info;

    header := cast(*Line_Program_Header) data.data;

    if header.size == 0xffff_ffff {
        log_error("We dont support 64 bit DWARF format yet.");
        return info, false;
    }

    program_end := header.size + size_of(type_of(header.size));
    if program_end > data.count {
        log_error("Invalid line program size: %\n", header.size);
        return info, false;
    }

    if header.version != 4 {
        log_error("Line program has unsupported DWARF version: %\n", header.version);
        return info, false;
    }

    if (cast(*u8)*header.minimum_instruction_length) + header.header_length > data.data + data.count {
        log_error("Invalid line program header length: %\n", header.header_length);
        return info, false;
    }

    offset := size_of(Line_Program_Header);

    if offset + header.opcode_base - 1> data.count {
        log_error("Invalid line program opcode base: %\n", header.opcode_base);
        return info, false;
    }

    standard_opcode_lengths: [] u8 = array_view(data, offset, header.opcode_base - 1);

    // log("Opcode lengths: %\n", standard_opcode_lengths);

    offset += header.opcode_base - 1;

    while true {
        dir, success := get_c_string_from_data(data, offset);
        if !success     return info, false;

        offset += dir.count + 1;
        if !dir break;

        array_add(*info.dirs, dir);
    }

    success: bool = ---;
    while true {
        file: File_Info = ---;
        file, offset, success = parse_file_info(info, data, offset, stop_at_zero = true);
        if !success     return info, false;

        if !file.path   break;

        array_add(*info.files, file);
    }

    sequence: Line_Info_Sequence;
    state: Line_Program_State = ---;
    reset(*state, header);
    while offset < program_end {
        byte := data[offset];
        offset += 1;
        if byte >= header.opcode_base {
            apply_special_opcode(*info, *state, byte, header.*, *sequence);
        } else {
            // log("Operation: %", cast(Line_Program_Operation) byte);
            if cast(Line_Program_Operation) byte == {
                case .EXTENDED_OPERATION;
                    len: u64 = ---;
                    len, offset, success = parse_uleb128(data, offset);
                    if !success                     return info, false;
                    if offset + cast (s64) len > data.count    {
                        log_error("Line program: Extended operation went out of bounds!\n");
                        return info, false;
                    }
                    op_start_offset := offset;
                    extended_op := cast(Line_Program_Extended_Operation) data[offset];
                    offset += 1;
                    if extended_op == {
                        case .END_SEQUENCE;
                            // log("Extended opration %", extended_op);
                            state.is_end = true;
                            array_add(*sequence.addresses, state.address);
                            array_add(*sequence.mappings, state.mapping);
                            array_add(*info.sequences, sequence);
                            sequence = .{};

                            // log("\t0x%: %\n", formatHex64(state.address), state.mapping);
                            offset += xx len - 1;
                            if offset == program_end {
                                break;
                            } else {
                                reset(*state, header);
                            }

                        case .SET_ADDRESS;
                            state.address, offset, success = parse_integer(data, offset, u64);
                            // log("Extended opration %: 0x%", extended_op, formatInt(state.address, base = 16));

                        case .DEFINE_FILE;
                            file: File_Info = ---;
                            file, offset, success = parse_file_info(info, data, offset, stop_at_zero = false);
                            if !success     return info, false;

                            // log("Extended opration %: %", extended_op, file);
                            array_add(*info.files, file);

                        case .SET_DISCRIMINATOR;
                            state.discriminator, offset, success = parse_uleb128(data, offset);
                            // log("Extended opration %: %", extended_op, state.discriminator);
                            if !success     return info, false;

                        case;
                            log_error("Found unknown extended line program operation: %\n", extended_op);
                            offset += xx len;
                    }
                    if op_start_offset + xx len != offset {
                        log_error("Invalid extended operator length for %: % vs %\n", extended_op, len, offset - op_start_offset);
                        return info, false;
                    }

                case .COPY;
                    array_add(*sequence.addresses, state.address);
                    array_add(*sequence.mappings, state.mapping);
                    // log("\t0x%: %\n", formatHex64(state.address), state.mapping);
                    state.discriminator = 0;
                    state.flags = (state.flags & .STATEMENT); // reset all flags except .STATEMENT
                case .ADVANCE_PC;
                    operation_advance: u64 = ---;
                    operation_advance, offset, success = parse_uleb128(data, offset);
                    if !success     return info, false;

                    advance_address(*state, operation_advance, header.*);
                case .ADVANCE_LINE;
                    delta: s64 = ---;
                    delta, offset, success = parse_sleb128(data, offset);
                    if !success     return info, false;
                    // log("Line delta: %\n", delta);

                    state.line = xx (cast(s64) state.line + delta);
                case .SET_FILE;
                    state.file_id, offset, success = parse_uleb128(data, offset, Dwarf_File_Id);
                    // log("Set file: %", state.file_id);
                    if !success     return info, false;
                case .SET_COLUMN;
                    state.column, offset, success = parse_uleb128(data, offset, u32);
                    if !success     return info, false;
                case .NEGATE_STMT;
                    if state.flags & .STATEMENT {
                        state.flags &= ~.STATEMENT;
                    } else {
                        state.flags |= .STATEMENT;
                    }
                case .SET_BASIC_BLOCK;
                    state.flags |= .BASIC_BLOCK;
                case .CONST_ADD_PC;
                    adjusted_opcode := 255 - header.opcode_base;
                    operation_advance := adjusted_opcode / header.line_range;
                    advance_address(*state, operation_advance, header.*);
                case .FIXED_ADVANCE_PC;
                    value: u16 = ---;
                    value, offset, success = parse_integer(data, offset, u16);
                    if !success     return info, false;
                    state.address += value;
                    state.op_index = 0;
                case .SET_PROLOGUE_END;
                    state.flags |= .PROLOGUE_END;
                case .SET_EPILOGUE_BEGIN;
                    state.flags |= .EPILOGUE_BEGIN;
                case .SET_ISA;
                    state.isa, offset, success = parse_uleb128(data, offset);
                    if !success     return info, false;
                case;
                    log_error("Found unknown line code operation: %\n", byte);
                    // @ToDo: Skip over this based on the header information
                    return info, false;
            }
        }
    }

    if sequence.addresses.count {
        log_error("Line program did not end with an end_sequence opcode.");
        return info, false;
    }

    // log("Line info: %\n", info);

    // log("Line table:\n");
    // for info.addresses {
    //     log("\t0x%: %\n", formatHex64(it), info.mappings[it_index]);
    // }


    return info, true;
}

#scope_file

parse_file_info :: (info: Line_Info, data: [] u8, offset_in: s64, stop_at_zero: bool) -> File_Info, offset: s64, success: bool {
    offset := offset_in;
    file: File_Info = ---;
    success: bool = ---;
    file.path, success = get_c_string_from_data(data, offset);
    if !success     return file, offset, false;

    offset += file.path.count + 1;
    if !file.path && stop_at_zero {
        return file, offset, true;
    }

    file.dir_id, offset, success = parse_uleb128(data, offset);
    if !success     return file, offset, false;
    if xx file.dir_id > info.dirs.count {
        log_error("File’s dir ID is out of bounds: %\n", file.dir_id);
        return file, offset, false;
    }

    mod_time: u64 = ---;
    mod_time, offset, success = parse_uleb128(data, offset);
    if !success     return file, offset, false;

    length: u64 = ---;
    length, offset, success = parse_uleb128(data, offset);
    if !success     return file, offset, false;

    return file, offset, true;
}

Line_Program_State :: struct {
    address: u64;
    op_index: u64; // Could be way smaller
    using mapping: Line_Mapping;
    discriminator: u64;
    isa: u64;
}

reset :: (using state: *Line_Program_State, header: Line_Program_Header) {
    address = 0;
    op_index = 0;
    file_id = 1;
    line = 1;
    column = 0;
    flags = ifx header.default_is_stmt then Line_Mapping.Flags.STATEMENT else 0;
    is_end = false;
    isa = 0;
    discriminator = 0;
}

apply_special_opcode :: (info: *Line_Info, state: *Line_Program_State, opcode: u8, header: Line_Program_Header, sequence: *Line_Info_Sequence) {
    adjusted_opcode := opcode - header.opcode_base;
    // log("special opcode %", opcode);
    operation_advance := adjusted_opcode / header.line_range;
    advance_address(state, operation_advance, header);
    line_delta := header.line_base + cast (s64) (adjusted_opcode % header.line_range);
    // log("special opcode line delta %", line_delta);
    state.line = xx (cast (s64) state.line + line_delta);

    array_add(*sequence.addresses, state.address);
    array_add(*sequence.mappings, state.mapping);
    // log("\t0x%: %\n", formatHex64(state.address), state.mapping);

    state.flags = (state.flags & .STATEMENT); // reset all flags except .STATEMENT
    state.discriminator = 0;
}

advance_address :: (state: *Line_Program_State, operation_advance: u64, header: Line_Program_Header) {
    // log("Advance address % for % (%)\n", operation_advance, formatHex64(state.address), state.op_index);
    state.address += header.minimum_instruction_length * ((state.op_index + operation_advance) / header.maximum_operations_per_instruction);
    state.op_index = (state.op_index + operation_advance) % header.maximum_operations_per_instruction;
    // log("After advance: % (%)\n", formatHex64(state.address), state.op_index);
}

Line_Program_Operation :: enum {
    EXTENDED_OPERATION  :: 0x00;
    COPY                :: 0x01;
    ADVANCE_PC;
    ADVANCE_LINE;
    SET_FILE;
    SET_COLUMN;
    NEGATE_STMT;
    SET_BASIC_BLOCK;
    CONST_ADD_PC;
    FIXED_ADVANCE_PC;
    SET_PROLOGUE_END;
    SET_EPILOGUE_BEGIN;
    SET_ISA;
}

Line_Program_Extended_Operation :: enum {
    END_SEQUENCE        :: 0x01;
    SET_ADDRESS;
    DEFINE_FILE;
    SET_DISCRIMINATOR;
}
