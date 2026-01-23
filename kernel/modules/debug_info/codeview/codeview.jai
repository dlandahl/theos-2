//
// Useful CodeView documentation:
//
// "Microsoft Symbol and Type Information" (General description, but the format structs are outdated! Newer information is in Microsoft’s cvinfo.h, see below.)
// https://pierrelib.pagesperso-orange.fr/exec_formats/MS_Symbol_Type_v1.0.pdf
//
// Microsoft PDB public release:
// https://github.com/microsoft/microsoft-pdb
// Especially cvinfo.h:
// https://github.com/microsoft/microsoft-pdb/blob/master/include/cvinfo.h
//
//
// 2016 LLVM Developers' Meeting: R. Kleckner "CodeView, the MS Debug Info Format in LLVM"
// https://www.youtube.com/watch?v=5twzd06NqGU
//
// MolecularMatters’ RawPDB library
// https://github.com/MolecularMatters/raw_pdb
//

parse_codeview_types :: (data: [] u8, expect_codeview_version := true, verbose := false) -> bool, [] *Codeview_Type {
    check :: (condition: bool, message := "", args: .. Any) #expand {
        if !condition {
            if message then log_error(message, ..args);
            `return false, .[];
        }
    } @PrintLike

    if !data    return true, .[];

    state: Codeview_Type_Parser_State;
    state.data = data;
    state.success = true;

    if expect_codeview_version {
        version := parse_primitive(*state, u32);
        check(state.success, "Could not read CodeView version");
        check(version == 4, "Unsupported CodeView version %", version);
    }

    index := 0;
    while state.success && state.offset < state.data.count {
        defer index += 1;
        type_start := state.offset;
        type_size := parse_primitive(*state, u16);
        check(state.success);
        type_end := type_start + size_of(type_of(type_size)) + type_size;
        check(type_end <= state.data.count, "Type % ends out of bounds: % vs %", index, type_end, state.data.count);

        defer {
            if !state.success then dump(state, type_start, type_size + 2);
        }

        type_kind := cast(Codeview_Leaf_Type) parse_primitive(*state, u16);
        check(state.success);

        if verbose log("Type 0x%: % (%)", h(index), type_kind, type_size);
        if type_kind == {
            case .STRUCTURE;
                t := New(Codeview_Struct);
                t.num_fields = parse_primitive(*state, u16);
                t.properties = cast(Struct_Properties) parse_primitive(*state, u16);
                t.field_list = parse_primitive(*state, Type_Id);
                t.derived = parse_primitive(*state, Type_Id);
                t.vshape = parse_primitive(*state, u32);
                t.size = parse_variable_integer(*state, u64);
                t.name = parse_string_zeroterminated(*state);
                t.unique_name = t.name;
                if t.properties & .UNIQUE_NAME {
                    t.unique_name = parse_string_zeroterminated(*state);
                }
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, t);

            case .ENUM;
                t := New(Codeview_Enum);
                t.num_fields = parse_primitive(*state, u16);
                t.properties = cast(Struct_Properties) parse_primitive(*state, u16);
                t.type = parse_primitive(*state, Type_Id);
                t.field_list = parse_primitive(*state, Type_Id);
                t.name = parse_string_zeroterminated(*state);
                t.unique_name = t.name;
                if t.properties & .UNIQUE_NAME {
                    t.unique_name = parse_string_zeroterminated(*state);
                }
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, t);

            case .ARRAY;
                t := New(Codeview_Array);
                t.element_type = parse_primitive(*state, Type_Id);
                t.index_type = parse_primitive(*state, Type_Id);
                t.size = parse_variable_integer(*state, u64);
                t.name = parse_string_zeroterminated(*state);
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, t);

            case .POINTER;
                t := New(Codeview_Pointer);
                t.type = parse_primitive(*state, Type_Id);
                t.flags = parse_primitive(*state, u32);

                array_add(*state.types, t);

            case .FIELDLIST;
                list := New(Codeview_List);

                while state.offset < type_end {
                    leaf_start := state.offset;
                    leaf := cast(Codeview_Leaf_Type) parse_primitive(*state, u16);
                    if leaf == {
                        case .MEMBER;
                            entry := New(Codeview_Member);
                            entry.access = parse_primitive(*state, u16);
                            entry.type = parse_primitive(*state, Type_Id);
                            entry.offset = parse_variable_integer(*state, u64);
                            entry.name = parse_string_zeroterminated(*state);
                            skip_leaf_padding(*state, 0, 4);

                            if verbose log("List member: \"%\" of type 0x% at 0x%", entry.name, h(cast(int) entry.type), h(entry.offset));

                            check(state.success);
                            array_add(*list.members, entry);

                        case .ENUMERATE;
                            entry := New(Codeview_Enumerate);
                            entry.access = parse_primitive(*state, u16);
                            entry.value = parse_variable_integer(*state, u64);
                            entry.name = parse_string_zeroterminated(*state);
                            skip_leaf_padding(*state, 0, 4);

                            if verbose log("List enumerate: \"%\" with value %, access %", entry.name, entry.value, entry.access);

                            check(state.success);
                            array_add(*list.enumerates, entry);

                        case .INDEX;
                            padding := parse_primitive(*state, u16); // padding
                            check(padding == 0, "Invalid padding of entry 0x% at 0x%", h(cast(int)leaf), leaf_start);
                            list.previous = parse_primitive(*state, Type_Id);
                            check(state.success);

                        case .NESTTYPE;
                            entry := New(Codeview_Nested_Type);
                            padding := parse_primitive(*state, u16);
                            check(padding == 0, "Invalid padding of entry 0x% at 0x%", h(cast(int)leaf), leaf_start);
                            entry.type = parse_primitive(*state, Type_Id);
                            entry.name = parse_string_zeroterminated(*state);
                            skip_leaf_padding(*state, 0, 4);

                            if verbose log("List nested type \"%\" for type 0x%", entry.name, h(cast(int) entry.type));

                            check(state.success);
                            array_add(*list.nested, entry);

                        case;
                            check(false, "Unexpected list entry type 0x% at %", h(cast(int)leaf), leaf_start);
                    }
                }

                check(list.members.count == 0 || list.enumerates.count == 0, "List % contains both % members and % enumerates ", index, list.members.count, list.enumerates.count);

                array_add(*state.types, list);

            case .ARGLIST;     #through;
            case .SUBSTR_LIST; #through;
            case .BUILDINFO;
                list := New(Codeview_Arguments);
                list.kind = type_kind;
                num_arguments: s64;
                if type_kind == {
                    case .ARGLIST; #through;
                    case .SUBSTR_LIST;
                        num_arguments = parse_primitive(*state, u32);
                    case .BUILDINFO;
                        num_arguments = parse_primitive(*state, u16);
                    case;
                        assert(false, "Unexpected kind %", type_kind); return false, .[];
                }

                args_end := state.offset + num_arguments * size_of(Type_Id);

                list.arguments.data = cast(*Type_Id) (state.data.data + state.offset);
                list.arguments.count = num_arguments;

                state.offset = args_end;
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, list);

            case .PROCEDURE;
                s := New(Codeview_Procedure);
                s.return_type = parse_primitive(*state, Type_Id);
                s.calling_convention = parse_primitive(*state, u8);
                s.attributes = parse_primitive(*state, u8);
                s.num_arguments = parse_primitive(*state, u16);
                s.arguments = parse_primitive(*state, Type_Id);

                array_add(*state.types, s);

            case .STRING_ID;
                s := New(Codeview_String_Id);
                s.id = parse_primitive(*state, u32);
                s.name = parse_string_zeroterminated(*state);
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, s);

            case .UDT_SRC_LINE;
                s := New(Codeview_Udt_Source_Line);
                s.type = parse_primitive(*state, Type_Id);
                s.src = parse_primitive(*state, Type_Id);
                s.line = parse_primitive(*state, u32);

                array_add(*state.types, s);

            case .FUNC_ID;
                s := New(Codeview_Function_Id);
                s.scope = parse_primitive(*state, Type_Id);
                s.type = parse_primitive(*state, Type_Id);
                s.name = parse_string_zeroterminated(*state);
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, s);

            case .ALIAS;
                s := New(Codeview_Alias);
                s.type = parse_primitive(*state, Type_Id);
                s.name = parse_string_zeroterminated(*state);
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, s);

            case .TYPESERVER2;
                s := New(Codeview_Typeserver2);
                s.sig70 = parse_guid(*state);
                s.age = parse_primitive(*state, type_of(s.age));
                s.name = parse_string_zeroterminated(*state);
                skip_leaf_padding(*state, 0, 4);

                array_add(*state.types, s);
            case .MODIFIER;
                s := New(Codeview_Modifier);
                s.type = parse_primitive(*state, Type_Id);
                s.modifier = parse_primitive(*state, Codeview_Modifier.Modifier_Type);
                skip_leaf_padding(*state, 0, 4); // @Cleanup: this seems wrong. Normally we only have padding after variable length data like strings…

                array_add(*state.types, s);

            case;
                log_error("Skipping unsupported leaf type % (0x%) of size 0x%", type_kind, h(cast(int)type_kind), h(type_size));
                array_add(*state.types, null);
                state.offset = type_start + size_of(type_of(type_size)) + type_size;
        }
        check(state.success);

        check(state.offset == type_end, "Unexpected end of type index %: % vs %", index, state.offset, type_end);
    }

    assert(state.offset == data.count);

    return true, state.types;
}

dump_codeview_types :: (types: [] *Codeview_Type, ids: [] *Codeview_Type) -> bool {
    if types {
        log("Types:");
        for types {
            description, success := describe_type(types, ids, it);
            if !success {
                log_error("Error while describing type at index %: %", it_index, description);
                return false;
            }
            log("0x%: %", formatHex(0x1000 + it_index), description);
        }
    }
    if ids {
        log("Ids:");
        for ids {
            description, success := describe_type(types, ids, it);
            if !success {
                log_error("Error while describing type index at index %: %", it_index, description);
                return false;
            }
            log("0x%: %", formatHex(0x1000 + it_index), description);
        }
    }

    return true;
}

Codeview_Debug_Info :: struct {
    types: [] *Codeview_Type;
    ids: [] *Codeview_Type; // Either points to "types" (if loaded from an object file) or is a separate array (if loaded from a PDB file)
    symbols: [..] *Codeview_Symbol;
    string_table: [] u8;
    file_checksums: [..] Codeview_File_Checksum;
    line_info: [..] Codeview_Line_Info_Sequence;
    inlinee_line_info: [..] Codeview_Inlinee_Line_Info;
}

get_string_from_table :: (info: Codeview_Debug_Info, id: Codeview_String_Table_Id) -> string, success: bool {
    result, success := get_c_string_from_data(info.string_table, cast(u32) id);
    return result, success;
}

parse_codeview_symbols :: (info: *Codeview_Debug_Info, data: [] u8, verbose := false) -> success: bool {
    check :: (condition: bool, message := "", args: .. Any) #expand {
        if !condition {
            if message then log_error(message, ..args);
            `return false;
        }
    } @PrintLike

    state: Codeview_Symbol_Parser_State;
    state.data = data;
    state.success = true;
    state.verbose = verbose;
    state.info = info;

    check(data.count >= 4, "CodeView symbol section has invalid size: %", data.count);
    version := parse_primitive(*state, u32);
    check(version == 4, "Unsupported CodeView version %", version);

    while state.success && state.offset < state.data.count {
        section_type := parse_primitive(*state, Codeview_Symbol_Section);
        section_size := parse_primitive(*state, u32);
        check(state.offset + section_size <= state.data.count, "Subsection % goes out of bounds: 0x%/0x%", section_type, h(state.offset + section_size), h(state.data.count));
        section_start := state.offset;
        if (section_type & .IGNORE) {
            log("Ignoring subsection type % (0x%)", (section_type & ~.IGNORE), h(cast(int) section_type));
            state.offset += section_size;
        }  else {
            if verbose log("Found % of size 0x% at offset 0x%", section_type, h(section_size), h(state.offset));
            if section_type == {
                case .STRING_TABLE;
                    if info.string_table {
                        log_error("Codeview symbols contained more than one string table.");
                        state.success = false;
                    } else {
                        info.string_table.count = section_size;
                        info.string_table.data = state.data.data + state.offset;
                    }

                    state.offset += section_size;
                case .FILE_CHECKSUMS;
                    if info.file_checksums {
                        log_error("Codeview symbols contained more than one file checksums section.");
                        state.success = false;
                    } else {
                        parse_file_checksums_section(*state, section_size);
                    }
                case .LINES;
                    parse_lines_section(*state, section_size);
                    check(state.offset == section_start + section_size, "Unexpected offset after parsing % subsections: 0x% vs 0x%", section_type, h(state.offset), h(state.data.count));
                case .SYMBOLS;
                    parse_symbols_section(*state, section_size);
                    check(state.offset == section_start + section_size, "Unexpected offset after parsing % subsections: 0x% vs 0x%", section_type, h(state.offset), h(state.data.count));
                case .INLINEELINES;
                    parse_inlinlee_lines_section(*state, section_size);
                    check(state.offset == section_start + section_size, "Unexpected offset after parsing % subsections: 0x% vs 0x%", section_type, h(state.offset), h(state.data.count));
                case;
                    log_error("Unsupported CodeView symbol subsection type % (0x%) of size 0x%", section_type, h(cast(int) section_type), h(section_size));
                    state.offset += section_size;
            }
        }
        skip_padding(*state);
    }

    check(state.offset == state.data.count, "Unexpected offset after parsing all subsections: 0x% vs 0x%", h(state.offset), h(state.data.count));

    return state.success;
}

