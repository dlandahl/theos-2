
#module_parameters(get_calendar_time := () -> Calendar_Time {
    apollo := current_time_consensus();
    return to_calendar(apollo);
});

Fat16_Media_Descriptor :: enum u8 {
    FLOPPY     :: 0xf0;
    HARD_DRIVE :: 0xf8;
}

Fat16_Media_Type :: enum u16 {
    FLOPPY_DISK :: 0xfff0;
    HARD_DISK   :: 0xfff8;
}

Fat16_Partition_State :: enum u16 {
    IN_USE       :: 0xfff7;
    NOT_IN_USE   :: 0xffff;
}

Fat16_Bootsector :: struct {
    jmp:                [3]u8;
    oem_name:           [8]u8;
    bytes_per_sector:      u16 #align 1;
    sectors_per_cluster:   u8;
    reserved_sectors:      u16;
    number_of_fat_tables:  u8;
    max_root_dir_entries:  u16 #align 1;
    number_of_sectors16:   u16 #align 1;
    media_descriptor:      Fat16_Media_Descriptor;
    sectors_per_fat_table: u16;
    sectors_per_track:     u16;
    heads_per_cylinder:    u16;
    num_hidden_sectors:    u32 #align 2;
    number_of_sectors32:   u32 #align 2;
    drive_number:          u8;
    unused:                u8;
    ext_boot_signature:    u8;
    serial_number:         u32 #align 1;
    volume_label:      [11]u8;
    file_system_label:  [8]u8;
    boot_code:        [448]u8;
    bootsector_magic:      u16;
}

#assert size_of(Fat16_Bootsector) == 512;

FAT16_BOOT_CODE :: u8.[
    0x0e, 0x1f, 0xbe, 0x5b, 0x7c, 0xac, 0x22, 0xc0,
    0x74, 0x0b, 0x56, 0xb4, 0x0e, 0xbb, 0x07, 0x00,
    0xcd, 0x10, 0x5e, 0xeb, 0xf0, 0x32, 0xe4, 0xcd,
    0x16, 0xcd, 0x19, 0xeb, 0xfe, 0x54, 0x68, 0x69,
    0x73, 0x20, 0x69, 0x73, 0x20, 0x6e, 0x6f, 0x74,
    0x20, 0x61, 0x20, 0x62, 0x6f, 0x6f, 0x74, 0x61,
    0x62, 0x6c, 0x65, 0x20, 0x64, 0x69, 0x73, 0x6b,
    0x2e, 0x20, 0x20, 0x50, 0x6c, 0x65, 0x61, 0x73,
    0x65, 0x20, 0x69, 0x6e, 0x73, 0x65, 0x72, 0x74,
    0x20, 0x61, 0x20, 0x62, 0x6f, 0x6f, 0x74, 0x61,
    0x62, 0x6c, 0x65, 0x20, 0x66, 0x6c, 0x6f, 0x70,
    0x70, 0x79, 0x20, 0x61, 0x6e, 0x64, 0x0d, 0x0a,
    0x70, 0x72, 0x65, 0x73, 0x73, 0x20, 0x61, 0x6e,
    0x79, 0x20, 0x6b, 0x65, 0x79, 0x20, 0x74, 0x6f,
    0x20, 0x74, 0x72, 0x79, 0x20, 0x61, 0x67, 0x61,
    0x69, 0x6e, 0x20, 0x2e, 0x2e, 0x2e, 0x20, 0x0d,
    0x0a, 0x00,
];

Fat16_Fat :: struct {
    media_type:      Fat16_Media_Type;
    partition_state: Fat16_Partition_State;
    clusters:        void;
}

Fat16_Attributes :: enum_flags u8 {
    READ_ONLY  :: 0x01;
    HIDDEN     :: 0x02;
    SYSTEM     :: 0x04;
    VOLUME_ID  :: 0x08;
    DIRECTORY  :: 0x10;
    ARCHIVE    :: 0x20;
    DEVICE     :: 0x40;
    RESERVED   :: 0x80;

    LFN_ENTRY  :: 0x0f;
}

