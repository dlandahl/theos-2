
// Based on https://uefi.org/specs/UEFI/2.10/05_GUID_Partition_Table_Format.html

MBR_OS_Indicator :: enum u8 {
    UEFI_SYSTEM_PARTITION    :: 0xef;
    PROTECTIVE_MBR           :: 0xff;
    LEGACY_MBR               :: 0xee;
}

MBR_Partition :: struct {
    boot_indicator:         u8;
    start_chs:          [3] u8;
    os_type:                MBR_OS_Indicator;
    end_chs:            [3] u8;
    start_lba:              u32 #align 2;
    size_in_logical_blocks: u32 #align 2;
}

Protective_MBR :: struct {
    boot_code:         [440] u8;
    disk_signature:          u32;
    _:                       u16;
    partitions:        [4]   MBR_Partition;
    boot_magic:              u16;
}

#assert size_of(Protective_MBR) == 512;

GPT_SIGNATURE    :: "EFI PART";
GPT_REVISION_ONE :: 0x00010000;

GPT_Header :: struct {
    signature:             u64;
    revision:              u32;
    header_size:           u32;
    header_crc32:          u32;
    _:                     u32;

    this_gpt_lba:          u64;
    alternate_gpt_lba:     u64;

    first_usable_lba:      u64;
    last_usable_lba:       u64;

    disk_guid:        [16] u8;

    partition_array_lba:   u64;
    partition_array_count: u32;
    partition_entry_size:  u32;
    partition_array_crc:   u32;
} #no_padding

#assert size_of(GPT_Header) == 92;

GPT_Partition :: struct {
    type_guid:     [16] u8;
    unique_guid:   [16] u8;
    starting_lba:       u64;
    ending_lba:         u64;
    attributes:         u64;
    name:          [36] u16;
}

#assert size_of(GPT_Partition) == 128;

PARTITION_TYPE_EFI_SYSTEM       :: #run guid_to_binary("C12A7328-F81F-11D2-BA4B-00A0C93EC93B");
PARTITION_TYPE_EFI_BASIC_DATA   :: #run guid_to_binary("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7");

GPT_Disk_Image :: struct {
    header:      *GPT_Header;
    header_copy: *GPT_Header;

    partition_table:      [] GPT_Partition;
    partition_table_copy:   *GPT_Partition;

    sector_size: int;

    all_file_data: string;
}

get_sector_pointer :: (disk: GPT_Disk_Image, sector: int) -> *void {
    return disk.all_file_data.data + sector * disk.sector_size;
}

parse_gpt_disk_image :: (memory_buffer: string, sector_size := 512) -> bool, GPT_Disk_Image {
    if memory_buffer.count < 10 * sector_size {
        return false, {};
    }

    partition_table_size    := size_of(GPT_Partition) * 128;
    partition_table_sectors := (partition_table_size + sector_size - 1) / sector_size;

    disk: GPT_Disk_Image;
    disk.all_file_data = memory_buffer;
    disk.sector_size   = sector_size;

    disk.header        = get_sector_pointer(disk, 1);
    disk.header_copy   = get_sector_pointer(disk, cast(int) disk.header.alternate_gpt_lba);

    disk.partition_table.data  = get_sector_pointer(disk, 2);
    disk.partition_table.count = 128;

    disk.partition_table_copy = get_sector_pointer(disk, cast(int) disk.header.alternate_gpt_lba - partition_table_sectors);

    return true, disk;
}

