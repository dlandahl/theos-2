// Original description of the MSF structure:
// Behaviour: implements a multistream file, where each stream is assigned
// a stream number.  All operations are transacted.  Logical change occurs
// atomically at Commit time only.  Operations include Open, Replace, Append,
// Read, and Delete stream, and Commit and Close.  Can query for the size of
// a stream or for an unused stream no.
//
// A MSF is implemented as a sequence of pages.  A page can contain
//  HDR     --  header structure, including stream table stream info
//  FPM     --  free page map: maps a page number (PN) to a boolean
//              where TRUE => page free
//  DATA    --  a stream data page
//
// The first few pages of a MSF are special:
//  PN  Type/Name   Description
//  0   HDR hdr     page 0: master index
//  1   FPM fpm0    first free page map
//  2   FPM fpm1    second free page map
//
// According to hdr.pnFpm, the first or the second free page map is valid.
//
// There is one special stream, snST, the "stream table" stream.  The stream
// table maps a stream number (SN) into a stream info (SI).  A stream info
// stores the stream size and an index to the subarray of the page numbers
// (PNs) that each stream uses.
//
// MSF capacity has been increased by making page numbers 32-bits and making
// 64K streams available. In the interest of the on-disk size of the file,
// the FPM has been split across the file at regular intervals, with new
// intervals introduced as needed. Also, a layer of indirection has been
// added to the stream table serialization. Where before the page list for
// the stream table was stored in the header page for the reconstruction of
// the stream table, now a page list of the pages is written instead. This
// way the page list for the stream table won't exceed a single page.
//
// This organization enables efficient two-phase commit.  At commit time,
// after one or more streams have been written (to new pages), a new
// StrmTbl stream is written and the new FPM is written.  Then, a single
// write to hdr swaps the roles of the two FPM sets and atomically
// updates the MSF to reflect the new location of the StrmTbl stream.

Msf :: struct {
    header: *Msf_Header_Big;
    parms: Msf_Parms;
    stream_table: Stream_Table;
    fpm: Free_Page_Map;
    fpm_freed: Free_Page_Map;
    siPnList: Stream_Info;

    content: string;
}

is_msf :: (file_content: string) -> bool {
    if file_content.count < size_of(Msf_Header_Big) return false;

    header := cast(*Msf_Header_Big) file_content.data;
    return (cast(string) header.magic) == MSF_HEADER_MAGIC;
}