get_filename_for_file_id :: (info: Codeview_Debug_Info, id: Codeview_File_Checksum_Id) -> string, success: bool {
    for info.file_checksums {
        if it.id == id {
            result, success := get_string_from_table(info, it.filename_id);
            return result, success;
        }
    }
    return "", false;
}

Codeview_Symbol :: struct {
    symbol_type: Codeview_Symbol_Type;
}

Codeview_Symbol_Compile :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .COMPILE;
    target_cpu: u8;
    language: u8;
    flags: u16;
    compiler_version: string;
}

Codeview_Symbol_Compile3 :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .COMPILE3;
    language:         u8;
    flags1:           u8;
    flags2:           u8;
    reserved:         u8;
    target_cpu:       u16;
    fe_version:       Version;
    be_version:       Version;
    compiler_version: string;

    Version :: struct {
        major: u16;
        minor: u16;
        build: u16;
        qfe: u16;
    }
}

Codeview_Symbol_Procedure :: struct {
    using #as base: Codeview_Symbol;
    parent:             u32;
    end:                u32;
    next:               u32;
    length:             u32;
    debug_start_offset: u32;
    debug_end_offset:   u32;
    type:               Type_Id;
    offset:             u32;
    segment_index:      u16;
    flags:              Flags;
    name:               string;

    Flags :: enum_flags u8 {
        CV_PFLAG_NOFPO      :: 0x01; // frame pointer present
        CV_PFLAG_INT        :: 0x02; // interrupt return
        CV_PFLAG_FAR        :: 0x04; // far return
        CV_PFLAG_NEVER      :: 0x08; // function does not return
        CV_PFLAG_NOTREACHED :: 0x10; // label isn't fallen into
        CV_PFLAG_CUST_CALL  :: 0x20; // custom calling convention
        CV_PFLAG_NOINLINE   :: 0x40; // function marked as noinline
        CV_PFLAG_OPTDBGINFO :: 0x80; // function has debug information for optimized code
    }

    // Additional info
    inlinesites: [..] *Codeview_Symbol_Inline_Site;
}

is_procedure :: (symbol: *Codeview_Symbol) -> bool {
    if symbol.symbol_type == {
        case .LPROC32; #through;
        case .GPROC32; #through;
        case .LPROC32_ID; #through;
        case .GPROC32_ID;
            return true;
        case;
            return false;
    }
}

Codeview_Symbol_Regrel :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .REGREL32;
    off:    u32;     // offset of symbol
    typind: Type_Id; // Type index or metadata token
    reg:    u16;     // register index for symbol
    name:   string;  // Length-prefixed name

}

Codeview_Symbol_Data :: struct {
    using #as base: Codeview_Symbol;
    type:          Type_Id;     // Type index, or Metadata token if a managed symbol
    offset:        u32;
    segment_index: u16;
    name:          string;
}

Codeview_Symbol_Buildinfo :: struct {
    using #as base: Codeview_Symbol;
    id: Item_Id #align 2;
} #no_padding

Codeview_Symbol_Frame_Proc :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .FRAMEPROC;
    frame_bytes:     u32 #align 2; // count of bytes of total frame of procedure
    pad_bytes:       u32 #align 2; // count of bytes of padding in the frame
    pad_offset:      u32 #align 2; // offset (relative to frame pointer) to where padding starts
    save_regs_bytes: u32 #align 2; // count of bytes of callee save registers
    eh_offset:       u32 #align 2; // offset of exception handler
    eh_section_id:   u16 #align 2; // section id of exception handler
    flags:           Flags #align 2;

    Flags :: enum_flags u32 {
        HAS_ALLOCA                     :: 0x00000001; // function uses _alloca()
        HAS_SET_JMP                    :: 0x00000002; // function uses setjmp()
        HAS_LONG_JMP                   :: 0x00000004; // function uses longjmp()
        HAS_INL_ASM                    :: 0x00000008; // function uses inline asm
        HAS_EH                         :: 0x00000010; // function has EH states
        INL_SPEC                       :: 0x00000020; // function was speced as inline
        HAS_SEH                        :: 0x00000040; // function has SEH
        NAKED                          :: 0x00000080; // function is __declspec(naked)
        SECURITY_CHECKS                :: 0x00000100; // function has buffer security check introduced by /GS.
        ASYNC_EH                       :: 0x00000200; // function compiled with /EHa
        GS_NO_STACK_ORDERING           :: 0x00000400; // function has /GS buffer checks, but stack ordering couldn't be done
        WAS_INLINED                    :: 0x00000800; // function was inlined within another function
        GS_CHECK                       :: 0x00001000; // function is __declspec(strict_gs_check)
        SAFE_BUFFERS                   :: 0x00002000; // function is __declspec(safebuffers)

        // @Hack: ENCODED_LOCAL_BASE_POINTER and ENCODED_PARAM_BASE_POINTER are actually 3-valued bitfields instead of flags.
        // But we model their three values as flags and put them in an order that allows print() to display them correctly.
        // ENCODED_LOCAL_BASE_POINTER  :: 0x0000C000; // record function's local pointer explicitly.
        ENCODED_LOCAL_BASE_POINTER_R13 :: 0x0000C000;
        ENCODED_LOCAL_BASE_POINTER_RSP :: 0x00004000;
        ENCODED_LOCAL_BASE_POINTER_RBP :: 0x00008000;
        // ENCODED_PARAM_BASE_POINTER  :: 0x00030000; // record function's parameter pointer explicitly.
        ENCODED_PARAM_BASE_POINTER_R13 :: 0x00030000;
        ENCODED_PARAM_BASE_POINTER_RSP :: 0x00010000;
        ENCODED_PARAM_BASE_POINTER_RBP :: 0x00020000;

        POGO_ON                        :: 0x00040000; // function was compiled with PGO/PGU
        VALID_COUNTS                   :: 0x00080000; // Do we have valid Pogo counts?
        OPT_SPEED                      :: 0x00100000; // Did we optimize for speed?
        GUARD_CF                       :: 0x00200000; // function contains CFG checks (and no write checks)
        GUARD_CFW                      :: 0x00400000; // function contains CFW checks and/or instrumentation
    }
} #no_padding
#run assert(size_of(Codeview_Symbol_Frame_Proc) == 0x1c, "size: 0x%", h(size_of(Codeview_Symbol_Frame_Proc)));

