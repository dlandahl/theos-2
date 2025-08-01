
#import "Lil_Uefi";
#import "Elf";

#load "../boot_data.jai";

#add_context system_table: *EFI_SYSTEM_TABLE;

VIRTUALBOX_COMPATIBILITY :: true;

#program_export
EfiMain :: (loaded_image: EFI_HANDLE, system_table: *EFI_SYSTEM_TABLE) -> EFI_UINTN #c_call {

    push_context {
        context.system_table = system_table;
        boot_services := system_table.BootServices;

        // Memory type for allocations that should keep the memory reserved in the kernel's physical memory management.
        // This is supposed to be a custom memory type, so that EfiLoaderData memory can be reused by the kernel, but there seems to be a bug in the UEFI implementation VBox uses that makes custom memory types hang the firmware.
        UserReservedMemoryType : EFI_MEMORY_TYPE : #ifx VIRTUALBOX_COMPATIBILITY then EFI_MEMORY_TYPE.EfiLoaderData else 0x8000_0000;

        boot_data_address: u64 = Boot_Data.BASE_ADDRESS;
        EFI_CHECK(boot_services.AllocatePages(.AllocateAddress, UserReservedMemoryType, size_of(Boot_Data) / 4096 + 1, *boot_data_address));

        boot_data := cast(*Boot_Data) boot_data_address;
        boot_data.* = .{};

        // Memory for the loaded kernel executable.
        kernel_base: *void;
        EFI_CHECK(boot_services.AllocatePool(UserReservedMemoryType, 0x40_0000, *kernel_base));
        // Aligning this to 2MB is necessary because we map it as large pages, but this potentially wastes a lot of memory.
        // Maybe we can use one of the other UEFI allocators.
        kernel_base = cast(*void, (cast(s64) kernel_base + (0x20_0000 - 1)) & -0x20_0000);

        {
            // Get framebuffer and clear the screen

            gop: *EFI_GRAPHICS_OUTPUT_PROTOCOL;
            EFI_CHECK(boot_services.LocateProtocol(*EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID, null, cast(**void) *gop));

            gop.SetMode(gop, 9);

            framebuffer: [] u32;
            framebuffer.data  = cast(*u32) gop.Mode.frame_buffer_base;
            framebuffer.count = cast(s64) gop.Mode.frame_buffer_size / size_of(u32);

            for* framebuffer {
                it.* = 0x00ffff00;
            }

            console := system_table.ConOut;
            EFI_CHECK(console.Reset(console, 0));

            boot_data.framebuffer.buffer = cast(*u32) gop.Mode.frame_buffer_base;
            boot_data.framebuffer.x_resolution = gop.Mode.info.HorizontalResolution;
            boot_data.framebuffer.y_resolution = gop.Mode.info.VerticalResolution;
            boot_data.framebuffer.stride = gop.Mode.info.PixelsPerScanLine;
        }

        for 0..system_table.NumberOfTableEntries-1 {
            // Find root ACPI table
            table := system_table.ConfigurationTable[it];

            low  := <<  cast(*u64) *table.VendorGuid;
            high := << (cast(*u64) *table.VendorGuid + 1);

            acpi_table_guid_low  : u64 : 0x11d3e4f18868e871;
            acpi_table_guid_high : u64 : 0x81883cc7800022bc;

            if low == acpi_table_guid_low && high == acpi_table_guid_high {
                magic: string = .{ 8, table.VendorTable };
                boot_data.acpi_rsdp = table.VendorTable;
                break;
            }
        }


        display("Loading kernel .elf...\r\n");

        loaded_image_protocol: *EFI_LOADED_IMAGE_PROTOCOL;
        EFI_CHECK(boot_services.HandleProtocol(loaded_image, *EFI_LOADED_IMAGE_PROTOCOL_GUID, xx *loaded_image_protocol));

        file_system: *EFI_SIMPLE_FILE_SYSTEM_PROTOCOL;
        EFI_CHECK(boot_services.HandleProtocol(loaded_image_protocol.DeviceHandle, xx *EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID, xx *file_system));

        boot_volume: *EFI_FILE_PROTOCOL;
        EFI_CHECK(file_system.OpenVolume(file_system, *boot_volume));

        kernel_file: *EFI_FILE_PROTOCOL;
        file_name := cast(*u16) "k\0e\0r\0n\0e\0l\0\0\0".data;

        open_file_flags := EFI_FILE_ATTRIBUTES.READ_ONLY | .HIDDEN | .SYSTEM;
        EFI_CHECK(boot_volume.Open(boot_volume, xx *kernel_file, file_name, .Read, open_file_flags));

        Efi_File_Info :: struct {
            using #as file_info: EFI_FILE_INFO;
            file_name: [64] u16; // EFI_FILE_INFO has an arbitrary length name at the end
        }

        file_info: Efi_File_Info;
        info_size := size_of(Efi_File_Info);

        EFI_CHECK(boot_volume.GetInfo(boot_volume, *EFI_FILE_INFO_GUID, xx *info_size, *file_info));

        size: u64 = 0x20_0000; // file_info.FileSize; // For some reason FileSize is zero, even though boot_volume.GetInfo claims to have returned a valid File_Info
        load_buffer: *void;

        EFI_CHECK(boot_services.AllocatePool(.EfiLoaderData, size, *load_buffer));
        EFI_CHECK(kernel_file.Read(kernel_file, *size, load_buffer));



        display("Detect memory size...\r\n");

        limit :: (region: Boot_Data.Memory_Region) -> u64 {
            return region.address + region.pages * 4096;
        }

        descriptor_size: u64; // Don't assume that memory map entries will match Lil_Uefi's EFI_MEMORY_DESCRIPTOR structure, the OVMF.fd one is larger
        mmap_size: u64;

        boot_services.GetMemoryMap(*mmap_size, null, null, *descriptor_size, null); // Get the size, don't EFI_CHECK because return status will be BufferTooSmall

        mmap_size += 32 * descriptor_size;
        max_mmap_size := mmap_size;
        memory_map: *u8;

        mmap_key: EFI_UINTN;

        EFI_CHECK(boot_services.AllocatePool(.EfiLoaderData, mmap_size, cast(**void) *memory_map));
        EFI_CHECK(boot_services.GetMemoryMap(*mmap_size, xx memory_map, *mmap_key, null, null));

        entry_count := mmap_size / descriptor_size;

        // Find size of physical memory and allocate page frame descriptor array
        highest_address: u64;

        for 0..entry_count-1 {
            desc := cast(*EFI_MEMORY_DESCRIPTOR) (memory_map + it * descriptor_size);

            if cast(EFI_MEMORY_TYPE) desc.Type == {
              case .EfiUnusableMemory;     #through;
              case .EfiMemoryMappedIO;     #through;
              case .EfiPalCode;            #through;
              case .EfiReservedMemoryType; #through;
              case .EfiMemoryMappedIOPortSpace;
                continue;
            }

            region: Boot_Data.Memory_Region;

            region.address = desc.PhysicalStart;
            region.pages   = desc.NumberOfPages;

            // These are not guaranteed to be sorted by address, so check each one to find the amount of physical memory.
            if limit(region) > highest_address {
                highest_address = limit(region);
            }
        }

        {
            // Reserve physical memory for page frame descriptors
            count := highest_address / 0x20_0000;
            bytes := count * size_of(Large_Page);

            EFI_CHECK(boot_services.AllocatePool(UserReservedMemoryType, bytes, cast(**void) *boot_data.large_pages.data));
            memset(boot_data.large_pages.data, 0, xx bytes);
            boot_data.large_pages.count = cast(s64) count;
        }

        {
            display("Building page tables...\r\n");

            memset(*boot_data.page_tables, 0, size_of(Page_Tables));

            using boot_data.page_tables;

            PAGE_USER       : u64 : 0x4;
            PAGE_PRESENT    : u64 : 0x1 | PAGE_USER; // Adding the USER/SUPERVISOR bit to all pages so we can do stuff in ring 3 and not think about this yet.
            PAGE_READ_WRITE : u64 : 0x2;
            PAGE_SIZE       : u64 : 0x80;

            pml4[0]      = cast(u64) boot_pdpt.data | PAGE_PRESENT | PAGE_READ_WRITE;
            boot_pdpt[0] = cast(u64) boot_pd.data   | PAGE_PRESENT | PAGE_READ_WRITE;
            boot_pd[0]   = cast(u64) boot_pt.data   | PAGE_PRESENT | PAGE_READ_WRITE;

            // Low memory where the bootloader is loaded
            boot_pd[1] = 0x20_0000 | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            boot_pd[2] = 0x40_0000 | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            boot_pd[3] = 0x60_0000 | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;

            boot_pt[0] = 0;
            for 1..511 {
                boot_pt[it] = (4096 * cast(u64) it) | PAGE_PRESENT | PAGE_READ_WRITE;
            }

            // UEFI seems to put the stack at the top of physical memory. I don't know if that's standardised. For now assume that the machine has 256Mb
            index: int = 128;
            for 0..20 {
                boot_pd[index] = (0x1000_0000 - cast(u64) it*0x20_0000) | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
                index -= 1;
            }

            virtual_base : u64 : 0xffff_ffff_8000_0000;
            pml4[0x1ff] = cast(u64) pdpt.data | PAGE_PRESENT | PAGE_READ_WRITE;
            pdpt[0x1fe] = cast(u64) pd.data   | PAGE_PRESENT | PAGE_READ_WRITE;

            // 16Mb memory within the top two gigabytes, for the loaded kernel executable. The linker script specifies that this is where the loaded kernel executable should be placed.
            // Todo: these page directory indeces are hardcoded in a few places below.
            // Maybe have a table that defines the map of the top two gigabytes of virtual memory.
            for 0..7 {
                address := cast(u64) kernel_base + cast(u64) it * 0x20_0000;
                pd[it] = address | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            }

            // Direct-map all physical memory to the bottom of kernel memory
            pml4[0x100] = cast(u64) direct_pdpt.data | PAGE_PRESENT | PAGE_READ_WRITE;

            for pd: 0..direct_pd.count-1 {
                direct_pdpt[pd] = cast(u64) direct_pd[pd].data | PAGE_PRESENT | PAGE_READ_WRITE;

                for pt: 0..0x1ff {
                    address := cast(u64) (pd*0x4000_0000 + pt*0x20_0000);
                    direct_pd[pd][pt] = address | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
                }
            }

            offset := cast(u64) boot_data.framebuffer.buffer & 0x1fffff;

            // Map the framebuffer. Todo: enable write combining for this memory
            pd[8]  = (cast(u64) boot_data.framebuffer.buffer - offset)             | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            pd[9]  = (cast(u64) boot_data.framebuffer.buffer - offset + 0x20_0000) | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            pd[10] = (cast(u64) boot_data.framebuffer.buffer - offset + 0x40_0000) | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            pd[11] = (cast(u64) boot_data.framebuffer.buffer - offset + 0x60_0000) | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;

            // Translate framebuffer address to virtual
            boot_data.framebuffer.buffer = cast(*u32) (virtual_base + 8*0x20_0000 + offset);


            // Map load_buffer, which contains the kernel ELF file, to be loaded into high virtual memory later.
            offset = cast(u64) load_buffer & 0x1fffff;

            pd[12] = (cast(u64) load_buffer - offset)             | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            pd[13] = (cast(u64) load_buffer - offset + 0x20_0000) | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            pd[14] = (cast(u64) load_buffer - offset + 0x40_0000) | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;

            // Translate load buffer address to virtual
            load_buffer = cast(*void) (virtual_base + 12*0x20_0000 + offset);


            // Map the page frame descriptors
            page_directories_needed := (boot_data.large_pages.count * size_of(Large_Page)) / (0x20_0000) + 2;
            offset = cast(u64) boot_data.large_pages.data & 0x1fffff;

            for 0..page_directories_needed-1 {
                base := cast(u64) boot_data.large_pages.data - offset + cast(u64) it * 0x20_0000;
                pd[15 + it] = base | PAGE_PRESENT | PAGE_READ_WRITE | PAGE_SIZE;
            }

            // Translate page frame descriptor array address to virtual
            boot_data.large_pages.data = cast(*Large_Page) (virtual_base + 14*0x20_0000 + offset);
            boot_data.page_directories_used = 15 + page_directories_needed;
        }

        mmap_key = 0;
        mmap_size = max_mmap_size;
        EFI_CHECK(boot_services.GetMemoryMap(*mmap_size, xx memory_map, *mmap_key, null, null));

        entry_count = mmap_size / descriptor_size;
        boot_data.memory_map_entries_used = 0;

        display("Parsing firmware memory map...\r\n");

        for 0..entry_count-1 {
            desc := cast(*EFI_MEMORY_DESCRIPTOR) (memory_map + it * descriptor_size);

            region: Boot_Data.Memory_Region;

            region.address = desc.PhysicalStart;
            region.pages   = desc.NumberOfPages;

            memory_type := cast(EFI_MEMORY_TYPE) desc.Type;

            #if VIRTUALBOX_COMPATIBILITY {
                // Cannot distinguish EfiLoaderData from memory that the kernel needs, due to EDK II bug about custom memory types.
                if memory_type == .EfiLoaderData memory_type = UserReservedMemoryType;
            } else {
                if memory_type == .EfiLoaderData memory_type = .EfiConventionalMemory;
            }

            if memory_type == {
              case UserReservedMemoryType;
                region.type = .RESERVED_BY_THE_BOOTLOADER;
              case .EfiACPIReclaimMemory;       #through;
              case .EfiACPIMemoryNVS;           #through;
              case .EfiUnusableMemory;          #through;
              case .EfiMemoryMappedIO;          #through;
              case .EfiMemoryMappedIOPortSpace; #through;
              case .EfiRuntimeServicesCode;     #through;
              case .EfiRuntimeServicesData;
                region.type = .RESERVED_BY_FIRMWARE;
              case .EfiLoaderCode;              #through;
              case .EfiBootServicesCode;        #through;
              case .EfiBootServicesData;        #through;
              case .EfiConventionalMemory;
                region.type = .FREE;
              case;
                region.type = .DONT_KNOW;
            }

            bd := boot_data;

            if bd.memory_map_entries_used != 0 {
                // If two regions are contiguous, just grow the previous one.
                // Won't always coalesce perfectly because the firmware doesn't guarantee that memory map entries are sorted by address.

                last_region := *bd.memory_map[bd.memory_map_entries_used-1];

                types_match := last_region.type == region.type;
                contiguous  := limit(last_region.*) == region.address;

                if types_match && contiguous {
                    last_region.pages += region.pages;
                    continue;
                }

                monotonic := last_region.address < region.address;
                if !monotonic {
                    display("Error: Firmware memory map is not in order.\r\n");
                    display("Last region: ", last_region.address, "|", last_region.pages, "|", last_region.type, "\r\n");
                    display("This region: ",      region.address, "|",      region.pages, "|",      region.type, "\r\n");

                    break;
                }

                if !contiguous {
                    gap_base := limit(last_region.*);

                    display("Warning: Firmware memory map is not contiguous: ", gap_base, " <-> ", region.address, "\r\n");

                    gap_region: Boot_Data.Memory_Region;
                    gap_region.type    = .NOT_REPORTED;
                    gap_region.address = gap_base;
                    gap_region.pages   = (region.address - gap_base) / 4096;

                    bd.memory_map[bd.memory_map_entries_used] = gap_region;
                    bd.memory_map_entries_used += 1;
                }
            }

            bd.memory_map[bd.memory_map_entries_used] = region;
            bd.memory_map_entries_used += 1;

            if bd.memory_map_entries_used == bd.memory_map.count {
                display("Ran out of memory map entries.\r\n");
                break;
            }
        }

        display("Exiting boot services...\r\n");
        while boot_services.ExitBootServices(loaded_image, mmap_key) == .InvalidParameter {
            // ExitBootServices itself can sometimes change the memory map, in which case you need to call it again.
            // Todo: does this mean we need to update the one we give the kernel?
            mmap_key = 0;
            mmap_size = max_mmap_size;
            boot_services.GetMemoryMap(*mmap_size, xx memory_map, *mmap_key, null, null);
        }

        serial_out("Loading page tables...\n");
        cr3 := boot_data.page_tables.pml4.data;
        #asm {
            cli;
            set_cr3 cr3;
        }

        {
            serial_out("Loading kernel ELF...\n");

            elf := load_buffer;

            elf_header := cast(*Elf64_Ehdr) elf;

            for 0..elf_header.e_phnum-1 {

                base := elf + elf_header.e_phoff;
                base += it  * elf_header.e_phentsize;
                program_header := cast(*Elf64_Phdr) base;

                if program_header.p_type != PT_LOAD continue;

                memcpy(
                    cast(*void) program_header.p_vaddr,
                    elf +       program_header.p_offset,
                    cast(s32)   program_header.p_filesz
                );

                if program_header.p_memsz > program_header.p_filesz {
                    start := program_header.p_vaddr + program_header.p_filesz;
                    count := program_header.p_memsz - program_header.p_filesz;
                    memset(cast(*void) start, 0, cast(s64) count);
                }
            }

            serial_out("Jumping to the kernel...\n");
            entry_point := << cast(*() #no_context) *(elf_header.e_entry);
            entry_point();
        }

        while true {}
    }

    return 0;
}

