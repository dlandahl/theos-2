
#assert CPU == .X64 "AES module relies on Intel hardware acceleration";

// It might seem reasonable to use the Int128 module here, but in fact we need none of the operations implemented there and it would create a dependency on Basic.

// Todo: there is advice here on how to improve pipelining in these algorithms:
// www.intel.com/content/dam/doc/white-paper/advanced-encryption-standard-new-instructions-set-paper.pdf

#scope_export

i128 :: union {
    struct {low, high: u64;};
    bytes: [16]u8;
    dwords: [4]u32;
}

to_i128 :: ($text: string) -> i128 #modify {
    return text.count == 16, "to_i128: length must be 16 bytes.";
} {
    return i128.{ bytes = xx text };
}

operator^ :: (a: i128, b: i128) -> i128 {
    c: i128;
    c.low = a.low ^ b.low;
    c.high = a.high ^ b.high;
    return c;
}

operator== :: (a: i128, b: i128) -> bool {
    // Don't use memcmp (or string ==) here, because in theory it creates a timing sidechannel.
    xor := a ^ b;
    return xor.low == 0 && xor.high == 0;
}

byteswap_i128 :: (value: i128) -> i128 {
    result: i128;
    for 0..15 result.bytes[it] = value.bytes[15-it];
    return result;
}



aes128_check_intel_instruction_set_support :: () -> bool {
    ecx: u64;

    #asm {
        ecx === c;
        mov eax: gpr === a, 1;
        cpuid eax, ebx:, ecx, edx:;
    }

    return cast(bool)(ecx & 1 << 25);
}

aes128_expand_key :: (key: i128) -> [11]i128 {

    key_schedule: [11]i128;
    key_schedule[0] = key;

    GenerateRoundKey :: (key: i128, $round: u8) -> i128 {
        t1, t2, t3: i128;

        #asm {
            movdqa t1, key;
            aeskeygenassist t2, t1, round;

            pshufd t2, t2, 0xff;
            movdqa t3, t1;
            pslldq t3, 0x4;
            pxor   t1, t3;
            pslldq t3, 0x4;
            pxor   t1, t3;
            pslldq t3, 0x4;
            pxor   t1, t3;
            pxor   t1, t2;
        }

        return t1;
    }

    key_schedule[1]  = GenerateRoundKey(key_schedule[0], 0x1);
    key_schedule[2]  = GenerateRoundKey(key_schedule[1], 0x2);
    key_schedule[3]  = GenerateRoundKey(key_schedule[2], 0x4);
    key_schedule[4]  = GenerateRoundKey(key_schedule[3], 0x8);
    key_schedule[5]  = GenerateRoundKey(key_schedule[4], 0x10);
    key_schedule[6]  = GenerateRoundKey(key_schedule[5], 0x20);
    key_schedule[7]  = GenerateRoundKey(key_schedule[6], 0x40);
    key_schedule[8]  = GenerateRoundKey(key_schedule[7], 0x80);
    key_schedule[9]  = GenerateRoundKey(key_schedule[8], 0x1b);
    key_schedule[10] = GenerateRoundKey(key_schedule[9], 0x36);

    return key_schedule;
}

aes128_encrypt_block :: (text: *i128, key_schedule: [11]i128) {
    _text := text.*;

    whitening_key := key_schedule[0];
    #asm {pxor _text, whitening_key;}

    for 1..9 {
        key := key_schedule[it];
        #asm {aesenc _text, key;}
    }

    key := key_schedule[10];
    #asm {aesenclast _text, key;}

    text.* = _text;
}

aes128_decrypt_block :: (text: *i128, key_schedule: [11]i128) {
    _text := text.*;

    whitening_key := key_schedule[10];
    #asm {pxor _text, whitening_key;}

    for 1..9 {
        key := key_schedule[10-it];
        result: i128;

        #asm {
            aesimc result, key; // Todo, decryption keys could be cached. Worth it?
            aesdec _text, result;
        }
    }

    key := key_schedule[0];
    #asm {aesdeclast _text, key;}

    text.* = _text;
}



// Cipher Block Chaining (CBC)...

