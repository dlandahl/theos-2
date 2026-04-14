
Text_Display :: struct {
    cursor_x: int; // Character index.
    cursor_y: int; // Character index.

    font: Netpbm_Image;

    spinlock: Spinlock(.IRQ);

    output_buffer: [] u32; // Virtual memory ring buffer for rendered pixels. Includes the X margin but not Y.

    initialized: bool;


    line_spacing :: 5;   // Number of pixels between the bottom of one character cell, and the top of the next one down.
    char_width   :: 9;
    char_height  :: 16;
    margin       :: 10;

    line_height  :: char_height + line_spacing;

    // The lowest and highest ASCII codes that are included in the font bitmap.
    first_code   :: #char " ";
    last_code    :: #char "~";
}

init_text_display :: () {
    using global.text_display_state;

    font = parse_netpbm(font_file);

    fb := *global.framebuffer;

    frame_buffer_size := fb.y_resolution * fb.stride * size_of(u32);
    frame_buffer_size  = align(0x20_0000, frame_buffer_size);

    // Create a circular virtual mapping for the text rendering buffer. That way we don't need to re-render all the text when scrolling.
    virtual := cast(*void) alloc_block(*global.virtual_large_page_allocator, frame_buffer_size * 2);

    pages_needed     := frame_buffer_size / 0x20_0000;
    pages            := NewArray(pages_needed, u64,, temp);

    for* pages it.* = allocate_large_page();

    for VM_Iterator.{virtual, pages_needed * 1024} {
        if it.level == 1 {
            page_index := it_index / 512;

            it.value  = pages[page_index % pages_needed];
            it.flags |= .PRESENT | .READ_WRITE | .PAGE_SIZE;

            continue;
        }

        if it.flags & .PRESENT == 0 {
            it.value  = get_4k_page();
            it.flags |= .PRESENT | .READ_WRITE;
        }
    }

    output_buffer.data  = virtual;
    output_buffer.count = pages_needed * 0x20_0000 / size_of(u32);

    memset(output_buffer.data, 0, output_buffer.count * size_of(u32));
    
    initialized = true;
}

font_file :: #run,host -> [] u8 {
    image := read_entire_file("font.pgm");
    return add_global_data(cast([] u8) image, .READ_ONLY);
}

go_to_next_row :: () #no_context {
    using global.text_display_state;

    defer {
        cursor_y += 1;
        cursor_x = 0;
    }

    // If a row scrolled off the top of the screen, clear it to black, for when the buffer wraps around.
    // Maybe this is inefficient, and we should detect at what point to do a larger clear, rather than
    // clearing per line. But this will need to be changed anyway when we have manual user scrolling. In the
    // future we'll keep one screen above and below the current scroll position alive, for fast scrolling.

    fb := global.framebuffer;
    rows_on_the_screen := (fb.y_resolution - 2 * margin) / line_height;

    if cursor_y < rows_on_the_screen return;

    row_to_clear         := cursor_y - rows_on_the_screen;
    first_pixel_to_clear := row_to_clear * line_height * fb.stride;
    first_pixel_to_clear &= (output_buffer.count - 1);

    pixels_per_row       := line_height * fb.stride;

    memset(output_buffer.data + first_pixel_to_clear, 0, pixels_per_row * size_of(u32));
}

