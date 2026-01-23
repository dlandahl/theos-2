MAX_IDENTIFIER_LENGTH :: 512;
MAX_CONCURRENT_TOKENS :: 8;  // Must be a power of two!  // @Cleanup: explain why or change.

Token_Type :: enum s16 {
    // Mentally insert ASCII types here

    // BITWISE_XOR :: #char "^";
    // BITWISE_NOT :: #char "~";
    // BITWISE_AND :: #char "&";
    // BITWISE_OR  :: #char "|";


    IDENT :: 256;
    STRING :: 258;

    TRIPLE_MINUS;
    TRIPLE_DOT;

    END_OF_INPUT;

    ERROR;
};

Value_Flags :: enum_flags u32 {
    HERE_STRING      :: 0x1;
    NUMBER           :: 0x2;
    HEX              :: 0x4;
    BINARY           :: 0x8;
    FLOAT            :: 0x10;

    REQUIRES_FLOAT64    :: 0x10_0000;
    DEFAULTS_TO_FLOAT64 :: 0x20_0000;
    REQUIRES_FLOAT64_DUE_TO_SIGNIFICANT_DIGITS :: 0x40_0000;

    OVERFLOWED       :: 0x1000_0000;
}

Token :: struct {
    type: Token_Type = .ERROR;

    l0, c0: s32;
    l1, c1: s32 = -1;

    string_value: string;

    value_flags: Value_Flags;  // If a number or a note. Mostly the old numeric_flags, but also has HERESTRING now.
    preceeding_whitespace: s32;
}

Lexer :: struct {
    current_line_number: s32;
    current_external_file_error_report_line_number: s32;
    current_character_index: s32;

    tokens: [MAX_CONCURRENT_TOKENS] Token;
    token_array_cursor:  s32;
    num_incoming_tokens: s32;

    input: string;
    input_cursor: s64;

    should_free_input := false;
    total_lines_processed:    s64;
    nonblank_lines_processed: s64;

    preceeding_whitespace: s32;
    previous_token_line_number: s64;

    eof_token: Token;  // This is maybe not necessary; we could just allocate a new token from the ring buffer!
    eof_token.type = .END_OF_INPUT;

    user_data: *void;

    scratch_buffer: [MAX_IDENTIFIER_LENGTH] u8;

    reported_error := false;
}

set_input_from_string :: (lexer: *Lexer, input: string) {
    if lexer.should_free_input  free(lexer.input);

    lexer.input = input;
    lexer.input_cursor = 0;
    lexer.should_free_input = false;

    lexer.current_line_number = 1;
    lexer.current_character_index = 1;
    lexer.previous_token_line_number = 0;
//    did_nbsp_warning = false;

    // @Incomplete: Push these tokens until later?
    lexer.num_incoming_tokens = 0;  // @Leak of whatever tokens were waiting.
}

set_input_from_file :: (lexer: *Lexer, file_path: string) -> bool {
    assert(file_path != "");

    // @Incomplete: Push these tokens until later?
    lexer.num_incoming_tokens = 0;  // @Leak of whatever tokens were waiting.

    value, success := read_entire_file(file_path, true, true);
    if !success  return false;

    if lexer.should_free_input free(lexer.input);
    lexer.should_free_input = true;

    lexer.input = value;
    lexer.input_cursor = 0;

    lexer.current_line_number = 1;
    lexer.current_character_index = 1;
    lexer.previous_token_line_number = 0;
//    did_nbsp_warning = false;

	return true;
}



peek_next_token :: (using lexer: *Lexer) -> *Token {
    if num_incoming_tokens {
        assert(tokens[token_array_cursor].l1 != -1);
        return *tokens[token_array_cursor];
    }

    compose_new_token(lexer);
    num_incoming_tokens += 1;

    assert(tokens[token_array_cursor].l1 != -1);
    return *tokens[token_array_cursor];
}

get_last_token :: (lexer: *Lexer) -> Token {
    // This returns to you the last accepted token (that you called eat_token on). You're allowed to do this as long
    // as you know you didn't fill all the slots with read-ahead un-accepted tokens.

    cursor := lexer.token_array_cursor;

    // Wrap backwards...  Note we are not using the power-of-two requirement here, @Cleanup: Remove that constraint?
    if cursor  cursor -= 1;
    else       cursor = MAX_CONCURRENT_TOKENS - 1;

    return lexer.tokens[cursor];
}