Codeview_Symbol_Local :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .LOCAL;
    type: Type_Id;
    flags: Flags;
    name: string;

    Flags :: enum_flags u16 {
        IS_PARAM         :: 0x0001; // variable is a parameter
        ADDR_TAKEN       :: 0x0002; // address is taken
        COMP_GENX        :: 0x0004; // variable is compiler generated
        IS_AGGREGATE     :: 0x0008; // the symbol is splitted in temporaries, which are treated by compiler as independent entities
        IS_AGGREGATED    :: 0x0010; // Counterpart of fIsAggregate - tells that it is a part of a fIsAggregate symbol
        IS_ALIASED       :: 0x0020; // variable has multiple simultaneous lifetimes
        IS_ALIAS         :: 0x0040; // represents one of the multiple simultaneous lifetimes
        IS_RET_VALUE     :: 0x0080; // represents a function return value
        IS_OPTIMIZED_OUT :: 0x0100; // variable has no lifetimes
        IS_ENREG_GLOB    :: 0x0200; // variable is an enregistered global
        IS_ENREG_STAT    :: 0x0400; // variable is an enregistered static
    }
}

Range_Attribute_Flags :: enum_flags u16 {
    MAYBE :: 1;    // May have no user name on one of control flow path.
}

Codeview_Symbol_Defrange_Register :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .DEFRANGE_REGISTER;

    register:  u16;                     // Register to hold the value of the symbol
    attribute: Range_Attribute_Flags;   // Attribute of the register range.
    range:     Codeview_Address_Range;  // Range of addresses where this program is valid
    gaps:      [] Codeview_Address_Gap; // The value is not available in following gaps.
}

Codeview_Symbol_Defrange_Framepointer_Rel :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .DEFRANGE_FRAMEPOINTER_REL;

    frame_pointer_offset: s32;                     // offset to frame pointer
    range:                Codeview_Address_Range;  // Range of addresses where this program is valid
    gaps:                 [] Codeview_Address_Gap; // The value is not available in following gaps.
}

Codeview_Symbol_Defrange_Framepointer_Rel_Full_Scope :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .DEFRANGE_FRAMEPOINTER_REL_FULL_SCOPE;

    frame_pointer_offset: s32;                     // offset to frame pointer
}

Codeview_Symbol_Defrange_Register_Rel :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .DEFRANGE_REGISTER_REL;

    base_register:                        u16; // Register to hold the base pointer of the symbol
    spilled_udt_member_and_offset_parent: u16; // Spilled member for s.i., padding, and offset in parent variable.
    base_pointer_offset:                  u32; // offset to register

    range:                                Codeview_Address_Range;  // Range of addresses where this program is valid
    gaps:                                 [] Codeview_Address_Gap; // The value is not available in following gaps.
}

get_spilled_udt_member :: (s: *Codeview_Symbol_Defrange_Register_Rel) -> bool {
    return (s.spilled_udt_member_and_offset_parent & 0x1) != 0;
}

get_offset_parent :: (s: *Codeview_Symbol_Defrange_Register_Rel) -> u16 {
    return s.spilled_udt_member_and_offset_parent >> 4;
}

Codeview_Symbol_Objname :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .OBJNAME;

    signature: u32;
    name:      string;
}

Codeview_Symbol_Block :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .BLOCK32;
    parent:        u32;
    end:           u32;
    length:        u32;
    offset:        u32;
    segment_index: u16;
    name:          string;
}

Codeview_Symbol_Constant :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .CONSTANT;
    type:          Type_Id;
    value:         Numeric_Leaf_Value;
    name:          string;
}

Numeric_Leaf_Value :: struct {
    type: Type;
    value: union {
        f32: float;
        f64: float64;
        unsigned: u64;
        signed: s64;
    }
}

Codeview_Symbol_Unamespace :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .UNAMESPACE;
    name: string;
}

Codeview_Symbol_Inline_Site :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .INLINESITE;
    parent:     u32; // pointer to the inliner
    end:        u32; // pointer to this block's end
    inlinee:    Item_Id;   // CV_ItemId of inlinee
    binary_annotations: [..] Codeview_Binary_Annotation; // an array of compressed binary annotations.

    children: [..] *Codeview_Symbol_Inline_Site;
}

Codeview_Symbol_Udt :: struct {
    using #as base: Codeview_Symbol;
    symbol_type = .UDT;
    type: Type_Id;
    name: string;
}

Codeview_Symbol_Function_List :: struct {
    using #as base: Codeview_Symbol;
    functions: [] Function;

    Function :: struct {
        func:             Type_Id;
        invocation_count: u32;
    }
}


Codeview_Binary_Annotation :: struct {
    opcode: Codeview_Binary_Annotation_Opcode;
    operand1: Operand;
    operand2: Operand;
    Operand :: union {
        unsigned: u32;
        signed:   s32;
    }
}

Codeview_Address_Range :: struct {
    start_offset: u32;
    start_section: u16;
    range_bytes: u16;
}

Codeview_Address_Gap :: struct {
    start_offset: u16;
    range_bytes: u16;
}

Type_Id :: #type,distinct u32;
Item_Id :: #type,isa      Type_Id; // Item Id is a stricter typeindex which may referenced from symbol stream. The code item always had a name.

// @Cleanup: Merge with Parser_State for PDBs
Codeview_Parser_State :: struct {
    data: [] u8;
    offset: s64;
    success: bool;
    verbose: bool;
}

Codeview_Type_Parser_State :: struct {
    using #as base: Codeview_Parser_State;
    types: [..] *Codeview_Type;
}

Codeview_Symbol_Parser_State :: struct {
    using #as base: Codeview_Parser_State;
    info: *Codeview_Debug_Info;
    current_procedure: *Codeview_Symbol_Procedure;
    open_inlinesites: [..] *Codeview_Symbol_Inline_Site;
}

Codeview_Type :: struct {
    kind: Codeview_Leaf_Type;
}

Codeview_Builtin :: struct {
    using #as base: Codeview_Type;
    kind = .BUILTIN;
    id: Type_Id;
}

Codeview_Struct :: struct {
    using #as base: Codeview_Type;
    kind = .STRUCTURE;
    num_fields: u16;
    properties: Struct_Properties;
    field_list: Type_Id;
    derived: Type_Id;
    vshape: u32;
    size: u64;
    name: string;
    unique_name: string;
}

Codeview_Enum :: struct {
    using #as base: Codeview_Type;
    kind = .ENUM;
    num_fields: u16;
    properties: Struct_Properties;
    type: Type_Id;
    field_list: Type_Id;
    name: string;
    unique_name: string;
}

Codeview_Array :: struct {
    using #as base: Codeview_Type;
    kind = .ARRAY;
    element_type: Type_Id;
    index_type: Type_Id;
    size: u64;
    name: string;
}

Codeview_Pointer :: struct {
    using #as base: Codeview_Type;
    kind = .POINTER;
    type: Type_Id;
    flags: u32;
}

Codeview_Procedure :: struct {
    using #as base: Codeview_Type;
    kind = .PROCEDURE;
    return_type: Type_Id;
    calling_convention: u8;
    attributes: u8;
    num_arguments: u16;
    arguments: Type_Id;
}

Codeview_List :: struct {
    using #as base: Codeview_Type;
    kind = .FIELDLIST;
    previous: Type_Id;
    members: [..] Codeview_Member;
    enumerates: [..] Codeview_Enumerate;
    nested: [..] Codeview_Nested_Type;
}

Codeview_Arguments :: struct {
    using #as base: Codeview_Type;
    arguments: [] Type_Id;
}

Codeview_String_Id :: struct {
    using #as base: Codeview_Type;
    kind = .STRING_ID;
    id: u32;
    name: string;
}

Codeview_Udt_Source_Line :: struct {
    using #as base: Codeview_Type;
    kind = .UDT_SRC_LINE;
    type: Type_Id;
    src: Type_Id;
    line: u32;
}

Codeview_Function_Id :: struct {
    using #as base: Codeview_Type;
    kind = .FUNC_ID;
    scope: Type_Id;
    type: Type_Id;
    name: string;
}

Codeview_Alias :: struct {
    using #as base: Codeview_Type;
    kind = .ALIAS;
    type: Type_Id;
    name: string;
}

Codeview_Typeserver2 :: struct {
    using #as base: Codeview_Type;
    kind = .TYPESERVER2;
    sig70: Guid;
    age: u32;
    name: string;
}

Codeview_Modifier :: struct {
    using #as base: Codeview_Type;
    kind = .MODIFIER;
    type: Type_Id;
    modifier: Modifier_Type;

    Modifier_Type :: enum_flags u16 {
        CONST     :: 0x01;
        VOLATILE  :: 0x02;
        UNALINGED :: 0x04;
    }
}

Codeview_Member :: struct {
    access: u16;
    type: Type_Id;
    offset: u64;
    name: string;
}

Codeview_Enumerate :: struct {
    access: u16;
    value: u64;
    name: string;
}

Codeview_Nested_Type :: struct {
    type: Type_Id;
    name: string;
}

Codeview_Line_Info_Sequence :: struct {
    text_offset: u32;
    segment_index: u16;
    flags: Flags;
    length_in_bytes: u32;
    file_blocks: [..] Codeview_Lines_File_Block;

    Flags :: enum u16 {
        HAS_COLUMNS :: 0x0001;
    }
}

