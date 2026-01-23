Text_Based_Dylib :: struct {
    tbd_version: int;
    targets: [] string;
    install_name: string;
    exports: [] Target_Exports;
}

Target_Exports :: struct {
    targets:    [] string;
    symbols:    [] string;
    re_exports: [] string;
}

parse_tbd_file :: (path: string) -> success: bool, [] Text_Based_Dylib {
    content, success := read_entire_file(path);
    if !success {
        log_error("Could not read file \"%\"", path);
        return false, .[];
    }

    success=, tbds := parse_tbd(content);
    return success, tbds;
}

is_tbd :: (file_content: string) -> bool {
    return begins_with(file_content, TBD_START); // This also covers TBD_V3_START.
}

parse_tbd :: (file_content: string, path := "(unspecified file)") -> success: bool, [] Text_Based_Dylib {
    lexer: Lexer;
    set_input_from_string(*lexer, file_content);

    tbds: [..] Text_Based_Dylib;
    if begins_with(file_content, TBD_V3_START) {
        complete := false;
        while !complete {
            success, tbdv3, complete=, lexer= := parse_yaml(lexer, Text_Based_Dylib_V3);
            if !success return false, tbds;

            targets: [..] string;
            for tbdv3.archs {
                array_add(*targets, tprint("%-%", it, tbdv3.platform));
            }
            exports: [..] Target_Exports;
            for exportv3: tbdv3.exports {
                targets: [..] string;
                for exportv3.archs {
                    array_add(*targets, tprint("%-%", it, tbdv3.platform));
                }

                export: Target_Exports;
                export.targets    = targets;
                export.symbols    = exportv3.symbols;
                export.re_exports = exportv3.re_exports;
                array_add(*exports, export);
            }

            tbd: Text_Based_Dylib;
            tbd.tbd_version = 3;
            tbd.install_name = tbdv3.install_name;
            tbd.targets = targets;
            tbd.exports = exports;
            array_add(*tbds, tbd);
        }
    } else {
        complete := false;
        while !complete {
            success, tbd, complete=, lexer= := parse_yaml(lexer, Text_Based_Dylib);
            if !success return false, tbds;
            if tbd.tbd_version != 4 {
                log_error("Found unsupported TBD version %. Only versions 3 and 4 are currently supported.", tbd.tbd_version);
                continue;
            }
            array_add(*tbds, tbd);
        }
    }

    return true, tbds;
}


#scope_module

// In theory, the whitespace after --- could be arbitrarily large, so this check is not perfect. But I don’t want to start the whole YAML parser just to see if a file is a TBD file. -rluba, 2024-02-23
TBD_START    :: "--- !tapi-tbd";
TBD_V3_START :: "--- !tapi-tbd-v3";

WHITESPACE_CHARS :: " \t\n\r"; // @Incomplete: Update this according to the YAML spec.

#import "Basic";
#import "File";
#import "String";

#scope_file

Text_Based_Dylib_V3 :: struct {
    archs: [] string;
    platform: string;
    install_name: string;
    exports: [] Target_Exports_V3;
}

Target_Exports_V3 :: struct {
    archs: [] string;
    symbols: [] string;
    re_exports: [] string;
}


#load "lexer.jai";

// This is not a full YAML parser because YAML is 100% batshit-crazy insane. We just handle what’s necessary to parse TBD files.
parse_yaml :: (lexer_in: Lexer, $T: Type, ignore_unknown := true) -> success: bool, T, complete: bool, Lexer {
	result: T;
	info := type_info(T);
    lexer := lexer_in;
	success := parse_document(*lexer, cast(*u8)*result, info, ignore_unknown, "");
	if !success		return false, result, true, .{};

    complete := (peek_next_token(*lexer).type == .END_OF_INPUT);

	return true, result, complete, lexer;
}

parse_document :: (lexer: *Lexer, slot: *u8, info: *Type_Info, ignore_unknown: bool, field_name: string) -> success: bool {
    while true {
        token := peek_next_token(lexer);
        if token.type == .END_OF_INPUT return true;
        if token.type == .TRIPLE_MINUS {
            eat_token(lexer);
            break;
        }

        // @ToDo: Most tokens should not appear here, but I don’t care atm. because TBDs don’t contain any pre-document information anyways.
        // -rluba, 2024-02-23
        eat_token(lexer);
    }

    success := parse_value(lexer, slot, info, ignore_unknown, field_name);
    if !success return false;

    // Eat end-of-document, if it exists
    token := peek_next_token(lexer);
    if token.type == .TRIPLE_DOT {
        eat_token(lexer);
    }

    return true;
}