Fat16_LFN_Entry :: struct {
    record_sequence:     u8;
    characters_1:    [5] u16 #align 1;
    attributes:          Fat16_Attributes;
    reserved:            u8;
    chk_short_name:      u8;
    characters_2:    [6] u16;
    cluster:             u16;
    characters_3:    [2] u16;
}

#assert size_of(Fat16_LFN_Entry) == 0x20;

Fat16_Short_Entry ::  struct {
    name:          [8] u8;
    extension:     [3] u8;
    attributes:        Fat16_Attributes;
    reserved:          u8;
    create_time_10ms:  u8;
    create_time:       DOSTIME;
    create_date:       DOSDATE;
    access_date:       DOSDATE;
    high_cluster:      u16;
    update_time:       DOSTIME;
    update_date:       DOSDATE;
    cluster:           u16;
    file_size:         u32;
}

#assert size_of(Fat16_Short_Entry) == 0x20;


Fat16_Disk_Image :: struct {
    bytes_per_cluster: int;

    bootsector: *Fat16_Bootsector;

    file_allocation_table: []u16;
    root_directory_area: *void;
    data_area: *void;

    lowest_maybe_free_fat_entry: int;
    all_file_data: string;
}

Fat16_Tree_Cursor :: struct {
    disk_image: *Fat16_Disk_Image;
    cluster: u16;
}

fat16_create_disk_image :: (size_bytes: int, set_oem_name := "JaiFAT16", set_volume_label := "NO NAME", set_serial_number: u32 = 0) -> Fat16_Disk_Image {
    // Code for creating a new FAT16 disk from scratch in memory.

    all_file_data: string;

    all_file_data.count = size_bytes;
    all_file_data.data  = alloc(size_bytes);

    total_sectors  := (size_bytes+511) / 512;
    total_clusters := total_sectors / 4;

    {
        // Setup the boot sector.
        using bootsector := cast(*Fat16_Bootsector)all_file_data.data;

        jmp = .[235, 60, 144];
        memcpy(*oem_name, set_oem_name.data, 8);

        bytes_per_sector      = 512;
        sectors_per_cluster   = 4;
        reserved_sectors      = 4;
        number_of_fat_tables  = 2;
        max_root_dir_entries  = 512;
        number_of_sectors16   = cast(u16) ifx total_sectors <  65536 then total_sectors else 0;
        number_of_sectors32   = cast(u32) ifx total_sectors >= 65536 then total_sectors else 0;
        media_descriptor      = .HARD_DRIVE;

        // This overestimates how many entries we need, because it assumes the whole disk is the
        // data region that needs to be addressable in the FAT. But not an issue for now.
        sectors_per_fat_table = cast(u16) ((total_clusters * 2) / bytes_per_sector);

        sectors_per_track     = 32;
        heads_per_cylinder    = 2;
        num_hidden_sectors    = 0;
        drive_number          = 0x80;
        unused                = 0;
        ext_boot_signature    = 0x29;
        serial_number         = set_serial_number;
        bootsector_magic      = 0xaa55;

        memcpy(*volume_label, set_volume_label.data, min(11, set_volume_label.count));
        memcpy(*file_system_label, "FAT16   ".data, 8);

        memcpy(*boot_code, FAT16_BOOT_CODE.data, FAT16_BOOT_CODE.count);
    }

    // Fill in the other pointers based on the values calculated for the boot sector.
    disk := fat16_parse_disk_image(all_file_data);

    return disk;
}

