// SHA2 hash function implementation.
// Standard: https://tools.ietf.org/html/rfc4634
// Smári McCarthy, 2020-05-01; updated 2022-01-25.

// TODO: We need to get away from endianism!
//       Most of this code is dumb because it's very stuck in little-endian
//       and assumes we're always going to want to end up with strings.

flip_endian :: (s: u32) -> u32 {
    return (((s & 0xff000000) >> 24) |
            ((s & 0x00ff0000) >> 8)  | 
            ((s & 0x0000ff00) << 8)  |
            ((s & 0x000000ff) << 24));
}


sha256 :: (data: string) -> string {
    H := sha256_base(data);
    digest: String_Builder;
    for 0..7 append(*digest, tprint("%", formatInt(H[it], base=16, minimum_digits=8)));
    return builder_to_string(*digest);
}

sha256_base :: (data: string) -> [8]u32 {
    initialization_vector := u32.[
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ];
    H := shabase(u32, data, initialization_vector);    
    return H;
}

sha256_base_flipped :: (data: string) -> [8]u32 {
    initialization_vector := u32.[
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ];
    H := shabase(u32, data, initialization_vector);
    I : [8]u32;
    for i:0..7 {
        I[i] = flip_endian(H[i]);
    }

    return I;
}

sha224 :: (data: string) -> string {
    initialization_vector := u32.[
        0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
        0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4
    ];

    H := shabase(u32, data, initialization_vector);
    digest: String_Builder;
    for 0..6 append(*digest, tprint("%", formatInt(H[it], base=16, minimum_digits=8)));
    return builder_to_string(*digest);
}

sha384 :: (data: string) -> string {
    initialization_vector := u64.[
        0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939,
        0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4
    ];
    H := shabase(u64, data, initialization_vector);
    digest: String_Builder;
    for 0..5 append(*digest, tprint("%", formatInt(H[it], base=16, minimum_digits=16)));
    return builder_to_string(*digest);
}

sha512 :: (data: string) -> string {
    initialization_vector := u64.[
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
    ];
    H := shabase(u64, data, initialization_vector);
    digest: String_Builder;
    for 0..7 append(*digest, tprint("%", formatInt(H[it], base=16, minimum_digits=16)));
    return builder_to_string(*digest);
}

SHA256_BLOCK_SIZE :: 64;
SHA256_HASH_SIZE :: 32;

hmac_sha256 :: (key: string, data: string) -> [SHA256_HASH_SIZE]u8 {

    k       : [SHA256_BLOCK_SIZE]u8;
    k_ipad  : [SHA256_BLOCK_SIZE]u8 = ---;
    k_opad  : [SHA256_BLOCK_SIZE]u8 = ---;
    ihash   : [SHA256_HASH_SIZE]u8 = ---;
    ohash   : [SHA256_HASH_SIZE]u8 = ---;

    if key.count > SHA256_BLOCK_SIZE {
        // If the key is larger than the hash algorithm's
        // block size, we must digest it first.
        f := sha256_base_flipped(key);
        memcpy(k.data, f.data, k.count/2);
    } else {
        memcpy(k.data, key.data, key.count);
    }

    memset(k_ipad.data, 0x36, SHA256_BLOCK_SIZE);
    memset(k_opad.data, 0x5c, SHA256_BLOCK_SIZE);

    for i:0..SHA256_BLOCK_SIZE-1 {
        k_ipad[i] ^= k[i];
        k_opad[i] ^= k[i];
    }

    H :: (x: $A, y: $B) -> [8]u32 {
        buf := talloc_string(x.count + y.count);
        memcpy(buf.data,           x.data, x.count);
        memcpy(buf.data + x.count, y.data, y.count);
        return sha256_base_flipped(buf);
    }

    // Perform HMAC algorithm: ( https://tools.ietf.org/html/rfc2104 )
    //      `H(K XOR opad, H(K XOR ipad, data))`
    memcpy(ihash.data,  H(k_ipad, data).data,   SHA256_HASH_SIZE);
    memcpy(ohash.data,  H(k_opad, ihash).data,  SHA256_HASH_SIZE);

    return ohash;
}


