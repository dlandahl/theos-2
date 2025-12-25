
/*

Usage example:

    Gate_Descriptor_Flags :: enum u16 {
        interrupt_stack_table :: 3;
        ignored               :: 5;
        gate_type             :: 4;
        always_zero           :: 1;
        protection_level      :: 2;
        present               :: 1;
    }

    main :: () {
        set :: bitfield_set; // Optional

        gate_flags: Gate_Descriptor_Flags;

        set(*gate_flags, .protection_level, 3);
        set(*gate_flags, .interrupt_stack_table, 1);

        print("Flags is %\n", formatInt(cast(u16) gate_flags, base=2));
    }

Todo: would like to have this syntax:

    Set(gate_flags.protection_level, 3);

*/

#module_parameters(ENABLE_RUNTIME_ERROR_CHECKS := true);

#scope_export

bitfield_set :: inline (bitfield: *$B, flag: $F, value: s64, $loc := #caller_location, $call := #caller_code) #modify {
    return handle_as(*B, *F);
} {
    bit_mask, bit_offset :: #run calculate_mask_and_offset(B, loc, call);

    #if ENABLE_RUNTIME_ERROR_CHECKS {
        max_value := bit_mask >> bit_offset;
        assert(value <= max_value, "The bitfield slot does not have enough bits to represent the value %. It can maximally represent %.", value, max_value);
    }

    // Don't dereference the pointer twice to mask out and set the new value.
    // Can make a difference when the pointer directly refers to a memory-mapped hardware register.
    temp := bitfield.*;
    temp &= cast,no_check(B) ~bit_mask;
    temp |= cast,no_check(B) (value << bit_offset);
    bitfield.* = temp;
}

bitfield_get :: inline (bitfield: $B, flag: $F, return_type: $R = 0, $loc := #caller_location, $call := #caller_code) -> R #modify {
    result := handle_as(*B, *F);

    tie := cast(*Type_Info_Enum)F;
    R = get_type(tie.internal_type);

    return result;
} {
    bit_mask, bit_offset :: #run calculate_mask_and_offset(B, loc, call);

    value := bitfield;
    value &=  cast,no_check(B) bit_mask;
    value >>= cast,no_check(B) bit_offset;
    return cast(R) value;
}

bitfield_set_bit :: inline (bitfield: *$B, flag: $F, $loc := #caller_location, $call := #caller_code) #modify {
    return handle_as(*B, *F);
} {
    bit_mask :: #run get_single_bit_mask(B, loc, call);

    bitfield.* |= bit_mask;
}

bitfield_clear_bit :: inline (bitfield: *$B, flag: $F, $loc := #caller_location, $call := #caller_code) #modify {
    return handle_as(*B, *F);
} {
    bit_mask :: #run get_single_bit_mask(B, loc, call);

    bitfield.* &= ~bit_mask;
}

bitfield_get_bit :: inline (bitfield: *$B, flag: $F, $loc := #caller_location, $call := #caller_code) -> bool #modify {
    return handle_as(*B, *F);
} {
    bit_mask :: #run get_single_bit_mask(B, loc, call);

    return bitfield.* & bit_mask > 0;
}

print_bitfield :: (builder: *String_Builder, bitfield: $B, format: *FormatStruct = null, $loc := #caller_location) {
    ti :: type_info(B);

    #run validate_bitfield(ti, loc);

    if !format format = *context.print_style.default_format_struct;

    if format.draw_type_name {
        append(builder, ti.name);
    }

    append(builder, format.begin_string);

    use_newlines := false;
    long_form := false;

    long_form_limit := format.use_long_form_if_more_than_this_many_members;
    if (long_form_limit < 0) || (ti.names.count > long_form_limit) {
        long_form = true;
        use_newlines = format.use_newlines_if_long_form;
    }

    if use_newlines append(builder, "\n");

    context.print_style.indentation_depth += 1;

    bit_offset: int;

    for ti.names {
        if use_newlines append_indentation(builder, format);

        if long_form {
            append(builder, it);
            append(builder, format.separator_between_name_and_value);
        }

        bit_count := ti.values[it_index];
        bit_mask := (1 << bit_count) - 1;

        value :=  bitfield;
        value >>= xx bit_offset;
        value &=  xx bit_mask;

        default := context.print_style.default_format_int;
        default.value = cast(u64) value;
        print_integer(builder, default);

        if long_form {
            append(builder, format.long_form_separator_between_fields);
        } else {
            if it_index < ti.names.count-1 append(builder, format.short_form_separator_between_fields);
        }

        if use_newlines append(builder, "\n");

        bit_offset += bit_count;
    }

    context.print_style.indentation_depth -= 1;

    if use_newlines append_indentation(builder, format);
    append(builder, format.end_string);
}

