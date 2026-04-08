
Text_Drawing_State :: struct {
    cursor_x: int;
    cursor_y: int;

    font: Netpbm_Image;

    spinlock: Spinlock(.IRQ);

    font_loaded: bool;
}

font_file :: #run,host -> [] u8 {
    image := read_entire_file("font.pgm");
    return add_global_data(cast([] u8) image, .READ_ONLY);
}

draw_text :: (text: string) #no_context {
    using global.text_drawing_state;

    if !font_loaded return;

    acquire(*spinlock);

    line_spacing :: 5;   // Number of pixels between the bottom of one character cell, and the top of the next one down.
    char_width   :: 9;
    char_height  :: 16;
    margin       :: 10;

    line_height  :: char_height + line_spacing;

    // The lowest and highest ASCII codes that are included in the font bitmap.
    first_code   :: #char " ";
    last_code    :: #char "~";

    framebuffer := global.framebuffer;

    for text {
        if it == #char "\n" {
            cursor_y += 1;
            cursor_x = 0;
            continue;
        }

        if it == #char "\r" continue;

        if it < first_code || it > last_code {
            it = #char "?";
        }

        max_x := (cursor_x + 1) * char_width + margin * 2;

        if max_x >= framebuffer.x_resolution {
            cursor_y += 1;
            cursor_x = 0;
        }

        screen_x := cursor_x * char_width  + margin;
        screen_y := cursor_y * line_height + margin;

        while screen_y + line_height + margin > framebuffer.y_resolution {
            source := (line_height + margin) * framebuffer.stride;
            target := margin * framebuffer.stride;

            count := cursor_y * line_height * framebuffer.stride;

            // Inefficient when printing strings with many newlines. Todo: Circular buffer.
            memcpy(framebuffer.software_buffer + target, framebuffer.software_buffer + source, count * size_of(u32));

            if global.bluescreen_occurred {
                for 0..count-1 {
                    framebuffer.software_buffer[target + it] |= 0xff;
                }
            }

            cursor_y -= 1;
            screen_y -= line_height;
        }

        source_top_left := char_width * (cast(int) it - first_code);
        target_top_left := screen_x + screen_y * framebuffer.stride;

        for char_y: 0..char_height-1 {
            for char_x: 0..char_width-1 {

                pixel_in_font   := source_top_left + char_x + char_y * font.width;
                pixel_on_screen := target_top_left + char_x + char_y * framebuffer.stride;

                value := cast(u32) font.data[pixel_in_font];

                pixel_color := value | (value << 8) | (value << 16) | (value << 24);
                if global.bluescreen_occurred pixel_color |= 0xff;

                red   := cast(int) (0xa0 * (1.0 / framebuffer.y_resolution) * (screen_y + char_y));
                green := cast(int) (0xa0 * (1.0 / framebuffer.x_resolution) * (screen_x + char_x));

                framebuffer.software_buffer[pixel_on_screen] = pixel_color;
            }
        }

        cursor_x += 1;
    }

    flush_screen();

    release(*spinlock);
}

flush_screen :: () #no_context {
    fb := global.framebuffer;
    size_bytes := fb.y_resolution * fb.stride * size_of(u32);

    memcpy(fb.hardware_buffer, fb.software_buffer, size_bytes);
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
