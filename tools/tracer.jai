
Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "Basic";
#import "GetRect";
#import "File_Utilities";
#import "File";
#import "Math";
#import "System";
#import "String";
#import "Bucket_Array";

#import "debug_info";
#import "executable_formats";

TRACE_INCLUDE_RUNTIME_CODE :: false;
#load "../kernel/trace.jai";

current_time: float64;
last\  _time: float64;

UI_SCALE := 2.0;

my_window: Window_Type;
window_width  : s32 = 1920;
window_height : s32 = 1080;

current_theme: s32 = xx Default_Themes.Default;
my_theme: Overall_Theme;

trace_data: Trace_Data;

Trace_Data :: struct {
    num_cores: int;
    tsc_frequency: u64;

    threads: [..] string;
    entries: [] Trace_Entry;
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

    array_resize(*trace_data.threads, header.num_threads+1);
    trace_data.threads[0] = "Early Boot";

    string_table := *header.string_table;

    for 0..header.num_threads-1 {
        entry := cast(*Trace_Header.String_Table_Entry)string_table;

        s: string;
        s.data = *entry.data;
        s.count = entry.name_length;

        trace_data.threads[entry.thread_id] = s;
        assert(entry.thread_id != 0);
        log("Found thread %. (id %)", s, entry.thread_id);

        string_table = *entry.data + entry.name_length;
    }

    trace_data.entries.data = string_table;
    trace_data.entries.count = header.num_trace_entries;

    array_resize(*show_hide_settings.cores,   trace_data.num_cores);
    array_resize(*show_hide_settings.threads, trace_data.threads.count);

    for* show_hide_settings.cores   it.* = true;
    for* show_hide_settings.threads it.* = true;
    for* show_hide_settings.tags    it.* = true;
}

debug_info: Debug_Info;

read_debug_info :: (kernel_file_name: string) {
    binary_file := read_entire_file(kernel_file_name);
    success, elf := parse_elf(binary_file, kernel_file_name);

    assert(success);

    if elf.debug_info_section && elf.debug_abbrev_section && elf.debug_line_section {
        info   := get_section_data(elf, elf.debug_info_section);
        abbrev := get_section_data(elf, elf.debug_abbrev_section);
        line   := get_section_data(elf, elf.debug_line_section);
        str    := get_section_data(elf, elf.debug_str_section);

        success &= apply_relocations(elf, elf.debug_line_section_index, line);
        success &= apply_relocations(elf, elf.debug_info_section_index, info);
        if !success {
            log("Failed to apply relocations.");
            return;
        }

        debug_info, success = parse_dwarf_debug_info(info, abbrev, line, str);
        if !success {
            log("Failed to parse debug info.");
            return;
        }
    } else {
        log("Failed to find debug sections in elf.");
    }
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "Kernel Event Viewer");
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

    trace_file_name = "../logs/qemu_trace.bin";
    trace_file_exists = file_exists(trace_file_name);

    if trace_file_exists {
        trace_file := read_entire_file(trace_file_name);
        parse_trace_data(trace_file);
    }

    kernel_file_name := "../.build/kernel";
    read_debug_info(kernel_file_name);

    // do_dwarf_lines(debug_info);

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
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            getrect_handle_event(event);

            if event.type == {
              case .KEYBOARD;
                if event.key_pressed {
                    if event.key_code == .ESCAPE {
                        active_widget_deactivate_all();
                    }

                    originally_selected_entry := selected_entry;

                    if event.key_code == .ARROW_UP {
                        while true {
                            if selected_entry == 0 {
                                selected_entry = originally_selected_entry;
                                break;
                            }
                            selected_entry -= 1;

                            entry := trace_data.entries[selected_entry];
                            if !show_hide_settings.cores  [entry.core_id] continue;
                            if !show_hide_settings.threads[entry.task_id] continue;
                            if !show_hide_settings.tags   [entry.tag]     continue;

                            update_highlighted_trace_entries();
                            break;
                        }
                    }
                    if event.key_code == .ARROW_DOWN {
                        while true {
                            if selected_entry == trace_data.entries.count-1 {
                                selected_entry = originally_selected_entry;
                                break;
                            }

                            selected_entry += 1;

                            entry := trace_data.entries[selected_entry];
                            if !show_hide_settings.cores  [entry.core_id] continue;
                            if !show_hide_settings.threads[entry.task_id] continue;
                            if !show_hide_settings.tags   [entry.tag]     continue;

                            update_highlighted_trace_entries();
                            break;
                        }
                    }

                    if event.key_code == #char "=" && event.ctrl_pressed {
                        UI_SCALE += 0.1;
                        my_init_fonts();
                    }
                    if event.key_code == #char "-" && event.ctrl_pressed {
                        UI_SCALE -= 0.1;
                        my_init_fonts();
                    }
                }
            }
        }

        draw_one_frame(dt);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

