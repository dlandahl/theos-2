
// Todo: None of the disk-reading code guards against badly formatted disks, it will just crash or give you nonsense output.
// A module like this is probably much more valuable if it can tell you where a disk is incorrectly formatted.

Fat16_Media_Descriptor :: enum u8 {
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

FAT16_CLUSTER_END_OF_CHAIN :u16: 0xffff;

Fat16_Entry_Attributes :: enum_flags u8 {
    READ_ONLY  :: 0x01;
    HIDDEN     :: 0x02;
    SYSTEM     :: 0x04;
    VOLUME_ID  :: 0x08;
    DIRECTORY  :: 0x10;
    ARCHIVE    :: 0x20;
    DEVICE     :: 0x40;
    RESERVED   :: 0x80;
}

Fat16_LFN_Entry :: struct {
    record_sequence:     u8;
    characters_1:    [5] u16 #align 1;
    attributes:          Fat16_Entry_Attributes;
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
    attributes:        Fat16_Entry_Attributes;
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
    root_directory: *Fat16_Short_Entry;
    data_area: *void;

    all_file_data: string;
    pool: Flat_Pool;
}

fat16_create_disk_image :: (size_bytes: int, set_oem_name := "JaiFAT16", set_volume_label := "NO NAME    ", set_serial_number: u32 = 0) -> Fat16_Disk_Image {
    // Code for creating a new FAT16 disk from scratch in memory.

    using image: Fat16_Disk_Image;

    all_file_data.count = size_bytes;
    all_file_data.data  = alloc(size_bytes);

    total_sectors  := (size_bytes+511) / 512;
    total_clusters := total_sectors / 4;

    {
        // Setup the boot sector.
        bootsector = cast(*Fat16_Bootsector)all_file_data.data;

        using bootsector;

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

        memcpy(*volume_label, set_volume_label.data, 11);
        memcpy(*file_system_label, "FAT16   ".data, 8);

        memcpy(*boot_code, FAT16_BOOT_CODE.data, FAT16_BOOT_CODE.count);
    }

    // Fill in the other pointers based on the values calculated for the boot sector.
    image = fat16_parse_disk_image(all_file_data);

    return image;
}

fat16_parse_disk_image :: (file_data: string) -> Fat16_Disk_Image {
    // Code for reading from an existing disk in memory.

    using image: Fat16_Disk_Image;
    init(*pool);

    all_file_data = file_data;

    {
        // Find the bootsector.
        bootsector = cast(*Fat16_Bootsector) file_data.data;
    }

    using bootsector;

    bytes_per_cluster = cast(int)bytes_per_sector * sectors_per_cluster;

    {
        // Find the file allocation table.
        fat_offset_bytes := reserved_sectors * bytes_per_sector;
        file_allocation_table.data = cast(*u16) (file_data.data + fat_offset_bytes);
        file_allocation_table.count = sectors_per_fat_table * bytes_per_sector / size_of(u16);
    }

    {
        // Find the root directory.
        root_directory_offset_sectors := reserved_sectors + (number_of_fat_tables * sectors_per_fat_table);
        root_directory_offset_bytes   := root_directory_offset_sectors * bytes_per_sector;

        root_directory = cast(*Fat16_Short_Entry) (file_data.data + root_directory_offset_bytes);
    }

    {
        // Find the data area.
        root_dir_sectors := ((max_root_dir_entries * 32) + (bytes_per_sector - 1)) / bytes_per_sector;
        data_area = cast(*void)root_directory + root_dir_sectors * bytes_per_sector;
    }

    return image;
}

fat16_list_directory :: (image: Fat16_Disk_Image, directory_data: *Fat16_Short_Entry) {
    dir_entry := directory_data;

    while true {
        defer dir_entry += 1;

        first_byte := (.*) cast(*u8) dir_entry;

        if first_byte == 0 {
            break;
        }

        if first_byte == 0xe5 {
            continue;
        }

        print("Entry '%' has attributes: %.\n", cast(string) dir_entry.name, dir_entry.attributes);
    }
}

fat16_read_cluster_chain :: (image: Fat16_Disk_Image, cluster: u16) -> *void {
    // Very slow way of doing it, but I'll linearize the cluster chains ahead of time regardless of what data we actually need from it.
    // This should be used for directories, not large files if you care about speed at all.

    result := image.pool.current_point;

    cluster_size := image.bytes_per_cluster;
    next_cluster := cast(int)cluster - 2;

    while true {
        cluster_data := get(*image.pool, cluster_size);
        memcpy(cluster_data, image.data_area + cluster_size * next_cluster, cluster_size);

        next_cluster = image.file_allocation_table[next_cluster];

        assert(next_cluster != 0, "Cluster chain should not contain unallocated entries.");

        if next_cluster & 0xfff8 == 0xfff8 {
            break;
        }
    }

    return result;
}



#import "Flat_Pool";
#import "Basic";

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




#run {
    #import "String";
    #import "Compiler";

    cl := get_toplevel_command_line();

    // Auto run the test without generating an executable, if the module gets passed to the compiler directly on the command line.
    if cl.count == 2 && contains(cl[1], "FAT16.jai") {
        set_build_options_dc(.{do_output = false});
        fat16_test();
    }
}

fat16_test :: () {
    #import "File";

    file_data := read_entire_file("../disk_image.img");
    if !file_data return;

    disk := fat16_parse_disk_image(file_data);

    context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 0;
    context.print_style.default_format_struct.use_newlines_if_long_form = true;

    print("Boot Sector: %\n\n", disk.bootsector.*);
    print("%\n%\n%\n\n",
          cast(string)disk.bootsector.oem_name,
          cast(string)disk.bootsector.volume_label,
          cast(string)disk.bootsector.file_system_label,
         );

    print("Root Directory: %\n\n", disk.root_directory.*);

    fat16_list_directory(disk, disk.root_directory);

    root_dir_contents := fat16_read_cluster_chain(disk, disk.root_directory.cluster);

    fat16_list_directory(disk, root_dir_contents);

    fat16_create_disk_image(0xa0_0000);
}
