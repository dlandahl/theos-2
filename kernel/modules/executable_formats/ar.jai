Archive :: struct {
    content: string;
    symbol_file_offsets: [] u32;
    symbol_names: [] string;
    files: [] Archive_File;
}

Archive_File :: struct {
    name: string;
    header_start_offset: u32;
    data: [] u8;
}

is_ar :: (file_content: string) -> bool {
    return begins_with(file_content, AR_FILE_MAGIC);
}

parse_ar_file :: (path: string) -> success: bool, Archive {
    ar: Archive = ---;
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, ar;
    }

    success, ar = parse_ar(content, path);
    return success, ar;
}

parse_ar :: (content: string, archive_filename: string, verbose := false) -> success: bool, Archive {
    assert(begins_with(content, AR_FILE_MAGIC));
    archive: Archive;
    archive.content = content;

    ar_content := array_view(cast ([] u8) content, AR_FILE_MAGIC.count);


    is_gnu_variant := false;
    extended_filename_data: [] u8;
    offset := 0;
    found_symbol_names := false;
    files: [..] Archive_File;
    while offset < ar_content.count {
        if offset + size_of(Ar_File_Header) > ar_content.count {
            log_error("Unexpected end at % while parsing archive \"%\"", offset, archive_filename);
            return false, .{};
        }

        header_start_offset := cast(u32) offset + AR_FILE_MAGIC.count;
        ar_header := cast (*Ar_File_Header) (ar_content.data + offset);
        offset += size_of(Ar_File_Header);

        if ar_header.ending != 0x0a60 {
            log_error("Unexpected ending characters in header at % while parsing archive \"%\": 0x%\n", offset, archive_filename, formatHex64(ar_header.ending));
            return false, .{};
        }

        file_size_string := cast(string) ar_header.file_size;
        file_size, success, remainder := string_to_int(file_size_string);
        if !success || trim(remainder) {
            log_error("Invalid file size in archive \"%\"\n", archive_filename);
            return false, .{};
        }
        if offset + file_size > ar_content.count {
            log_error("Invalid file header in archive \"%\"\n", archive_filename);
            return false, .{};
        }

        filename := cast(string) ar_header.identifier;

        if verbose log("Found file \"%\" of size % in \"%\"\n", filename, file_size, archive_filename);

        if begins_with(filename, "#1/") {
            real_filename_length_string := slice(filename, 3, filename.count - 3);
            real_filename_length, success, remainder := string_to_int(real_filename_length_string);
            if !success || trim(remainder) {
                log_error("Error while parsing archive \"%\": Could not parse real file name length from \"%\": % \"%\"", archive_filename, filename, success, remainder);
                continue;
            }
            if file_size < real_filename_length {
                log_error("Error while parsing archive \"%\": Real file name length goes out of bounds: % vs %", archive_filename, real_filename_length, file_size);
                continue;
            }
            filename.count = real_filename_length;
            filename.data = ar_content.data + offset;
            if verbose log("Real file name: \"%\"", filename);
            offset += real_filename_length;
            file_size -= real_filename_length;
        }

        trimmed_filename := trim(filename);
        skip_file := false;
        if trimmed_filename == "/" {
            skip_file = true;
            is_gnu_variant = true;
            if found_symbol_names {
                // This is Microsoft's symbol cross-reference table. Skip it
                // log("Skipping over Microsoft’s symbol cross-reference table.");
            } else {
                success: bool;
                archive.symbol_names, archive.symbol_file_offsets, success = parse_gnu_symbol_archive_file(ar_content, offset, file_size, archive_filename);
                // log("Symbol names: %", archive.symbol_names);
                if !success return false, .{};
                found_symbol_names = true;
            }
        } else if trimmed_filename == "//" {
            skip_file = true;
            if extended_filename_data {
                log_error("Error while parsing archive \"%\": Found more than one extended filename section!", archive_filename);
                return false, .{};
            }

            extended_filename_data.count = file_size;
            extended_filename_data.data = ar_content.data + offset;
        } else if trimmed_filename == "/<XFGHASHMAP>/" {
            // Windows libraries compiled with "/guard" contain this section, which would otherwise trigger the if below.
        } else if is_gnu_variant && begins_with(filename, "/") {
            if !extended_filename_data {
                log_error("Error while parsing archive \"%\": Found extended filename \"%\", but no extended filename data file!", archive_filename, filename);
                return false, .{};
            }

            real_filename_offset_string := slice(filename, 1, filename.count - 1);
            real_filename_offset, success, remainder := string_to_int(real_filename_offset_string);
            if !success || trim(remainder) {
                log_error("Error while parsing archive \"%\": Could not parse real file name offset from \"%\": % \"%\"", archive_filename, filename, success, remainder);
                continue;
            }
            if real_filename_offset >= extended_filename_data.count {
                log_error("Error while parsing archive \"%\": Real file name offset goes out of bounds: % vs %", archive_filename, real_filename_offset, extended_filename_data.count);
                continue;
            }

            filename_offset := real_filename_offset;
            while filename_offset < extended_filename_data.count && extended_filename_data[filename_offset] != 0 && extended_filename_data[filename_offset] != #char "\n" { // Linux separates filenames by "\n", Windows by 0.
                filename_offset += 1;
            }
            if filename_offset == extended_filename_data.count {
                log_error("Error while parsing archive \"%\": Real file name for \"%\" starting at % goes out of bounds!", archive_filename, filename, real_filename_offset);
                continue;
            }
            filename = .{filename_offset - real_filename_offset, extended_filename_data.data + real_filename_offset};
            if verbose log("Real file name: \"%\"", filename);
        } else if begins_with(filename, "__.SYMDEF") {
            skip_file = true;
            // log("Found symbol definitions file: % %", offset, filename);
            success: bool;
            if begins_with(filename, "__.SYMDEF64") {
                archive.symbol_names, success = parse_bsd_symbol_archive_file(ar_content, offset, file_size, archive_filename, u64);
            } else {
                archive.symbol_names, success = parse_bsd_symbol_archive_file(ar_content, offset, file_size, archive_filename, u32);
            }
            // log("Symbol names: %", archive.symbol_names);
            if !success return false, .{};
            found_symbol_names = true;
        }

        if !skip_file {
            if ends_with(filename, "/") filename.count -= 1; // System V / GNU uses "/" to denote the end of a filename

            file_data := ([]u8).{file_size, ar_content.data + offset};
            array_add(*files, .{filename, header_start_offset, file_data});
        }

        offset += file_size;

        if offset % 2 {
            if ar_content[offset] != #char "\n" {
                log_error("Unexpected filler character in archive \"%\"", archive_filename);
                return false, .{};
            }
            offset += 1;
        }
    }

    if !found_symbol_names {
        log_error("Could not find symbol name file in archive \"%\"", archive_filename);
        return false, .{};
    }

    archive.files = files;

    return true, archive;
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
    // Early out if no symbols to avoid the underflow for num_symbols-1
    if num_symbols == 0 {
        return .[], .[], true; // Not an error.
    }

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

AR_FILE_MAGIC :: "!<arch>\n";

Ar_File_Header :: struct {
    identifier: [16] u8;
    timestamp:  [12] u8;
    owner:      [6] u8;
    group:      [6] u8;
    file_mode:  [8] u8;
    file_size:  [10] u8;
    ending:     u16;
}

// From <ranlib.h>
Ranlib_Symbol :: struct (Offset_Type: Type) {
    ran_strx: Offset_Type;
    ran_off: Offset_Type;
}


#scope_file

formatHex64 :: #bake_arguments formatInt(base = 16, minimum_digits = 16);

#import "Basic";
#import "Bit_Operations";
#import "File";
#import "String";