#scope_module

#import "Compiler";
#import "Basic";

calculate_mask_and_offset :: ($bitfield: Type, loc: Source_Code_Location, call: Code) -> int, int {
    ti := cast(*Type_Info_Enum) bitfield;
    validate_bitfield(ti, loc);

    bit_offset: int;

    nodes := compiler_get_nodes(call);
    procedure_call := cast(*Code_Procedure_Call) nodes;
    expression := procedure_call.arguments_unsorted[1].expression;

    // This procedure should have been called with either an identifier, or an unary or binary enum dereference as the second argument.
    operator_type: Operator_Type;

    if expression.kind == {
      case .UNARY_OPERATOR;
        unary := cast(*Code_Unary_Operator) expression;
        operator_type = unary.operator_type;
        expression = unary.subexpression;

      case .BINARY_OPERATOR;
        binary := cast(*Code_Binary_Operator) expression;
        operator_type = binary.operator_type;
        expression = binary.left;

      case .IDENT;
        operator_type = #char ".";
    }

    if operator_type != #char "." || expression.kind != .IDENT {
        name := ifx ti.name else "(anonymous type)";
        error := tprint("Here, please pass a single field from the bitfield \"%\"", name);
        compiler_report(error, make_location(expression));
    }

    ident := cast(*Code_Ident) expression;
    field_name := ident.name;

    bit_count: int;
    found: bool;

    for ti.names {
        if it == field_name {
            bit_count = ti.values[it_index];
            found = true;
            break;
        }

        bit_offset += ti.values[it_index];
    }

    if !found {
        name := ifx ti.name else "(anonymous type)";
        error := tprint("The name \"%\" is not a field of the bitfield \"%\". (You can't use variables as the second argument to bitfield_set.)", field_name, name);
        compiler_report(error, make_location(expression));
    }

    bit_mask := (1 << bit_count) - 1;

    bit_mask <<= bit_offset;
    return bit_mask, bit_offset;
}

#import "Bit_Operations";
get_single_bit_mask :: ($bitfield: Type, loc: Source_Code_Location, call: Code) -> int {
    bit := calculate_mask_and_offset(bitfield, loc, call);

    count := popcount(bit);
    if count != 1 {
        ti := cast(*Type_Info_Enum) bitfield;
        name := ifx ti.name else "(anonymous type)";

        error := tprint("A member of the bitfield \"%\" was used as a single bit argument, but is % bits wide.", name, count);
        compiler_report(error, loc);
    }

    return bit;
}

validate_bitfield :: (bitfield: *Type_Info, loc: Source_Code_Location) {
    if bitfield.type != .ENUM {
        compiler_report("Argument to bitfield routine is not an enum.", loc);
        return;
    }

    ti := cast(*Type_Info_Enum) bitfield;

    total_width: int;

    for ti.values {
        total_width += it;
    }

    expected_width := bitfield.runtime_size*8;

    if total_width != expected_width {
        name := ifx ti.name else "(anonymous type)";
        error_message := tprint("Bitfield \"%\" values do not sum to the width of its integer type. The total width was %, expected %", name, total_width, expected_width);
        compiler_report(error_message, loc);
    }
}

handle_as :: (B: *Type, F: *Type) -> bool {
    // This setup allows you to put #as on a struct member that represents a bitfield, and it works how you would expect.
    // You can then write e.g. bitfield_get(struct_instance, .bitfield_member);
    F.* = B.*;

    if cast(*Type_Info, B.*).type == .STRUCT {
        for cast(*Type_Info_Struct, B.*).members {
            if it.flags & .AS && it.type.type == .ENUM {
                B.* = get_type(it.type);
                F.* = get_type(it.type);
                return true;
            }
        }
    }

    return true;
}