AES128_CBC_Context :: struct {
    key_schedule: [11]i128;
    last_ciphertext: i128;
}

aes128_cbc_create_context :: (initialization_vector: i128, encryption_key: i128) -> AES128_CBC_Context {
    // Use one context per stream of blocks to be encoded or decoded.
    ctx: AES128_CBC_Context;
    ctx.key_schedule = aes128_expand_key(encryption_key);
    ctx.last_ciphertext = initialization_vector;

    return ctx;
}

aes128_cbc_encrypt_block :: (ctx: *AES128_CBC_Context, block: *i128) {
    block.* ^= ctx.last_ciphertext;
    aes128_encrypt_block(block, ctx.key_schedule);
    ctx.last_ciphertext = block.*;
}

aes128_cbc_decrypt_block :: (ctx: *AES128_CBC_Context, block: *i128) {
    cipher := block.*;
    aes128_decrypt_block(block, ctx.key_schedule);
    block.* ^= ctx.last_ciphertext;
    ctx.last_ciphertext = cipher;
}

aes_cbc_roundtrip_test :: () {

PLAINTEXT :: #string,cr END
Some say the world will end in fire,
Some say in ice.
From what I've tasted of desire
I hold with those who favour fire.
But if it had to perish twice,
I think I know enough of hate
To say that for destruction ice
Is also great
And would suffice.
END;

    #import "Basic";

    print("%\n", PLAINTEXT.count.(float) / 16);

    key := to_i128("aesEncryptionKey");
    iv  := to_i128("AESEncryptionIv ");

    enc_ctx := aes128_cbc_create_context(iv, key);
    dec_ctx := aes128_cbc_create_context(iv, key);

    text := cast(*i128)PLAINTEXT.data;

    for 0..PLAINTEXT.count/16-1 {
        aes128_cbc_encrypt_block(*enc_ctx, text + it);

        context.print_style.default_format_int.base = 16;
        print("%\n", text[it].bytes);
    }

    for 0..PLAINTEXT.count/16-1 {

        aes128_cbc_decrypt_block(*dec_ctx, text + it);

        decrypted: string;
        decrypted.count = 16;
        decrypted.data = text[it].bytes.data;

        print("%", decrypted);
    }
}



// Galois Counter Mode.

aes128_gcm_encrypt_stream :: (data: []u8, encryption_key: i128, initialization_vector: []u8, additional_authenticated_data: []u8) -> i128 {
    key_schedule := aes128_expand_key(encryption_key);

    hash_key: i128;
    aes128_encrypt_block(*hash_key, key_schedule);
    hash_key = byteswap_i128(hash_key);

    counter0 := get_counter0(hash_key, initialization_vector);

    encrypt_stream_counter_xor(data, key_schedule, counter0);

    auth := ghash(hash_key, additional_authenticated_data, data);

    aes128_encrypt_block(*counter0, key_schedule);

    return counter0 ^ auth;
}

aes128_gcm_decrypt_stream :: (data: []u8, encryption_key: i128, initialization_vector: []u8, additional_authenticated_data: []u8, authentication_tag: i128) -> bool {
    key_schedule := aes128_expand_key(encryption_key);

    hash_key: i128;
    aes128_encrypt_block(*hash_key, key_schedule);
    hash_key = byteswap_i128(hash_key);

    counter0 := get_counter0(hash_key, initialization_vector);

    tag_block := counter0;
    aes128_encrypt_block(*tag_block, key_schedule);

    auth := ghash(hash_key, additional_authenticated_data, data);

    if tag_block ^ auth != authentication_tag {
        return false;
    }

    encrypt_stream_counter_xor(data, key_schedule, counter0);

    return true;
}

#scope_module

gcm_inc32 :: (counter: *i128) {
    #asm {
        mov.32 n:, [counter + 12];
        bswap.32 n;
        inc n;
        bswap.32 n;
        mov.32 [counter + 12], n;
    }
}