parse_value :: (lexer: *Lexer, slot: *u8, info: *Type_Info, ignore_unknown: bool, field_name: string, flow := false) -> success: bool {
	prepare_slot :: (lexer: *Lexer, expected_type: Type_Info_Tag, info: *Type_Info, slot: *u8, log_on_error := true) -> *u8, success: bool, info: *Type_Info {
		value_info := info;
		if info.type == .POINTER {
			pointer_info := cast(*Type_Info_Pointer) info;
			value_info = pointer_info.pointer_to;
		}

        if info.type == .ENUM {
            info_enum := cast(*Type_Info_Enum) info;
            value_info = info_enum.internal_type;
        }

		if value_info.type != expected_type {
            if log_on_error {
                teaser := slice(lexer.input, lexer.input_cursor, lexer.input.count - lexer.input_cursor);
                if teaser.count > 50	teaser.count = 50;
                builder: String_Builder;
                print_type_to_builder(*builder, info);
                type_name := builder_to_string(*builder,, allocator = temp);
                log_error("Cannot parse % value into type \"%\". Remaining input is: %…", expected_type, type_name, teaser);
            }
			return null, false, value_info;
		}

		if info.type == .POINTER {
			value_slot := alloc(value_info.runtime_size);
			initializer: (*void) #no_context;
			if value_info.type == .STRUCT {
				struct_info := cast(*Type_Info_Struct) value_info;
				initializer = struct_info.initializer;
			}
			if initializer {
				initializer(value_slot);
			} else {
				memset(value_slot, 0, value_info.runtime_size);
			}
			(.*)cast(**u8)slot = value_slot;
			return value_slot, true, value_info;
		} else {
			return slot, true, value_info;
		}
	}

    while true {
        success := true;
        token := peek_next_token(lexer);
        if token.type == {
            case #char "!";
                eat_token(lexer);
                token = peek_next_token(lexer);
                if token.type == .IDENT && token.preceeding_whitespace == 0 {
                    // log("Found tag %", token.ident_value.name);
                    eat_token(lexer);
                } else {
                    // log("Found empty tag");
                }
                continue;

            case #char "[";
                eat_token(lexer);
                #through;
            case #char "-";
                is_flow := (token.type == #char "[");

                value_slot: *u8;
                value_info: *Type_Info;
                if slot {
                    value_slot, success, value_info = prepare_slot(lexer, .ARRAY, info, slot);
                }
                if success {
                    success = parse_array(lexer, value_slot, cast(*Type_Info_Array) value_info, ignore_unknown = ignore_unknown, flow = is_flow);
                }
                return success;

            case .STRING;
                eat_token(lexer);

                value_slot: *u8;
                value_info: *Type_Info;
                if slot {
                    value_slot, success, value_info = prepare_slot(lexer, .STRING, info, slot);
                }
                if success {
                    if value_slot {
                        (.*)cast(*string)value_slot = token.string_value;
                    }
                }
                return success;

            case .IDENT;
                after_ident := peek_token(lexer, 1);
                if after_ident.type == #char ":" {
                    value_slot: *u8;
                    value_info: *Type_Info;
                    if slot {
                        value_slot, success, value_info = prepare_slot(lexer, .STRUCT, info, slot);
                    }
                    if success {
                        success = parse_object(lexer, value_slot, cast(*Type_Info_Struct) value_info, ignore_unknown = ignore_unknown);
                    }
                } else {
                    string_value: string;
                    eat_token(lexer);
                    if flow {
                        builder: String_Builder;
                        init_string_builder(*builder,, temp);
                        append(*builder, token.string_value);

                        while true {
                            token = peek_next_token(lexer);
                            if token.type == {
                                case #char ","; #through;
                                case #char "]";
                                    break;
                                case .IDENT;
                                    eat_token(lexer);
                                    for 1..token.preceeding_whitespace append(*builder, " "); // @Incomplete: not quite correct, but good enough for our purposes
                                    append(*builder, token.string_value);
                                case;
                                    report_parse_error(lexer, token, "Unexpected token % while parsing a string in flow mode", token.type);
                                    return false;
                            }
                        }
                        string_value = builder_to_string(*builder,, temp);
                    } else {
                        string_value = token.string_value;
                    }

                    if slot {
                        value_slot: *u8;
                        value_info: *Type_Info;
                        value_slot, success, value_info = prepare_slot(lexer, .FLOAT, info, slot, log_on_error = false);
                        if !success {
                            value_slot, success, value_info = prepare_slot(lexer, .INTEGER, info, slot, log_on_error = false);
                        }
                        if !success {
                            value_slot, success, value_info = prepare_slot(lexer, .STRING, info, slot, log_on_error = true);
                        }

                        if success {
                            if value_info.type == {
                                case .FLOAT;
                                    success = parse_and_write_float(lexer, token, string_value, value_info, value_slot);

                                case .INTEGER;
                                    info_int := cast(*Type_Info_Integer) value_info;
                                    success = parse_and_write_integer(lexer, token, string_value, info_int, value_slot);

                                case .STRING;
                                    (.*)cast(*string)value_slot = string_value;

                                case; assert(false);
                            }
                        }
                    }
                }

                return success;

            case;
                report_parse_error(lexer, token, "Unexpected token %", token.type);
                return false;
        }
    }

    assert(false);
    return false;
}

