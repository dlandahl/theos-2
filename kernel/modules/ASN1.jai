
#import "Basic";

Asn1_Tag :: enum u8 {
    INTEGER            :: 0x02;
    BIT_STRING         :: 0x03;
    OCTET_STRING       :: 0x04;
    NULL               :: 0x05;
    OBJECT_IDENTIFIER  :: 0x06;
    UTF8_STRING        :: 0x0c;
    PRINTABLE_STRING   :: 0x13;
    IA5_STRING         :: 0x15;
    UTC_TIME           :: 0x17;
    GENERALIZED_TIME   :: 0x18;
    SEQUENCE           :: 0x30;
    SET                :: 0x31;
    CONTEXT_0          :: 0xa0;
}

Asn1_Parser :: struct {
    using root: Construction;

    construction_stack: [..] Construction;

    Construction :: struct {
        data: []u8;
        cursor: int;
    }

    error: bool;
    debug_mode: bool;
}

get_current_construction :: (parser: Asn1_Parser) -> *Asn1_Parser.Construction {
    // Be aware the returned pointer can become stale if you create a new construction, with asn1_sequence etc.

    if parser.construction_stack {
        return *parser.construction_stack[parser.construction_stack.count-1];
    }

    return *parser.root;
}

peek_tag :: (parser: Asn1_Parser) -> Asn1_Tag {
    if parser.error return 0;

    using get_current_construction(parser);

    // if cursor >= data.count return 0xff;
    return cast(Asn1_Tag) data[cursor];
}

read_length :: (parser: *Asn1_Parser) -> int {
    if parser.error return 0;

    parse_error :: () #expand {
        `parser.error = true;
        `return 0;
    }

    using get_current_construction(parser);

    if cursor >= data.count parse_error();

    first := data[cursor];
    cursor += 1;

    if (first & 0x80) == 0 {
        if cursor + first > data.count parse_error();
        return first;
    }

    octets := first & 0x7f;

    if octets == 0 || octets > 4    parse_error();
    if cursor + octets > data.count parse_error();

    length: int;
    for 0..octets-1 {
        length = (length << 8) | data[cursor + it];
    }

    cursor += octets;
    return length;

    // Todo error: return parser.cursor + length.* <= parser.data.count;
}

read_value :: (parser: *Asn1_Parser, expected_tag: Asn1_Tag) -> [] u8 {
    if parser.error return .{};

    using get_current_construction(parser);

    // Todo: if parser.cursor >= parser.data.count return false;

    tag := cast(Asn1_Tag)data[cursor];
    cursor += 1;

    if tag != expected_tag {
        parser.error = true;
        return .{};
    }

    length := read_length(parser);

    result := []u8.{length, data.data + cursor};
    cursor += length;

    return result;
}

Bit_String :: struct {
    value: []u8;
    unused: int; // How many of the low bits of the last byte in the array are not part of the string.
}

read_bit_string :: (parser: *Asn1_Parser) -> _ := Bit_String.{} {
    if parser.error return;

    bits := read_value(parser, .BIT_STRING);

    if bits.count == 0 {
        parser.error = true;
        return;
    }

    result: Bit_String;
    result.unused = bits.data.*;

    bits.data += 1;
    bits.count -= 1;

    result.value = bits;

    return result;
}