starts_identifier :: inline (c: u8) -> bool {
    if is_alpha(c)     return true;
    if c == #char "_"  return true;
    if c == #char "/"  return true;
    return false;
}


Hex_Digit_Type :: enum u8 {
    ASCII_8_BIT :: 0;
    UNICODE_16  :: 1;
    UNICODE_32  :: 2;
}

get_and_eat_remainder_of_line :: (lexer: *Lexer, line: s32, column: s32) -> string {
    if lexer.current_line_number != line {
        report_parse_error(lexer, line, column, "Trying to eat line  but the lexer has alread moved to line %", lexer.current_line_number);
        report_detail(lexer, "The lexer is currently here.");
        lexer.input_cursor = lexer.input.count;
        return "";
    }

    col_delta := column - lexer.current_character_index;
    assert(col_delta >= lexer.input_cursor);
    start := lexer.input_cursor + col_delta;
    eat_until_newline(lexer);
    end := lexer.input_cursor;
    return slice(lexer.input, start, end - start);
}

eat_character :: (using lexer: *Lexer) {
    c := input.data[input_cursor];
    if c == #char "\n" {
        // :DoThisOnNewline
        current_line_number += 1;
        total_lines_processed += 1;
        current_character_index = 0;  // Will get incremented to 1 below.
    }

	input_cursor += 1;
    current_character_index += 1;
}


peek_next_character :: (lexer: *Lexer) -> s16 {
    if (lexer.input_cursor >= lexer.input.count) {
        return -1;
    }

    result := lexer.input.data[lexer.input_cursor];
    return result;
}


report_parse_error :: (lexer: *Lexer, format: string, arguments: .. Any) {
    report_parse_error(lexer, lexer.current_line_number, lexer.current_character_index, format, ..arguments);
} @PrintLike

report_parse_error :: (lexer: *Lexer, token: *Token, format: string, arguments: .. Any) {
    report_parse_error(lexer, token.l0, token.c0, format, ..arguments);
} @PrintLike

report_detail :: (lexer: *Lexer, format: string, arguments: .. Any) {
    report_detail(lexer, lexer.current_line_number, lexer.current_character_index, format, ..arguments);
} @PrintLike

report_parse_error :: (lexer: *Lexer, line: s32, col: s32, format: string, arguments: .. Any) {
    // @Cleanup: Move this function, make it user-overridable.
    message := tprint(format, ..arguments);
    log_error("%:%: %", line, col, message);
    lexer.reported_error = true;
}

report_detail :: (lexer: *Lexer, line: s32, col: s32, format: string, arguments: .. Any) {
    // @Cleanup: Move this function, make it user-overridable.
    message := tprint(format, ..arguments);
    log("%:%: %", line, col, message);
}