Codeview_Lines_File_Block :: struct {
    file_id: Codeview_File_Checksum_Id;
    lines: [] Codeview_Line_Info;
    columns: [] Codeview_Column_Type;
}

Codeview_File_Checksum_Id :: #type,isa u32;

Codeview_Line_Info :: struct {
    text_offset:             u32; // Relative to its sequence's text_offset
    line_and_delta_and_flag: u32;
}

Codeview_Column_Type :: u16;


Codeview_String_Table_Id :: #type,isa u32;

Codeview_File_Checksum :: struct {
    id: Codeview_File_Checksum_Id;
    filename_id: Codeview_String_Table_Id;
    checksum_type: Checksum_Type;
    checksum: [] u8;
    Checksum_Type :: enum u8 {
        NONE    :: 0;
        MD5     :: 1;
        SHA1    :: 2;
        SHA_256 :: 3;
    }
}

get_line_number :: (using info: Codeview_Line_Info) -> u32 {
    return line_and_delta_and_flag & 0x00FF_FFFF;
}

get_line_number_end_delta :: (using info: Codeview_Line_Info) -> u8 {
    return cast(u8) ((line_and_delta_and_flag >> 24) & 0x7F);
}

line_info_is_for_statement :: (using info: Codeview_Line_Info) -> bool {
    return (line_and_delta_and_flag & 0x80000000) != 0;
}

get_id_type :: (types: [] *Codeview_Type, ids: [] *Codeview_Type, type: Type_Id) -> *Codeview_Type, success: bool {
    id_types := ifx ids else types;
    type, success := get_type(id_types, type);
    return type, success;
}

get_type :: (types: [] *Codeview_Type, type: Type_Id) -> *Codeview_Type, success: bool {
    if (type >= 0x1000) {
        index := cast(s64) (type - 0x1000);
        if index >= types.count {
            log_error("Type is out of bounds: %/%", index, types.count-1);
            return null, false;
        }

        s := types[index];
        return s, true;
    } else {
        push_allocator(temp);
        builtin := New(Codeview_Builtin);
        builtin.id = type;
        return builtin, true;
    }
}

describe_builtin :: (type_id: Type_Id) -> string {
    assert(type_id < 0x1000);
    builtin_pointer_modifier := cast(Codeview_Pointer_Type) ((type_id >> 8) & 0xff);
    builtin_type := cast(Codeview_Builtin_Type) (type_id & 0xff);

    push_allocator(temp);
    builder: String_Builder;
    if builtin_pointer_modifier {
        print_to_builder(*builder, "% pointer to ", builtin_pointer_modifier);
    }

    print_to_builder(*builder, "% (builtin)", builtin_type);
    return builder_to_string(*builder);
}

describe_id_type :: (types: [] *Codeview_Type, ids: [] *Codeview_Type, type_id: Type_Id) -> string, success: bool {
    type, success := get_id_type(types, ids, type_id);
    if !success then return tprint("Invalid id type reference 0x%", h(cast(s64)type_id)), false;

    if type {
        description, success := describe_type(types, ids, type);
        return description, success;
    } else {
        return tprint("unparsed type %", type_id - 0x1000), true;
    }
}

describe_type :: (types: [] *Codeview_Type, ids: [] *Codeview_Type, type_id: Type_Id) -> string, success: bool {
    type, success := get_type(types, type_id);
    if !success then return tprint("Invalid type reference 0x%", h(cast(s64)type_id)), false;

    if type {
        description, success := describe_type(types, ids, type);
        return description, success;
    } else {
        return tprint("unparsed type %", type_id - 0x1000), true;
    }
}

describe_type :: (types: [] *Codeview_Type, ids: [] *Codeview_Type, type: *Codeview_Type) -> string, success: bool {
    if type == null {
        return "Found null type, so this record was probably not supported by the parser.", false;
    }

    if type.kind == {
        case .BUILTIN;
            builtin := cast(*Codeview_Builtin) type;
            return describe_builtin(builtin.id), true;

        case .STRUCTURE;
            s := cast(*Codeview_Struct) type;

            push_allocator(temp);
            builder: String_Builder;
            print_to_builder(*builder, "Struct \"%\"", s.name);
            if s.name != s.unique_name {
                print_to_builder(*builder, " (\"%\")", s.unique_name);
            }

            field_list, f_success := describe_type(types, ids, s.field_list);
            derived, d_success := describe_type(types, ids, s.derived);
            print_to_builder(*builder, ": % fields, properties: %, field list 0x%: (%), derived: %, vshape: %, size: %", s.num_fields, s.properties, h(cast(int) s.field_list), field_list, derived, s.vshape, s.size);
            return builder_to_string(*builder), (f_success && d_success);

        case .ENUM;
            s := cast(*Codeview_Enum) type;
            builder: String_Builder;
            print_to_builder(*builder, "Enum \"%\"", s.name);
            if s.name != s.unique_name {
                print_to_builder(*builder, " (\"%\")", s.unique_name);
            }
            type_string, t_success := describe_type(types, ids, s.type);
            field_list, fl_success := describe_type(types, ids, s.field_list);
            print_to_builder(*builder, ": % fields, properties: %, underlying type: %, field list: % %", s.num_fields, s.properties, type_string, s.field_list - 0x1000, field_list);
            return builder_to_string(*builder), (t_success && fl_success);

        case .ARRAY;
            s := cast(*Codeview_Array) type;
            element_type, e_success := describe_type(types, ids, s.element_type);
            index_type, i_success := describe_type(types, ids, s.index_type);
            result := tprint("Array \"%\" of size %: element type: %, index type: %", s.name, s.size, element_type, index_type);
            return result, (e_success && i_success);

        case .POINTER;
            pointer := cast(*Codeview_Pointer) type;
            type_string, t_success := describe_type(types, ids, pointer.type);
            result := tprint("Pointer to 0x% (%) (flags: 0x%)", h(cast(int)pointer.type), type_string, h(pointer.flags));
            return result, t_success;

        case .PROCEDURE;
            proc := cast(*Codeview_Procedure) type;
            arguments, a_success := describe_type(types, ids, proc.arguments);
            return_type, r_success := describe_type(types, ids, proc.return_type);
            result := tprint("Procedure: (% arguments: %) -> % (%, 0x%)", proc.num_arguments, arguments, return_type, proc.attributes, h(proc.calling_convention));
            return result, (a_success && r_success);

        case .FIELDLIST;
            list := cast(*Codeview_List) type;
            push_allocator(temp);
            builder: String_Builder;
            print_to_builder(*builder, "List");
            if list.members {
                print_to_builder(*builder, " (% members)", list.members.count);
            }
            if list.enumerates {
                print_to_builder(*builder, " (% enumerates)", list.enumerates.count);
            }
            if list.nested {
                print_to_builder(*builder, " (% nested types)", list.nested.count);
            }
            // @Temporary: Don't describe the previous type because LLVM sometimes creates incorrect previous references (which break the linker)
            // and we want to analyze those.
            if list.previous != 0 {
                print_to_builder(*builder, " previous: % (0x%)", list.previous - 0x1000, h(cast(u64) list.previous));
            }
            // if list.previous != 0 {
            //     print_to_builder(*builder, " previous: %", describe_type(types, ids, list.previous));
            // }
            return builder_to_string(*builder), true;

        case .ARGLIST; #through;
        case .SUBSTR_LIST; #through;
        case .BUILDINFO;
            list := cast(*Codeview_Arguments) type;
            push_allocator(temp);
            builder: String_Builder;
            if type.kind == {
                case .ARGLIST;     print_to_builder(*builder, "Arguments:");
                case .SUBSTR_LIST; print_to_builder(*builder, "Substrings:");
                case .BUILDINFO;   print_to_builder(*builder, "Build info:");
                case; assert(false, "Unexpected kind %", type.kind); return "", false;
            }

            subtype_source := types;
            if type.kind != .ARGLIST && ids {
                subtype_source = ids;
            }
            success := true;
            for list.arguments {
                subtype, t_success := get_type(subtype_source, it);
                success &&= t_success;
                type_string, t_success= := describe_type(types, ids, subtype);
                success &&= t_success;
                print_to_builder(*builder, " %: %", it_index, type_string);
            }
            return builder_to_string(*builder), success;

        case .STRING_ID;
            s := cast(*Codeview_String_Id) type;
            return tprint("String ID: 0x% %", h(cast(int) s.id), s.name), true;

        case .UDT_SRC_LINE;
            s := cast(*Codeview_Udt_Source_Line) type;
            source_type, s_success := get_id_type(types, ids, s.src);
            source: string = ---;
            if source_type && source_type.kind == .STRING_ID {
                source = (cast(*Codeview_String_Id) source_type).name;
            } else {
                s_success = false;
                source = tprint("Invalid source id: 0x%", h(cast(s64) s.src));
            }

            type_string, t_success := describe_type(types, ids, s.type);
            result := tprint("UDT Source Line %:%: %", source, s.line, type_string);
            return result, (s_success && t_success);

        case .FUNC_ID;
            s := cast(*Codeview_Function_Id) type;
            push_allocator(temp);

            builder: String_Builder;
            type_string, success := describe_type(types, ids, s.type);
            print_to_builder(*builder, "Function %: %", s.name, type_string);
            if s.scope != 0 {
                scope, s_success := describe_type(types, ids, s.scope);
                success &&= s_success;
                print_to_builder(*builder, "in scope %", scope);
            }

            return builder_to_string(*builder), success;

        case .ALIAS;
            s := cast(*Codeview_Alias) type;
            type_string, success := describe_type(types, ids, s.type);
            result := tprint("Alias %: %", s.name, type_string);
            return result, success;

        case .TYPESERVER2;
            s := cast(*Codeview_Typeserver2) type;
            push_allocator(temp);
            builder: String_Builder;
            print_to_builder(*builder, "Typeserver2: %-%-%-",
                h(s.sig70.data1, minimum_digits = 8),
                h(s.sig70.data2, minimum_digits = 4),
                h(s.sig70.data3, minimum_digits = 4),
            );
            for s.sig70.data4 {
                print_to_builder(*builder, "%", h(it, minimum_digits = 2));
            }
            print_to_builder(*builder, " % %" , s.age, s.name);
            return builder_to_string(*builder), true;

        case .MODIFIER;
            s := cast(*Codeview_Modifier) type;
            type_string, success := describe_type(types, ids, s.type);
            result := tprint("Modifier % for %", s.modifier, type_string);
            return result, success;

        case;
            assert(false, "Unhandled type kind %", type.kind);
            return "", false;
    }
}