read_time :: (parser: *Asn1_Parser) -> Apollo_Time, is_utc := false {
    if parser.error return APOLLO_TIME_INVALID;

    tag := peek_tag(parser);
    if tag != .UTC_TIME && tag != .GENERALIZED_TIME {
        return APOLLO_TIME_INVALID;
    }

    value := read_value(parser, tag);

    next_byte :: () -> u8 #expand {
        if !value.count {
            `return APOLLO_TIME_INVALID;
        }

        byte := value[0];
        value.count -= 1;
        value.data  += 1;
        return byte;
    }

    next_two_digit_decimal :: () -> s8 #expand {
        dec := (next_byte() - #char "0") * 10;
        dec += (next_byte() - #char "0");
        return cast(s8)dec;
    }

    cal: Calendar_Time;
    cal.time_zone = .UTC;

    cal.year = next_two_digit_decimal();

    // Tag-specific year parsing.
    if tag == {
      case .UTC_TIME;
        if cal.year < 50 cal.year += 2000;
        else             cal.year += 1900;
      case .GENERALIZED_TIME;
        cal.year = cal.year * 100 + next_two_digit_decimal();
    }

    bounds_check :: (value: int, max: int) #expand {
        if value < 0 || value > max {
            `return APOLLO_TIME_INVALID;
        }
    }

    cal.month_starting_at_0  = next_two_digit_decimal();
    cal.month_starting_at_0 -= 1;
    bounds_check(cal.month_starting_at_0, 11);

    cal.day_of_month_starting_at_0  = next_two_digit_decimal();
    cal.day_of_month_starting_at_0 -= 1;

    {
        // Bounds checking the day of the month.

        days_in_month :: int.[ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ];
        max_day := days_in_month[cal.month_starting_at_0];

        is_leap_year := (cal.year % 4 == 0) && ((cal.year % 100 != 0) || (cal.year % 400 == 0));
        if cal.month_starting_at_0 == 1 && is_leap_year {
            max_day += 1;
        }

        bounds_check(cal.day_of_month_starting_at_0, max_day-1);
    }

    // This is the point where we switch to Apollo, because we're done dealing with years and dates,
    // and can convert everything to seconds easily without handling e.g. leap years. That way we don't
    // have to carry the calendar time values if they overflow, etc.
    apollo := native_calendar_to_apollo(cal);

    hours := next_two_digit_decimal();
    bounds_check(hours, 23);
    apollo += seconds_to_apollo(cast(int)hours * 60 * 60);

    if !value.count {
        // GENERALIZED_TIME is allowed to be done here. UTC_TIME must have minutes value and an explicit time zone.
        return ifx tag == .UTC_TIME then APOLLO_TIME_INVALID else apollo;
    }

    has_minutes := (tag == .GENERALIZED_TIME && is_digit(value[0])) || (tag == .UTC_TIME);

    if has_minutes {
        minutes := next_two_digit_decimal();
        bounds_check(minutes, 59);
        apollo += seconds_to_apollo(cast(int)minutes * 60);
    }

    if !value.count {
        // GENERALIZED_TIME is allowed to be done here. UTC_TIME must an explicit time zone.
        return ifx tag == .UTC_TIME then APOLLO_TIME_INVALID else apollo;
    }

    next := next_byte();

    // Seconds are always optional.
    if has_minutes && is_digit(next) {
        value.data -= 1; value.count += 1;

        seconds := next_two_digit_decimal();
        bounds_check(seconds, 59);
        apollo += seconds_to_apollo(cast(int)seconds);

        next = next_byte();

        // Nested, since technically milliseconds are not allowed if seconds were not provided.
        if tag == .GENERALIZED_TIME && next == #char "." {
            milliseconds := cast(int)next_two_digit_decimal() * 10;
            milliseconds += (next_byte() - #char "0");

            bounds_check(milliseconds, 999);
            apollo += milliseconds_to_apollo(milliseconds);

            next = next_byte();
        }
    }

    if next == #char "Z" {
        // Let's not allow trailing bytes. It might mean the length is encoded wrong, which the user would want to be aware of.
        if value.count return APOLLO_TIME_INVALID;

        return apollo, is_utc=true;
    }

    if (next == #char "-") || (next == #char "+") {
        direction := next;

        hour_offset   := next_two_digit_decimal();
        minute_offset := next_two_digit_decimal();

        // Howland Island Time (UTC-12), Line Islands Time (UTC+14).
        hour_max := ifx direction == #char "-" then 12 else 14;

        bounds_check(hour_offset, hour_max);
        bounds_check(minute_offset, 59);

        total_offset := seconds_to_apollo(hour_offset*60*60 + minute_offset*60);

        if direction == #char "+" {
            apollo += total_offset;
        } else {
            apollo -= total_offset;
        }

        // There should be no more bytes after the offset.
        if value.count return APOLLO_TIME_INVALID;

        // (Timestamp was not UTC, but we converted it.)
        return apollo, is_utc=true;
    }

    if tag == .UTC_TIME {
        // 'UTC_TIME' is supposed to have an explicit time zone, either Z or +/-.
        return APOLLO_TIME_INVALID;
    }

    if value.count return APOLLO_TIME_INVALID;
    return apollo, is_utc=false;
}

read_string :: (parser: *Asn1_Parser) -> string {
    if parser.error return "";

    tag := peek_tag(parser);
    if tag != .UTF8_STRING && tag != .PRINTABLE_STRING {
        parser.error = true;
        return "";
    }

    value := read_value(parser, tag);
    return cast(string)value;
}



asn1_sequence :: #bake_arguments asn1_construction(tag=.SEQUENCE);
asn1_context  :: #bake_arguments asn1_construction(tag=.CONTEXT_0);
asn1_set      :: #bake_arguments asn1_construction(tag=.SET);

