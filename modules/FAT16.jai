
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

Fat16_Boot_Code :: u8.[
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

Fat16_Image_Info :: struct {
    size_bytes: int;

    oem_name: string;
    volume_label: string;
    file_system_label: string;

    cluster_size_bytes: int;
}

fat16_print_filesystem_tree :: (image: string) {
    bs := cast(*Fat16_Bootsector) image.data;

    print("%\n", formatStruct(bs.*, use_long_form_if_more_than_this_many_members=0, use_newlines_if_long_form=true));

    using bs;
    root_directory_offset_sectors := reserved_sectors + (number_of_fat_tables * sectors_per_fat_table);
    root_directory_offset_bytes   := root_directory_offset_sectors * bytes_per_sector;
}



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
    cal.hour                       = cast(u8)  hour;
    cal.minute                     = cast(u8)  minute;
    cal.second                     = cast(u8)  second * 2;

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

    d: DOSDATE = (year << 9)  | (month  << 5) | (day);
    t: DOSTIME = (hour << 11) | (minute << 5) | (second);

    return d, t;
}