parse_msf :: (file_content: string, path := "", verbose := false) -> success: bool, Msf {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false, .{};
        }
    } @PrintLike

    using msf: Msf;
    msf.parms = RGMSFPARMS[0];

    content = file_content;

    offset := 0;
    check(offset + size_of(Msf_Header_Big) <= content.count, "File is too small to be a MSF file: %", path);

    header_data := get_page_data(msf, PN_HDR);
    header = cast(*Msf_Header_Big) header_data.data;
    check(cast(string) header.magic == MSF_HEADER_MAGIC, "Invalid header magic for MSF file \"%\"", path);

    valid_page_size := false;
    for RGMSFPARMS_HC {
        if header.page_size == it.cbPg {
            msf.parms = it;
            valid_page_size = true;
            break;
        }
    }
    check(valid_page_size, "Invalid page size in PBD file \"%\": %", path, header.page_size);

    // MSF_HB::load
    stream_table.page_size_in_bytes = parms.page_size_in_bytes;

    if verbose log("MSF header: %\n", header.data);

    // (de-) serializeFpm
    {
        pnFirst := header.valid_fpm_page_no;
        check(pnFirst == 1 || pnFirst == 2, "Invalid first page number: %", pnFirst);

        // Calc number of bytes needed to represent FPM, aligned to FPM::native_word sizes
        cbFpm := cast(s32) (header.page_count + 8 - 1) / 8;
        cbFpm = size_of(u64) * ((cbFpm + size_of(u64) - 1) / size_of(u64));

        // Calc number of pages needed to represent that number of bytes
        cpnFpm := (cbFpm + parms.cbPg - 1) / parms.cbPg;

        // @ToDo: This is a very stupid algorithm. We could just copy the map in one go and/or just point at it!
        pnNextWrite := pnFirst;
        assert(cpnFpm * header.page_size >= cbFpm);
        init(*fpm,       parms.cbitsFpm, parms.cbPg);
        init(*fpm_freed, parms.cbitsFpm, parms.cbPg);
        ensure_room(*fpm, cast(u32) (cpnFpm * header.page_size * 8), fill = false);
        set_all(*fpm);

        fpm_buffer := cast(*u8) fpm.rgw.data;
        pnNextRead := pnFirst;
        while cpnFpm {
            success := copy_page_data(msf, pnNextRead, 0, header.page_size, fpm_buffer);
            if !success return false, .{};

            cpnFpm -= 1;
            pnNextRead += xx header.page_size;
            fpm_buffer += header.page_size;
        }

        if verbose log("FPM: %", fpm);
    }

    // Build the stream table stream info from the header, then
    // load the stream table stream and deserialize it
    stream_table_byte_count := header.st.byte_count;
    check(stream_table_byte_count >= 0, "Invalid stream info size: %", stream_table_byte_count);
    stream_table_stream_info: Stream_Info;
    {
        page_size_in_bytes := parms.page_size_in_bytes;

        // siStCreateBigMsf:
        // Build siSt from the layers of indirection between here and there.
        cpn := get_number_of_pages_for_bytes(xx stream_table_byte_count, page_size_in_bytes);
        cbpn := cast(s32) (cpn * size_of(UPN));
        alloc(*msf.siPnList, cbpn, page_size_in_bytes);

        num_pn := get_number_of_pages_for_bytes(xx cbpn, page_size_in_bytes);
        check(num_pn <= header.mpspnpnSt.count, "Corrupt stream info data");

        memcpy(siPnList.stream_page_numbers.data, header.mpspnpnSt.data, num_pn * size_of(PN32));

        // siPnList now contains the list of pages that contain the stream_page_numbers for the stream table
        alloc(*stream_table_stream_info, stream_table_byte_count, page_size_in_bytes);

        success, bytes_read := read_stream(msf, siPnList, 0, cast(*u8) stream_table_stream_info.stream_page_numbers.data, cbpn);
        check(success, "Couldn’t read the stream table stream info");
        check(bytes_read == cbpn, "Corrupt stream info data (#2)");
    }

    stream_data := NewArray(stream_table_byte_count, u8);
    defer array_free(stream_data);
    success, bytes_read := read_stream(msf, stream_table_stream_info, 0, stream_data.data, stream_table_byte_count);
    check(success, "Couldn’t read the stream table");
    check(bytes_read == stream_table_byte_count, "Corrupt stream table data (#2)");

    if verbose log("Stream data (% bytes): %", stream_data.count, stream_data);
    success = deserialize(msf, *msf.stream_table, stream_data);
    check(success, "Couldn’t deserialize stream table");

    // The stream_infos[STREAM_INFO_STREAM_INDEX] just loaded is bogus: it is the Stream_Table stream in effect
    // prior to the previous Commit.  Replace it with the good copy saved in the MSF hdr.
    msf.stream_table.stream_infos[STREAM_TABLE_STREAM_INDEX] = stream_table_stream_info;

    success = verify_integrity(msf);
    check(success, "MSF did not pass integrity check");

    if verbose {
        // Log some more debug info
        max_stream := get_highest_used_stream_number_plus_one(msf.stream_table);
        if max_stream > 0 {
            for si: 1..max_stream - 1 {
                size := get_stream_size(msf, si);
                if size log("Stream % has size %", si, size);
            }
        }
    }

    return true, msf;
}

get_stream_data :: (msf: Msf, stream_index: UNSN) -> [] u8, success: bool {
    size := get_stream_size(msf, stream_index);
    if size < 0 return .[], false;

    data := NewArray(size, u8);
    success, bytes_read := read_stream(msf, msf.stream_table.stream_infos[stream_index], 0, data.data, xx data.count);
    return data, success && bytes_read == size;
}


get_stream_size :: (msf: Msf, stream_index: UNSN) -> s64 {
    assert(is_valid_user_stream_number(msf, stream_index));
    assert(is_valid_stream_number(msf, stream_index));
    if !stream_exists(msf, stream_index)   return -1;

    return msf.stream_table.stream_infos[stream_index].byte_count;
}

is_valid_stream_number :: (msf: Msf, stream_index: UNSN) -> bool {
    return stream_index < UNSN_MAX;
}

is_valid_user_stream_number :: (msf: Msf, stream_index: UNSN) -> bool {
    return is_valid_stream_number(msf, stream_index) && stream_index != STREAM_TABLE_STREAM_INDEX;
}

stream_exists :: (msf: Msf, stream_index: UNSN) -> bool {
    return stream_index < msf.stream_table.stream_infos.count && msf.stream_table.stream_infos[stream_index].byte_count != Stream_Info.INVALID;
}