Codeview_Inlinee_Line_Info :: struct {
    inlinee: Type_Id;
    file_id: Codeview_File_Checksum_Id;
    source_line: u32;
    extra_files: [] u32;
}


decode_inline_site_line_info :: (info: Codeview_Debug_Info, procedure: Codeview_Symbol_Procedure, site: Codeview_Symbol_Inline_Site) -> [] Codeview_Line_Info_Sequence, success: bool {
    Binary_Annotation_State :: struct {
        offset: u32;
        file_id: Codeview_File_Checksum_Id;
        line: s64;
        line_end_delta: u32;
        column: s64;
        column_end_delta: s64;
        is_statement: bool;

        sequence: Codeview_Line_Info_Sequence;
        block: Codeview_Lines_File_Block;
        lines: [..] Codeview_Line_Info;
        columns: [..] Codeview_Column_Type;

        line_info: [..] Codeview_Line_Info_Sequence;
    }

    reset :: (using s: *Binary_Annotation_State) {
        is_statement = true;
        line_end_delta = 1;
        column = 0;
        column_end_delta = 0;
        offset = 0;

    }

    finish_block :: (using s: *Binary_Annotation_State, end_offset: u32) {
        assert(lines.count > 0);
        block.lines = s.lines;
        block.columns = s.columns;

        block_length_in_bytes := end_offset - lines[0].text_offset;
        sequence.length_in_bytes += block_length_in_bytes;
        array_add(*sequence.file_blocks, s.block);
    }

    init_block :: (using s: *Binary_Annotation_State) {
        // @Cleanup: This is silly. What's the best way to hand off a dynamic array?
        s.lines.count = 0;
        s.lines.allocated = 0;
        s.lines.data = null;
        s.columns.count = 0;
        s.columns.allocated = 0;
        s.columns.data = null;

        block.file_id = s.file_id;
    }

    finish_sequence :: (using s: *Binary_Annotation_State, last_statement_length: u32) {
        if lines finish_block(s, offset + last_statement_length);

        array_add(*line_info, sequence);
    }

    emit_line :: (using s: *Binary_Annotation_State) {
        if file_id != block.file_id {
            if lines finish_block(s, offset);
            init_block(s);
        }

        l: Codeview_Line_Info;
        l.text_offset = offset;
        l.line_and_delta_and_flag = cast(u32)(line & 0x00FF_FFFF);
        if line_end_delta > 1 {
            l.line_and_delta_and_flag |= (line_end_delta & 0x7f) << 24;
        }
        if is_statement {
            l.line_and_delta_and_flag |= 0x8000_0000;
        }
        array_add(*lines, l);

        // @Incomplete: We're discarding column_end_delta here because the original CodeView line information structs
        // have no way of representing it.
        array_add(*columns, cast(u16) column);
        if column sequence.flags |= .HAS_COLUMNS;
    }

    init_sequence :: (using s: *Binary_Annotation_State, procedure: Codeview_Symbol_Procedure) {
        s.sequence.text_offset = procedure.offset; // @We don’t know for sure if this is right because the MSVC compiler puts every procedure in its own section when building a release build. So they all start at offset 0. -rluba, 2023-12-20
        s.sequence.segment_index = procedure.segment_index;
        s.sequence.length_in_bytes = 0;
        s.sequence.flags = 0;

        // @Cleanup: This is silly. What's the best way to hand off a dynamic array?
        s.sequence.file_blocks.count = 0;
        s.sequence.file_blocks.allocated = 0;
        s.sequence.file_blocks.data = null;

        init_block(s);
    }

    line_info: *Codeview_Inlinee_Line_Info;
    for * info.inlinee_line_info {
        if it.inlinee == site.inlinee {
            line_info = it;
            break;
        }
    }

    if !line_info {
        inlinee := describe_type(info.types, info.ids, site.inlinee);
        log_error("Couldn't find line info for inlinee 0x% (%) of inline site in procedure %", formatHex(site.inlinee), inlinee, procedure.name);
        return .[], false;
    }

    s: Binary_Annotation_State;
    reset(*s);
    s.file_id = line_info.file_id;
    s.line = line_info.source_line;
    init_sequence(*s, procedure);

    for site.binary_annotations {
        if it.opcode == {
            case .INVALID;
                // Padding
            case .CODE_OFFSET;
                s.offset = it.operand1.unsigned;
            case .CHANGE_CODE_OFFSET;
                s.offset += it.operand1.unsigned;
                emit_line(*s);
            case .CHANGE_CODE_LENGTH;
                finish_sequence(*s, it.operand1.unsigned);
                init_sequence(*s, procedure);
            case .CHANGE_FILE;
                s.file_id = cast(Codeview_File_Checksum_Id) it.operand1.unsigned;
            case .CHANGE_LINE_OFFSET;
                s.line += it.operand1.signed;
            case .CHANGE_LINE_END_DELTA;
                s.line_end_delta = it.operand1.unsigned;
            case .CHANGE_RANGE_KIND;
                s.is_statement = (it.operand1.unsigned == 1);
            case .CHANGE_COLUMN_START;
                s.column = it.operand1.unsigned;
            case .CHANGE_COLUMN_END_DELTA;
                s.column_end_delta = it.operand1.signed;
            case .CHANGE_CODE_OFFSET_AND_LINE_OFFSET;
                s.offset += it.operand1.unsigned;
                s.line += it.operand2.signed;
                emit_line(*s);
            case .CHANGE_CODE_LENGTH_AND_CODE_OFFSET;
                s.offset += it.operand2.unsigned;
                emit_line(*s);
                finish_sequence(*s, it.operand1.unsigned);
                init_sequence(*s, procedure);
            case .CHANGE_COLUMN_END;
                s.column_end_delta = it.operand1.signed - s.column; // @Stability: this is not right if someone encodes the end column before the start column. But who would do that, right???
        }
    }
    if s.lines {
        log_error("Inline site in % ended with unfinished line info sequence.", procedure.name);
        return .[], false;
    }

    // Sequences normally start at the procedure start
    // But inlinee sequences start at the offset where the inlining started
    // So we neeed to adjust the sequence starts now that we know the inlining happened.
    // (And sinc all line offsets are relative to the sequence start, we need to update them too when we change the sequence start.)
    //  -rluba, 2023-12-20
    for *sequence: s.line_info {
        assert(sequence.file_blocks.count > 0);
        assert(sequence.file_blocks[0].lines.count > 0);
        base_offset := sequence.file_blocks[0].lines[0].text_offset;
        sequence.text_offset += base_offset;
        for *block: sequence.file_blocks {
            for *line: block.lines {
                line.text_offset -= base_offset;
            }
        }
    }

    return s.line_info, true;
}

Guid :: struct {
    data1: u32;
    data2: u16;
    data3: u16;
    data4: [8] u8;
}

// Splits a Codeview_Line_Info_Sequence for a procedure into multiple sequences that also contain the line info
// for all the procedure's inline sites.
overlay_inlinesites :: (sequences: [] Codeview_Line_Info_Sequence, procedure: Codeview_Symbol_Procedure, inline_sites: [] *Codeview_Symbol_Inline_Site, debug_info: Codeview_Debug_Info) -> bool, [] Codeview_Line_Info_Sequence {
    new_sequences := sequences;
    for site: inline_sites {
        success, new_sequences= := overlay_inlinesite(new_sequences, procedure, site, debug_info);
        if !success return false, .[];
    }

    return true, new_sequences;
}

overlay_inlinesite :: (sequences: [] Codeview_Line_Info_Sequence, procedure: Codeview_Symbol_Procedure, inline_site: *Codeview_Symbol_Inline_Site, debug_info: Codeview_Debug_Info) -> bool, new_sequences: [] Codeview_Line_Info_Sequence {
    inlinee_sequences, success := decode_inline_site_line_info(debug_info, procedure, inline_site);
    if !success {
        log_error("Could not decode inline site %", inline_site.*);
        return false, .[];
    }

    result_sequences := sequences;
    for inner: inlinee_sequences {
        found := false;
        for sequence, sequence_index: result_sequences {
            if sequence.text_offset <= inner.text_offset && sequence.text_offset + sequence.length_in_bytes >= inner.text_offset + inner.length_in_bytes {
                assert(sequence.segment_index == inner.segment_index);
                // log("Sequence\n\t%\nfrom inline site\n\t%\nshould split sequence\n\t%", inner, inline_site.*, sequence);
                found = true;

                replacements: [3] Codeview_Line_Info_Sequence;
                index := 0;
                if sequence.text_offset < inner.text_offset {
                    start := sequence;
                    start.length_in_bytes = inner.text_offset - sequence.text_offset;
                    copy_and_truncate_blocks(*start, sequence.text_offset);
                    replacements[index] = start;
                    index += 1;
                }
                replacements[index] = inner;
                index += 1;
                if sequence.text_offset + sequence.length_in_bytes > inner.text_offset + inner.length_in_bytes {
                    end := sequence;
                    end.text_offset = inner.text_offset + inner.length_in_bytes;
                    end.length_in_bytes = sequence.text_offset + sequence.length_in_bytes - end.text_offset;
                    copy_and_truncate_blocks(*end, sequence.text_offset);
                    replacements[index] = end;
                    index += 1;
                }

                replacements_view: [] Codeview_Line_Info_Sequence = replacements;
                replacements_view.count = index;

                // @Cleanup: Slightly imprecise: In reality, the children should only overlap our own sequence,
                // i.e. "inner", but that just makes the bookkeeping on all the sequence arrays more cumbersome,
                // so I'm ignoring this here and feed in all chunks.
                for inline_site.children {
                    success, replacements_view = overlay_inlinesite(replacements_view, procedure, it, debug_info);
                    if !success return false, .[];
                }

                new_sequences := NewArray(result_sequences.count + replacements_view.count - 1, Codeview_Line_Info_Sequence);
                for i: 0..sequence_index-1 {
                    new_sequences[i] = result_sequences[i];
                }
                for replacements_view {
                    new_sequences[sequence_index + it_index] = it;
                }
                for i: sequence_index+1..result_sequences.count-1 {
                    new_sequences[replacements_view.count + i - 1] = result_sequences[i];
                }
                result_sequences = new_sequences;

                break;
            }
        }

        if !found {
            log_error("Sequence % of inline site % does not overlap any sequence in %", inner, inline_site.*, result_sequences);
            return false, .[];
        }
    }

    return true, result_sequences;
}

