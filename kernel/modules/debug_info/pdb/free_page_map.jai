Free_Page_Map :: struct { // (in-memory version)
    BPW :: 8 * size_of(u64);
    iwMac: u32;      // set to max size of the FPM bit array, based on small or big msfs
    iwRover: u32;    // heuristic approach for finding a free page quickly
    cbPg: s32;
    fBigMsf: bool;

    rgw: [..] s64;
    wFill: s64;          // keep track of the last fill type, as any appending we do to the array needs to be this type
}

init :: (fpm: *Free_Page_Map, cbitsFpm: s32, cbPg: s32) {
    fpm.iwMac = xx (cbitsFpm / fpm.BPW);
    fpm.iwRover = 0;
    fpm.wFill = 0;
    fpm.cbPg = cbPg;
}

ensure_room :: (using fpm: *Free_Page_Map, upnMac: UPN, fill: bool) {
    required_slots := (upnMac + BPW - 1) / BPW;
    if required_slots > rgw.count {
        old_count := rgw.count;
        array_resize(*rgw, required_slots);
        if fill {
            for i: old_count..xx required_slots-1 {
                rgw[i] = wFill;
            }
        }
    }
}

set_all :: (using fpm: *Free_Page_Map) {
    wFill = ~0;
    for * rgw {
        it.* = wFill;
    }
    
    iwRover = 0;
}

is_free_page :: (using fpm: Free_Page_Map, page_number: UPN) -> bool {
    iw := page_number / BPW;
    if iw >= rgw.count && iw < iwMac {
        // catch all of the virtual pages that we would have if
        // we were still using a static array
        return wFill != 0;
    } else if iw < rgw.count {
        // check an actual entry
        mask := 1 << (page_number & (BPW - 1));
        return (rgw[iw] & mask) != 0;
    } else {
        // outta here.  no more room.
        return false;
    }

}

alloc_page :: (using fpm: *Free_Page_Map, page_number: UPN) {
    assert(is_free_page(fpm, page_number));
    iw := page_number / BPW;
    rgw[iw] &= ~(1 << (page_number & (BPW - 1)));
}

free_page :: (using fpm: *Free_Page_Map, page_number: UPN) {
    iw := page_number / BPW;
    rgw[iw] |= (1 << (page_number & (BPW - 1)));
    iwRover = 0; // @ToDo: Why not " = iw"?? -rluba, 2023-12-02
}

is_fpm_page_number :: (using fpm: Free_Page_Map, pn: UPN) -> bool {
    // For a bigMsf, the page map pages are scattered
    // at regular intervals throughout the file.

    // Allow the first three special pages to be allocated
    if (pn < RESERVED_PAGE_NUMBERS) return false;

    // Every other pair of page map pages starts at offsets
    // 1 and 2 from the start of their page range.
    // (The following calculation works because cbPg is always
    // a power of 2.)

    // REVIEW: Bug.  we should be reserving pages at cbPg * CHAR_BIT
    //  page numbers, thus we are reserving 8 times as many pages as
    //  necessary.
    //
    pnT := pn & cast,no_check(u32) (cbPg - 1);  // pn % cbPg
    return (pnT == 1 || pnT == 2);
}