#scope_file
#load "md.jai";

sha256_consts :: u32.[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

sha512_consts :: u64.[
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817
];


BSIG0 :: (x: u32) -> u32 { return (x >>> 2) ^ (x >>> 13) ^ (x >>> 22); }
BSIG1 :: (x: u32) -> u32 { return (x >>> 6) ^ (x >>> 11) ^ (x >>> 25); }
SSIG0 :: (x: u32) -> u32 { return (x >>> 7) ^ (x >>> 18) ^ (x >> 3); }
SSIG1 :: (x: u32) -> u32 { return (x >>> 17) ^ (x >>> 19) ^ (x >> 10); }

BSIG0 :: (x: u64) -> u64 { return (x >>> 28) ^ (x >>> 34) ^ (x >>> 39); }
BSIG1 :: (x: u64) -> u64 { return (x >>> 14) ^ (x >>> 18) ^ (x >>> 41); }
SSIG0 :: (x: u64) -> u64 { return (x >>> 1) ^ (x >>> 8) ^ (x >> 7); }
SSIG1 :: (x: u64) -> u64 { return (x >>> 19) ^ (x >>> 61) ^ (x >> 6); }

CH  :: (x: $T, y: T, z: T) -> T { return (x & y) ^ ( (~x) & z); }
MAJ :: (x: $T, y: T, z: T) -> T { return (x & y) ^ (x & z) ^ (y & z); }


shabase :: ($T: Type, data: string, initialization_vector: [8]T) -> [8]T {
    #if T == u32 {
        // Config for SHA256 and SHA224.
        WORD :: 32;
        BLOCK :: 64;
        BYTES :: 4;
        WSIZE :: 64;
        SHA_CONSTS :: sha256_consts;
    }
    #if T == u64 {
        // Config for SHA512 and SHA384.
        WORD :: 64;
        BLOCK :: 128;
        BYTES :: 8;
        WSIZE :: 80;
        SHA_CONSTS :: sha512_consts;
    }

    M :: (i: T, t: T, data_padded: string) -> T {
        dp : T;
        idx := (i-1)*BLOCK+(t*BYTES);
        // TODO: Endianness. This is a slow way of enforcing big-endianness.
        //       Clean up with []u64 and data[(i-1)*16+t] with endian-enforcement.
        for 0..(BYTES-1) {
            dp |= (cast(T) data_padded[idx+xx it]) << (8*((BYTES-1)-it));
        }
        return dp;
    }

    W : [WSIZE]T;
    a, b, c, d, e, f, g, h : T;
    T1 : T = 0;
    T2 : T = 0;
    H := initialization_vector;
    blocks, data_padded := merkle_damgard(data, BLOCK);

    for 1..blocks {
        // Prepare message schedule W:
        for t:0..15 {
            W[t] = M(cast(T) it, cast(T) t, data_padded);
        }
        for t:16..WSIZE-1 {
            W[t] = SSIG1(W[t-2]) + W[t-7] + SSIG0(W[t-15]) + W[t-16];
        }

        // Initialize working variables:
        a = H[0];
        b = H[1];
        c = H[2];
        d = H[3];
        e = H[4];
        f = H[5];
        g = H[6];
        h = H[7];

        // Perform main hash computation:
        for t:0..WSIZE-1 {
            T1 = h + BSIG1(e) + CH(e,f,g) + SHA_CONSTS[t] + W[t];
            T2 = BSIG0(a) + MAJ(a,b,c);
            h = g;
            g = f;
            f = e;
            e = d + T1;
            d = c;
            c = b;
            b = a;
            a = T1 + T2;
        }

        // Compute H(i):
        H[0] += a;
        H[1] += b;
        H[2] += c;
        H[3] += d;
        H[4] += e;
        H[5] += f;
        H[6] += g;
        H[7] += h;
    }

    // free(data_padded);
    return H;
}