asn1_construction :: (parser: *Asn1_Parser, body: Code, flags: For_Flags, loc := #caller_location, tag: Asn1_Tag) #expand {
    if parser.error return;

    container := read_value(parser, tag);
    const := array_add(*parser.construction_stack);
    const.data = container;

    if parser.debug_mode {
        log("Entering. Stack = % %", parser.construction_stack.count, loc);
    }

    while true {
        const = get_current_construction(parser); // Pointer may be stale now.

        `it := const;
        `it_index := parser.construction_stack.count;

        // Even if we say continue, if we're at the end of the construction, stop automatically.
        if it.cursor >= it.data.count break;

        #insert body;

        // Break (skip the rest of the construction) is the default. Put continue to not break.
        break;
    }

    if parser.debug_mode {
        if parser.error log("Exiting with error.");
        else log("Exiting");
    }

    pop(*parser.construction_stack);
}



OID_COUNTRY_NAME           :: u64.[2, 5, 4, 6];
OID_STATE_OR_PROVINCE_NAME :: u64.[2, 5, 4, 8];
OID_ORGANISATION_NAME      :: u64.[2, 5, 4, 10];

OID_SIGNATURE_RSA_SHA256   :: u64.[1, 2, 840, 113549, 1, 1, 11];
OID_SIGNATURE_ECDSA_SHA256 :: u64.[1, 2, 840, 10045, 4, 3, 2];
OID_SIGNATURE_ED25519      :: u64.[1, 3, 101, 112];

OID_KEY_TYPE_RSA           :: u64.[1, 2, 840, 113549, 1, 1, 1];
OID_KEY_TYPE_EC            :: u64.[1, 2, 840, 10045, 2, 1];

compare_oid :: (input: []u8, other: []u64) -> bool {
    if input.count < 1 || other.count < 2 return false;

    // Concise binary object representation (CBOR).
    if input[0] / 40 != other[0] return false;
    if input[0] % 40 != other[1] return false;

    input_cursor := 1;
    other_cursor := 2;

    while other_cursor < other.count {
        next_value: u64 = 0;

        while true {
            if input_cursor >= input.count {
                return false;
            }

            byte := input[input_cursor];
            input_cursor += 1;

            next_value <<= 7;
            next_value |= byte & 0x7f;

            if !(byte & 0x80) break;
        }

        if next_value != other[other_cursor] {
            return false;
        }

        other_cursor += 1;
    }

    return true;
}

X509_Certificate :: struct {

    Distinguished_Name :: struct {
        country:           string;
        state_or_province: string;
        organisation:      string;
    }

    version: int;
    serial_number: []u8;

    signature_algorithm: enum {
        TODO_UNKNOWN;
        RSA_SHA256;
        ECDSA_SHA256;
        ED25519;
    };

    issuer: Distinguished_Name;

    not_valid_before: Apollo_Time;
    not_valid_after: Apollo_Time;

    subject: Distinguished_Name;

    public_key_algorithm: enum {
        TODO_UNKNOWN;
        RSA;
        EC;
    };

    public_key: Bit_String;
    signature: Bit_String;
}

read_x509_distinguished_name :: (parser: *Asn1_Parser) -> X509_Certificate.Distinguished_Name {
    dn: X509_Certificate.Distinguished_Name;

    for :asn1_sequence parser {
        for :asn1_set parser {
            for :asn1_sequence parser {
                oid := read_value(parser, .OBJECT_IDENTIFIER);
                string_value := read_string(parser);

                if compare_oid(oid, OID_COUNTRY_NAME)           dn.country           = string_value;
                if compare_oid(oid, OID_STATE_OR_PROVINCE_NAME) dn.state_or_province = string_value;
                if compare_oid(oid, OID_ORGANISATION_NAME)      dn.organisation      = string_value;
            }
        }

        continue;
    }

    return dn;
}