galois_multiply :: (x: i128, y: i128) -> i128 {
    /*
      Todo: According to NIST document this algorithm can be sped up a lot.

      "Multiplication in a binary field can use a variety of time-memory tradeoffs. It can be implemented
      with no key-dependent memory, in which case it will generally run several times slower than AES.
      Implementations that are willing to sacrifice modest amounts of memory can easily realize speeds
      greater than that of AES."

      csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf

      However this might be superseded by the PCLMULQDQ version from Intel below, since we already depend on the AES instruction set.

    */

    z: i128;

    v := y;
    w := x;

    R :: i128.{ low = 0x0000_0000_0000_0000, high = 0xe100_0000_0000_0000 };

    for 0..127 {
        if w.high & 0x8000_0000_0000_0000 {
            z ^= v;
        }

        lsb := v.low & 1;
        v.low = (v.low >> 1) | (v.high << 63);
        v.high >>= 1;

        if lsb != 0 {
            v ^= R;
        }

        w.high = (w.high << 1) | (w.low >> 63);
        w.low <<= 1;
    }

    return z;
}

// Todo: PCLMULQDQ version of GHASH.
// builders.intel.com/docs/networkbuilders/advanced-encryption-standard-galois-counter-mode-optimized-ghash-function-technology-guide-1693300747.pdf

ghash_internal :: (hash_key: i128, accumulator: *i128, data: []u8) {

    for 0..data.count/16-1 {
        block := (.*) (cast(*i128) data.data + it);
        block = byteswap_i128(block);

        accumulator.* ^= block;
        accumulator.* = galois_multiply(accumulator.*, hash_key);
    }

    remaining := data.count % 16;

    if remaining > 0 {
        block: i128;
        memcpy(block.bytes.data, data.data + data.count - remaining, remaining);
        block = byteswap_i128(block);

        accumulator.* ^= block;
        accumulator.* = galois_multiply(accumulator.*, hash_key);
    }
}

ghash :: (hash_key: i128, additional_authenticated_data: []u8, ciphertext: []u8) -> i128 {
    accumulator: i128;

    ghash_internal(hash_key, *accumulator, additional_authenticated_data);
    ghash_internal(hash_key, *accumulator, ciphertext);

    length_block: i128;
    length_block.low  = cast(u64) ciphertext.count * 8;
    length_block.high = cast(u64) additional_authenticated_data.count * 8;

    accumulator ^= length_block;
    accumulator = galois_multiply(accumulator, hash_key);

    return byteswap_i128(accumulator);
}

get_counter0 :: (hash_key: i128, iv: []u8) -> i128 {
    if iv.count == 12 {
        counter0: i128;

        for 0..11 counter0.bytes[it] = iv[it];
        counter0.dwords[3] = 0x0100_0000;

        return counter0;
    }

    return ghash(hash_key, .[], iv);
}

encrypt_stream_counter_xor :: (buffer: []u8, key_schedule: [11]i128, counter0: i128) {

    counter := counter0;

    for 0..buffer.count/16-1 {
        gcm_inc32(*counter);

        key := counter;
        aes128_encrypt_block(*key, key_schedule);

        block := cast(*i128) buffer.data + it;
        block.* ^= key;
    }

    remaining := buffer.count % 16;

    if remaining > 0 {
        gcm_inc32(*counter);
        key := counter;
        aes128_encrypt_block(*key, key_schedule);

        offset := buffer.count - remaining;

        block: i128;
        memcpy(block.bytes.data, buffer.data + offset, remaining);
        block ^= key;
        memcpy(buffer.data + offset, block.bytes.data, remaining);
    }
}



// AES GCM test cases from csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf

Aes128_NIST_Test_Case :: struct {
    secret_key: string;
    plaintext: string;
    initialization_vector: string;
    aad: string;

    expected_auth_tag: string;
    expected_ciphertext: string;
}