format_gpt_disk_image :: (memory_buffer: [] u8, sector_size := 512) -> GPT_Disk_Image {
    assert(memory_buffer.count % sector_size == 0);

    total_logical_blocks    := memory_buffer.count / sector_size;

    partition_table_size    := size_of(GPT_Partition) * 128;
    partition_table_sectors := (partition_table_size + sector_size - 1) / sector_size;

    disk: GPT_Disk_Image;
    disk.sector_size = sector_size;
    disk.all_file_data = cast(string) memory_buffer;

    {
        // Create protective MBR.

        pmbr: *Protective_MBR = get_sector_pointer(disk, 0);
        memset(pmbr, 0, sector_size);

        // This displays a helpful message when the user's computer tries to do BIOS boot.
        // The jump is needed because the boot code is from the FAT16 bootsector that has
        // other fields before the message, with a different message spliced in. Todo: Cleanup.
        jmp := u8.[235, 60, 144];
        memcpy(pmbr.boot_code.data,      jmp.data,       jmp.count);
        memcpy(pmbr.boot_code.data + 62, BOOT_CODE.data, BOOT_CODE.count);

        pmbr.partitions[0].start_chs              = .[0x00, 0x02, 0x00];
        pmbr.partitions[0].os_type                = .LEGACY_MBR;
        pmbr.partitions[0].end_chs                = .[0xff, 0xff, 0xff];
        pmbr.partitions[0].start_lba              = 1;
        pmbr.partitions[0].size_in_logical_blocks = cast(u32) min(total_logical_blocks - 1, 0xffff_ffff);
        pmbr.boot_magic                           = 0xaa55;
    }

    {
        // Init GPT Header.

        first_data_lba := partition_table_sectors + 2; // Two blocks for PMBR and GPT header, plus enough blocks for the partition array.
        last\_data_lba := total_logical_blocks - partition_table_sectors - 2; // Minus two, because one block for alternate GPT, and LBA are zero-indexed.

        gpt: *GPT_Header = get_sector_pointer(disk, 1);
        memset(gpt, 0, sector_size);

        gpt.signature              = (.*) cast(*u64) GPT_SIGNATURE.data;
        gpt.revision               = GPT_REVISION_ONE;
        gpt.header_size            = size_of(GPT_Header);
        gpt.header_crc32           = 0;
        gpt.this_gpt_lba           = 1;
        gpt.alternate_gpt_lba      = cast(u64) total_logical_blocks - 1;
        gpt.first_usable_lba       = cast(u64) first_data_lba;
        gpt.last\_usable_lba       = cast(u64) last\_data_lba;
        gpt.disk_guid              = generate_random_guid();
        gpt.partition_array_lba    = 2;
        gpt.partition_array_count  = 128;
        gpt.partition_entry_size   = size_of(GPT_Partition);
        gpt.partition_array_crc    = 0xab54d286; // CRC32 of zero initialized partition array.

        // Finally do the checksum when other fields are initialized.
        gpt.header_crc32 = do_crc32(gpt, size_of(GPT_Header));

        disk.header = gpt;

        // Clear partition array.
        partition_table: [] GPT_Partition;
        partition_table.data    = get_sector_pointer(disk, 2);
        partition_table.count   = 128;
        memset(partition_table.data, 0, partition_table.count * size_of(GPT_Partition));

        disk.partition_table = partition_table;

        // Create alternate header.
        alternate_gpt: *GPT_Header = get_sector_pointer(disk, cast(int) gpt.alternate_gpt_lba);
        memcpy(alternate_gpt, gpt, size_of(GPT_Header));

        alternate_gpt.this_gpt_lba      = gpt.alternate_gpt_lba;
        alternate_gpt.alternate_gpt_lba = gpt.this_gpt_lba;
        alternate_gpt.header_crc32      = 0;
        alternate_gpt.header_crc32      = do_crc32(alternate_gpt, size_of(GPT_Header));

        disk.header_copy = alternate_gpt;

        // Clear alternate partition array.
        alternate_partition_table: *GPT_Partition = get_sector_pointer(disk, cast(int) gpt.alternate_gpt_lba - partition_table_sectors);
        memset(alternate_partition_table, 0, partition_table_size);

        disk.partition_table_copy = alternate_partition_table;
    }

    return disk;
}

finalize_gpt_disk_image :: (disk: GPT_Disk_Image) {
    // 1. Recalculate header checksum.
    disk.header.partition_array_crc = do_crc32(disk.partition_table);
    disk.header.header_crc32        = 0;
    disk.header.header_crc32        = do_crc32(disk.header, size_of(GPT_Header));

    // 2. Recalculate alternate header checksum.
    disk.header_copy.partition_array_crc = disk.header.partition_array_crc;
    disk.header_copy.header_crc32        = 0;
    disk.header_copy.header_crc32        = do_crc32(disk.header_copy, size_of(GPT_Header));

    // 3. Copy partition table.
    source      := disk.partition_table.data;
    destination := disk.partition_table_copy;
    bytes       := disk.partition_table.count * size_of(GPT_Partition);
    memcpy(destination, source, bytes);
}

create_partition :: (disk: GPT_Disk_Image, type_guid: [16] u8, name: string, offset_in_sectors: int, size_in_sectors: int) -> [] u8, *GPT_Partition {
    // Todo: Make sure this doesn't overlap with any existing partitions.

    for *disk.partition_table {
        // Find a free slot in the partition table.
        for byte: it.type_guid if byte != 0 continue it;

        memset(it, 0, size_of(GPT_Partition));

        it.starting_lba = cast(u64) (offset_in_sectors);
        it.ending_lba   = cast(u64) (offset_in_sectors + size_in_sectors - 1);

        for char: 0..min(name.count, it.name.count)-1 {
            it.name[char] = name[char];
        }

        it.unique_guid = generate_random_guid();
        it.type_guid   = type_guid;

        result: [] u8;
        result.data  = get_sector_pointer(disk, offset_in_sectors);
        result.count = size_in_sectors * disk.sector_size;

        return result, it;
    }

    return .[], null; // No free GPT entries.
}