draw_text :: (text: string) #no_context {
    using global.text_display_state;

    if !initialized return;

    acquire(*spinlock); // Todo: Don't do it this way.

    framebuffer := global.framebuffer;

    ringbuffer_modulo_mask := output_buffer.count - 1;

    for text {
        if it == #char "\n" {
            go_to_next_row();
            continue;
        }

        if it == #char "\r" continue;

        if it < first_code || it > last_code {
            it = #char "?";
        }

        max_x := (cursor_x + 1) * char_width + 2 * margin;

        if max_x >= framebuffer.x_resolution {
            go_to_next_row();
        }

        screen_x := cursor_x * char_width  + margin;
        screen_y := cursor_y * line_height; // No Y margin because it would mess up the ring buffer. It is added when blitting to the frame buffer.

        source_top_left := char_width * (cast(int) it - first_code);  // First pixel index into the font bitmap for this character.
        target_top_left := screen_x + screen_y * framebuffer.stride;  // First pixel index into the output ringbuffer for this X/Y character cell.

        for char_y: 0..char_height-1 {

            // Start pixel of the current pixel row of the current character, in the font bitmap and output ringbuffer.
            current_row_font    := source_top_left + char_y * font.width;
            current_row_screen  := target_top_left + char_y * framebuffer.stride;

            for char_x: 0..char_width-1 {

                pixel_in_font   := current_row_font   + char_x;
                pixel_on_screen := current_row_screen + char_x;

                value := cast(u32) font.data[pixel_in_font];

                pixel_color := value | (value << 8) | (value << 16) | (value << 24);
                pixel_color |= 0xff * cast(u32) global.bluescreen_occurred;

                output_buffer[pixel_on_screen & ringbuffer_modulo_mask] = pixel_color;
            }
        }

        cursor_x += 1;
    }

    flush_screen();

    release(*spinlock);
}

flush_screen :: () #no_context {
    using global.text_display_state;
    fb := global.framebuffer;

    // Copy the text buffer to the hardware buffer.

    pixels_per_character_row := line_height * fb.stride;

    // First pixel index to copy.
    copy_start := cursor_y * pixels_per_character_row;         // End of the buffer is the current row x pixels per row.
    copy_start -= fb.stride * (fb.y_resolution - 2 * margin);  // Start one screen before the end of the buffer.

    if copy_start < 0 then copy_start = 0;
    copy_start %= output_buffer.count;

    copy_count       := fb.stride * (fb.y_resolution - 2 * margin);
    copy_destination := fb.hardware_buffer + margin * fb.stride;

    memcpy(copy_destination, output_buffer.data + copy_start, copy_count * size_of(u32)); // Todo: non-temporal stores might be faster.
}

Netpbm_Image :: struct {
    width: int;
    height: int;

    type: enum {
        UNINITIALIZED :: 0;
        ASCII_BITMAP;
        ASCII_GRAYMAP;
        ASCII_PIXMAP;
        BITMAP;
        GRAYMAP;
        PIXMAP;
    }

    data: *u8;
}

parse_netpbm :: (file: [] u8) -> Netpbm_Image {
    buffer := file.data;
    assert(buffer[0] == #char "P");

    image: Netpbm_Image;
    image.type = xx (buffer[1] - #char "0");
    assert(image.type == .GRAYMAP || image.type == .PIXMAP);

    is_whitespace :: (char: u8) -> bool {
        return char == 0x20
            || char == 0x09
            || char == 0x0a
            || char == 0x0b
            || char == 0x0c
            || char == 0x0d
            || char == #char "#";
    }

    skip_whitespace_and_comments :: () #expand {
        while is_whitespace(buffer[`cursor]) {
            if buffer[`cursor] == #char "#" {
                while buffer[`cursor] != 0xa `cursor += 1;
            }
            cursor += 1;
        }
    }

    parse_int :: () -> int #expand {
        digit := buffer[`cursor];
        result: int;

        while !is_whitespace(digit) {
            assert(digit >= #char "0" && digit <= #char "9");
            result *= 10;
            result += digit - #char "0";
            `cursor += 1;
            digit = buffer[`cursor];
        }
        return result;
    }

    cursor := 2;
    skip_whitespace_and_comments();

    image.width = parse_int();

    skip_whitespace_and_comments();

    image.height = parse_int();

    skip_whitespace_and_comments();

    max_value := parse_int();
    assert(max_value == 255);

    skip_whitespace_and_comments();

    image.data = buffer + cursor;

    return image;
}