parse_x509_certificate :: (certificate: []u8) -> bool, X509_Certificate {
    parser := Asn1_Parser.{data=certificate};
    parser.debug_mode = false;

    cert: X509_Certificate;

    for :asn1_sequence parser {
        for :asn1_sequence parser {
            cert.version = 1;

            for :asn1_context parser {
                version_value := read_value(*parser, .INTEGER);
                if version_value.count > 1 return false, .{};

                cert.version = version_value.data.* + 1;
            }

            cert.serial_number = read_value(*parser, .INTEGER);

            for :asn1_sequence parser {
                oid := read_value(*parser, .OBJECT_IDENTIFIER);

                if compare_oid(oid, OID_SIGNATURE_RSA_SHA256)    cert.signature_algorithm = .RSA_SHA256;
                if compare_oid(oid, OID_SIGNATURE_ECDSA_SHA256)  cert.signature_algorithm = .ECDSA_SHA256;
                if compare_oid(oid, OID_SIGNATURE_ED25519)       cert.signature_algorithm = .ED25519;
            }

            cert.issuer = read_x509_distinguished_name(*parser);

            for :asn1_sequence parser {
                cert.not_valid_before = read_time(*parser);
                cert.not_valid_after  = read_time(*parser);
            }

            cert.subject = read_x509_distinguished_name(*parser);

            for :asn1_sequence parser {
                for :asn1_sequence parser {
                    oid := read_value(*parser, .OBJECT_IDENTIFIER);

                    if compare_oid(oid, OID_KEY_TYPE_RSA) cert.public_key_algorithm = .RSA;
                    if compare_oid(oid, OID_KEY_TYPE_EC)  cert.public_key_algorithm = .EC;
                }

                cert.public_key = read_bit_string(*parser);
            }
        }

        // Todo: Additional optional IDs and extensions.

        for :asn1_sequence parser {}; // Signature algorithm, same as TBS signature algorithm.

        cert.signature = read_bit_string(*parser);
    }

    return !parser.error, cert;
}











#run {
    #import "String";
    #import "Compiler";

    cl := get_toplevel_command_line();

    // Auto run the test without generating an executable, if the module gets passed to the compiler directly on the command line.
    if cl.count == 2 && contains(cl[1], "ASN1.jai") {
        set_build_options_dc(.{do_output = false});

        result, cert := parse_x509_certificate(test_cert);
        assert(result);

        context.print_style.default_format_struct.use_newlines_if_long_form = true;
        context.print_style.default_format_int.base = 16;
        log("%\n", cert);

        context.print_style.default_format_int.base = 10;
        s1 := calendar_to_string(to_calendar(cert.not_valid_before));
        s2 := calendar_to_string(to_calendar(cert.not_valid_after));
        log("%\n%", s1, s2);
    }
}

