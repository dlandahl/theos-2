
// Stuff that's shared between bootloader and kernel

Framebuffer :: struct {
    buffer: *u32;
    x_resolution: int;
    y_resolution: int;
    stride: int;
}

Page_Tables :: struct {
    pml4: [0x200] u64;

    // Page tables for the kernel executable, at the top of virtual memory
    pdpt: [0x200] u64;
    pd:   [0x200] u64;

    // Page tables for the direct mapping, above the middle of virtual memory
    direct_pdpt:   [0x200] u64;
    direct_pd: [64][0x200] u64;

    // Page tables for the bootloader executable, at the bottom of virtual memory
    boot_pdpt: [0x200] u64;
    boot_pd:   [0x200] u64;

    // The lowest 2MB is a regular page table rather than a large page, so we can trap null pointers.
    boot_pt:   [0x200] u64;
}

DIRECT_MAPPING_BASE :: 0xffff_8000_0000_0000;

Boot_Data :: struct {
    page_tables: Page_Tables; // This should be the first field to ensure alignment of page tables to a page boundary

    BASE_ADDRESS :: 0x10_0000;

    trace_buffers: [4] u64;

    kernel_elf: []u8;

    page_directories_used: int;

    framebuffer: Framebuffer;

    acpi_rsdp: *void;

    Memory_Region :: struct {
        address: u64;
        pages: u64;

        type: enum {
            FREE;
            RESERVED_BY_THE_BOOTLOADER;
            RESERVED_BY_FIRMWARE;
            DONT_KNOW;
            NOT_REPORTED;
        }
    }

    memory_map: [100] Memory_Region;
    memory_map_entries_used: int;

    large_pages: [] Large_Page;
}

Large_Page :: struct {
    // Used for the free-list of unused physical pages, and the clear-list, index of the next page the be filled with zeros before it can be reused.
    list_next: s32;

    state: enum u8 {
        FREE;
        ALLOCATED;
        DISK_CACHE;
        RESERVED;
    };

    // ------- Disk cache entry -------
    more_recently_used: s32;
    less_recently_used: s32;


    // ------- Disk cache hash table entry -------
    lru_entry: s32; // The 2MB disk block with the same index as this page, where is it in the cache

    // At the moment, the hash function of the LRU cache is f(x)=x mod N, where N is the number of large pages.
    // Collisions are resolved by evicting the old block.
    lru_current_block: u64;
}

#program_export
memset :: (target: *void, value: u8, count: s64) -> *void #c_call {
    #asm {
        cld;

        count  === c;
        target === di;
        value  === a;
        rep_stos.b target, value, count;
    }

    return target;
}

#program_export
memcpy :: (dst: *void, src: *void, count: s64) -> *void #c_call {
    #asm {
        cld;

        src   === si;
        dst   === di;
        count === c;
        rep_movs.b dst, src, count;
    }

    return dst;
}

// For some reason the function interposition trick doesn't work with memcmp, even though it works with memset and memcpy.
#program_export
_memcmp :: (a: *void, b: *void, count: u64) -> s16 #c_call {
    for 0..count-1 {
        if a.(*u8)[it] != b.(*u8)[it] return -1;
    }

    return 0;

    /*
    start := a;

    #asm {
        cld;
        
        count === c;
        a     === si;
        b     === di;
        repe_cmps.b b, a, count;
    }

    if start + count == a {
        return 0;
    }

    return cast(s16) (*(a-1) - *(b-1));
    */
}

shutdown_emulator :: () #no_context {
    out :: (port: u16, value: u16) #no_context {
        #asm {
            port  === d;
            value === a;
            out.w port, value;
        }
    }

    out(0xb004, 0x2000);
    out(0x0604, 0x2000);
    out(0x4004, 0x3400);
}