scroll_position: float;

trace_file_name: string;
trace_file_exists: bool;

selected_entry: int;
highlighted_trace_entries: [..] int;


show_hide_settings: struct {
    cores:   [..]bool;
    threads: [..]bool;
    tags:    [9]bool;
};

draw_one_frame :: (dt: float) {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!
    my_theme.button_theme.font = mono_font;

    // bg_col := my_theme.background_color;
    Simp.clear_render_target(.15, .11, .11, 1);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    r := get_rect(0, 0, xx width, xx height);
    r = shrink(r, 25*UI_SCALE);

    file_load_rect, main_region_rect := cut_top(r, 50*UI_SCALE);
    {
        // File loading section.

        file_load_rect.h -= 20*UI_SCALE;
        file_load_rect.y += 20*UI_SCALE;

        ti := my_theme.text_input_theme;
        ti.text_color = ifx trace_file_exists then my_theme.text_input_theme.text_color else .{1, 0, 0, 1};
        ti.text_color_pressed = ti.text_color;
        ti.font = mono_font;
        action, new_text, state := text_input(file_load_rect, trace_file_name, *ti);

        if action & .TEXT_MODIFIED {
            trace_file_exists = file_exists(state.text);
            trace_file_name = state.text;
        }

        if action & .ENTERED {
            trace_file := read_entire_file(trace_file_name);
            parse_trace_data(trace_file);
        }
    }

    visibility_options_rect, slidable_rect := cut_top(main_region_rect, 200*UI_SCALE);

    {
        row_width  := 225*UI_SCALE;
        row_height := 25*UI_SCALE;

        // Visibility options view.
        t := my_theme.label_theme;
        t.font = mono_font;
        t.alignment = .Left;
        
        ct := my_theme.checkbox_theme;
        ct.button_theme.label_theme = t;
        ct.text_color_selected = .{1, 0.9, 0.8, 1};
        ct.text_color          = .{.55, .55, .55, 1.0};
        ct.text_color_pressed  = .{1, 0.9, 0.8, 1};
        ct.surface_color_flash = .{1, 0.9, 0.8, 1};
        ct.surface_color_down  = .{1, 0.9, 0.8, 1};
        ct.button_color_selected   = .{1, 0.9, 0.8, 1};

        b := my_theme.text_input_theme.button_theme;
        b.surface_color = .{.08*.7, .208*.7, .236*.7, 1.0};
        b.label_theme.alignment = .Center;

        row_rect := visibility_options_rect;

        row_rect.y += row_rect.h - row_height;
        row_rect.h = row_height;
        row_rect.w = row_width;

        label(row_rect, "Show/Hide by Core", *t);

        {
            row_rect.y -= row_height;
            button_rect := shrink(row_rect, 2*UI_SCALE);
            button_rect.w -= 30*UI_SCALE;
            if button(button_rect, "All/None", *b) && show_hide_settings.cores.count {
                set := !show_hide_settings.cores[0];
                for* show_hide_settings.cores it.* = set;
            }
        }

        for 0..trace_data.num_cores-1 {
            row_rect.y -= row_height;

            if row_rect.y <= visibility_options_rect.y - visibility_options_rect.h + row_rect.h + 200*UI_SCALE {
                row_rect.y = visibility_options_rect.y;
                row_rect.y += visibility_options_rect.h - row_height * 2;
                row_rect.x += row_width;
            }

            if base_checkbox(row_rect, tprint("Core %", it), show_hide_settings.cores[it], *ct, it) {
                show_hide_settings.cores[it] = !show_hide_settings.cores[it];
            }
        }

        row_rect.y = visibility_options_rect.y;
        row_rect.y += visibility_options_rect.h - row_height;
        row_rect.x += row_width;

        label(row_rect, "Show/Hide by Thread", *t);

        {
            row_rect.y -= row_height;
            button_rect := shrink(row_rect, 2*UI_SCALE);
            button_rect.w -= 30*UI_SCALE;
            if button(button_rect, "All/None", *b) && show_hide_settings.threads.count {
                set := !show_hide_settings.threads[0];
                for* show_hide_settings.threads it.* = set;
            }
        }
        
        for 0..trace_data.threads.count-1 {
            row_rect.y -= row_height;

            if row_rect.y <= visibility_options_rect.y - visibility_options_rect.h + row_rect.h + 175*UI_SCALE {
                row_rect.y = visibility_options_rect.y;
                row_rect.y += visibility_options_rect.h - row_height * 2;
                row_rect.x += row_width;
            }

            if base_checkbox(row_rect, trace_data.threads[it], show_hide_settings.threads[it], *ct, it) {
                show_hide_settings.threads[it] = !show_hide_settings.threads[it];
            }
        }

        row_rect.y = visibility_options_rect.y;
        row_rect.y += visibility_options_rect.h - row_height;
        row_rect.x += row_width;

        label(row_rect, "Show/Hide by Tag", *t);

        {
            row_rect.y -= row_height;
            button_rect := shrink(row_rect, 2*UI_SCALE);
            button_rect.w -= 30*UI_SCALE;
            if button(button_rect, "All/None", *b) && show_hide_settings.tags.count {
                set := !show_hide_settings.tags[0];
                for* show_hide_settings.tags it.* = set;
            }
        }

        tag_info := type_info(Trace_Tag);

        for tag_info.names {
            row_rect.y -= row_height;

            if row_rect.y <= visibility_options_rect.y - visibility_options_rect.h + row_rect.h + 175*UI_SCALE {
                row_rect.y = visibility_options_rect.y;
                row_rect.y += visibility_options_rect.h - row_height * 2;
                row_rect.x += row_width;
            }

            if base_checkbox(row_rect, it, show_hide_settings.tags[it_index], *ct, it_index) {
                show_hide_settings.tags[it_index] = !show_hide_settings.tags[it_index];
            }
        }
    }

    st := my_theme.slidable_region_theme;
    st.divider_thickness_type = .ABSOLUTE_FROM_THEME_FIELD;
    st.divider_thickness = 10*UI_SCALE;
    st.first_background.shape.rounding_flags = 0;
    st.second_background.shape.rounding_flags = 0;
    st.initial_divider_position_type = .ABSOLUTE_FROM_THEME_FIELD;
    st.initial_divider_position = 500*UI_SCALE;

    slide_state, left_rect, right_rect := slidable_region(slidable_rect, *st);

    {
        // Vertical trace events view (left slide region).

        st := my_theme.scrollable_region_theme;
        st.region_background.shape.rounding_flags = 0;

        state, scroll_rect := begin_scrollable_region(left_rect, *st);

        state.bar_rect.w = 25*UI_SCALE; // Scroll bar width is hardcoded to be relative to render target height, in GetRect. This means we can't easily make it fit into the parent area correctly.

        row_height := 18.0*UI_SCALE;
        row_rect := scroll_rect;
        row_rect.h = row_height;
        row_rect.y += scroll_position;
        row_rect.y += scroll_rect.h;

        for trace_data.entries {
            if !show_hide_settings.cores  [it.core_id] continue;
            if !show_hide_settings.threads[it.task_id] continue;
            if !show_hide_settings.tags   [it.tag]     continue;

            row_rect.y -= row_height;

            if row_rect.y < 0 || row_rect.y > cast(float)height continue;

            row_theme := my_theme.button_theme;
            row_theme.alignment = .Left;
            row_theme.text_color = .{.75, .75, .75, 1};
            row_theme.font = mono_font;

            if selected_entry != it_index {
                row_theme.surface_color = .{};
                row_theme.frame_color = .{};
            }

            if array_find(highlighted_trace_entries, it_index) {
                row_theme.surface_color = .{0.5, 0.3, 0.3, 0.6};
                row_theme.frame_color = .{0.5, 0.3, 0.3, 0.8};
            }

            if button(row_rect, "", *row_theme, it_index) {
                selected_entry = it_index;
                update_highlighted_trace_entries();
            }

            label_rect := row_rect;
            lt := *row_theme.label_theme;

            time_seconds := cast(float)it.tsc / cast(float)trace_data.tsc_frequency;
            text := tprint("%", formatFloat(time_seconds, trailing_width=3, zero_removal=.NO));
            label(label_rect, text, lt);

            label_rect.x += 75*UI_SCALE;

            text = tprint("%", it.tag);
            label(label_rect, text, lt);

            label_rect.x += 200*UI_SCALE;

            {
                // Say what the thread name was.
                if it.task_id > cast(u64)trace_data.threads.count-1 {
                    text = "(Error in data)";
                } else {
                    text = tprint("%", trace_data.threads[it.task_id]);
                }

                label(label_rect, text, lt);

                label_rect.x += 150*UI_SCALE;
            }

            if it.tag == {
              case .scheduling_timer;
                text = tprint("Preempt disable count %", it.user[0]);
                label(label_rect, text, lt);

              case .syscall;
                syscall_names := string.["Zero (Invalid)", "Yield", "Get Cpu Local Data", "Sleep", "Print", "Allocate", "Trylock Mutex", "Unlock Mutex"];
                label(label_rect, syscall_names[it.user[0]], lt);

              case .context_switch;
                if it.user[1] > cast(u64)trace_data.threads.count-1 {
                    text = "(Error in data)";
                } else {
                    text = tprint("Switch to %", trace_data.threads[it.user[1]]);
                }

                label(label_rect, text, lt);

              case .small_object_alloc;  #through;
              case .small_object_free;   #through;
              case .block_alloc;         #through;
              case .block_resize;        #through;
              case .block_free;
                text = tprint("% bytes at 0x%", it.user[1], cast(*void)it.user[0]);
                label(label_rect, text, lt);
            }
        }

        end_scrollable_region(state, row_rect.x, row_rect.y, *scroll_position);
    }

    switch_to_right_rect(slide_state);

    {
        // Right slide region (currently stack trace.)
        entry := trace_data.entries[selected_entry];

        row_height := 20*UI_SCALE;

        stack_trace_rect := shrink(right_rect, 5*UI_SCALE);

        row_theme := my_theme.label_theme;
        row_theme.alignment = .Left;
        row_theme.text_color = .{.75, .75, .75, 1};
        row_theme.font = mono_font;

        row_rect := stack_trace_rect;
        row_rect.h = row_height;
        row_rect.y += stack_trace_rect.h;
        row_rect.y -= row_height + 5*UI_SCALE;

        for entry.stack_trace {
            if it == 0xffff_ffff || it == 0xffff_fffe || it == 0 {
                break;
            }

            address := cast(u64)it + 0xffff_ffff_0000_0000;

            proc_name, file, line := get_debug_info_for_address(address);

            remove_prefix :: (s: string) #expand {
                if starts_with(file, s) {
                    file.data  += s.count;
                    file.count -= s.count;
                }
            }

            remove_prefix("/home/dlandahl/");
            remove_prefix("new_os/");

            text := tprint("%. [%] %", it_index, formatInt(it, base=16), proc_name);
            label(row_rect, text, *row_theme);

            row_rect.y -= row_height;

            if file {
                text = tprint("   at %:%", file, line);
                label(row_rect, text, *row_theme);

                row_rect.y -= row_height;
            }

            row_rect.y -= 5*UI_SCALE;
        }
    }

    finish(slide_state);

    draw_popups();

    //
    // Swap buffers!
    //

    Simp.swap_buffers(my_window);
}