test_cert :: u8.[
    0x30, 0x82, 0x03, 0x21, 0x30, 0x82, 0x02, 0x09, 0xa0, 0x03, 0x02, 0x01, 0x02, 0x02, 0x08, 0x15,
    0x5a, 0x92, 0xad, 0xc2, 0x04, 0x8f, 0x90, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7,
    0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, 0x30, 0x22, 0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04,
    0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x13, 0x30, 0x11, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0a,
    0x45, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x20, 0x43, 0x41, 0x30, 0x1e, 0x17, 0x0d, 0x31, 0x38,
    0x31, 0x30, 0x30, 0x35, 0x30, 0x31, 0x33, 0x38, 0x31, 0x37, 0x5a, 0x17, 0x0d, 0x31, 0x39, 0x31,
    0x30, 0x30, 0x35, 0x30, 0x31, 0x33, 0x38, 0x31, 0x37, 0x5a, 0x30, 0x2b, 0x31, 0x0b, 0x30, 0x09,
    0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x1c, 0x30, 0x1a, 0x06, 0x03, 0x55,
    0x04, 0x03, 0x13, 0x13, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x75, 0x6c, 0x66, 0x68,
    0x65, 0x69, 0x6d, 0x2e, 0x6e, 0x65, 0x74, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a,
    0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00, 0x30,
    0x82, 0x01, 0x0a, 0x02, 0x82, 0x01, 0x01, 0x00, 0xc4, 0x80, 0x36, 0x06, 0xba, 0xe7, 0x47, 0x6b,
    0x08, 0x94, 0x04, 0xec, 0xa7, 0xb6, 0x91, 0x04, 0x3f, 0xf7, 0x92, 0xbc, 0x19, 0xee, 0xfb, 0x7d,
    0x74, 0xd7, 0xa8, 0x0d, 0x00, 0x1e, 0x7b, 0x4b, 0x3a, 0x4a, 0xe6, 0x0f, 0xe8, 0xc0, 0x71, 0xfc,
    0x73, 0xe7, 0x02, 0x4c, 0x0d, 0xbc, 0xf4, 0xbd, 0xd1, 0x1d, 0x39, 0x6b, 0xba, 0x70, 0x46, 0x4a,
    0x13, 0xe9, 0x4a, 0xf8, 0x3d, 0xf3, 0xe1, 0x09, 0x59, 0x54, 0x7b, 0xc9, 0x55, 0xfb, 0x41, 0x2d,
    0xa3, 0x76, 0x52, 0x11, 0xe1, 0xf3, 0xdc, 0x77, 0x6c, 0xaa, 0x53, 0x37, 0x6e, 0xca, 0x3a, 0xec,
    0xbe, 0xc3, 0xaa, 0xb7, 0x3b, 0x31, 0xd5, 0x6c, 0xb6, 0x52, 0x9c, 0x80, 0x98, 0xbc, 0xc9, 0xe0,
    0x28, 0x18, 0xe2, 0x0b, 0xf7, 0xf8, 0xa0, 0x3a, 0xfd, 0x17, 0x04, 0x50, 0x9e, 0xce, 0x79, 0xbd,
    0x9f, 0x39, 0xf1, 0xea, 0x69, 0xec, 0x47, 0x97, 0x2e, 0x83, 0x0f, 0xb5, 0xca, 0x95, 0xde, 0x95,
    0xa1, 0xe6, 0x04, 0x22, 0xd5, 0xee, 0xbe, 0x52, 0x79, 0x54, 0xa1, 0xe7, 0xbf, 0x8a, 0x86, 0xf6,
    0x46, 0x6d, 0x0d, 0x9f, 0x16, 0x95, 0x1a, 0x4c, 0xf7, 0xa0, 0x46, 0x92, 0x59, 0x5c, 0x13, 0x52,
    0xf2, 0x54, 0x9e, 0x5a, 0xfb, 0x4e, 0xbf, 0xd7, 0x7a, 0x37, 0x95, 0x01, 0x44, 0xe4, 0xc0, 0x26,
    0x87, 0x4c, 0x65, 0x3e, 0x40, 0x7d, 0x7d, 0x23, 0x07, 0x44, 0x01, 0xf4, 0x84, 0xff, 0xd0, 0x8f,
    0x7a, 0x1f, 0xa0, 0x52, 0x10, 0xd1, 0xf4, 0xf0, 0xd5, 0xce, 0x79, 0x70, 0x29, 0x32, 0xe2, 0xca,
    0xbe, 0x70, 0x1f, 0xdf, 0xad, 0x6b, 0x4b, 0xb7, 0x11, 0x01, 0xf4, 0x4b, 0xad, 0x66, 0x6a, 0x11,
    0x13, 0x0f, 0xe2, 0xee, 0x82, 0x9e, 0x4d, 0x02, 0x9d, 0xc9, 0x1c, 0xdd, 0x67, 0x16, 0xdb, 0xb9,
    0x06, 0x18, 0x86, 0xed, 0xc1, 0xba, 0x94, 0x21, 0x02, 0x03, 0x01, 0x00, 0x01, 0xa3, 0x52, 0x30,
    0x50, 0x30, 0x0e, 0x06, 0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x05,
    0xa0, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x25, 0x04, 0x16, 0x30, 0x14, 0x06, 0x08, 0x2b, 0x06,
    0x01, 0x05, 0x05, 0x07, 0x03, 0x02, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01,
    0x30, 0x1f, 0x06, 0x03, 0x55, 0x1d, 0x23, 0x04, 0x18, 0x30, 0x16, 0x80, 0x14, 0x89, 0x4f, 0xde,
    0x5b, 0xcc, 0x69, 0xe2, 0x52, 0xcf, 0x3e, 0xa3, 0x00, 0xdf, 0xb1, 0x97, 0xb8, 0x1d, 0xe1, 0xc1,
    0x46, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00,
    0x03, 0x82, 0x01, 0x01, 0x00, 0x59, 0x16, 0x45, 0xa6, 0x9a, 0x2e, 0x37, 0x79, 0xe4, 0xf6, 0xdd,
    0x27, 0x1a, 0xba, 0x1c, 0x0b, 0xfd, 0x6c, 0xd7, 0x55, 0x99, 0xb5, 0xe7, 0xc3, 0x6e, 0x53, 0x3e,
    0xff, 0x36, 0x59, 0x08, 0x43, 0x24, 0xc9, 0xe7, 0xa5, 0x04, 0x07, 0x9d, 0x39, 0xe0, 0xd4, 0x29,
    0x87, 0xff, 0xe3, 0xeb, 0xdd, 0x09, 0xc1, 0xcf, 0x1d, 0x91, 0x44, 0x55, 0x87, 0x0b, 0x57, 0x1d,
    0xd1, 0x9b, 0xdf, 0x1d, 0x24, 0xf8, 0xbb, 0x9a, 0x11, 0xfe, 0x80, 0xfd, 0x59, 0x2b, 0xa0, 0x39,
    0x8c, 0xde, 0x11, 0xe2, 0x65, 0x1e, 0x61, 0x8c, 0xe5, 0x98, 0xfa, 0x96, 0xe5, 0x37, 0x2e, 0xef,
    0x3d, 0x24, 0x8a, 0xfd, 0xe1, 0x74, 0x63, 0xeb, 0xbf, 0xab, 0xb8, 0xe4, 0xd1, 0xab, 0x50, 0x2a,
    0x54, 0xec, 0x00, 0x64, 0xe9, 0x2f, 0x78, 0x19, 0x66, 0x0d, 0x3f, 0x27, 0xcf, 0x20, 0x9e, 0x66,
    0x7f, 0xce, 0x5a, 0xe2, 0xe4, 0xac, 0x99, 0xc7, 0xc9, 0x38, 0x18, 0xf8, 0xb2, 0x51, 0x07, 0x22,
    0xdf, 0xed, 0x97, 0xf3, 0x2e, 0x3e, 0x93, 0x49, 0xd4, 0xc6, 0x6c, 0x9e, 0xa6, 0x39, 0x6d, 0x74,
    0x44, 0x62, 0xa0, 0x6b, 0x42, 0xc6, 0xd5, 0xba, 0x68, 0x8e, 0xac, 0x3a, 0x01, 0x7b, 0xdd, 0xfc,
    0x8e, 0x2c, 0xfc, 0xad, 0x27, 0xcb, 0x69, 0xd3, 0xcc, 0xdc, 0xa2, 0x80, 0x41, 0x44, 0x65, 0xd3,
    0xae, 0x34, 0x8c, 0xe0, 0xf3, 0x4a, 0xb2, 0xfb, 0x9c, 0x61, 0x83, 0x71, 0x31, 0x2b, 0x19, 0x10,
    0x41, 0x64, 0x1c, 0x23, 0x7f, 0x11, 0xa5, 0xd6, 0x5c, 0x84, 0x4f, 0x04, 0x04, 0x84, 0x99, 0x38,
    0x71, 0x2b, 0x95, 0x9e, 0xd6, 0x85, 0xbc, 0x5c, 0x5d, 0xd6, 0x45, 0xed, 0x19, 0x90, 0x94, 0x73,
    0x40, 0x29, 0x26, 0xdc, 0xb4, 0x0e, 0x34, 0x69, 0xa1, 0x59, 0x41, 0xe8, 0xe2, 0xcc, 0xa8, 0x4b,
    0xb6, 0x08, 0x46, 0x36, 0xa0
];




