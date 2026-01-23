Apple_Universal_Binary :: struct {
    content: string;
    files: [] Arch_File;
}

is_apple_universal :: (file_content: string) -> bool {
    if file_content.count < size_of(Apple_Universal_File_Header) return false;
    header := cast(*Apple_Universal_File_Header) file_content.data;
    return header.magic == APPLE_UNIVERSAL_FILE_MAGIC;
}

parse_apple_universal_file :: (path: string) -> success: bool, Apple_Universal_Binary {
    aub: Apple_Universal_Binary = ---;
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, aub;
    }

    success, aub = parse_apple_universal(content, path);
    return success, aub;
}

parse_apple_universal :: (content: string, filename: string, verbose := false) -> success: bool, Apple_Universal_Binary {
    check :: (condition: bool, message: string, args: .. Any) #expand {
        if !condition {
            log_error(message, ..args);
            `return false, aub;
        }
    } @PrintLike

    aub: Apple_Universal_Binary;
    if content.count < size_of(Apple_Universal_File_Header) return false, aub;
    header := (cast(*Apple_Universal_File_Header) content.data).*;
    byte_swap_in_place(*header.arch_count);
    check(header.magic == APPLE_UNIVERSAL_FILE_MAGIC, "%: Unexpected header magic sequence", filename);
    aub.content = content;

    offset := size_of(Apple_Universal_File_Header);

    end := offset + header.arch_count * size_of(Arch_Header);
    check(end <= content.count, "%: Architectures go out of bounds: % vs %", filename, end, content.count);

    aub.files = NewArray(header.arch_count, Arch_File);
    for i: 0..header.arch_count-1 {
        assert(offset + size_of(Arch_Header) <= content.count);
        arch_header := (.*) (cast(*Arch_Header) (content.data + offset));
        offset += size_of(Arch_Header);
        byte_swap_in_place(*arch_header.cpu_type);
        byte_swap_in_place(*arch_header.cpu_subtype);
        byte_swap_in_place(*arch_header.file_offset);
        byte_swap_in_place(*arch_header.size);
        byte_swap_in_place(*arch_header.align);

        check(arch_header.file_offset + arch_header.size <= content.count, "%: Architecture % (%/%) goes out of bounds", filename, i, arch_header.cpu_type, arch_header.cpu_subtype);
        file: Arch_File;
        file.cpu_type = arch_header.cpu_type;
        file.cpu_subtype = arch_header.cpu_subtype;
        file.data.data = content.data + arch_header.file_offset;
        file.data.count = arch_header.size;
        aub.files[i] = file;
    }

    return true, aub;
}

#scope_file

parse_gnu_symbol_archive_file :: (data: [] u8, offset: s64, symbol_file_size: s64, filename: string) -> symbol_names: [] string, symbol_file_offsets: [] u32, success: bool {
    file_end_offset := offset + symbol_file_size;
    assert(file_end_offset <= data.count);

    if offset + size_of(u32) > file_end_offset {
        log_error("Error while parsing archive \"%\": Unexpected end while parsing symbol table.", filename);
        return .[], .[], false;
    }

    num_symbols := byte_swap((.*)(cast(*u32) (data.data + offset)));
    // log("Found % symbols\n", num_symbols);
    offset += size_of(u32);

    table_size := num_symbols * size_of(u32);
    if offset + table_size > file_end_offset {
        log_error("Error while parsing archive \"%\": Unexpected end while parsing symbol table indices", filename);
        return .[], .[], false;
    }

    symbol_file_offsets := NewArray(num_symbols, u32);
    for i: 0..num_symbols-1 {
        symbol_file_offsets[i] = byte_swap((cast(*u32) (data.data + offset)).*); // @Incomplete: host endianness
        offset += size_of(u32);
    }

    symbol_names := NewArray(num_symbols, string);
    for 0..num_symbols-1 {
        name, success := get_c_string_from_data(data, offset);
        // log("%: %, %", it, name, success);
        if !success     return .[], .[], false;
        offset += name.count + 1;
        symbol_names[it] = name;
    }

    return symbol_names, symbol_file_offsets, true;
}

parse_bsd_symbol_archive_file :: (data: [] u8, offset: s64, symbol_file_size: s64, filename: string, $Offset_Type: Type) -> symbol_names: [] string, success: bool {
    file_end_offset := offset + symbol_file_size;
    assert(file_end_offset <= data.count);

    parse_length_and_get_data :: (description: string) -> data: [] u8 #expand {
        if offset + size_of(u32) > file_end_offset {
            log_error("Error while parsing archive \"%\": Unexpected end while parsing the size of %.", filename, description);
            `return .[], false;
        }

        num_bytes := (.*)(cast(*u32) (data.data + offset));
        // log("Found 0x% bytes of %\n", formatInt(num_bytes, base = 16), description);
        offset += size_of(u32);

        if offset + num_bytes > file_end_offset {
            log_error("Error while parsing archive \"%\": Unexpected end while parsing %.", filename, description);
            `return .[], false;
        }

        result: [] u8;
        result.count = num_bytes;
        result.data = data.data + offset;

        offset += num_bytes;
        return result;
    }

    symbol_data := parse_length_and_get_data("symbol table");
    string_data := parse_length_and_get_data("symbol string table");

    Symbol_Type :: Ranlib_Symbol(Offset_Type);
    if symbol_data.count % size_of(Symbol_Type) != 0 {
        log_error("Error while parsing archive \"%\": Unexpected symbol table size. Expected a multiple of % but % has a remainder of %", filename, size_of(Symbol_Type), symbol_data.count, symbol_data.count % size_of(Symbol_Type));
        return .[], false;
    }

    symbols: [] Symbol_Type;
    symbols.count = symbol_data.count / size_of(Symbol_Type);
    symbols.data = xx symbol_data.data;

    // log("Found % symbols", symbols.count);
    symbol_names := NewArray(symbols.count, string);
    for symbols {
        // log("Symbol %: % / %", it_index, it.ran_strx, it.ran_off);
        name, success := get_c_string_from_data(string_data, xx it.ran_strx);
        if !success     return .[], false;
        // log("%", name);
        if !begins_with(name, "_") {
            log_error("Error while parsing archive \"%\": Expected symbol % name \"%\" to begin with \"_\".", filename, it_index, name);
            return .[], false;
        }
        name = slice(name, 1, name.count -1);
        symbol_names[it_index] = name;
    }

    return symbol_names, true;
}

get_c_string_from_data :: (data: [] u8, offset: s64) -> result: string, success: bool {
    str: string = ---;
    str.data = data.data + offset;
    str.count = 0;
    while offset + str.count < data.count && str.data[str.count] != 0 {
        str.count += 1;
    }
    if offset + str.count >= data.count {
        log_error("Unexpected end of data while parsing a string at offset %\n", offset);
        return "", false;
    }

    // log("Found string \"%\"\n", str);

    return str, true;
}

APPLE_UNIVERSAL_FILE_MAGIC: u32 : 0xBEBAFECA;

Apple_Universal_File_Header :: struct {
    magic := APPLE_UNIVERSAL_FILE_MAGIC;
    arch_count: u32;
}

Arch_Header:: struct {
    cpu_type:     Cpu_Type;
    cpu_subtype: Cpu_Subtype;
    file_offset:  u32;
    size:         u32;
    align:        u32;
}

Arch_File :: struct {
    cpu_type:     Cpu_Type;
    cpu_subtype: Cpu_Subtype;
    data: [] u8;
}

#scope_file

formatHex64 :: #bake_arguments formatInt(base = 16, minimum_digits = 16);

#import "Basic";
#import "Bit_Operations";
#import "File";
#import "String";