is_valid_page_number :: (msf: Msf, pn: UPN) -> bool {
    return pn < msf.parms.pnMax;
}

verify_integrity :: (msf: Msf) -> bool {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false;
        }
    } @PrintLike

    // check that every page is either free, freed, or in use in exactly one stream
    fpm_in_use: Free_Page_Map;
    init(*fpm_in_use, msf.parms.cbitsFpm, msf.parms.cbPg);
    ensure_room(*fpm_in_use, msf.header.page_count, fill = true);

    max_stream := get_highest_used_stream_number_plus_one(msf.stream_table);
    for sn: 0..max_stream-1 {
        si := msf.stream_table.stream_infos[sn];
        if si.byte_count == Stream_Info.INVALID continue;
        for pn: si.stream_page_numbers {
            check(is_valid_page_number(msf, pn), "Invalid page number % at % in stream %", pn, it_index, sn);
            check(!is_free_page(msf.fpm, pn), "Inconsistent data: % is marked as free", pn);
            check(!is_free_page(msf.fpm_freed, pn), "Inconsistent data: % is marked as freed", pn);
            check(!is_free_page(fpm_in_use, pn), "Inconsistent data: % is used more than once", pn);
            free_page(*fpm_in_use, pn);
        }
    }

    // Also check the the page numbers reserved in siPnList : they're not in a stream
    cpn := get_number_of_pages_for_bytes(xx msf.siPnList.byte_count, msf.parms.page_size_in_bytes);
    if cpn > 0 {
        for spn: 0..cpn-1 {
            pn := msf.siPnList.stream_page_numbers[spn];
            check(!is_free_page(msf.fpm, pn), "Inconsistent data: % is marked as free", pn);
            check(!is_free_page(msf.fpm_freed, pn), "Inconsistent data: % is marked as freed", pn);
            check(!is_free_page(fpm_in_use, pn), "Inconsistent data: % is used more than once", pn);
            free_page(*fpm_in_use, pn);
        }
    }

    for pn: msf.parms.pnDataMin..msf.parms.pnMax-1 {
        if !is_fpm_page_number(msf.fpm, pn) {
            uses := 0;
            uses += cast(int) is_free_page(msf.fpm, pn);
            uses += cast(int) is_free_page(msf.fpm_freed, pn);
            uses += cast(int) is_free_page(fpm_in_use, pn);
            check(uses == 1, "Inconsistent data: page % is used % times", pn, uses);
        }
    }

    return true;
}

#scope_module

get_page_data :: (msf: Msf, page_number: UPN) -> [] u8, success: bool {
    offset := offset_for_page(msf, page_number, 0);
    if offset + msf.parms.cbPg > msf.content.count {
        log_error("Page number is out of bounds: %", page_number);
        return .[], false;
    }

    return array_view(cast ([] u8) msf.content, offset, msf.parms.cbPg), true;
}

copy_page_data :: (msf: Msf, page_number: UPN, offset: s32, count: int, buffer: *u8) -> bool {
    data, success := get_page_data(msf, page_number);
    if !success return false;
    memcpy(buffer, data.data + offset, count);
    return true;
}


offset_for_page :: (msf: Msf, pn: UPN, off: s32) -> int {
    assert(off < msf.parms.cbPg);
    return off + cast(s32)pn * msf.parms.cbPg;
}

Msf_Stream :: struct {
    impv: u32;
    sig:  u32;
    age:  u32;
}

SN    :: u16;   // stream number
UNSN  :: u32;   // unified stream number

PN16  :: u16;   // page number
SPN16 :: u16;   // stream page number
PN32  :: u32;   // page number
SPN32 :: u32;   // stream page number

PN    :: PN16;
SPN   :: PN16;

UPN   :: PN32;  // universal page no.
USPN  :: SPN32; // universal stream page no.


SMALLPAGES :: false;

PG_MAX :: 0x1000;
#if SMALLPAGES {
    PG_MIN :: 0x200;
} else {
    PG_MIN :: 0x400;
}

PN_MAX_MAX  :: 0xffff; // max no of pgs in any msf


UNSN_MAX    :: 0x10000;  // 64k streams
UPN_MAX_MAX :: 0x100000; // 2^20 pages

PN_HDR :: 0;
RESERVED_PAGE_NUMBERS :: 3;    // first three pages in a big MSF are the header and two FPMs

MSF_HEADER_MAGIC :: "Microsoft C/C++ MSF 7.00\r\n\x1a\x44\x53\0";

