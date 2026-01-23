Tpi_Stream_Header :: struct {
  version:                    Tpi_Stream_Version;
  header_size:                u32;
  type_index_begin:           u32;
  type_index_end:             u32;
  type_record_bytes:          u32;

  hash_stream_index:          u16;
  hash_aux_stream_index:      u16;
  hash_key_size:              u32;
  num_hash_buckets:           u32;

  hash_value_buffer_offset:   s32;
  hash_value_buffer_length:   u32;

  index_offset_buffer_offset: s32;
  index_offset_buffer_length: u32;

  hash_adj_buffer_offset:     s32;
  hash_adj_buffer_length:     u32;
}

Tpi_Stream_Version :: enum u32 {
    V40 :: 19950410;
    V41 :: 19951122;
    V50 :: 19961031;
    V70 :: 19990903;
    V80 :: 20040203;
}

parse_tpi_stream :: (msf: Msf, stream_index: UNSN, verbose := false) -> [] *Codeview_Type, success: bool {
    check :: (condition: bool, message: string, args: .. Any) #expand #no_debug {
        if !condition {
            log_error(message, ..args);
            `return .[], false;
        }
    } @PrintLike

    tpi_data, success := get_stream_data(msf, stream_index);
    check(success, "Couldn’t get data for TPI stream %", stream_index);
    state: Pdb_Parser_State;
    state.data = tpi_data;
    tpi_header := get(*state, Tpi_Stream_Header);
    check(!state.failed, "Couldn’t get TPI header");
    if verbose log("TPI header for stream %: %", stream_index, tpi_header);
    check(tpi_header.version == .V80, "Unexpected TPI header version: %", tpi_header.version);
    check(tpi_header.header_size == size_of(Tpi_Stream_Header), "Unexpected TPI header size: %", tpi_header);
    check(tpi_header.type_index_begin == 0x1000, "Unexpected TPI type index beginning: %", tpi_header.type_index_begin); // @Incomplete: We could handle different offsets but currently don’t because has never ocurred.

    type_data := get_array(*state, tpi_header.type_record_bytes, u8);
    check(!state.failed, "Couldn’t get TPI data");
    success=, result := parse_codeview_types(type_data, expect_codeview_version = false, verbose = verbose);

    expected_type_count := tpi_header.type_index_end - tpi_header.type_index_begin;
    check(result.count == expected_type_count, "Number of parsed types in stream % does not match the information in the header: % vs %", stream_index, result.count, expected_type_count);
    return result, success;
}