fat16_parse_disk_image :: (file_data: string) -> Fat16_Disk_Image {
    // Code for reading from an existing disk in memory.

    using image: Fat16_Disk_Image;

    all_file_data = file_data;

    // Find the bootsector.
    bootsector = cast(*Fat16_Bootsector) file_data.data;
    using bootsector;

    bytes_per_cluster = cast(int)bytes_per_sector * sectors_per_cluster;

    // Find the file allocation table.
    fat_offset_bytes := reserved_sectors * bytes_per_sector;
    file_allocation_table.data = cast(*u16) (file_data.data + fat_offset_bytes) + 2;
    file_allocation_table.count = sectors_per_fat_table * bytes_per_sector / size_of(u16) - 2;

    // Todo: Metadata in FAT.
    file_allocation_table.data[-2] = 0xfff8;
    file_allocation_table.data[-1] = 0xffff;

    // Find the root directory.
    root_directory_offset_sectors := reserved_sectors + (number_of_fat_tables * sectors_per_fat_table);
    root_directory_offset_bytes   := root_directory_offset_sectors * bytes_per_sector;

    root_directory_area = (file_data.data + root_directory_offset_bytes);

    // Find the data area.
    root_dir_sectors := ((max_root_dir_entries * 32) + (bytes_per_sector - 1)) / bytes_per_sector;
    data_area = root_directory_area + root_dir_sectors * bytes_per_sector;

    return image;
}

fat16_get_root_directory :: (disk: *Fat16_Disk_Image) -> Fat16_Tree_Cursor {
    handle: Fat16_Tree_Cursor;
    handle.cluster = 0;
    handle.disk_image = disk;

    return handle;
}

fat16_change_directory :: (relative_to: Fat16_Tree_Cursor, path: string) -> bool, Fat16_Tree_Cursor {

    current_directory := relative_to;
    remainder         := trim(path, "\\/");

    while remainder {
        _, left:, remainder = split_from_left_by_any(remainder, "\\/");

        // Todo: Handle long names.
        assert(left.count < 8);

        short_entry := fat16_find_directory_entry(current_directory, left);

        if !short_entry {
            log_error("Directory entry \"%\" not found while evaluating path %.", left, path);
            return false, .{};
        }

        if short_entry.attributes & .DIRECTORY == 0 {
            log_error("Directory entry \"%\", found while evaluating path %, is not a directory.", left, path);
            return false, .{};
        }

        current_directory.cluster = short_entry.cluster;
    }

    return true, current_directory;
}

fat16_create_directory :: (relative_to: Fat16_Tree_Cursor, path: string) -> Fat16_Tree_Cursor {
    entry, existed, parent := fat16_find_or_create_directory_entry(relative_to, path);

    if existed {
        return .{relative_to.disk_image, entry.cluster}; // Todo, we could warn if it's not a directory, etc.
    }

    new_cluster := fat16_allocate_fat_entry(relative_to.disk_image);
    relative_to.disk_image.file_allocation_table[new_cluster] = 0xfff8;

    entry.cluster = new_cluster + 2;
    entry.attributes = .DIRECTORY;

    new_directory := relative_to;
    new_directory.cluster = entry.cluster;

    for each_entry(new_directory, skip_unused = false) {
        it.* = .{};
    }

    self_link := fat16_find_or_create_directory_entry(new_directory, ".");
    back_link := fat16_find_or_create_directory_entry(new_directory, "..");

    assert(self_link && back_link);

    self_link.cluster = entry.cluster;
    back_link.cluster = parent.cluster;

    self_link.attributes = .DIRECTORY;
    back_link.attributes = .DIRECTORY;

    return .{relative_to.disk_image, entry.cluster}; // Todo, we could warn if it's not a directory, etc.
}