parse_and_write_float :: (lexer: *Lexer, token: *Token, string_value: string, info: *Type_Info, slot: *u8) -> bool {
    float_value, success, remainder := string_to_float64(string_value);
    if !success || remainder {
        report_parse_error(lexer, token, "Could not parse \"%\" as a float", string_value);
        return false;
    }
    if info.runtime_size == 4 {
        ((.*) cast(*float) slot) = cast(float) float_value;
    } else {
        assert(info.runtime_size == 8);
        ((.*) cast(*float64) slot) = float_value;
    }
    return true;
}

parse_and_write_integer :: (lexer: *Lexer, token: *Token, string_value: string, info: *Type_Info_Integer, pointer: *void) -> bool {
    if info.signed {
        return parse_and_write_integer(lexer, token, string_value, info, pointer, signed = true);
    } else {
        return parse_and_write_integer(lexer, token, string_value, info, pointer, signed = false);
    }
}

parse_and_write_integer :: (lexer: *Lexer, token: *Token, string_value: string, info: *Type_Info_Integer, pointer: *void, $signed: bool) -> bool {
    #if signed {
        Int_Type :: s64;
    } else {
        Int_Type :: u64;
    }

    int_value, int_success, remainder := string_to_int(string_value, T = Int_Type);
    if !int_success {
        #if signed {
            report_parse_error(lexer, token, "Could not parse \"%\" as an integer.", string_value);
        } else {
            report_parse_error(lexer, token, "Could not parse \"%\" as an unsigned integer.", string_value);
        }
        return false;
    }

    valid, low, high := Reflection.range_check_and_store(int_value, info, pointer);

    if !valid {
        report_parse_error(lexer, token, "The value '%' is out of range. (It must be between % and %.)", int_value, low, high);
        return false;
    }

    return true;
}


