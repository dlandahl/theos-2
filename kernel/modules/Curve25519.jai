
generate_keypair :: (secret_key: *[32]u8) -> [32]u8 {
    public_key: [32]u8;

    _9: [32]u8;
    _9[0] = 9;

    scalarmult(*public_key, secret_key, *_9);

    return public_key;
}

x25519 :: (public_key: *[32]u8, secret_key: *[32]u8) -> [32]u8 {
    shared_key: [32]u8;
    scalarmult(*shared_key, secret_key, public_key);

    return shared_key;
}



#scope_module

// Based on https://martin.kleppmann.com/papers/curve25519.pdf

field_elem :: [16]s64;

#no_reset _121665: field_elem;
#run {
    _121665[0] = 0xdb41;
    _121665[1] = 1;
}

scalarmult :: (out: *[32]u8, scalar: *[32]u8, point: *[32]u8) {
    clamped := scalar.*;
    clamped[0] &= 0xf8;
    clamped[31] = (clamped[31] & 0x7f) | 0x40;

    a, b, c, d, e, f, x: field_elem;
    unpack25519(*x, point);
    b = x;
    a[0], d[0] = 1;

    for< i: 0..254 {
        bit := (clamped[i >> 3] >> (i & 7)) & 1;
        swap25519(*a, *b, bit);
        swap25519(*c, *d, bit);
        fadd(*e, a, c);
        fsub(*a, a, c);
        fadd(*c, b, d);
        fsub(*b, b, d);
        fmul(*d, e, e);
        fmul(*f, a, a);
        fmul(*a, c, a);
        fmul(*c, b, e);
        fadd(*e, a, c);
        fsub(*a, a, c);
        fmul(*b, a, a);
        fsub(*c, d, f);
        fmul(*a, c, _121665);
        fadd(*a, a, d);
        fmul(*c, c, a);
        fmul(*a, d, f);
        fmul(*d, b, x);
        fmul(*b, e, e);
        swap25519(*a, *b, bit);
        swap25519(*c, *d, bit);
    }

    finverse(*c, c);
    fmul(*a, a, c);
    pack25519(out, a);
}

unpack25519 :: (out: *field_elem, in: *[32]u8) {
    for i: 0..15 {
        out.*[i] = in.*[2*i] + in.*[2*i + 1].(s64) << 8;
    }
    out.*[15] &= 0x7fff;
}

carry25519 :: (elem: *field_elem) {
    for i: 0..15 {
        carry := elem.*[i] >> 16;
        elem.*[i] -= carry << 16;

        if i < 15 {
            elem.*[i + 1] += carry;
        } else {
            elem.*[0] += 38 * carry;
        }
    }
}

fadd :: (out: *field_elem, a: field_elem, b: field_elem) {
    for i: 0..15 out.*[i] = a[i] + b[i];
}

fsub :: (out: *field_elem, a: field_elem, b: field_elem) {
    for i: 0..15 out.*[i] = a[i] - b[i];
}

fmul :: (out: *field_elem, a: field_elem, b: field_elem) {
    product: [31]s64;

    for i: 0..15 {
        for j: 0..15 product[i+j] += a[i] * b[j];
    }

    for i: 0..14 product[i] += 38 * product[i + 16];
    for i: 0..15 out.*[i] = product[i];

    carry25519(out);
    carry25519(out);
}

finverse :: (out: *field_elem, in: field_elem) {
    c := in;
    for< i: 0..253 {
        fmul(*c, c, c);
        if i != 2 && i != 4 {
            fmul(*c, c, in);
        }
    }
    out.* = c;
}

swap25519 :: (p: *field_elem, q: *field_elem, bit: s64) {
    c := ~(bit - 1);
    for i: 0..15 {
        t := c & (p.*[i] ^ q.*[i]);
        p.*[i] ^= t;
        q.*[i] ^= t;
    }
}

pack25519 :: (out: *[32]u8, in: field_elem) {
    t := in;
    for 1..3 carry25519(*t);

    m: field_elem;
    for 1..2 {
        m[0] = t[0] - 0xffed;
        for i: 1..14 {
            m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1);
            m[i - 1] &= 0xffff;
        }

        m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
        carry := (m[15] >> 16) & 1;
        m[14] &= 0xffff;
        swap25519(*t, *m, 1 - carry);
    }

    for i: 0..15 {
        out.*[2*i] = cast(u8) (t[i] & 0xff);
        out.*[2*i + 1] = cast(u8) (t[i] >> 8);
    }
}







#run {
    #import "String";
    #import "Compiler";
    #import "Basic";

    cl := get_toplevel_command_line();

    // Auto run the test without generating an executable, if the module gets passed to the compiler directly on the command line.
    // Todo: maybe use #file for this in case the filename is changed.

    if cl.count == 2 && contains(cl[1], "Curve25519.jai") {
        set_build_options_dc(.{do_output = false});

        secret_key: [32]u8;
        secret_key[0] = 1;

        context.print_style.default_format_int.base = 16;
        log("%", generate_keypair(*secret_key));
    }
}
