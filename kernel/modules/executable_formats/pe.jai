MS_DOS_MAGIC_PREFIX :: 0x5a4d;
PE_MAGIC_PREFIX :: 0x00004550;

Ms_Dos_Header :: struct {
    magic:    u16;      // Magic number
    cblp:     u16;      // Bytes on last page of file
    cp:       u16;      // Pages in file
    crlc:     u16;      // Relocations
    cparhdr:  u16;      // Size of header in paragraphs
    minalloc: u16;      // Minimum extra paragraphs needed
    maxalloc: u16;      // Maximum extra paragraphs needed
    ss:       u16;      // Initial (relative) SS value
    sp:       u16;      // Initial SP value
    csum:     u16;      // Checksum
    ip:       u16;      // Initial IP value
    cs:       u16;      // Initial (relative) CS value
    lfarlc:   u16;      // File address of relocation table
    ovno:     u16;      // Overlay number
    res:      [4] u16;  // Reserved words
    oemid:    u16;      // OEM identifier (for oeminfo)
    oeminfo:  u16;      // OEM information; oemid specific
    res2:     [10] u16; // Reserved words
    lfanew:   u32;      // File address of new exe header
}

parse_pe_file :: (path: string) -> success: bool, Coff {
    coff: Coff = ---;
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, coff;
    }

    success, coff = parse_pe(content, path);
    return success, coff;
}

is_pe :: (file_content: string) -> bool, coff_start: int {
    if file_content.count < size_of(Ms_Dos_Header) return false, 0;

    dos_header := cast(*Ms_Dos_Header) file_content.data;
    if dos_header.magic != MS_DOS_MAGIC_PREFIX return false, 0;

    pe_magic_address := dos_header.lfanew;
    if pe_magic_address + size_of(u32) > file_content.count return false, 0;

    pe_magic := (.*)(cast(*u32) (file_content.data + pe_magic_address));
    if pe_magic != PE_MAGIC_PREFIX return false, 0;

    header_offset := pe_magic_address + size_of(u32);
    remainder := slice(file_content, header_offset, file_content.count - header_offset);

    return is_coff(remainder), header_offset;
}

parse_pe :: (file_content: string, path := "(unspecified file)", verbose := false) -> success: bool, Coff {
    check :: (condition: bool, message: string, args: .. Any) #expand {
        if !condition {
            log_error(message, ..args);
            `return false, coff;
        }
    } @PrintLike

    coff: Coff;

    success, coff_start := is_pe(file_content);
    check(success, "File does not appear to be a PE binary");

    success, coff = parse_coff(file_content, path, start_offset = coff_start, verbose = verbose);

    return success, coff;
}


#import "String";
