
TRACE_INCLUDE_RUNTIME_CODE :: false;
#load "../kernel/trace.jai";

#import "GetRect";
#import "File_Utilities";

current_time: float64;
last\  _time: float64;

SCALE :: 1;

my_window: Window_Type;
window_width  : s32 = 1920*SCALE;
window_height : s32 = 1080*SCALE;

current_theme: s32 = xx Default_Themes.Default;
my_theme: Overall_Theme;

trace_data: Trace_Data;

Trace_Data :: struct {
    num_cores: int;
    tsc_frequency: u64;

    threads: [..] string;
    entries: [..] Trace_Entry;
}

parse_trace_data :: (_trace_file: string) {
    trace_file := _trace_file;
    trace_data = .{};

    start := find_index_from_left(trace_file, KERNEL_TRACE_MAGIC_STRING);
    if start == -1 {
        return;
    }

    start += KERNEL_TRACE_MAGIC_STRING.count;

    trace_file.data  += start;
    trace_file.count -= start;

    header := cast(*Trace_Header)trace_file.data;

    trace_data.num_cores     = header.num_cpu_cores;
    trace_data.tsc_frequency = header.tsc_frequency;

    array_resize(*trace_data.threads, header.num_threads);
    string_table := *header.string_table;

    for 0..header.num_threads-1 {
        entry := cast(*Trace_Header.String_Table_Entry)string_table;

        s: string;
        s.data = *entry.data;
        s.count = entry.name_length;

        trace_data.threads[it] = s;
        log("Found thread %.", s);

        string_table = *entry.data + entry.name_length;
    }

    array_resize(*trace_data.entries, header.num_trace_entries);

    dest  := trace_data.entries.data;
    src   := string_table;
    bytes := header.num_trace_entries * size_of(Trace_Entry);
    memcpy(dest, src, bytes);
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "A Window");
    #if OS == .WINDOWS {
        // @Feature: Add user-specific typelist support.
        Windows.DragAcceptFiles(my_window, cast(Windows.BOOL) true);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
        X11.enable_drag_and_drop(my_window, typelist);
    } else #if OS == .MACOS {
        #import "Objective_C";
        #import "Objective_C/AppKit";
        types := NSArray(NSPasteboardType).arrayWithObject(NSPasteboardTypeFileURL);
        NSView.registerForDraggedTypes(my_window, types);
    }

    Simp.set_render_target(my_window);

    my_init_fonts();
    ui_init();

    file_name = "../logs/vbox_trace.bin";
    exists = file_exists(file_name);

    if exists {
        trace_file := read_entire_file(file_name);
        parse_trace_data(trace_file);
    }

    quit := false;
    while !quit {
        current_time = seconds_since_init();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit my_init_fonts();
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            getrect_handle_event(event);

            if event.type == {
              case .KEYBOARD;
                if event.key_pressed && event.key_code == .ESCAPE {
                    active_widget_deactivate_all();
                }
            }
        }

        draw_one_frame(dt);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

scroll_position: float;
file_name: string;
exists: bool;