STREAM_TABLE_STREAM_INDEX :: 0;
FIRST_USER_STREAM_INDEX   :: 1;

max_for_cb :: (cb: int) -> int {
    return (cb + PG_MIN - 1) / PG_MIN;
}

Msf_Header_Big :: union {
    using data: struct {
        magic:             [0x1e] u8;  // version string
        page_size:         s32;        // page size
        valid_fpm_page_no: UPN;        // page no. of valid FPM
        page_count:        UPN;        // original name: pnMac
        st:                Stream_Info_Persist;               // stream table stream info
        mpspnpnSt:         [#run max_for_cb(max_for_cb(Stream_Table.MAX_SER) * size_of(PN32))] PN32;
    }
    pg:                Pg;
}
#run {
    #import "Basic";
    assert(MSF_HEADER_MAGIC.count == size_of(type_of(Msf_Header_Big.magic)), "Size mismatch: % vs %", MSF_HEADER_MAGIC.count, size_of(type_of(Msf_Header_Big.magic)));
}
#assert(size_of(Pg) == size_of(Msf_Header_Big));

Msf_Parms :: struct {
    cbPg:           s32;
    page_size_in_bytes:         u32;
    mask_cb_pg_mod: u32;
    cbitsFpm:       s32;
    cpgFileGrowth:  s32;
    pnMax:          UPN;
    cpnFpm:         UPN;
    pnFpm0:         UPN;
    pnFpm1:         UPN;
    pnDataMin:      UPN;
};

RGMSFPARMS :: Msf_Parms.[
    .{PG_MIN, 10, PG_MIN - 1, PN_MAX_MAX + 1, 8, PN_MAX_MAX, 8, 1, 1 + 8, 1 + 8 + 8},
    .{2048,   11, 2048   - 1, PN_MAX_MAX + 1, 4, PN_MAX_MAX, 4, 1, 1 + 4, 1 + 4 + 4},
    .{PG_MAX, 11, PG_MAX - 1, 0x7fff + 1, 4, 0x7fff, 4, 1, 1 + 4, 1 + 4 + 4},
];

RGMSFPARMS_HC :: Msf_Parms.[
    .{PG_MIN, 10, PG_MIN - 1, UPN_MAX_MAX, 8, UPN_MAX_MAX, 1, 1, 1 + 1, 1 + 1 + 1},
    .{2048,   11, 2048   - 1, UPN_MAX_MAX, 4, UPN_MAX_MAX, 1, 1, 1 + 1, 1 + 1 + 1},
    .{PG_MAX, 12, PG_MAX - 1, UPN_MAX_MAX, 2, UPN_MAX_MAX, 1, 1, 1 + 1, 1 + 1 + 1},
];

Stream_Table :: struct { // (in memory) stream table
    // The stream table is serialized as follows:  Number of streams, followed by the stream table's SN->SI map (an array
    // of SI's), followed by each SI's SPN->PN map. So in this calculation, (u)pnMaxMax*sizeof((U)PN) takes into account
    // that the total number of SPN's for all SI's can be at most (u)pnMaxMax.

    MAX_SER :: UNSN_MAX * size_of(Stream_Info_Persist) + size_of(UNSN) + UPN_MAX_MAX * size_of(UPN); // cbBigMSFMaxSer


    page_size_in_bytes: u32;
    stream_infos:   [..] Stream_Info;
}

get_highest_used_stream_number_plus_one :: (st: Stream_Table) -> UNSN {
    // Find snMac, the largest sn such that stream_infos[snMac-1].isValid(),
    // or 0 if there does not exist any stream_infos[sn].isValid().
    for < st.stream_infos {
        if it.byte_count != Stream_Info.INVALID return xx (it_index + 1);
    }
    return 0;
}

Stream_Info :: struct {
    INVALID :: -1;
    byte_count: s32 = INVALID;
    stream_page_numbers: [..] UPN; // SPN->PN map
}

alloc :: (si: *Stream_Info, size: s32, page_size_in_bytes: u32) {
    si.byte_count = size;
    page_count := get_number_of_pages_for_bytes(xx size, page_size_in_bytes);

    // Allocate the SPN->PN map based on the calculated
    // required number of pages.
    array_resize(*si.stream_page_numbers, page_count);
    for * si.stream_page_numbers {
        it.* = cast,no_check(UPN) -1;
    }
}

Stream_Info_Persist :: struct {
    byte_count: s32;
    stream_page_numbers: s32;
}

