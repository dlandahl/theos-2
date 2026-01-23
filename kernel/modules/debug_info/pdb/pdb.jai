// Implemented using the information in https://github.com/microsoft/microsoft-pdb
// Most of the comments are from that original codebase
//
// The LLVM guys also published some reverse-engineered information about PDB:
// https://llvm.org/docs/PDB/index.html

is_pdb :: is_msf;

Pdb :: struct {
    header: Pdb_Header;
    signature: GUID;
    name_table: Name_Table;

    contains_id_stream: bool;
    no_type_merge:      bool;
    minimal_debug_info: bool;

    tpi: [] *Codeview_Type;
    ipi: [] *Codeview_Type;

    msf: Msf;
}

Pdb_Header :: struct {
    version: Pdb_Version;
    signature: u32;
    age: u32;
}

Pdb_Version :: enum u32 {
    VC2      :: 19941610;
    VC4      :: 19950623;
    VC41     :: 19950814;
    VC50     :: 19960307;
    VC98     :: 19970604;
    VC70     :: 20000404;
    VC70Dep  :: 19990604;  // deprecated vc70 implementation version
    VC80     :: 20030901;
    VC110    :: 20091201;
    VC140    :: 20140508;
}


parse_pdb :: (file_content: string, path := "", verbose := false) -> success: bool, Pdb {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false, .{};
        }
    } @PrintLike

    success: bool;
    pdb: Pdb;
    success, pdb.msf = parse_msf(file_content, path);
    check(success, "Could not parse PDB file as MSF");

    pdb_data, success= := get_stream_data(pdb.msf, STREAM_INDEX_PDB);
    check(success, "Could not get PDB stream data");

    state: Pdb_Parser_State;
    state.data = pdb_data;
    pdb.header = get(*state, Pdb_Header);
    check(!state.failed, "PDB stream header went out of bounds");

    check(pdb_data.count != size_of(Pdb_Header), "Unsupported PDB version: %", pdb.header.version); // This is the case in some old PDB version

    if verbose log("PDB header: %", pdb.header);
    if pdb.header.version == {
        case .VC4; #through;
        case .VC41; #through;
        case .VC50; #through;
        case .VC98; #through;
        case .VC70; #through;
        case .VC80; #through;
        case .VC110; #through;
        case .VC140;
            if verbose log("Supported PDB version %", pdb.header.version);
            if pdb.header.version >= .VC70 {
                pdb.signature = get(*state, GUID);
                check(!state.failed, "PDB signature went out of bounds");
                if verbose log("Signature: %", pdb.signature);
            }

            success = parse_name_table(*state, *pdb.name_table, verbose = verbose);
            check(success && !state.failed, "Could not parse name table");

            while state.offset + 4 <= state.data.count {
                sig := get(*state, u32);
                if verbose log("Sig: 0x%", sig);
                if sig == {
                    case xx Pdb_Version.VC110;       pdb.contains_id_stream = true;
                    case xx Pdb_Version.VC140;       pdb.contains_id_stream = true;
                    case FEATURE_NO_TYPE_MERGE;      pdb.no_type_merge = true;
                    case FEATURE_MINIMAL_DEBUG_INFO; pdb.minimal_debug_info = true;
                    case; log_error("Warning: Unknown PDB flag 0x%", formatHex(sig));
                }
            }

            pdb.tpi, success = parse_tpi_stream(pdb.msf, STREAM_INDEX_TPI, verbose = verbose);
            check(success, "Could not parse TPI stream");
            pdb.ipi, success = parse_tpi_stream(pdb.msf, STREAM_INDEX_IPI, verbose = verbose);
            check(success, "Could not parse IPI stream");

            if verbose {
                success = dump_codeview_types(pdb.tpi, pdb.ipi);
                check(success, "Could not dump CodeView types");
            } else {
                // @ToDo: Just validate without dumping. But currently these two steps are intertwined.
            }

        case;
            log_error("Unsupported PDB version %", pdb.header.version);
            return false, .{};
    }


    return true, pdb;
}

#load "msf.jai";
#load "free_page_map.jai";

#scope_module

Pdb_Parser_State :: struct {
    data: [] u8;
    offset: int;
    failed := false;
    fail_location: Source_Code_Location;
}