fat16_write_file :: (relative_to: Fat16_Tree_Cursor, path: string, content: string) -> bool {
    // Overwrites file contents if it already exists, creates file if it doesn't.
    disk := relative_to.disk_image;

    parent, file_name := parse_path(relative_to, path);
    if !file_name return false; // The path doesn't exist, a warning was generated by change_directory. Todo: Return error code.

    entry, already_existed := fat16_find_or_create_directory_entry(relative_to, path);

    if already_existed {
        if entry.attributes & .DIRECTORY return false; // Todo: Return error code.

        // Might be marginally faster to reuse the existing clusters, but I'd rather keep the code a bit simpler.
        erase_cluster_chain(disk, entry.cluster);
    }

    // Slower than necessary, because we could allocate all the clusters ahead of time, and then do larger contiguous memcpys.
    next_cluster := fat16_allocate_fat_entry(disk);
    entry.cluster = next_cluster + 2;

    whole_clusters_needed := content.count / disk.bytes_per_cluster;
    remaining             := content.count % disk.bytes_per_cluster;

    for 0..whole_clusters_needed-1 {
        source      := content.data   + it           * disk.bytes_per_cluster;
        destination := disk.data_area + next_cluster * disk.bytes_per_cluster;

        memcpy(destination, source, disk.bytes_per_cluster);

        if it != whole_clusters_needed - 1 || remaining {
            // Todo: Clarify this offset by 2 thing.
            disk.file_allocation_table[next_cluster] = fat16_allocate_fat_entry(disk)+2;
            next_cluster = disk.file_allocation_table[next_cluster]-2;
        }
    }

    // Do the final cluster.

    if remaining {
        source      := content.data   + content.count - remaining;
        destination := disk.data_area + next_cluster * disk.bytes_per_cluster;

        memcpy(destination, source, remaining);
    }

    disk.file_allocation_table[next_cluster] = 0xffff;

    entry.attributes = .ARCHIVE;
    entry.file_size = cast(u32)content.count;

    return true;
}

fat16_read_file :: (relative_to: Fat16_Tree_Cursor, path: string) -> success: bool, string {
    disk := relative_to.disk_image;

    // Todo: Return error codes.

    parent, file_name := parse_path(relative_to, path);
    if !file_name return false, ""; // The path doesn't exist, a warning was generated by change_directory.

    file := fat16_find_directory_entry(parent, file_name);
    if !file {
        log_error("Could not find file '%' while trying to read it.", file_name);
        return false, "";
    }

    buffer := alloc(file.file_size);

    whole_clusters := file.file_size / disk.bytes_per_cluster;
    next_cluster := file.cluster - 2;

    for 0..whole_clusters-1 {
        source      := disk.data_area + next_cluster * disk.bytes_per_cluster;
        destination := buffer         + it           * disk.bytes_per_cluster;

        memcpy(destination, source, disk.bytes_per_cluster);

        // Todo: Is there an off by one error with the cluster indices?
        next_cluster = disk.file_allocation_table[next_cluster] - 2;
    }

    {
        remaining := file.file_size % disk.bytes_per_cluster;

        destination := buffer + file.file_size - remaining;
        source      := disk.data_area + next_cluster * disk.bytes_per_cluster;

        memcpy(destination, source, remaining);
    }

    s: string;
    s.count = file.file_size;
    s.data = buffer;

    return true, s;
}

fat16_copy_fat_table :: (using disk: *Fat16_Disk_Image) {
    fat_size := bootsector.sectors_per_fat_table * bootsector.bytes_per_sector;

    fat_1_base := all_file_data.data + bootsector.reserved_sectors      * bootsector.bytes_per_sector;
    fat_2_base := fat_1_base         + bootsector.sectors_per_fat_table * bootsector.bytes_per_sector;

    memcpy(fat_2_base, fat_1_base, fat_size);
}

erase_cluster_chain :: (disk: *Fat16_Disk_Image, cluster: u16) {

    assert(cluster >= 2);
    next := cluster - 2;

    while true {
        assert(next != 0);

        old_value := disk.file_allocation_table[next];
        disk.file_allocation_table[next] = 0;

        if next < disk.lowest_maybe_free_fat_entry {
            disk.lowest_maybe_free_fat_entry = next;
        }

        if old_value >= 0xfff8 return;

        next = disk.file_allocation_table[old_value];
    }
}