draw_one_frame :: (dt: float) {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!
    my_theme.button_theme.font = button_font;

    // bg_col := my_theme.background_color;
    Simp.clear_render_target(.15, .11, .11, 1);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    r := get_rect(0, 0, xx width, xx height);
    r = shrink(r, 25);

    file_load_rect, slidable_rect := cut_top(r, 50);
    {
        // File loading section.

        file_load_rect.h -= 20;
        file_load_rect.y += 20;

        button_rect:, file_load_rect = cut_left(file_load_rect, 250);
        button_rect.w -= 10;

        ti := my_theme.text_input_theme;
        ti.text_color = ifx exists then my_theme.text_input_theme.text_color else .{1, 0, 0, 1};
        ti.text_color_pressed = ti.text_color;
        ti.font = button_font;
        action, new_text, state := text_input(file_load_rect, file_name, *ti);

        if action == .TEXT_MODIFIED {
            exists = file_exists(state.text);
            file_name = state.text;
        }

        if button(button_rect, "Load File", *my_theme.button_theme) && exists {
            trace_file := read_entire_file(file_name);
            parse_trace_data(trace_file);
        }
    }

    st := my_theme.slidable_region_theme;
    st.divider_thickness_type = .ABSOLUTE_FROM_THEME_FIELD;
    st.divider_thickness = 10;
    st.first_background.shape.rounding_flags = 0;
    st.second_background.shape.rounding_flags = 0;

    slide_state, left_rect, right_rect := slidable_region(slidable_rect, *st);

    {
        // Vertical trace events view (left slide region).

        st := my_theme.scrollable_region_theme;
        st.region_background.shape.rounding_flags = 0;
        stn := *st.scrollbar_nib_theme;
        // stn.enable_variable_frame_thickness = false;
        // stn.rectangle_shape.frame_thickness_type = .ABSOLUTE_FROM_THEME_FIELD;
        // stn.rectangle_shape.frame_thickness = 3;
        // stn.rectangle_shape.roundedness_type = .ABSOLUTE_FROM_THEME_FIELD;
        // stn.rectangle_shape.roundedness = 8;
        // stn.frame_thickness_flash = .01;

        state, scroll_rect := begin_scrollable_region(left_rect, *st);

        state.bar_rect.w = 25; // Scroll bar width is hardcoded to be relative to render target height, in GetRect. This means we can't easily make it fit into the parent area correctly.

        row_height := 18.0;
        row_rect := scroll_rect;
        row_rect.h = row_height - 2;
        row_rect.y += scroll_position;
        row_rect.y += scroll_rect.h;
        // row_rect.x += 5;
        // row_rect.w -= 5;

        for trace_data.entries {
            row_rect.y -= row_height;

            row_theme: = my_theme.button_theme;
            row_theme.alignment = .Left;
            row_theme.text_color = .{.75, .75, .75, 1};
            row_theme.font = button_font;
            row_theme.surface_color = .{};
            row_theme.frame_color = .{};

            button(row_rect, "", *row_theme, it_index);
            label_rect := row_rect;

            time_seconds := cast(float)it.tsc / cast(float)trace_data.tsc_frequency;

            text := tprint("%", formatFloat(time_seconds, trailing_width=3, zero_removal=.NO));
            label(label_rect, text, *row_theme.label_theme);

            label_rect.x += 75;

            text = tprint("%", it.tag, );
            label(label_rect, text, *row_theme.label_theme);

            label_rect.x += 200;

            text = tprint("%", trace_data.threads[it.user[0]-1]);
            label(label_rect, text, *row_theme.label_theme);

            label_rect.x += 125;

            text = tprint("->   %", trace_data.threads[it.user[1]-1]);
            label(label_rect, text, *row_theme.label_theme);
        }

        end_scrollable_region(state, row_rect.x, row_rect.y, *scroll_position);
    }

    switch_to_right_rect(slide_state);

    {
        // Draw CPU core tracks.
        for 0..trace_data.num_cores-1 {
            
        }
    }

    finish(slide_state);

    draw_popups();

    //
    // Swap buffers!
    //

    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
    if !working_directory_set {
        // So that we can load our font, set to path of running executable.
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);

        working_directory_set = true;
    }

    my_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", 64);
    assert(my_font != null);

    button_font = Simp.get_font_at_size("data", "FiraMono-Medium.ttf", 14);
    assert(button_font != null);

    title_font = Simp.get_font_at_size("data", "Miama.otf", 128);

    story_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", 16);
//    title_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
}

Font :: Simp.Dynamic_Font;

my_font:     *Font;
button_font: *Font;
title_font:  *Font;
story_font:  *Font;

working_directory_set := false;

Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "File";
#import "Basic";
#import "Math";
#import "System";
#import "String";

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}