#scope_module

native_calendar_to_apollo :: (ct: Calendar_Time) -> Apollo_Time {
    // Todo: Doesn't work with dates before 1 AD. That doesn't seem to work on Linux either, but it should definitely be made to work.
    // Maybe this should also work with out of bounds calendar values (hour=24 etc.), because that way users can do calendar calculations and store them correctly as apollo time without always having to carry the calendar time.

    // Calculate Apollo Time relative to 1.1.1970 and then add the offset at the end, to make everything easier to think about.
    LEAP_YEARS_BEFORE_1970 :: 477;

    last_year := cast(s64) ct.year - 1;
    leap_years_before := last_year/4 - last_year/100 + last_year/400;

    leap_year_count := leap_years_before - LEAP_YEARS_BEFORE_1970;

    year_difference := cast(s64) ct.year - 1970;

    seconds := 31536000 * (year_difference - leap_year_count);
    seconds += 31622400 * leap_year_count;

    cumulative_days :: int.[
        0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365
    ];

    seconds += cumulative_days[ct.month_starting_at_0] * 86400;

    is_leap_year := (ct.year % 4 == 0) && ((ct.year % 100 != 0) || (ct.year % 400 == 0));

    if ct.month_starting_at_0 > 1 && is_leap_year {
        seconds += 86400;
    }

    seconds += cast(int) ct.day_of_month_starting_at_0 * 86400;
    seconds += cast(int) ct.hour * 60 * 60;
    seconds += cast(int) ct.minute * 60;
    seconds += cast(int) ct.second;

    apollo := seconds_to_apollo(seconds);
    apollo += milliseconds_to_apollo(ct.millisecond);
    apollo += APOLLO_TIME_FOR_JAN_1_1970;

    return apollo;
}
