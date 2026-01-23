// A module for parsing COFF (Windows), ELF (Linux), and Mach-O (macOS) executables and object files,
// with varying degrees of support.
// It also handles package formats like AR (static libraries), Apple Universal Binaries, and Text-Based Dylibs.
//
// We mostly use it to look at the output of Jai backends
// but can also be useful for writting debuggers and other system tools.

#load "apple_universal.jai";
#load "ar.jai";
#load "coff.jai";
#load "elf.jai";
#load "macho.jai";
#load "pe.jai";
#load "tbd/tbd.jai";

string_from_zero_padded_array :: (padded: [] u8) -> string {
    result := cast(string) padded;
    while result[result.count - 1] == 0 result.count -= 1;
    return result;
}

#scope_module

formatHex :: #bake_arguments formatInt(base = 16);

#import "Basic";
#import "File";