parse_path :: (relative_to: Fat16_Tree_Cursor, path: string) -> parent_folder: Fat16_Tree_Cursor, entry_name: string {
    parent  := relative_to;
    trimmed := trim(path, "\\/");

    found, left, file_name := split_from_right_by_any(trimmed, "\\/");

    if found {
        success:, parent = fat16_change_directory(relative_to, left);
        if !success return .{}, "";
    } else {
        file_name = left;
    }

    return parent, file_name;
}

fat16_find_directory_entry :: (parent: Fat16_Tree_Cursor, file_name: string) -> *Fat16_Short_Entry {

    _, base_name, extension := split_from_left(file_name, #char ".");
    assert(base_name.count <= 8);
    assert(extension.count <= 3);

    for each_entry(parent) {
        other_name, other_extension := fat16_get_name(it);

        name_match := equal_nocase(other_name, base_name);
        ext_match  := equal_nocase(other_extension, extension);

        if name_match && ext_match {
            return it;
        }
    }

    return null;
}

fat16_find_or_create_directory_entry :: (relative_to: Fat16_Tree_Cursor, path: string) -> *Fat16_Short_Entry, existed: bool, parent_cursor: Fat16_Tree_Cursor {

    parent, file_name := parse_path(relative_to, path);
    if !file_name return null, false, parent;
 
    existing := fat16_find_directory_entry(parent, file_name);
    if existing return existing, true, parent;


    _, base_name, extension := split_from_left(file_name, #char ".");
    assert(base_name.count <= 8);
    assert(extension.count <= 3);

    if base_name.count == 0 {
        // It was a . or .. link directory.
        base_name = file_name;
        extension = "\x20\x20\x20";
    }

    base_name = to_upper_copy(base_name,, temp);
    extension = to_upper_copy(extension,, temp);


    for each_entry(parent, skip_unused = false) {
        first_byte := (.*) cast(*u8) it;

        if first_byte && first_byte != 0xe5 {
            continue;
        }

        // Found a free directory entry slot.

        for* it.name {
            if it_index < base_name.count {
                it.* = base_name[it_index];
            } else {
                it.* = #char " ";
            }
        }

        for* it.extension {
            if it_index < extension.count {
                it.* = extension[it_index];
            } else {
                it.* = #char " ";
            }
        }

        calendar_time    := get_calendar_time();
        dosdate, dostime := calendar_to_dostime(calendar_time);

        it.create_time_10ms = cast(u8) (calendar_time.millisecond / 10);
        it.create_time      = dostime;
        it.create_date      = dosdate;
        it.access_date      = dosdate;
        it.high_cluster     = 0;
        it.update_time      = dostime;
        it.update_date      = dosdate;
        it.cluster          = 0; // Caller must set this up, otherwise this refers to the root directory.
        it.file_size        = 0;

        return it, false, parent;
    }

    assert(false);
    return null, false, parent;
}

fat16_get_name :: (entry: *Fat16_Short_Entry) -> string, string {
    // Remove spaces from the end, FAT16 filenames get padded with spaces.
    // Todo: Handle long names.

    base_name: string;
    base_name.data  = entry.name.data;
    base_name.count = 8;

    while base_name.count > 0 && base_name.data[base_name.count-1] == #char " " {
        base_name.count -= 1;
    }

    extension: string;
    extension.data  = entry.extension.data;
    extension.count = 3;

    while extension.count > 0 && extension.data[extension.count-1] == #char " " {
        extension.count -= 1;
    }

    return base_name, extension;
}

fat16_allocate_fat_entry :: (using disk: *Fat16_Disk_Image) -> u16 {
    start := lowest_maybe_free_fat_entry;
    end   := file_allocation_table.count - 1;

    for start..end {
        if file_allocation_table[it] == 0 {
            lowest_maybe_free_fat_entry = it + 1;
            return cast(u16)it;
        }
    }

    return 0xffff;
}