#scope_module

generate_random_guid :: () -> [16] u8 {
    union {
        result: [16] u8;
        qwords: [2] u64;
    }

    // Lets not rely on the caller having seeded the random number generator.
    state: Random_State;
    random_seed(*state, cast(S128) current_time_consensus());

    qwords[0] = random_get(*state);
    qwords[1] = random_get(*state);

    result[6] &= 0b0000_1111;
    result[6] |= 0b0100_0000;

    result[8] &= 0b0011_1111;
    result[8] |= 0b1000_0000;

    return result;
}

guid_to_binary :: (guid_string: string) -> [16] u8 {
    segments := split(guid_string, #char "-");
    assert(segments.count == 5);

    result: [16] u8;
    cursor: int;

    do_segment :: (segment: string, $T: Type, big_endian := false) #expand {
        assert(segment.count == size_of(T) * 2);

        a, success, remainder := string_to_int(segment, base=16, T);
        assert(success && !remainder);

        if big_endian byte_swap_in_place(*a);

        (.*) cast(*T) (result.data + cursor) = a;

        cursor += size_of(T);
    }

    // Last segment is a u48, so split it into u32 and u16.
    first  := slice(segments[4], 0, 8);
    second := slice(segments[4], 8, 4);

    do_segment(segments[0], u32);
    do_segment(segments[1], u16);
    do_segment(segments[2], u16);
    do_segment(segments[3], u16, big_endian = true);
    do_segment(first,       u32, big_endian = true);
    do_segment(second,      u16, big_endian = true);

    return result;
}

do_crc32 :: (data: *void, count: int) -> u32 {
    result: u32 = 0xffff_ffff;

    for 0..count-1 {
        result ^= data.(*u8)[it];
        result  = (result >> 8) ^ CRC32_TABLE[result & 0xff];
    }

    result ^= 0xffff_ffff;
    return result;
}

do_crc32 :: (input: [] $T) -> u32 {
    return do_crc32(input.data, input.count * size_of(T));
}

// Source polynomial for this table is 0x04c11db7 (or inverted, 0xedb88320.)

CRC32_TABLE :: u32.[
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
    0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
    0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
    0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
    0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
    0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
    0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
    0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
    0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
    0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
    0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
    0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
    0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
    0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
    0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
    0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
    0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
    0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
    0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
    0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
    0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
    0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
];

BOOT_CODE :: u8.[
    0x0E, 0x1F, 0xBE, 0x5B, 0x7C, 0xAC, 0x22, 0xC0,
    0x74, 0x0B, 0x56, 0xB4, 0x0E, 0xBB, 0x07, 0x00,
    0xCD, 0x10, 0x5E, 0xEB, 0xF0, 0x32, 0xE4, 0xCD,
    0x16, 0xCD, 0x19, 0xEB, 0xFE, 0x59, 0x6F, 0x75,
    0x72, 0x20, 0x50, 0x43, 0x20, 0x61, 0x74, 0x74,
    0x65, 0x6D, 0x70, 0x74, 0x65, 0x64, 0x20, 0x74,
    0x6F, 0x20, 0x62, 0x6F, 0x6F, 0x74, 0x20, 0x75,
    0x73, 0x69, 0x6E, 0x67, 0x20, 0x42, 0x49, 0x4F,
    0x53, 0x2E, 0x20, 0x54, 0x68, 0x65, 0x20, 0x73,
    0x79, 0x73, 0x74, 0x65, 0x6D, 0x20, 0x6F, 0x6E,
    0x20, 0x74, 0x68, 0x69, 0x73, 0x20, 0x64, 0x69,
    0x73, 0x6B, 0x20, 0x64, 0x6F, 0x65, 0x73, 0x20,
    0x6E, 0x6F, 0x74, 0x20, 0x73, 0x75, 0x70, 0x70,
    0x6F, 0x72, 0x74, 0x20, 0x74, 0x68, 0x69, 0x73,
    0x2E, 0x20, 0x50, 0x6C, 0x65, 0x61, 0x73, 0x65,
    0x20, 0x63, 0x6F, 0x6E, 0x66, 0x69, 0x67, 0x75,
    0x72, 0x65, 0x20, 0x79, 0x6F, 0x75, 0x72, 0x20,
    0x50, 0x43, 0x20, 0x74, 0x6F, 0x20, 0x70, 0x65,
    0x72, 0x66, 0x6F, 0x72, 0x6D, 0x20, 0x61, 0x20,
    0x55, 0x45, 0x46, 0x49, 0x20, 0x62, 0x6F, 0x6F,
    0x74, 0x2E, 0x00
];

#import "Random";
#import "String";
#import "Basic";
#import "Bit_Operations";