get_hex_digit :: (lexer: *Lexer, type: Hex_Digit_Type) -> (value: u8, success: bool) {
    c := peek_next_character(lexer);

    if      (c >= #char "a") && (c <= #char "f") { eat_character(lexer); return cast(u8)(10 + c - #char "a"), true; }
    else if (c >= #char "A") && (c <= #char "F") { eat_character(lexer); return cast(u8)(10 + c - #char "A"), true; }
    else if (c >= #char "0") && (c <= #char "9") { eat_character(lexer); return cast(u8)(c - #char "0"), true; }

    report_parse_error(lexer, "A hex digit is required here.\n");

    if type == {
    case .ASCII_8_BIT;
        report_detail(lexer, "\\x must be followed by exactly two hex digits.\n");
    case .UNICODE_16;
        report_detail(lexer, "\\u must be followed by exactly four hex digits.\n");
    case .UNICODE_32;
        report_detail(lexer, "\\U must be followed by exactly eight hex digits.\n");
    }

    return 0, false;
}

get_decimal_digit :: (lexer: *Lexer) -> s32 {
    c := peek_next_character(lexer);

    if (c >= #char "0") && (c <= #char "9") {
        eat_character(lexer);
        return c - #char "0";
    }

    report_parse_error(lexer, "A decimal digit is required here.\n");
    report_detail(lexer, "\\d must be followed by exactly three decimal digits.\n");

    return -1;
}

set_end_of_token :: (lexer: *Lexer, token: *Token) {
    token.l1 = lexer.current_line_number;
    token.c1 = lexer.current_character_index;
}

unwind_one_character :: (lexer: *Lexer) {
    assert(lexer.input_cursor != 0);
    lexer.input_cursor -= 1;
    lexer.current_character_index -= 1;
}


continues_identifier :: (c: s32) -> bool {
    return is_alnum(xx c) || c == #char "_" || c == #char "-" || c == #char "." || c == #char "/";
}

starts_number :: (c: s32) -> bool {
    return is_digit(cast(u8) c);
}

get_unused_token :: (lexer: *Lexer) -> *Token {
    assert(lexer.num_incoming_tokens < MAX_CONCURRENT_TOKENS);

    index := (lexer.token_array_cursor + lexer.num_incoming_tokens) & (MAX_CONCURRENT_TOKENS - 1);
    result := *lexer.tokens[index];

    result.l0            = lexer.current_line_number;
    result.c0            = lexer.current_character_index;
    result.type          = .ERROR;
    result.value_flags   = 0;
    result.preceeding_whitespace = lexer.preceeding_whitespace;

    return result;
}

parse_ident :: (lexer: *Lexer, result: *Token) -> string {
    builder: String_Builder;
    while 1 {
        c := peek_next_character(lexer);
        if !continues_identifier(c) break;

        eat_character(lexer);
        append(*builder, cast(u8) c);
    }

    set_end_of_token(lexer, result);

    return builder_to_string(*builder);
}

check_for_keyword :: (token: *Token) -> Token_Type {  // Returns Token_Type 0 if it is not a keyword.
    return 0;
}

make_ident_or_keyword :: (lexer: *Lexer) -> *Token {
    result := get_unused_token(lexer);
    result.type = .IDENT;

    name := parse_ident(lexer, result);
    result.string_value = name;

    set_end_of_token(lexer, result);

    keyword_type := check_for_keyword(result);
    if keyword_type result.type = keyword_type;

    return result;
}

make_string_constant :: (lexer: *Lexer, end_char: s16) -> *Token {
    result := get_unused_token(lexer);
    result.type = .STRING;

    eat_character(lexer);  // We only get here if we saw a single quote.

    builder: String_Builder;
    while 1 {
        c := peek_next_character(lexer);
        eat_character(lexer);

        if c == end_char {
            break;
        }

		if c == -1 {
			report_parse_error(lexer, "End of file during string constant!\n");
			break;
		}

        if c == #char "\n" {
            report_parse_error(lexer, "Newline in string constant!\n");
            break;
        }

        if c == #char "\\" {
            // @Robustness: add support for more escapes sequences

            next := peek_next_character(lexer);
            if next == #char "n" {
                c = #char "\n";
                eat_character(lexer);
            } else if next == #char "r" {
                c = #char "\r";
                eat_character(lexer);
            } else if next == #char "t" {
                c = #char "\t";
                eat_character(lexer);
            } else if next == #char "0" {
                c = 0;
                eat_character(lexer);
            } else if next == #char "e" {
                c = 0x1B;
                eat_character(lexer);
            } else if next == #char "x" {
                eat_character(lexer);
                // If get_hex_digit failed, we issued an error,
                // so we don't worry about the value of c in that case.
                high := get_hex_digit(lexer, .ASCII_8_BIT);
                low  := get_hex_digit(lexer, .ASCII_8_BIT);
                c = cast(s16)(high * 16 + low);
            } else if next == #char "d" {
                eat_character(lexer);
                // get_decimal_digit returns -1 on failure. If so, we issued an error,
                // so we don't worry about the value of c.
                high := get_decimal_digit(lexer);
                if high >= 0 {
                    middle := get_decimal_digit(lexer);
                    if middle >= 0 {
                        low := get_decimal_digit(lexer);
                        if low < 0  low = 0;
                        c = cast(s16)(high * 100 + middle * 10 + low);
                        if c > 255 {
                            l0 := lexer.current_line_number;
                            l1 := l0;
                            c0 := lexer.current_character_index - 3;
                            c1 := lexer.current_character_index;
                            // @Cleanup report_error(*lexer, l0, c0, l1, c1, lexer.active_load, "Decimal value of %d exceeds the limit of 255.\n", c);
                            lexer.reported_error = true;  // @Hack
                        }
                    }
                }
            } else if (next == #char "u") || (next == #char "U") {
                eat_character(lexer);

                num_digits: s32 = 4;
                type := Hex_Digit_Type.UNICODE_16;
                if next == #char "U" {
                    num_digits = 8;
                    type = .UNICODE_32;
                }

                value: u32;
                for i: 0..num_digits-1 {
                    digit, success := get_hex_digit(lexer, type);
                    if !success break;

                    value <<= 4;
                    value += digit;
                }

                LEN_MAX :: 4;
                buf: [LEN_MAX] u8;

                s: string;
                s.data = buf.data;

                character_utf32_to_utf8(value, *s);
                append(*builder, s);

                continue;  // NOTE: Do not fall through to the bottom.
            } else if next == end_char {
                c = end_char;
                eat_character(lexer);
            } else if next == #char "\\" {
                c = #char "\\";
                eat_character(lexer);
            } else if next == #char "%" {
                c = 31;
                eat_character(lexer);
            } else {
                // @Cleanup reporinterp.report(REPORT_WARNING, lexer, null, "Unknown escape sequence '\\%c' in string constant!", next);
                c = next;
                eat_character(lexer);
            }
        }

        // NOTE: In the case of Unicode characters, we continue
        // rather than falling through to the bottom, so don't depend
        // on that!
        append(*builder, cast(u8) c);
    }

    append(*builder, 0);  // Zero-terminate the string!

    data := builder_to_string(*builder);
    data.count -= 1;   // Don't count the zero-termination in the length.

    if data {
        result.string_value = data;
    } else {
        // :EmptyStringLiteral
        // Later stages of the compiler require string literals to have null data pointers,
        // so let's start early.
        result.string_value = "";
    }

    set_end_of_token(lexer, result);

    return result;
}

