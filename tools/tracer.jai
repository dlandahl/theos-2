
TRACE_INCLUDE_RUNTIME_CODE :: false;
#load "../kernel/trace.jai";

#import "GetRect";

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

parse_trace_data :: () {
    trace_file := read_entire_file("../logs/vbox_trace.bin");

    start := find_index_from_left(trace_file, KERNEL_TRACE_MAGIC_STRING);
    if start == -1 {
        // Todo.
        assert(false);
    }

    start += KERNEL_TRACE_MAGIC_STRING.count;

    trace_file.data  += start;
    trace_file.count -= start;

    header := cast(*Trace_Header)trace_file.data;

    trace_data.num_cores     = header.num_cpu_cores;
    trace_data.tsc_frequency = header.tsc_frequency;

    string_table := *header.string_table;

    array_resize(*trace_data.threads, header.num_threads);

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

    parse_trace_data();

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

draw_one_frame :: (dt: float) {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!

    bg_col := my_theme.background_color;
    Simp.clear_render_target(bg_col.x, bg_col.y, bg_col.z, 1);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);


    button_theme := my_theme.button_theme;
    button_theme.font = button_font;
    button_theme.enable_variable_frame_thickness = true;
    // 'k' is some resolution-adjusting unit of distance. Right now it is
    // 1/10 of the screen height, so, 108 pixels at 1920x1080.
    k := window_height * .1;
    r := get_rect(k, window_height - .5*k, 22*k, k);

    for trace_data.entries {
        r.y -= window_height / 28;
        label_theme: Label_Theme;
        label_theme.alignment = .Left;
        label_theme.text_color = .{.5, .5, .5, 1};
        label_theme.font = button_font;

        text := tprint("%", it);
        label(r, text, *label_theme);
    }

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

    pixel_height := window_height / 24;
    my_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);

    pixel_height /= 2;
    button_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(button_font != null);

    pixel_height = window_height / 7;
    title_font = Simp.get_font_at_size("data", "Miama.otf", pixel_height);

    pixel_height = window_height / 30;
    story_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
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