Fat16_Directory_Iterator :: struct {
    handle: Fat16_Tree_Cursor;
    skip_unused: bool;
}

each_entry :: (directory: Fat16_Tree_Cursor, skip_unused := true) -> Fat16_Directory_Iterator {
    return .{directory, skip_unused};
}

for_expansion :: (using iterator: *Fat16_Directory_Iterator, body: Code, flags: For_Flags) #expand {
    assert(flags == 0);

    // Iterates directory contents. Doesn't recurse into subdirectories.
    // Todo: Handle long names.

    is_root := handle.cluster == 0;
    disk    := handle.disk_image;

    directory_entries_per_cluster := disk.bytes_per_cluster / 0x20;
    next_cluster := handle.cluster - 2;

    directory_data: *Fat16_Short_Entry;
    if is_root directory_data = disk.root_directory_area;

    `it_index := -1;

    while true {
        it_index += 1;

        if is_root {
            if it_index >= disk.bootsector.max_root_dir_entries {
                break;
            }
        } else {
            if it_index % directory_entries_per_cluster == 0 {
                if next_cluster >= 0xfff8 {
                    // Found the end of the cluster chain.
                    break;
                }

                directory_data = disk.data_area + disk.bytes_per_cluster * next_cluster;
                next_cluster   = disk.file_allocation_table[next_cluster];
            }
        }

        `it := directory_data + it_index;

        first_byte := (.*) cast(*u8) it;

        if first_byte == 0xe5 if skip_unused continue;
        if first_byte == 0    if skip_unused break;

        if it.attributes == .LFN_ENTRY continue;

        #insert body;
    }
}

fat16_print_directory_tree :: (root: Fat16_Tree_Cursor, depth := 0) {
    for each_entry(root) {
        name := fat16_get_name(it);
        if it.name[0] == #char "." continue;

        for 1..depth print("| ");
        print("%\n", name);

        if it.attributes & .DIRECTORY {
            success, sub := fat16_change_directory(root, name);
            assert(success);

            fat16_print_directory_tree(sub, depth + 1);
        }
    }
}



#import "Basic";
#import "String";

DOSTIME :: #type,distinct u16;
DOSDATE :: #type,distinct u16;

dostime_to_calendar :: (d: DOSDATE, t: DOSTIME) -> Calendar_Time {
    // Either DOSTIME or DOSDATE can be left 0 if you only want to convert one.

    year   := (d >> 9);
    month  := (d >> 5)  & 0x0f;
    day    := (d)       & 0x1f;

    hour   := (t >> 11);
    minute := (t >> 5)  & 0x3f;
    second := (t)       & 0x1f;

    cal: Calendar_Time;
    cal.year                       = cast(s32) year + 1980;
    cal.month_starting_at_0        = cast(s8)  ifx month then month - 1;
    cal.day_of_month_starting_at_0 = cast(s8)  ifx day   then day - 1;
    cal.hour                       = cast(s8)  hour;
    cal.minute                     = cast(s8)  minute;
    cal.second                     = cast(s8)  second * 2;

    return cal;
}

calendar_to_dostime :: (cal: Calendar_Time) -> DOSDATE, DOSTIME {
    // Out of range year values will generate a runtime cast range check failure. Maybe we should return a bool instead.

    year   := cast(u16) (cal.year - 1980);
    month  := cast(u16) (cal.month_starting_at_0 + 1);
    day    := cast(u16) (cal.day_of_month_starting_at_0 + 1);

    hour   := cast(u16) (cal.hour);
    minute := cast(u16) (cal.minute);
    second := cast(u16) (cal.second / 2);

    d := cast(DOSDATE) ((year << 9)  | (month  << 5) | (day));
    t := cast(DOSTIME) ((hour << 11) | (minute << 5) | (second));

    return d, t;
}