parse_array :: (lexer: *Lexer, slot: *u8, info: *Type_Info_Array, ignore_unknown: bool, flow: bool) -> success: bool {
	element_size: int;
	if slot {
		element_size = info.element_type.runtime_size;
		assert(element_size != -1, "Unknown element size");
	}

    array: Resizable_Array;

    initializer: (*void) #no_context;
    element_type: *Type_Info;
    if slot {
        element_type = info.element_type;
        if element_type.type == .STRUCT {
            struct_info := cast(*Type_Info_Struct) element_type;
            initializer = struct_info.initializer;
        }
    }

    token := peek_next_token(lexer);
    depth := token.c0 - 1;

    while true {
        token = peek_next_token(lexer);
        if flow {
            if token.type == #char "]" {
                eat_token(lexer);
                break;
            } else if array.count {
                if token.type == #char "," {
                    eat_token(lexer);
                } else {
                    report_parse_error(lexer, token, "Unexpected token % while parsing flow array", token.type);
                    return false;
                }
            }
        } else {
            if is_document_end(token) break;

            if array.count {
                if token.preceeding_whitespace < depth break;

                if token.preceeding_whitespace != depth {
                    report_parse_error(lexer, token, "Invalid indentation size of % instead of % while parsing array", token.preceeding_whitespace, depth);
                    return false;
                }
            }

            if token.type != #char "-" || (array.count && token.c0 != token.preceeding_whitespace + 1) {
                report_parse_error(lexer, token, "Unexpected token % while parsing array", token.type);
                return false;
            }

            eat_token(lexer);
        }

        element_data: *void;
        if slot {
            maybe_grow(*array, element_size);
            element_data = array.data + array.count * element_size;
            if initializer {
                initializer(element_data);
            } else {
                memset(element_data, 0, element_size);
            }
        }

        success := parse_value(lexer, element_data, element_type, ignore_unknown, "", flow = flow);
        if !success	return false;
        array.count += 1;
    }

    if slot {
        if info.array_type == .VIEW {
            view := (cast(*Array_View_64) slot);
            view.count = array.count;
            view.data = array.data;
        } else if info.array_count == -1 {
            // Resizable array
            (.*)(cast(*Resizable_Array) slot) = array;
        } else {
            // Fixed-size array
            if (info.array_count != array.count) {
                log_error("Expected array of size %, but found array of size %\n", info.array_count, array.count);
                return false;
            }

            memcpy(slot, array.data, array.count * element_size);
        }
    }

	return true;
}

is_document_end :: (token: *Token) -> bool {
    return token.type == .END_OF_INPUT || (token.c0 == 1 && (token.type == .TRIPLE_MINUS || token.type == .TRIPLE_DOT));
}

Member_Offset :: struct {
    member: *Type_Info_Struct_Member;
    offset_in_bytes: s64;
}

find_member :: (name: string, info: *Type_Info_Struct, base_offset := 0) -> found: bool, member_offset: int, *Type_Info {
    for * member: info.members {
        member_offset := base_offset + member.offset_in_bytes;
        if member.name == name {
            return true, member_offset, member.type;
        }

        if (member.flags & .USING) && (member.type.type == .STRUCT) {
            found, found_offset, found_type_info := find_member(name, cast(*Type_Info_Struct) member.type, member_offset);
            if found return true, found_offset, found_type_info;
        }
    }
    return false, -1, null;
}

// @Incomplete: Maybe support single-pair flow sequence objects
parse_object :: (lexer: *Lexer, slot: *u8, info: *Type_Info_Struct, ignore_unknown: bool) -> success: bool {
    token := peek_next_token(lexer);
    depth := token.c0 - 1;

    first := true;
	while true {
        token := peek_next_token(lexer);
        if is_document_end(token) break;

        if !first {
            if token.preceeding_whitespace < depth break;

            if token.preceeding_whitespace != depth {
                report_parse_error(lexer, token, "Invalid indentation size of % instead of % while parsing object", token.preceeding_whitespace, depth);
                return false;
            }
        }

        if token.type != .IDENT || (!first && token.c0 != token.preceeding_whitespace + 1) {
            report_parse_error(lexer, token, "Unexpected token % while parsing object", token.type);
            return false;
        }
        first = false;

        eat_token(lexer);
        ident: = token;
        yaml_ident_name := ident.string_value;
        jai_ident_name := to_jai_ident(yaml_ident_name);

        token = peek_next_token(lexer);
        if token.type != #char ":" {
            report_parse_error(lexer, token, "Unexpected token % after identifier while parsing object", token.type);
            return false;
        }

        member_slot: *u8;
        member_info: *Type_Info;
        if info {
            member_found, member_offset, member_info= := find_member(jai_ident_name, info);

            if member_found {
                member_slot = slot + member_offset;
            } else if !ignore_unknown {
                report_parse_error(lexer, ident, "Missing member % in %", jai_ident_name, info.*);
                return false;
            }
        }
        eat_token(lexer); // ":"

        success := parse_value(lexer, member_slot, member_info, ignore_unknown, jai_ident_name);
        if !success return false;
	}

	return true;
}

to_jai_ident :: (name: string) -> string {
    TO_REPLACE :: "-.";
    if !contains_any_character(name, TO_REPLACE) return name;

    result := copy_string(name,, temp);
    replace_chars(result, TO_REPLACE, #char "_");
    return result;
}

Reflection :: #import "Reflection";
#import "Math";