make_one_character_token :: (lexer: *Lexer, c: Token_Type) -> *Token {
    // Should be called after eat_character. We subtract 1 from the
    // starting character index to account for that.  @Speed

    result := get_unused_token(lexer);
    result.type = c;
    result.c0 -= 1;

    set_end_of_token(lexer, result);

    return result;
}

count_herestring_lines :: (lexer: *Lexer, token: *Token) -> s64 {
    line := token.l1;
    assert(line != -1);
    assert(line >= lexer.previous_token_line_number);

    net_lines := 0;
    if line > lexer.previous_token_line_number {
        net_lines = (token.l1 - token.l0) + 1;
        lexer.nonblank_lines_processed += net_lines + 1;  // Extra +1 for herestring terminator.
        lexer.previous_token_line_number = line + 1;  // +1 for herestring terminator.
    }

    return net_lines;
}

eat_token :: (lexer: *Lexer) {
    assert(lexer.num_incoming_tokens > 0);

    assert((MAX_CONCURRENT_TOKENS & (MAX_CONCURRENT_TOKENS - 1)) == 0);  // Assert that it's a power of two.

    {  // @Simplify: a herestring is the only thing that can be multiline right now (I think), and it is handled in count_herestring_lines!
        token := *lexer.tokens[lexer.token_array_cursor];
        line := token.l1;
        assert(line != -1);
        assert(line >= lexer.previous_token_line_number);

        if line > lexer.previous_token_line_number {
            lexer.nonblank_lines_processed += (token.l1 - token.l0) + 1;
            lexer.previous_token_line_number = line;
        }
    }

    lexer.num_incoming_tokens -= 1;
    lexer.token_array_cursor = (lexer.token_array_cursor + 1) & (MAX_CONCURRENT_TOKENS - 1);
}

check_for_equals :: (lexer: *Lexer, c: Token_Type, augmented: Token_Type, eat := true, subtractor: s32 = 0) -> *Token {
    // subtractor is the base token width minus one, for ... reasons ... @Cleanup.
    result: *Token;
    if eat eat_character(lexer);

    next := peek_next_character(lexer);
    if next == #char "=" {
        eat_character(lexer);
        result = make_one_character_token(lexer, augmented);
        result.c0 -= (subtractor + 1);
    } else {
        result = make_one_character_token(lexer, c);
        result.c0 -= subtractor;
    }

    return result;
}