EFI_CHECK :: check_efi_status;

check_efi_status :: (status: EFI_STATUS, loc := #caller_location) {
    if status == .Success {
        return;
    }

    ti := type_info(EFI_STATUS);

    for ti.values if it == cast(int) status {
        enum_name := ti.names[it_index];
        display("UEFI call failed on line ", loc.line_number, " with status ", enum_name, "\r\n");

        return;
    }

    display("UEFI call failed on line ", loc.line_number, " with unknown status code 0x", cast(u64) status, "\r\n");
}

display :: (args: .. Any) {
    for args {
        if it.type.type == .STRING {
            display_string(<< cast(*string) it.value_pointer);
        }

        if it.type.type == .INTEGER {
            integer: u64;
            memcpy(*integer, it.value_pointer, it.type.runtime_size);
            display_int(integer);
        }
    }
}

display_string :: (message: string) {
    buffer: [256] u16;
    wide_text := ascii_to_wide(message, buffer);

    console := context.system_table.ConOut;
    console.OutputString(console, wide_text);
}

display_int :: (value: u64) {
    hex_chars := "0123456789abcdef";
    result: [16] u8;

    for 0..15 {
        result[it] = hex_chars[(value >> (60 - it * 4)) & 0xF];
    }

    display_string(cast(string) result);
}