get_debug_info_for_address :: (address: u64) -> proc_name: string, file: string, line: int {
    // Todo: This is currently called every frame. Might be worth it to cache the result.
    for cu: debug_info.compilation_units {
        if address < cu.low_pc || address >= cu.high_pc continue;

        proc_name: string;

        for sp: cu.subprograms {
            if address < sp.low_pc || address >= sp.high_pc continue;

            proc_name = sp.name;
            break;
        }

        for seq: cu.line_info.sequences {
            first := seq.addresses[0];
            last  := seq.addresses[seq.addresses.count-1];

            if address < first || address >= last continue;

            for< seq_addr: seq.addresses {
                if seq_addr > address continue;

                mapping   := seq.mappings[it_index];
                file_name := get_filename_for_file_id(cu.line_info, mapping.file_id);

                return proc_name, file_name, mapping.line;
            }
        }
    }

    return "(no debug info)", "", 0;
}

update_highlighted_trace_entries :: () {
    array_reset(*highlighted_trace_entries);

    sel := *trace_data.entries[selected_entry];

    for selected_entry+1..trace_data.entries.count-1 {
        // Scan forward to find related trace entries.
        other := *trace_data.entries[it];

        if sel.tag == {
          case .block_resize; #through;
          case .block_alloc;
            if other.tag == .block_free || other.tag == .block_resize {
                if sel.user[0] == other.user[0] {
                    array_add(*highlighted_trace_entries, it);
                    if other.tag == .block_free break;
                }
            }

          case .small_object_alloc;
            if other.tag == .small_object_free {
                if sel.user[0] == other.user[0] {
                    array_add(*highlighted_trace_entries, it);
                    break;
                }
            }

          case .context_switch;
            if other.tag == .context_switch && sel.user[1] == other.task_id {
                array_add(*highlighted_trace_entries, it);
                break;
            }
        }
    }

    for< 0..selected_entry-1 {
        // Scan backwards.
        other := *trace_data.entries[it];

        if sel.tag == {
          case .block_resize; #through;
          case .block_free;
            if other.tag == .block_alloc || other.tag == .block_resize {
                if sel.user[0] == other.user[0] {
                    array_add(*highlighted_trace_entries, it);
                    if other.tag == .block_alloc break;
                }
            }

          case .small_object_free;
            if other.tag == .small_object_alloc {
                if sel.user[0] == other.user[0] {
                    array_add(*highlighted_trace_entries, it);
                    break;
                }
            }

          case .context_switch;
            if other.tag == .context_switch && other.user[1] == sel.task_id {
                array_add(*highlighted_trace_entries, it);
                break;
            }
        }
    }
}

my_init_fonts :: () {
    if !working_directory_set {
        // So that we can load our font, set to path of running executable.
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);

        working_directory_set = true;
    }

    Simp.release_font(mono_font);
    Simp.release_font(bigger_mono_font);

    mono_font        = Simp.get_font_at_size("data", "FiraMono-Medium.ttf", cast(int)(14*UI_SCALE));
    bigger_mono_font = Simp.get_font_at_size("data", "FiraMono-Medium.ttf", cast(int)(16*UI_SCALE));
}

Font :: Simp.Dynamic_Font;

mono_font:        *Font;
bigger_mono_font: *Font;

working_directory_set := false;

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}