test_cases :: Aes128_NIST_Test_Case.[
    .{
        secret_key            = "00000000000000000000000000000000",
        initialization_vector = "000000000000000000000000",
        expected_auth_tag     = "58e2fccefa7e3061367f1d57a4e7455a",
    },
    .{
        secret_key            = "00000000000000000000000000000000",
        plaintext             = "00000000000000000000000000000000",
        initialization_vector = "000000000000000000000000",
        expected_auth_tag     = "ab6e47d42cec13bdf53a67b21257bddf",
        expected_ciphertext   = "0388dace60b6a392f328c2b971b2fe78",
    },
    .{
        secret_key            = "feffe9928665731c6d6a8f9467308308",
        plaintext             = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255",
        initialization_vector = "cafebabefacedbaddecaf888",
        expected_auth_tag     = "4d5c2af327cd64a62cf35abd2ba6fab4",
        expected_ciphertext   = "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
    },
    .{
        secret_key            = "feffe9928665731c6d6a8f9467308308",
        plaintext             = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
        initialization_vector = "cafebabefacedbaddecaf888",
        aad                   = "feedfacedeadbeeffeedfacedeadbeefabaddad2",
        expected_auth_tag     = "5bc94fbc3221a5db94fae95ae7121a47",
        expected_ciphertext   = "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091",
    },
    .{
        secret_key            = "feffe9928665731c6d6a8f9467308308",
        plaintext             = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
        initialization_vector = "cafebabefacedbad",
        aad                   = "feedfacedeadbeeffeedfacedeadbeefabaddad2",
        expected_auth_tag     = "3612d2e79e3b0785561be14aaca2fccb",
        expected_ciphertext   = "61353b4c2806934a777ff51fa22a4755699b2a714fcdc6f83766e5f97b6c742373806900e49f24b22b097544d4896b424989b5e1ebac0f07c23f4598",
    },
    .{
        secret_key            = "feffe9928665731c6d6a8f9467308308",
        plaintext             = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
        initialization_vector = "9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b",
        aad                   = "feedfacedeadbeeffeedfacedeadbeefabaddad2",
        expected_auth_tag     = "619cc5aefffe0bfa462af43c1699d050",
        expected_ciphertext   = "8ce24998625615b603a033aca13fb894be9112a5c3a211a8ba262a3cca7e2ca701e4a9a4fba43c90ccdcb281d48c7c6fd62875d2aca417034c34aee5",
    },
];

#run aes128_gcm_nist_test();

aes128_gcm_nist_test :: () {
    #import "Basic";

    if #compile_time {
        #import "Compiler";
        set_build_options_dc(.{do_output = false});
    }

    context.print_style.default_format_int.base = 16;

    parse :: (hex: string) -> []u8 {
        result: []u8;
        result.count = hex.count / 2;
        result.data = talloc(result.count);

        for *result {
            digit_1 := hex[it_index*2];
            digit_2 := hex[it_index*2 + 1];

            if is_digit(digit_1) digit_1 -= #char "0";
            else                 digit_1 -= #char "a" - 10;
            if is_digit(digit_2) digit_2 -= #char "0";
            else                 digit_2 -= #char "a" - 10;

            it.* = digit_1 * 16 + digit_2;
        }

        return result;
    }

    all_passed := true;

    for test_cases {

        secret_key: i128;
        memcpy(secret_key.bytes.data, parse(it.secret_key).data, 16);

        plaintext           := parse(it.plaintext);
        iv                  := parse(it.initialization_vector);
        aad                 := parse(it.aad);
        expected_auth_tag   := parse(it.expected_auth_tag);
        expected_ciphertext := parse(it.expected_ciphertext);

        auth_tag := aes128_gcm_encrypt_stream(plaintext, secret_key, iv, aad);

        if cast(string)auth_tag.bytes != cast(string)expected_auth_tag {
            print("Fail: auth tag does not match in test case % - got %\n", it_index + 1, auth_tag.bytes);
            all_passed = false;
        }

        if cast(string)plaintext != cast(string)expected_ciphertext {
            print("Fail: ciphertext does not match in test case %.\n", it_index + 1);
            all_passed = false;
        }

        authenticated := aes128_gcm_decrypt_stream(plaintext, secret_key, iv, aad, auth_tag);

        if !authenticated {
            print("Fail: authentication failed in test case %.\n", it_index + 1);
            all_passed = false;
        }

        if cast(string)plaintext != cast(string)parse(it.plaintext) {
            print("Fail: roundtrip failed in test case %.\n", it_index + 1);
            all_passed = false;
        }
    }

    if all_passed print("All tests passed.\n");
}
