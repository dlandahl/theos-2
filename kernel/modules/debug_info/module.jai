// A module for parsing debug information in DWARF or Codeview format.
// It’s not complete by any means, but it’s nonetheless useful for analyzing the types and source line information emitted by Jai and other compilers.

#load "codeview/codeview.jai";
#load "dwarf/dwarf.jai";
#load "pdb/pdb.jai";

#scope_module

formatHex :: #bake_arguments formatInt(base = 16);

get_c_string_from_data :: (data: [] u8, offset: s64) -> result: string, success: bool {
    str: string = ---;
    str.data = data.data + offset;
    str.count = 0;
    while offset + str.count < data.count && str.data[str.count] != 0 {
        str.count += 1;
    }
    if offset + str.count == data.count {
        log_error("Unexpected end of data while parsing a string at offset %\n", offset);
        return "", false;
    }

    // log("Found string \"%\"\n", str);

    return str, true;
}


#import "Basic";