Pg :: struct {
    rgb: [PG_MAX] u8;
}

get_number_of_pages_for_bytes :: (byte_count: u32, page_size_in_bytes: u32) -> u32 {
    // valid pages sizes are only 1k, 2k, 4k.
    assert(page_size_in_bytes >= 10 && page_size_in_bytes <= 12);
    return cast(u32) ((byte_count + (1 << page_size_in_bytes) - 1) >> page_size_in_bytes);
}


// Read a stream, cluster reads of contiguous pages
read_stream :: (msf: Msf, si: Stream_Info, off: s32, buffer: *u8, count: s32) -> bool, bytes_read: s32 {
    // ensure off and count remain within the stream
    if (off < 0 || off > si.byte_count || count < 0) {
        log_error("Read stream values are out of bounds: %, %", off, count);
        return false, 0;
    }

    clamped_count := count;
    if (clamped_count > si.byte_count - off) {
        clamped_count = si.byte_count - off;
    }

    if clamped_count == 0 return true, clamped_count;

    remaining := cast(u32) clamped_count;

    spn := cast(USPN) (off >> msf.parms.mask_cb_pg_mod); //(SPN)(off / cbPg());
    page_offset := (cast(u32) off) & msf.parms.mask_cb_pg_mod;    //off % cbPg();

    // first partial page, if any
    // @Speed: this could be folded into the loop belowfolded into the loop below
    if page_offset != 0 {
        assert(page_offset <= cast(u32) msf.parms.cbPg);
        count_first := min(cast(u32) msf.parms.cbPg - page_offset, remaining);
        assert(count_first >= 0);
        success := copy_page_data(msf, si.stream_page_numbers[spn], xx page_offset, xx count_first, buffer);
        if !success return false, clamped_count;

        remaining -= count_first;
        spn += 1;
        buffer += count_first;
    }

    // intermediate full pages, if any
    while remaining > 0 {
        // accumulate contiguous pages into one big read
        count_to_read: u32;
        current_page := si.stream_page_numbers[spn];
        start_page := current_page;
        while remaining > 0 && si.stream_page_numbers[spn] == current_page {
            spn += 1;
            current_page += 1;
            page_size := min(cast(u32) msf.parms.cbPg, remaining);
            count_to_read += page_size;
            remaining -= page_size;
        }

        success := copy_page_data(msf, start_page, 0, count_to_read, buffer);
        if !success return false, clamped_count;

        buffer += count_to_read;
    }

    assert(remaining == 0);
    return true, clamped_count;
}

deserialize :: (msf: Msf, stream_table: *Stream_Table, data: [] u8) -> bool {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return false;
        }
    } @PrintLike

    cursor := data.data;
    cursor_end := data.data + data.count;
    check(data.count >= size_of(SPN32), "Invalid stream table: Couldn’t read ");
    snMacT := (.*) (cast(*SPN32) cursor);
    cursor += size_of(SPN32);
    check(snMacT < UNSN_MAX, "Invalid stream table: Invalid stream count");
    if snMacT > stream_table.stream_infos.count {
        array_resize(*stream_table.stream_infos, snMacT);
    }

    success, bytes_consumed := read_stream_info_counts(stream_table.stream_infos, cursor, cursor_end);
    check(success, "Invalid stream table: Invalid end of stream table counts");
    cursor += bytes_consumed;
    assert(cursor <= cursor_end);

    // [de]serialize each valid SI
    for * si: stream_table.stream_infos {
        if si.byte_count == Stream_Info.INVALID continue;

        count := get_number_of_pages_for_bytes(xx si.byte_count, stream_table.page_size_in_bytes);
        byte_count := count * size_of(PN32);
        check(cursor + byte_count <= cursor_end, "Invalid stream table: Stream info % went out of bounds", it_index);
        array_resize(*si.stream_page_numbers, count);
        memcpy(si.stream_page_numbers.data, cursor, byte_count);
        cursor += byte_count;
    }

    assert(cursor <= cursor_end);
    check(cursor == cursor_end, "Invalid stream table: Unexpected leftover data of % byte", cursor_end - cursor);
    return true;
}

read_stream_info_counts :: (dest: [] Stream_Info, cursor: *u8, end: *u8) -> success: bool, int {
    size := dest.count * size_of(s32);
    if cursor + size > end return false, 0;

    src_count_pointer := cast(*s32) cursor;
    for dest {
        dest[it_index].byte_count = src_count_pointer.*;
        src_count_pointer += 1;
    }

    return true, size;
}
