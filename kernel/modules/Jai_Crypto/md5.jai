/*
    A simple MD5 utility
    Author: Mim Hufford
    Date:   01 May 2020
*/

md5 :: (input: string) -> string {

    // pad size to nearest 512 bits, plus make sure there is
    // room for 64 bits at the end to include the original size
    pad  := 64 - (input.count + 8) % 64;
    size := input.count + 8 + pad;
    assert(size % 64 == 0);

    // create a buffer we can work with
    data : []u8 = ---;
    data.count = size;
    data.data  = alloc(size);

    // zero everything out
    memset(data.data, 0, size);

    // copy in the original input
    memcpy(data.data, input.data, input.count);

    // write a 1 bit right after the original input
    data[input.count] = 0b1000_0000;

    // write original size (in bits) into last 64 bits
    dst := cast(*u64) (data.data + size - 8);
    dst.* = cast(u64) (input.count * 8);

    // set up digest parts
    a0 : u32 = 0x67452301;
    b0 : u32 = 0xefcdab89;
    c0 : u32 = 0x98badcfe;
    d0 : u32 = 0x10325476;

    // for each 512 bit chunk
    for chunk: 0..cast(u32)(size/64)-1 {
        A, B, C, D := a0, b0, c0, d0;

        // 64 passes
        for 0..cast(u32)63 {
            F, g : u32;

            if it < 16 {
                F = D ^ (B & (C ^ D));
                g = it;
            } else if it < 32 {
                F = C ^ (D & (B ^ C));
                g = (it*5 + 1) % 16;
            } else if it < 48 {
                F = B ^ C ^ D;
                g = (it*3 + 5) % 16;
            } else {
                F = C ^ (B | (~D));
                g = (it*7) % 16;
            }

            // grab the relevant 32 bits from the original input
            word := (.*) ((cast(*u32)data.data) + chunk*16 + g);

            // apply this section of data
            F += A + K[it] + word;
            A = D;
            D = C;
            C = B;
            B += F <<< s[it];
        }

        // update the digest with this chunk's data
        a0 += A;
        b0 += B;
        c0 += C;
        d0 += D;
    }

    // generate the digest
    sb : String_Builder;

    append :: (sb: *String_Builder, n: u32) {
        // Might be nicer here to just byte-swap if wrong endian and then do one print with minimum_digits=8.
        print_to_builder(sb, "%", formatInt((n >>  0) & 0xFF, base=16, minimum_digits=2));
        print_to_builder(sb, "%", formatInt((n >>  8) & 0xFF, base=16, minimum_digits=2));
        print_to_builder(sb, "%", formatInt((n >> 16) & 0xFF, base=16, minimum_digits=2));
        print_to_builder(sb, "%", formatInt((n >> 24) & 0xFF, base=16, minimum_digits=2));
    }

    append(*sb, a0);
    append(*sb, b0);
    append(*sb, c0);
    append(*sb, d0);

    return builder_to_string(*sb);
}

#scope_file

#import "Basic";

s :: u32.[
    7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
    5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
    4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
    6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,
];

K :: u32.[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

md5_tests :: () {
    assert(md5("") == "d41d8cd98f00b204e9800998ecf8427e");
    assert(md5("Mim Hufford") == "111126655c03434e1c4d7d1d9104b790");
    assert(md5("The quick brown fox jumps over the lazy dog") == "9e107d9d372bb6826bd81d3542a419d6");
    assert(md5("The man in black fled across the desert the gunslinger followed.") == "fe48b3e0d34c4a261dcd13fc277888a1");
    assert(md5("The man in black fled across the desert the gunslinger followed. The man in black fled across the desert the gunslinger followed.") == "eab13003ea3ff3c14370019a685956d3");
}