fail :: (using state: *Pdb_Parser_State, loc: Source_Code_Location) {
    if failed return;
    failed = true;
    fail_location = loc;
}

get :: (using state: *Pdb_Parser_State, $T: Type, loc := #caller_location) -> T, success: bool {
    if failed || offset + size_of(T) > data.count {
        fail(state, loc);
        dummy: T;
        return dummy, false;
    }

    result := (.*)(cast(*T) (data.data + offset));
    offset += size_of(T);
    return result, true;
}

get_array :: (using state: *Pdb_Parser_State, count: int, $T: Type, loc := #caller_location) -> [] T, success: bool {
    if failed || offset + count * size_of(T) > data.count {
        fail(state, loc);
        return .[], false;
    }

    result: [] T;
    result.data = cast(*T) (data.data + offset);
    result.count = count;
    offset += count * size_of(T);
    return result, true;
}

#scope_file

String_Offset :: #type,isa s32;
Name_Index    :: #type,isa u32;

// see reload() in PDB/include/nmtni.h
parse_name_table :: (state: *Pdb_Parser_State, name_table: *Name_Table, verbose := false) -> bool {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false;
        }
    } @PrintLike

    // load "buffer"
    buffer_size := get(state, u32);
    name_table.buffer = get_array(state, buffer_size, u8);

    if verbose log("Buffer: %", name_table.buffer);

    parse_pdb_map(state, *name_table.string_to_name_map, verbose = verbose);
    num_name_indices := get(state, Name_Index);

    // @ToDo: Rebuild name_to_string_map from string_to_name_map, if we need it
    // for name_table.string_to_name_map {
    //     name_table.name_to_string
    // }

    return true;
}

Pdb_Map :: struct (Key: Type, Value: Type) {
    keys: [] Key;
    values: [] Value;
    present: Int_Set;
    deleted: Int_Set;

    MAX_PRESENT :: Math.U64_MAX / (size_of(Key) + size_of(Value));
}

parse_pdb_map :: (state: *Pdb_Parser_State, map: *Pdb_Map($K, $T), verbose := false) -> bool {
    map_count := get(state, u32);
    map_size  := get(state, u32);
    {
        size := get(state, u32);
        map.present.words = get_array(state, size, u32);
    }
    {
        size := get(state, u32);
        map.deleted.words = get_array(state, size, u32);
    }

    bits_present := cardinality(map.present);
    if bits_present > map.MAX_PRESENT {
        log_error("Map has too many entries: %", bits_present);
        return false;
    }
    if bits_present != map_count {
        log_error("Map has disagreeing count values: % vs. %", bits_present, map_count);
        return false;
    }

    map.keys = NewArray(map_size, map.Key);
    map.values = NewArray(map_size, map.Value);
    if map_count > max_load_factor(map) {
        log_error("Map load factor is too high: % / %", map_count, max_load_factor(map));
        return false;
    }

    for i: 0..map_size-1 {
        if is_set(map.present, i) {
            if verbose log("Loading %", i);
            map.keys[i] = get(state, map.Key);
            map.values[i] = get(state, map.Value);
        }
    }

    if state.failed return false;

    if verbose log("Map data: count: % size: %,  % / % / % / %", map_count, map_size, map.present, map.deleted, map.keys, map.values);
    return true;
}

max_load_factor :: (map: Pdb_Map) -> int {
    return map.keys.count * 2/3 + 1;
}

Name_Table :: struct {
    buffer: [] u8;
    string_to_name_map: Pdb_Map(String_Offset, Name_Index);
    // name_to_string_map: Pdb_Map(Name_Index, String_Offset);
}


STREAM_INDEX_PDB: SN : 1;
STREAM_INDEX_TPI: SN : 2;
STREAM_INDEX_DBI: SN : 3;
STREAM_INDEX_IPI: SN : 4;

FEATURE_NO_TYPE_MERGE      :: 0x4D544F4E;    // "NOTM"
FEATURE_MINIMAL_DEBUG_INFO :: 0x494E494D;    // "MINI"

GUID :: struct {
    Data1: u32;
    Data2: u16;
    Data3: u16;
    Data4: [8] u8;
}

#load "int_set.jai";
#load "tpi.jai";


Math :: #import "Math";