copy_and_truncate_blocks :: (sequence: *Codeview_Line_Info_Sequence, old_sequence_text_offset: u32) {
    assert(sequence.text_offset >= old_sequence_text_offset);
    text_offset_delta := sequence.text_offset - old_sequence_text_offset;
    result: [..] Codeview_Lines_File_Block;
    array_copy(*result, sequence.file_blocks);
    sequence.file_blocks = result;

    start := sequence.text_offset;
    end := sequence.text_offset + sequence.length_in_bytes;
    for *block: sequence.file_blocks {
        block_start := old_sequence_text_offset + block.lines[0].text_offset;
        if block_start > end {
            // log("Removing block\n\t%\nbecause it's past the new end of\n\t%", block.*, sequence.*);
            remove block;
            continue;
        }
        block_end := old_sequence_text_offset + block.lines[block.lines.count - 1].text_offset;
        if block_end < start {
            // log("Removing block\n\t%\nbecause it's before the new start of\n\t%", block.*, sequence.*);
            remove block;
            continue;
        }

        // @ToDo: This is not fully correct. If the new sequence starts at offset 10 and we have line info for offset 0 and 20,
        // we should not throw away the line info for offset 0 completely. Instead we should adjust it to start at offset 10.
        // -rluba, 2023-12-27
        line_start_index := 0;
        while line_start_index < block.lines.count && old_sequence_text_offset + block.lines[line_start_index].text_offset < start {
            line_start_index += 1;
        }
        line_past_end_index := line_start_index + 1;
        while line_past_end_index < block.lines.count && old_sequence_text_offset + block.lines[line_past_end_index].text_offset < end {
            line_past_end_index += 1;
        }

        // log("Old block\n\t%", block.*);
        block.lines   = array_view(block.lines,   line_start_index, line_past_end_index - line_start_index);
        block.columns = array_view(block.columns, line_start_index, line_past_end_index - line_start_index);
        for *block.lines {
            assert(it.text_offset >= text_offset_delta);
            it.text_offset -= text_offset_delta;
        }
        // log("New block\n\t%", block.*);
    }
}



#scope_file

parse_symbols_section :: (state: *Codeview_Symbol_Parser_State, size: int) {
    parse_symbol :: (state: *Codeview_Symbol_Parser_State) {
        check :: (condition: bool, message := "", args: .. Any) #expand {
            if !condition {
                `state.success = false;
                if message then log_error(message, ..args);
                `return;
            }
        } @PrintLike

        symbols := *state.info.symbols;

        symbol_size  := parse_primitive(state, u16);
        check(symbol_size > 0, "Symbol has no size!");
        symbol_start := state.offset;
        check(symbol_start + symbol_size <= state.data.count, "Symbol at 0x% of size 0x% goes out of bounds", h(symbol_size), h(symbol_start));
        symbol_type  := cast(Codeview_Symbol_Type) parse_primitive(state, u16);
        // log("Symbol type % of size 0x% starts at 0x%", symbol_type, h(symbol_size), h(symbol_start));

        if symbol_type == {
            case .COMPILE;
                s := New(Codeview_Symbol_Compile);
                s.target_cpu       = parse_primitive(state, u8);
                s.language         = parse_primitive(state, u8);
                s.flags            = parse_primitive(state, u16);
                s.compiler_version = parse_string_length_prefixed(state);
                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .COMPILE3;
                s := New(Codeview_Symbol_Compile3);
                s.language         = parse_primitive(state, u8);
                s.flags1         = parse_primitive(state, u8);
                s.flags2         = parse_primitive(state, u8);
                s.reserved         = parse_primitive(state, u8);
                s.target_cpu       = parse_primitive(state, u16);

                s.fe_version.major = parse_primitive(state, u16);
                s.fe_version.minor = parse_primitive(state, u16);
                s.fe_version.build = parse_primitive(state, u16);
                s.fe_version.qfe   = parse_primitive(state, u16);

                s.be_version.major = parse_primitive(state, u16);
                s.be_version.minor = parse_primitive(state, u16);
                s.be_version.build = parse_primitive(state, u16);
                s.be_version.qfe   = parse_primitive(state, u16);

                s.compiler_version = parse_string_zeroterminated(state);

                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .LPROC32; #through;
            case .GPROC32; #through;
            case .LPROC32_ID; #through;
            case .GPROC32_ID;
                s := New(Codeview_Symbol_Procedure);
                s.symbol_type        = symbol_type;
                s.parent             = parse_primitive(state, u32);
                s.end                = parse_primitive(state, u32);
                s.next               = parse_primitive(state, u32);
                s.length             = parse_primitive(state, u32);
                s.debug_start_offset = parse_primitive(state, u32);
                s.debug_end_offset   = parse_primitive(state, u32);
                s.type               = parse_primitive(state, Type_Id);
                s.offset             = parse_primitive(state, u32);
                s.segment_index      = parse_primitive(state, u16);
                s.flags              = parse_primitive(state, Codeview_Symbol_Procedure.Flags);
                s.name               = parse_string_zeroterminated(state);
                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);
                state.current_procedure = s;

            case .REGREL32;
                s := New(Codeview_Symbol_Regrel);
                s.off    = parse_primitive(state, u32);
                s.typind = parse_primitive(state, Type_Id);
                s.reg    = parse_primitive(state, u16);
                s.name   = parse_string_zeroterminated(state);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .LDATA32; #through;
            case .GDATA32; #through;
            case .LMANDATA; #through;
            case .GMANDATA;
                s := New(Codeview_Symbol_Data);
                s.symbol_type        = symbol_type;
                s.type               = parse_primitive(state, Type_Id);
                s.offset             = parse_primitive(state, u32);
                s.segment_index      = parse_primitive(state, u16);
                s.name               = parse_string_zeroterminated(state);
                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .FRAMEPROC;
                s := cast(*Codeview_Symbol_Frame_Proc) (state.data.data + symbol_start);
                check(symbol_size >= size_of(Codeview_Symbol_Frame_Proc) /*padding*/, "Unexpected size: 0x%", h(symbol_size));
                assert(s.symbol_type == .FRAMEPROC);
                state.offset = symbol_start + size_of(Codeview_Symbol_Frame_Proc);
                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .LOCAL;
                s := New(Codeview_Symbol_Local);
                s.type = parse_primitive(state, Type_Id);
                s.flags = parse_primitive(state, Codeview_Symbol_Local.Flags);
                s.name = parse_string_zeroterminated(state);
                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .DEFRANGE_REGISTER;
                s := New(Codeview_Symbol_Defrange_Register);
                s.register  = parse_primitive(state, u16);
                s.attribute = parse_primitive(state, Range_Attribute_Flags);
                s.range     = parse_range(state);

                header_size   := state.offset - symbol_start;
                s.gaps = parse_gaps(state, symbol_size - header_size);
                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .DEFRANGE_FRAMEPOINTER_REL;
                s := New(Codeview_Symbol_Defrange_Framepointer_Rel);
                s.frame_pointer_offset = parse_primitive(state, s32);
                s.range                = parse_range(state);

                header_size   := state.offset - symbol_start;
                s.gaps = parse_gaps(state, symbol_size - header_size);
                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .DEFRANGE_FRAMEPOINTER_REL_FULL_SCOPE;
                s := New(Codeview_Symbol_Defrange_Framepointer_Rel_Full_Scope);
                s.frame_pointer_offset = parse_primitive(state, s32);

                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .DEFRANGE_REGISTER_REL;
                s := New(Codeview_Symbol_Defrange_Register_Rel);
                s.base_register                        = parse_primitive(state, u16);
                s.spilled_udt_member_and_offset_parent = parse_primitive(state, u16);
                s.base_pointer_offset                  = parse_primitive(state, u32);
                s.range                                = parse_range(state);

                header_size   := state.offset - symbol_start;
                s.gaps = parse_gaps(state, symbol_size - header_size);
                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .OBJNAME;
                s := New(Codeview_Symbol_Objname);
                s.signature = parse_primitive(state, u32);
                s.name      = parse_string_zeroterminated(state);
                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .BLOCK32;
                s := New(Codeview_Symbol_Block);
                s.parent             = parse_primitive(state, u32);
                s.end                = parse_primitive(state, u32);
                s.length             = parse_primitive(state, u32);
                s.offset             = parse_primitive(state, u32);
                s.segment_index      = parse_primitive(state, u16);
                s.name               = parse_string_zeroterminated(state);
                maybe_skip_padding(state, symbol_start + symbol_size);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .CONSTANT;
                s := New(Codeview_Symbol_Constant);
                s.type  = parse_primitive(state, Type_Id);
                s.value = parse_numeric_leaf_value(state);
                s.name  = parse_string_zeroterminated(state);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .UNAMESPACE;
                s := New(Codeview_Symbol_Unamespace);
                s.name = parse_string_zeroterminated(state);
                if state.verbose log("%: %", symbol_type, s.*);
                array_add(symbols, s);

            case .INLINESITE;
                s := New(Codeview_Symbol_Inline_Site);
                s.parent             = parse_primitive(state, u32);
                s.end                = parse_primitive(state, u32);
                s.inlinee            = parse_primitive(state, Item_Id);

                if state.verbose {
                    log("Opcodes:");
                    dump(state, state.offset, symbol_start + symbol_size - state.offset);
                }
                while state.offset < symbol_start + symbol_size {
                    op: Codeview_Binary_Annotation;
                    op.opcode = parse_primitive(state, Codeview_Binary_Annotation_Opcode);
                    // log("Inlinesite opcode: %", op.opcode);
                    if op.opcode == {
                        case .INVALID;
                            if state.verbose log("% (usually padding)", op.opcode);
                            continue;
                        case .CHANGE_LINE_OFFSET; #through;
                        case .CHANGE_COLUMN_END_DELTA;
                            op.operand1.signed = decode_compressed_s32(parse_compressed_integer(state));
                            if state.verbose log("%: %", op.opcode, op.operand1.signed);
                        case .CHANGE_CODE_OFFSET_AND_LINE_OFFSET;
                            combined := parse_compressed_integer(state);
                            op.operand1.unsigned = combined & 0x0F;
                            op.operand2.signed = decode_compressed_s32(combined >> 4);
                            if state.verbose log("%: % (0x%) %", op.opcode, op.operand1.unsigned, h(op.operand1.unsigned), op.operand2.signed);
                        case .CHANGE_CODE_LENGTH_AND_CODE_OFFSET;
                            op.operand1.unsigned = parse_compressed_integer(state);
                            op.operand2.unsigned = parse_compressed_integer(state);
                            if state.verbose log("%: % (0x%) % (0x%)", op.opcode, op.operand1.unsigned, h(op.operand1.unsigned), op.operand2.unsigned, h(op.operand2.unsigned));
                        case;
                            op.operand1.unsigned = parse_compressed_integer(state);
                            if state.verbose log("%: % (0x%)", op.opcode, op.operand1.unsigned, h(op.operand1.unsigned));
                    }
                    array_add(*s.binary_annotations, op);
                }

                if state.verbose log("%: %", symbol_type, s.*);

                check(state.success);
                check(state.current_procedure != null, "Found a % while not inside a procedure", symbol_type);

                array_add(symbols, s);
                if state.open_inlinesites.count {
                    array_add(*state.open_inlinesites[state.open_inlinesites.count - 1].children, s);
                } else {
                    array_add(*state.current_procedure.inlinesites, s);
                }
                array_add(*state.open_inlinesites, s);

            case .PROC_ID_END;
                check(symbol_size == 2, "Unexpected size for %: 0x%", symbol_type, h(symbol_size));
                if state.verbose log("%", symbol_type);
                check(state.current_procedure != null, "Found a % while not inside a procedure", symbol_type);
                state.current_procedure = null;

            case .INLINESITE_END;
                check(symbol_size == 2, "Unexpected size for %: 0x%", symbol_type, h(symbol_size));
                if state.verbose log("%", symbol_type);
                check(state.current_procedure != null, "Found a % while not inside a procedure", symbol_type);
                check(state.open_inlinesites.count > 0, "Found a % while not inside an inline site", symbol_type);
                pop(*state.open_inlinesites);

            case .END;
                check(symbol_size == 2, "Unexpected size for %: 0x%", symbol_type, h(symbol_size));
                if state.verbose log("%", symbol_type);

            case .BUILDINFO;
                s := cast(*Codeview_Symbol_Buildinfo) (state.data.data + symbol_start);
                check(symbol_size >= size_of(Codeview_Symbol_Buildinfo) /*padding*/, "Unexpected size: 0x%", h(symbol_size));
                assert(s.symbol_type == .BUILDINFO);
                state.offset = symbol_start + size_of(Codeview_Symbol_Buildinfo);
                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);

                check(state.success);
                array_add(symbols, s);

            case .UDT; // @ToDo: The results I got for this seemed incorrect. Needs checking. -luba, 2022-12-03
                s := New(Codeview_Symbol_Udt);
                s.type = parse_primitive(state, Type_Id);
                s.name = parse_string_zeroterminated(state);
                maybe_skip_padding(state, symbol_start + symbol_size);

                if state.verbose log("%: %", symbol_type, s.*);

                check(state.success);
                array_add(symbols, s);

            case .CALLEES; #through;
            case .CALLERS; #through;
            case .INLINEES;
                s := New(Codeview_Symbol_Function_List);
                s.symbol_type = symbol_type;
                count := parse_primitive(state, u32);
                s.functions = NewArray(count, Codeview_Symbol_Function_List.Function);
                for * s.functions {
                    it.func = parse_primitive(state, Type_Id);
                }
                for * s.functions {
                    if state.offset < symbol_start + symbol_size {
                        it.invocation_count = parse_primitive(state, u32);
                    } else {
                        // From the official documentation: " Counts > reclen are assumed to be zero"
                        it.invocation_count = 0;
                    }
                }

                if state.verbose log("%: %", symbol_type, s.*);

                check(state.success);
                array_add(symbols, s);

            case;
                log_error("Skipping unsupported symbol type % (0x%) of size 0x% starting at 0x%", symbol_type, h(cast(int)symbol_type), h(symbol_size), h(symbol_start));
                state.offset = symbol_start + symbol_size;
        }

        expected_offset := symbol_start + symbol_size;
        check(state.offset == expected_offset, "Unexpected offset after parsing symbol: 0x% vs 0x%", h(state.offset), h(expected_offset));
    }

    subsection_start := state.offset;
    while state.success && state.offset < subsection_start + size {
        parse_symbol(state);
    }
}