//
// @Robustness: We might want to modify eat_input_due_to_block_comment so that
// characters in front of comment items need to be clear... e.g. right now it considers
// the string "/////*" to be a nested open-comment... not sure if we want that.
//
eat_input_due_to_block_comment :: (lexer: *Lexer) {
    comment_depth: s32 = 1;

    while comment_depth {
        c := peek_next_character(lexer);

        if c == -1 { // End of input!
            report_parse_error(lexer, "End of input from within a comment.\n");  // XXX Do a real error message here...
            return;
        }

        if c == #char "/" {
            eat_character(lexer);
            c := peek_next_character(lexer);
            if c == #char "*" {
                eat_character(lexer);
                comment_depth += 1;
            }
        } else if c == #char "*" {
            eat_character(lexer);
            c := peek_next_character(lexer);
            if c == #char "/" {
                eat_character(lexer);
                comment_depth -= 1;
            }
        } else {
            eat_character(lexer);
        }
    }
}

eat_until_newline :: (lexer: *Lexer) {
    // Eat until newline or end-of-input or zero
/*
#if USE_SIMD
    __m128i newline = _mm_set1_epi8('\n";
    while (lexer.input.count - lexer.input_cursor >= LEXER_SIMD_WIDTH) {
        __m128i characters = _mm_loadu_si128  ((__m128i *)(lexer.input.data + lexer.input_cursor));
        __m128i test       = _mm_cmpeq_epi8   (characters, newline);
        int     mask       = _mm_movemask_epi8(test);
        if (mask) {
            // We found a newline.
            auto advance = _tzcnt_u32(mask) + 1;  // +1 for the newline.
            lexer.input_cursor += advance;
            lexer.current_character_index = 1;
            lexer.current_line_number += 1;
            lexer.total_lines_processed += 1;
            return;
        } else {
            lexer.input_cursor            += 16;
            lexer.current_character_index += 16;
        }
    }

    if (lexer.input_cursor == lexer.input.count) return;
#endif // USE_SIMD
*/

    c: s32;
    while 1 {
        c = peek_next_character(lexer);
        if c == 0 break;
        if c == #char "\n" break;
        if c == -1 break;
        eat_character(lexer);
    }
}

