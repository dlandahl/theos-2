
#assert CPU == .X64 "AES module relies on Intel hardware acceleration";

// It might seem reasonable to use the Int128 module here, but in fact we need none of the operations implemented there and it would create a dependency on Basic.

// Todo: there is advice here on how to improve pipelining in these algorithms:
// https://www.intel.com/content/dam/doc/white-paper/advanced-encryption-standard-new-instructions-set-paper.pdf

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



#if false #run {
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

}





#if false {
    // WARNING: This implementation of Galois counter mode is not finished and probably doesn't produce correct results.

    aes128_gcm_encrypt_stream_in_place :: (padded_stream: []u8, key: i128, nonce: [3]u32, authenticated_data: []u8) -> auth_tag: i128 {
        counter := i128.{
            dwords = .[1, nonce[0], nonce[1], nonce[2]]
        };

        key_schedule := aes128_expand_key(key);

        blocks: []i128;
        blocks.data = cast(*i128)padded_stream.data;
        blocks.count = padded_stream.count / 16;

        for 0..blocks.count-1 {
            inc32(*counter);

            E_k := aes128_encrypt_block(counter, key_schedule);

            blocks[it] ^= E_k;
        }

        return .{};
    }
}





#scope_file

inc32 :: (a: *i128) {
    #no_aoc {
        a.dwords[0] += 1;
    }
}

operator^ :: (a: i128, b: i128) -> i128 {
    c: i128;
    c.low = a.low ^ b.low;
    c.high = a.high ^ b.high;
    return c;
}

shr :: (a: i128) -> i128 {
    b: i128;
    b.low = a.low >> 1;
    b.high = a.high >> 1;

    b.low |= a.high << 63;
    return b;
}

galois_multiply :: (X: i128, Y: i128) -> i128 {
    R: i128;
    R.bytes[15] = 0xe1;

    V := X;
    Z: i128;

    for 0..127 {
        bit := (127 - it).(u64);

        is_set := ifx bit < 64
            then Y.low  & (1 << bit).(u64)
            else Y.high & (1 << (bit - 64)).(u64);

        if is_set Z ^= V;

        V = shr(V);

        if V.low & 1 V ^= R;
    }

    return Z;
}