ascii_to_wide :: (input: string, buffer: [] u16) -> *u16 {
    for cast([] u8) input {
        buffer[it_index] = cast(u16) it;
    }

    buffer[input.count] = 0;
    return buffer.data;
}

#program_export
__chkstk :: () {}

serial_out :: (data: string) #no_context {
    COM1 :: 0x3f8;

    for cast([] u8) data {
        for 1..10_0000 {
            status: u8;
            port := COM1 + 5;

            #asm {
                status === a;
                port   === d;
                in.b status, port;
            }

            if status & 0x20 break;

            #asm { pause; }
        }

        byte := it;
        port := COM1;

        #asm {
            byte === a;
            port === d;
            out.b port, byte;
        }
    }
}

write_number :: (n: u64, base := 16) {
    if n == 0 {
        serial_out("0\r\n");
        return;
    }

    if base > 16  base = 16;
    if base < 2   base = 2;

    ubase := cast,no_check(u64) base;

    // This is of course a horrible hack.
    // A u64 in base 2 can be up to 64 digits,
    // so we need at least that much space. Add a few more digits for superstition.
    buf: [69] u8;

    starting_cursor : s32 = buf.count;
    cursor := starting_cursor;


    while n {
        cursor -= 1;
        index := n % ubase;
        if index <= 9 {
            buf[cursor] = cast(u8)(index + #char "0");
        } else {
            buf[cursor] = cast(u8)(index - 10 + #char "a");
        }

        n /= ubase;
    }

    s: string = ---;
    s.data  = buf.data + cursor;
    s.count = starting_cursor - cursor;
    serial_out(s);
    serial_out("\r\n");
}