parse_range :: (state: *Codeview_Symbol_Parser_State) -> Codeview_Address_Range {
    #assert(size_of(Codeview_Address_Range) == 8);
    if (state.offset + size_of(Codeview_Address_Range) > state.data.count) {
        log_error("Address range goes out of bounds");
        state.success = false;
        return .{};
    }

    range := cast(*Codeview_Address_Range) (state.data.data + state.offset);
    state.offset += size_of(Codeview_Address_Range);
    return range.*;
}

parse_gaps :: (state: *Codeview_Symbol_Parser_State, gap_data_size: int) -> [] Codeview_Address_Gap {
    if gap_data_size % size_of(Codeview_Address_Gap) != 0 {
        log_error("Unexpected gap size: 0x%", h(gap_data_size));
        state.success = false;
        return .[];
    }

    gaps: [] Codeview_Address_Gap;
    gaps.data = cast(*Codeview_Address_Gap) (state.data.data + state.offset);
    gaps.count = gap_data_size / size_of(Codeview_Address_Gap);
    state.offset += gap_data_size;
    return gaps;
}

parse_file_checksums_section :: (state: *Codeview_Symbol_Parser_State, size: int) {
    parse_entry :: (state: *Codeview_Symbol_Parser_State, subsection_start: int, size: int) -> success: bool, Codeview_File_Checksum {
        check :: (condition: bool, message := "", args: .. Any) #expand {
            if !condition {
                `state.success = false;
                if message then log_error(message, ..args);
                `return false, .{};
            }
        } @PrintLike

        entry: Codeview_File_Checksum;
        entry.id = cast(Codeview_File_Checksum_Id) (state.offset - subsection_start);
        entry.filename_id = parse_primitive(state, Codeview_String_Table_Id);
        checksum_length := parse_primitive(state, u8);
        entry.checksum_type = parse_primitive(state, Codeview_File_Checksum.Checksum_Type);
        check(state.offset + checksum_length <= subsection_start + size);
        entry.checksum.count = checksum_length;
        entry.checksum.data = state.data.data + state.offset;
        state.offset += checksum_length;
        skip_padding(state, 0, 4);

        if state.verbose log("File checksum 0x%: 0x% % %", h(entry.id), h(cast(int)entry.filename_id), entry.checksum_type, entry.checksum);
        return true, entry;
    }

    subsection_start := state.offset;

    while state.success && state.offset < subsection_start + size {
        success, entry := parse_entry(state, subsection_start, size);
        if success array_add(*state.info.file_checksums, entry);
    }
}

parse_lines_section :: (state: *Codeview_Symbol_Parser_State, size: int) {
    parse_file_block :: (state: *Codeview_Symbol_Parser_State, subsection_start: int, size: int, has_columns: bool) -> Codeview_Lines_File_Block {
        check :: (condition: bool, message := "", args: .. Any) #expand {
            if !condition {
                `state.success = false;
                if message then log_error(message, ..args);
                `return .{};
            }
        } @PrintLike

        block_start := state.offset;
        block: Codeview_Lines_File_Block;
        block.file_id = parse_primitive(state, Codeview_File_Checksum_Id);
        line_count := parse_primitive(state, u32);
        block_length_in_bytes := parse_primitive(state, u32);

        lines_length := line_count * size_of(Codeview_Line_Info);
        columns_length := 0;
        if has_columns columns_length = line_count * size_of(Codeview_Column_Type);

        expected_length := (state.offset - block_start) + lines_length + columns_length;
        check(block_length_in_bytes == expected_length, "Unexpected file block length: 0x% vs 0x% for % lines", h(block_length_in_bytes), h(expected_length), line_count);
        check(block_start + block_length_in_bytes <= subsection_start + size, "Line block is out of bounds");

        block.lines.count = line_count;
        block.lines.data = cast (*Codeview_Line_Info) (state.data.data + state.offset);
        state.offset += lines_length;
        if has_columns {
            block.columns.count = line_count;
            block.columns.data = cast (*Codeview_Column_Type) (state.data.data + state.offset);
            state.offset += columns_length;
        }

        return block;
    }

    subsection_start := state.offset;

    sequence: Codeview_Line_Info_Sequence;
    sequence.text_offset     = parse_primitive(state, u32);
    sequence.segment_index   = parse_primitive(state, u16);
    sequence.flags           = parse_primitive(state, Codeview_Line_Info_Sequence.Flags);
    sequence.length_in_bytes = parse_primitive(state, u32);

    has_columns := (sequence.flags & .HAS_COLUMNS) != 0;

    blocks_start := state.offset;
    while state.success && state.offset < subsection_start + size {
        block := parse_file_block(state, subsection_start, size, has_columns);
        if !state.success return;
        array_add(*sequence.file_blocks, block);
    }
    array_add(*state.info.line_info, sequence);
    // @ToDo: Check that the blocks are contiguous and end at the right end!
}

