// Merkle-Damgård construction, as used by many hash functions.
// Smári McCarthy, 2020-05-01.

merkle_damgard :: (data: string, block_size: int) -> blocks: int, padded: string {
    // We can allow a Merkel-Damgård construction of (roughly) any block size.
    // We only really want 64 and 128 bytes though.
    length_block := block_size >> 3;    // Byte count for input length counter.
    pad_length := block_size-length_block;

    lastblock_size := (data.count+1) % block_size; // including guard byte
    padding_bytes  := pad_length - lastblock_size;
    if lastblock_size > pad_length { padding_bytes += block_size; };

    data_padded: string;
    // Structure: [data][guard][padding][length]. The +1 is for the guard byte.
    data_padded.count = data.count + 1 + padding_bytes + length_block;
    data_padded.data = talloc(data_padded.count);

    memset(data_padded.data, 0, data_padded.count);
    memcpy(data_padded.data, data.data, data.count);

    data_padded[data.count] = 0b10000000; // Start padding with guard byte

    for < 0..length_block-1 {
        idx := data.count+padding_bytes+(length_block-it);
        if it*8 < 64 { // TODO: This is a workaround for a pre-beta Jai issue
                       // where shifts by more than word-length loops back.
            data_padded[idx] = cast(u8) ((data.count*8)>>(it*8)) & 0xff;
        }
    }
    return blocks = data_padded.count/block_size, padded = data_padded;
}