compose_new_token :: (lexer: *Lexer) -> *Token {
    while 1 {
        // We used to recurse by calling compose_new_token further, but that is
        // not so great  -= 1 at least in theory you could compose an input that
        // would cause a stack overflow. So instead, we loop, and return
        // when we find a good token.

        c := peek_next_character(lexer);

        lexer.preceeding_whitespace = 0;
        start := lexer.current_character_index;
        while (c != -1) && is_space(cast(u8) c) {
            if c == #char "\n" {
                lexer.preceeding_whitespace = 0;
            } else {
                lexer.preceeding_whitespace += 1;
            }
            eat_character(lexer);
            c = peek_next_character(lexer);
        }

        if c == -1 {
            return make_one_character_token(lexer, .END_OF_INPUT);
        }

        if starts_identifier(cast(u8) c) {
            return make_ident_or_keyword(lexer);
        }

        if c == #char "." {
            // Check for double-dot... but if it is not specifically double-dot
            // then it might be a single-dot, and it might be a floating-point
            // number...

            eat_character(lexer);
            c = peek_next_character(lexer);
            if c == #char "." {
                eat_character(lexer);
                c = peek_next_character(lexer);
                if c == #char "." {
                    eat_character(lexer);
                    token := make_one_character_token(lexer, .TRIPLE_DOT);
                    token.c0 -= 2; // Include the previous dots
                    return token;
                } else {
                    unwind_one_character(lexer);  // Get the '.' back.
                    return make_one_character_token(lexer, #char ".");
                }
            }

            if is_digit(cast(u8) c) {
                unwind_one_character(lexer);  // Get the '.' back.
                return make_ident_or_keyword(lexer);
            }

            return make_one_character_token(lexer, #char ".");
        }

        if starts_number(cast(u8) c) {
            return make_ident_or_keyword(lexer);
        }

        result: *Token;
        if c == {
        // case #char "(";  #through;
        // case #char ")";  #through;
        // case #char ";";  #through;
        case #char "[";  #through;
        case #char "]";  #through;
        case;
            eat_character(lexer);
            result = make_one_character_token(lexer, cast(Token_Type) c);
        case 0xE2;
            orig_pos := lexer.input.data + lexer.input_cursor;

            u, consumed_length, conv_result := character_utf8_to_utf32(orig_pos, lexer.input.count - lexer.input_cursor);

            if conv_result == .CONVERSION_OK {
                lexer.input_cursor += consumed_length;

                if u == {
                case 0x200B;
                    // @Cleanup interp.report(REPORT_WARNING, lexer, null, "Illegal Unicode zero-width space found in the program text. This could be a problem with pasting the data from another source.\n");
                    return compose_new_token(lexer);
                case 0x2066; #through;
                case 0x2067; #through;
                case 0x2068; #through;
                case 0x202A; #through;
                case 0x202B; #through;
                case 0x202D; #through;
                case 0x202E; #through;
                case 0x2069; #through;
                case 0x202C;
                    // @Cleanup interp.report(REPORT_WARNING, lexer, null, "Illegal Unicode directional-formatting character found in the program text. This could be a problem with pasting the data from another source.\n");
                    return compose_new_token(lexer);
                case;
                    report_parse_error(lexer, "Unicode characters in this range are not supported by the parser at lexer time. (Offending character code was U+%x.\n", u);
                    return compose_new_token(lexer);
                }

                result = make_one_character_token(lexer, cast(Token_Type) u);
            } else {
                report_parse_error(lexer, "Attempted to parse a Unicode character here, but was unable to read a whole valid character.\n");
                result = make_one_character_token(lexer, 0);  // @Cleanup?
            }
        case #char "#";
            eat_until_newline(lexer);
            continue;
        case #char "-"; {
            eat_character(lexer);

            next := peek_next_character(lexer);
            if next == #char "-" {
                eat_character(lexer);
                next = peek_next_character(lexer);

                if next == #char "-" {
                    eat_character(lexer);
                    result = make_one_character_token(lexer, .TRIPLE_MINUS);
                    result.c0 -= 2;
                    return result;
                } else {
                    unwind_one_character(lexer);
                }
            }
            result = make_one_character_token(lexer, cast(Token_Type) c);
        }
        case #char "!";
            eat_character(lexer);
            result = make_one_character_token(lexer, cast(Token_Type) c);
        case #char ",";
            eat_character(lexer);
            result = make_one_character_token(lexer, cast (Token_Type) c);
        case #char "\""; #through;
        case #char "'";
            result = make_string_constant(lexer, c);
        case 0xc2;
            eat_character(lexer);
            other_c := peek_next_character(lexer);
            if other_c == 0xa0 {  // Unicode non-breaking space.
                eat_character(lexer);
                continue;
            }

            result = make_one_character_token(lexer, cast(Token_Type) c);
        }

        assert(result != null);
        return result;
    }
}

is_non_newline_whitespace :: (c: s16) -> bool {
    return c == #char " ";
}

peek_token :: (lexer: *Lexer, lookahead_index: s32) -> *Token {
    assert(lookahead_index <  MAX_CONCURRENT_TOKENS);
    assert(lookahead_index >= 0);

    if lookahead_index == 0 return peek_next_token(lexer);

    while lexer.num_incoming_tokens <= lookahead_index {
		if lexer.reported_error {
			eof := *lexer.eof_token;
            set_end_of_token(lexer, eof);
            eof.l0 = eof.c0;
            eof.l1 = eof.c1;
            return eof;
		}

        compose_new_token(lexer);
        lexer.num_incoming_tokens += 1;
    }

    index := (lexer.token_array_cursor + lookahead_index) & (MAX_CONCURRENT_TOKENS - 1);
    return *lexer.tokens[index];
}

has_a_big_exponent :: inline (value: float64) -> bool {
    // Return true if this is exponent too big to fit into float32.
    union {
        _f64: float64;
        _s64: s64;
    };

    _f64 = value;

    exponent := (_s64 >> 52) & 0x7ff;

    if (exponent != 0) && (exponent != 0x7ff) {
        exponent -= 1023;
        return (exponent > 127) || (exponent < -126);
    }

    return false;
}

#import "Pool";
#import "Unicode";