parse_inlinlee_lines_section :: (state: *Codeview_Symbol_Parser_State, size: int) {
    parse_inlinee :: (state: *Codeview_Symbol_Parser_State, with_extra_files: bool) {
        info: Codeview_Inlinee_Line_Info;
        info.inlinee = parse_primitive(state, Type_Id);
        info.file_id = parse_primitive(state, Codeview_File_Checksum_Id);
        info.source_line = parse_primitive(state, u32);
        if with_extra_files {
            count :=  parse_primitive(state, u32);
            data := cast(*u32) (state.data.data + state.offset);
            state.offset += size_of(u32) * count;
            info.extra_files.count = count;
            info.extra_files.data = data;
        }

        if state.success {
            array_add(*state.info.inlinee_line_info, info);
            if state.verbose log("Inlinee line: 0x% 0x% % %", h(cast(int)info.inlinee), h(info.file_id), info.source_line, info.extra_files);
        }
    }

    subsection_start := state.offset;

    variant := parse_primitive(state, Codeview_Inlinee_Source_Variant);
    if state.verbose log("Inlinee lines variant: %", variant);

    while state.success && state.offset < subsection_start + size {
        parse_inlinee(state, with_extra_files = (variant == .EX));
    }

    if state.success && state.offset > subsection_start + size {
        log_error("Inlinee went out of bounds: 0x% vs 0x%", h(state.offset), h(subsection_start + size));
        state.success = false;
    }
}

parse_primitive :: (using state: *Codeview_Parser_State, $T: Type) -> value: T {
    if !success then return 0;

    end_offset := offset + size_of(T);
    if end_offset > data.count  {
        log_error("Unexpected end of data while parsing %", T);
        success = false;
        return 0;
    }
    value := (.*)(cast(*T) (data.data + offset));
    // log("value at % (0x%) of size %: % (0x%)", offset, h(offset), size_of(T), value, h(value));
    offset = end_offset;
    return value;
}

parse_numeric_leaf_value :: (using state: *Codeview_Parser_State) -> Numeric_Leaf_Value {
    if !success return .{type = void};

    start_offset := offset;
    leaf_value := parse_primitive(state, u16);
    result: Numeric_Leaf_Value;
    if leaf_value < 0x8000 {
        result.type = u16;
        result.value.unsigned = leaf_value;
        return result;
    }

    if cast(Codeview_Leaf_Type) leaf_value == {
        case .CHAR;      result.type = u8;      result.value.unsigned = parse_primitive(state, u8);
        case .SHORT;     result.type = s16;     result.value.signed   = parse_primitive(state, s16);
        case .USHORT;    result.type = u16;     result.value.unsigned = parse_primitive(state, u16);
        case .LONG;      result.type = s32;     result.value.signed   = parse_primitive(state, s32);
        case .ULONG;     result.type = u32;     result.value.unsigned = parse_primitive(state, u32);
        case .QUADWORD;  result.type = s64;     result.value.signed   = parse_primitive(state, s64);
        case .UQUADWORD; result.type = u64;     result.value.unsigned = parse_primitive(state, u64);
        case .REAL32;    result.type = float;   result.value.f32      = parse_primitive(state, float);
        case .REAL64;    result.type = float64; result.value.f64      = parse_primitive(state, float64);
        case;
            log_error("Unexpected leaf type while parsing numeric leaf at %: %", start_offset, leaf_value);
            success = false;
            return .{type = void};
    }

    return result;
}

parse_variable_integer :: (using state: *Codeview_Parser_State, $Return_Type := s64) -> value: Return_Type {
    if !success then return 0;

    start_offset := offset;
    leaf_value := parse_primitive(state, u16);
    if leaf_value < 0x8000 {
        return leaf_value;
    }

    if cast(Codeview_Leaf_Type) leaf_value == {
        case .CHAR;      return parse_primitive(state, u8);
        case .SHORT;     return xx parse_primitive(state, s16);
        case .USHORT;    return xx parse_primitive(state, u16);
        case .LONG;      return xx parse_primitive(state, s32);
        case .ULONG;     return xx parse_primitive(state, u32);
        case .QUADWORD;  return xx parse_primitive(state, s64);
        case .UQUADWORD; return xx parse_primitive(state, u64);
        case;
            log_error("Unexpected leaf type while parsing integer at %: %", start_offset, leaf_value);
            success = false;
            return 0;
    }
}

// Result points into state.data
parse_string_zeroterminated :: (using state: *Codeview_Parser_State) -> value: string {
    if !success then return "";

    start_offset := offset;
    result: string;
    result.data = data.data + offset;
    end := data.data + data.count;
    p := result.data;
    while true {
        if p == end {
            log_error("Unexpected end while parsing string at %", start_offset);
            success = false;
            return "";
        }
        if !p.* then break;
        p += 1;
    }
    result.count = p - result.data;
    offset += result.count + 1;
    return result;
}

// Result points into state.data
parse_string_length_prefixed :: (using state: *Codeview_Parser_State, $T: Type = u8) -> value: string {
    if !success then return "";

    start_offset := offset;
    result: string;
    result.count = parse_primitive(state, T);
    result.data = data.data + offset;

    offset += result.count;
    if offset > state.data.count {
        log_error("Length prefixed string at 0x% of size 0x% goes out of bounds", h(start_offset), h(result.count));
        success = false;
        return "";
    }


    return result;
}

parse_guid :: (using state: *Codeview_Parser_State) -> Guid {
    result: Guid;
    if !success then return result;

    end_offset := offset + size_of(Guid);
    if end_offset > data.count  {
        log_error("Unexpected end of data while parsing Guid");
        success = false;
        return result;
    }

    memcpy(*result, data.data + offset, size_of(Guid));
    offset = end_offset;
    return result;
}

skip_leaf_padding :: (using state: *Codeview_Parser_State, start: s64, alignment: int) {
    if !success then return;

    mask := (alignment - 1);
    assert(alignment & mask == 0);
    pos := offset - start;
    remainder := pos & mask;
    if remainder {
        pad := alignment - remainder;
        for i: 0..pad-1 {
            value := data[offset + i];
            expected := cast(u8) Codeview_Leaf_Type.PAD0 + pad - i;
            if value != expected {
                log_error("Unexpected leaf padding value at 0x%: 0x% should be 0x%. Padding of size % started at 0x%:", h(offset + i), h(value), h(expected), pad, h(offset));
                for 0..pad-1 print("% ", h(data[offset + it]), to_standard_error = true);
                print("\n", to_standard_error = true);
                success = false;
            }
        }
        offset += pad;
    }
}

maybe_skip_padding :: (using state: *Codeview_Parser_State, end: s64, start: s64 = 0, alignment: int = 4) {
    if state.offset != end {
        skip_padding(state, start, alignment);
    }
}

skip_padding :: (using state: *Codeview_Parser_State, start: s64 = 0, alignment: int = 4) {
    if !success then return;

    mask := (alignment - 1);
    assert(alignment & mask == 0);
    pos := offset - start;
    remainder := pos & mask;
    if remainder {
        pad := alignment - remainder;
        for i: 0..pad-1 {
            value := data[offset + i];
            if value != 0  {
                log_error("Unexpected padding value at 0x%: 0x% should be 0x0. Padding of size % started at 0x%:", h(offset + i), h(value), pad, h(offset));
                for 0..pad-1 print("% ", h(data[offset + it]), to_standard_error = true);
                print("\n", to_standard_error = true);
                success = false;
            }
        }
        offset += pad;
    }
}

dump :: (using state: Codeview_Parser_State, start: s64, size: s64) {
    for i: 0..size-1 {
        print("% ", formatByte(data[start + i]), to_standard_error = true);
    }
    print("\n", to_standard_error = true);
}

parse_compressed_integer :: (using state: *Codeview_Parser_State) -> u32 {
    u1: u32 = parse_primitive(state, u8);
    if (u1 & 0x80) == 0x00 {
        return u1;
    }

    u2: u32 = parse_primitive(state, u8);
    if (u1 & 0xC0) == 0x80 {
        return (cast(u32)(u1 & 0x3F) << 8) | u2;
    }
    u3: u32 = parse_primitive(state, u8);
    u4: u32 = parse_primitive(state, u8);
    if (u1 & 0xE0) == 0xC0 {
        return ((u1 & 0x1F) << 24) | (u2 << 16) | (u3 << 8) | u4;
    }

    state.success = false;
    return 0;
}

decode_compressed_s32 :: (value: u32) -> s32 {
    if value & 1 return -(cast(s32) (value >> 1));
    else         return   cast(s32) (value >> 1);
}


CODEVIEW_VERSION: u32: 4;

formatByte :: #bake_arguments formatInt(base = 16, minimum_digits = 2);
h :: formatHex;

#load "codeview_enums.jai";
#import "String";

