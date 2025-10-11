
bs16 :: #bake_constants byte_swap(T=u16);
bs32 :: #bake_constants byte_swap(T=u32);

byte_swap_protocol_header :: (header: *$T) #modify {
    ti := cast(*Type_Info) T;
    return ti.type == .STRUCT;
} {
    #insert -> string {
        builder: String_Builder;
        info := type_info(T);

        for* info.members {
            if it.flags & .CONSTANT                 continue;
            if array_find(it.notes, "DontByteswap") continue;

            if it.type.runtime_size < 2 {
                // Don't need to byte-swap 1-byte fields, or void types.
                continue;
            }

            if it.type == type_info(tls_u24) {
                print(*builder, "    header.%1 = byte_swap_u24(header.%1);\n", it.name);
                continue;
            }

            if it.type.type == {
              case .INTEGER;
                print(*builder, "    header.%1 = byte_swap(header.%1);\n", it.name);
              case .ENUM;
                print(*builder, "    header.%1 = xx byte_swap(xx header.%1);\n", it.name);

              case .ARRAY;
                tia := cast(*Type_Info_Array)it.type;

                // Other array types will contain pointers, which shouldn't be in a network packet header.
                assert(tia.array_type == .FIXED);

                if tia.element_type.runtime_size < 2 {
                    continue;
                }

                print(*builder, "    for* header.%1 it.* = byte_swap(it.*);\n", it.name);

              case;
                assert(false, "Auto-byteswapping field of type % is not implemented. Field: %.", it.type.type, it.name);
            }

            // Todo: in a bitfield, we need to byte-swap anything that's larger than a byte.
        }

        return builder_to_string(*builder);
    }
}



BROADCAST_MAC :: u8.[0xff, 0xff, 0xff, 0xff, 0xff, 0xff];

Ethernet_Header :: struct {
    destination_mac: [6] u8;
    source_mac:      [6] u8;

    ethertype: Ethertype;
}

#assert size_of(Ethernet_Header) == 14;

Ethertype :: enum u16 {
    IPv4      :: 0x0800;
    ARP       :: 0x0806;
    IPv6      :: 0x86DD;
    UNKNOWN   :: 0x86F0;
}

init_ethernet_header :: (net: *Network_Connection) -> Ethernet_Header {
    eth: Ethernet_Header;
    eth.destination_mac = net.router_mac_address;
    eth.source_mac = net.adapter.mac_address;
    eth.ethertype = .IPv4;

    byte_swap_protocol_header(*eth);

    return eth;
}



Ipv4_Header :: struct {

    #as bitfield: enum u64 {
        ihl             :: 4;
        version         :: 4;
        ecn             :: 2;
        dscp            :: 6;
        total_length    :: 16;
        identification  :: 16;
        fragment_offset :: 13;
        flags           :: 3;
    } @DontByteswap // The default u64 byteswapping won't be correct, so we'll have to do it manually for now.

    time_to_live: u8;

    protocol: enum u8 {
        ICMP  :: 1;
        IGMP  :: 2;
        TCP   :: 6;
        UDP   :: 17;
        ENCAP :: 41;
        OSPF  :: 89;
        SCTP  :: 132;
    }

    checksum: u16;

    source_address: u32;       @DontByteswap
    destination_address: u32;  @DontByteswap
} #no_padding

internet_checksum :: (header: $H) -> u16 {
    return internet_checksum(cast(*u8, *header), size_of(H));
}

internet_checksum :: (bytes: *u8, count: int) -> u16 {
    sum: u32 = 0;

    assert(count % 2 == 0); // Todo

    num_words := count / size_of(u16);

    for 0..num_words-1 {
        high := bytes[it*2    ].(u16) << 8;
        low  := bytes[it*2 + 1].(u16);

        sum += high.(u32) + low.(u32);
    }

    while sum > 0xffff {
        sum = (sum >> 16) + (sum & 0xffff);
    }

    return ~bs16(xx sum);
}

init_ip_header :: (
    net: *Network_Connection,
    protocol: type_of(Ipv4_Header.protocol),
    destination_ip: u32,
    total_length: int
) -> Ipv4_Header {

    assert(total_length >= size_of(Ipv4_Header) && total_length < 0xffff);

    ip: Ipv4_Header;
    set(*ip, .version, 4);
    set(*ip, .ihl, 5);
    set(*ip, .total_length, bs16(xx total_length));

    ip.time_to_live = 128;
    ip.protocol = protocol;
    ip.source_address = net.our_ip;
    ip.destination_address = destination_ip;

    byte_swap_protocol_header(*ip);
    ip.checksum = internet_checksum(ip);

    return ip;
}



Arp_Packet :: struct {
    HTYPE__hardware_type: enum u16 {
        ethernet :: 0x0001;
    }

    PTYPE__protocol_type: Ethertype;

    HLEN__hardware_length: u8;
    PLEN__protocol_length: u8;

    OPER__operation: enum u16 {
        request :: 0x0001;
        reply   :: 0x0002;
    }

    SHA__sender_hardware_address: [6]u8;
    SPA__sender_protocol_address: u32 #align 1;  @DontByteswap

    THA__target_hardware_address: [6]u8;
    TPA__target_protocol_address: u32 #align 1;  @DontByteswap
}

#assert size_of(Arp_Packet) == 28;

transmit_arp_probe :: (net: *Network_Connection) {

    probe: struct {
        using eth: Ethernet_Header;
        using arp: Arp_Packet;
    }

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    probe.destination_mac = BROADCAST_MAC;
    probe.source_mac      = net.adapter.mac_address;
    probe.ethertype       = .ARP;

    byte_swap_protocol_header(*probe.eth);

    probe.HTYPE__hardware_type = .ethernet;
    probe.PTYPE__protocol_type = .IPv4;
    probe.HLEN__hardware_length = 6;
    probe.PLEN__protocol_length = 4;
    probe.OPER__operation       = .request;

    probe.SHA__sender_hardware_address = net.adapter.mac_address;
    probe.SPA__sender_protocol_address = 0;
    probe.THA__target_hardware_address = .[0,0,0,0,0,0];
    probe.TPA__target_protocol_address = net.our_ip;

    byte_swap_protocol_header(*probe.arp);

    add_to_packet(*packet, probe);
    i8254x_transmit_packet(*net.adapter, packet);

    // Todo: actually respond to IP address conflicts

    free_4k_page(cast(u64, packet.data - DIRECT_MAPPING_BASE));
}

handle_arp :: (net: *Network_Connection, eth: *Ethernet_Header) {
    assert(eth.ethertype == .ARP);

    arp := cast(*Arp_Packet) (eth + 1);

    byte_swap_protocol_header(arp);

    if arp.SPA__sender_protocol_address == arp.TPA__target_protocol_address {
        // Gratuitous ARP
        table_add(*net.arp_table, arp.SPA__sender_protocol_address, arp.SHA__sender_hardware_address);
        return;
    }

    if net.our_ip != arp.TPA__target_protocol_address return;

    if arp.OPER__operation == .reply {
        if net.dhcp_handshake_state >= .ARP_PROBE_1_TRANSMITTED && net.dhcp_handshake_state <= .ARP_PROBE_3_TRANSMITTED {
            // Response to ARP probe that was sent in response to DHCP offer.
            // Here we need to transmit DHCP DECLINE to tell the router about the address conflict.
            transmit_dhcp_decline(net);
            net.dhcp_handshake_state == .NOT_STARTED;
        }
        return;
    }

    reply: struct {
        using eth: Ethernet_Header;
        using arp: Arp_Packet;
    }

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    reply.destination_mac = arp.SHA__sender_hardware_address;
    reply.source_mac      = net.adapter.mac_address;
    reply.ethertype       = .ARP;

    byte_swap_protocol_header(*reply.eth);

    reply.HTYPE__hardware_type = .ethernet;
    reply.PTYPE__protocol_type = .IPv4;
    reply.HLEN__hardware_length = 6;
    reply.PLEN__protocol_length = 4;
    reply.OPER__operation       = .reply;

    reply.SHA__sender_hardware_address = net.adapter.mac_address;
    reply.SPA__sender_protocol_address = net.our_ip;
    reply.THA__target_hardware_address = arp.SHA__sender_hardware_address;
    reply.TPA__target_protocol_address = arp.SPA__sender_protocol_address;

    byte_swap_protocol_header(*reply.arp);

    add_to_packet(*packet, reply);
    i8254x_transmit_packet(*net.adapter, packet);
    log("ARP reply sent");

    free_4k_page(cast(u64, packet.data - DIRECT_MAPPING_BASE));

    return;
}



Udp_Header :: struct {
    source_port: u16;
    destination_port: u16;

    length: u16;
    checksum: u16;
}

FIRST_EPHEMERAL_PORT :: 0xc000;



tcp_checksum :: (tcp: Tcp_Header, source: u32, dest: u32, payload := "") -> u16 {
    Pseudo_Header :: struct {
        source_address: u32;
        destination_address: u32;
        zeroes: u8;
        protocol: type_of(Ipv4_Header.protocol);
        tcp_length: u16;

        tcp: Tcp_Header;

        payload: [0x100] u8;
    }

    pseudo: Pseudo_Header;
    pseudo.tcp = tcp;
    pseudo.source_address = source;
    pseudo.destination_address = dest;
    pseudo.protocol = .TCP;
    pseudo.tcp_length = bs16(cast(u16, size_of(Tcp_Header) + payload.count));

    memcpy(pseudo.payload.data, payload.data, payload.count);

    count := payload.count;
    if count % 2 count += 1;

    return internet_checksum(cast(*u8, *pseudo), size_of(Pseudo_Header) + count - 0x100);
}

init_tcp_header :: (net: *Network_Connection, con: *Tcp_Connection, flags: Tcp_Header.Flags, payload := "") -> Tcp_Header {
    tcp: Tcp_Header;
    tcp.source_port = con.port;
    tcp.destination_port = con.remote_port;
    tcp.sequence_number = con.sequence_number;
    tcp.ack_number = con.ack_number+1;
    tcp.data_offset = 5 << 4;
    tcp.flags = flags;
    tcp.window = 4096;

    byte_swap_protocol_header(*tcp);
    tcp.checksum = tcp_checksum(tcp, net.our_ip, con.remote_ip, payload);

    return tcp;
}

Tcp_Header :: struct {
    source_port: u16;
    destination_port: u16;

    sequence_number: u32;
    ack_number: u32;

    data_offset: u8;

    Flags :: enum_flags u8 {
        FIN;
        SYN;
        RST;
        PSH;
        ACK;
        URG;
        ECE;
        CWR;
    }

    flags: Flags;

    window: u16;
    checksum: u16;
    urgent_pointer: u16;
}

Tcp_Connection :: struct {
    port: u16;

    remote_port: u16;
    remote_ip: u32;

    handshake_state: enum {
        NOT_STARTED;
        SYN_SENT;
        COMPLETED;
        FIN_TRANSMITTED;
        CONNECTION_CLOSED;
    }

    // Accumulated each time we transmit new bytes that have not been transmitted before
    sequence_number: u32;

    // The next sequence number we expect to see is always this + 1.
    // Peer sequence numbers less than this have been acknowledged before.
    ack_number: u32;

    in_flight: [..] Tcp_Transmission_Info;

    received_segments: [..] string;
}

Tcp_Transmission_Info :: struct {
    // There should be an instance of this for each unacknowledged transmitted packet in a connection.
    // Except for ACKs sent by us, as we don't expect to receive an ACK for those.
    packet: Network_Packet;
    sequence: u32;
    flags: Tcp_Header.Flags; // This value is stored in the packet header, but it seems cleaner to keep a separate copy of it rather than parsing it out of the packet.

    last_sent_at: Apollo_Time; // To detect if we need to retransmit
    attempts: int;
}

record_tcp_packet_for_potential_retransmission :: (net: *Network_Connection, con: *Tcp_Connection, packet: Network_Packet, flags: Tcp_Header.Flags) {

    bytes_to_transmit := packet.length - (size_of(Ethernet_Header) + size_of(Ipv4_Header) + size_of(Tcp_Header));
    if bytes_to_transmit == 0 bytes_to_transmit = 1;
    con.sequence_number += cast(u32) bytes_to_transmit;

    info := array_add(*con.in_flight);
    info.last_sent_at = get_monotonic_time();
    info.packet = packet;

    // The sequence number in the ACK will include the bytes transmitted in this packet, so store that.
    // The sequence number of the packet we're transmitting right now does not match this sequence number, as it describes the first byte being transmitted in that packet.
    info.sequence = con.sequence_number;
    info.flags = flags;
}

transmit_tcp_packet :: (net: *Network_Connection, con: *Tcp_Connection, header_flags: Tcp_Header.Flags, payload := "", needs_acknowledgement := true) {
    if con.handshake_state == .CONNECTION_CLOSED {
        log_error("Trying to transmit TCP packet over a connection that has already been closed.");
        return;
    }

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    eth := init_ethernet_header(net);
    add_to_packet(*packet, eth);

    datagram_length := size_of(Ipv4_Header) + size_of(Tcp_Header) + payload.count;
    ip := init_ip_header(net, .TCP, con.remote_ip, datagram_length);
    add_to_packet(*packet, ip);

    tcp := init_tcp_header(net, con, header_flags, payload);
    add_to_packet(*packet, tcp);

    add_to_packet(*packet, payload);

    if needs_acknowledgement {
        record_tcp_packet_for_potential_retransmission(net, con, packet, header_flags);
    }

    i8254x_transmit_packet(*net.adapter, packet);
}

initiate_tcp_connection :: (net: *Network_Connection, remote_ip: u32, remote_port: u16) -> *Tcp_Connection {

    port := FIRST_EPHEMERAL_PORT + cast(u16, rdtsc() & 0xfff);

    log("Initating TCP connection with %:%", format_ip(remote_ip), remote_port);
    // Clear the high bit to ensure we have at least a couple gigabytes of headroom until we add code to handle overflow.
    sequence_number := cast(u32, random_get() & 0x7fff_ffff);

    // Todo: this should be changed to a Bucket_Array for pointer stability.
    con := array_add(*net.tcp_connections);
    con.* = .{
        port = port,
        remote_port = remote_port,
        remote_ip = remote_ip,
        handshake_state = .NOT_STARTED,
        sequence_number = sequence_number,
        ack_number = 0xffff_ffff,
    }; 

    transmit_tcp_packet(net, con, .SYN, needs_acknowledgement=false);
    con.handshake_state = .SYN_SENT;

    return con;
}

update_tcp_connection :: (net: *Network_Connection, con: *Tcp_Connection) {
    // Periodically check if something needs to be retransmitted.
    time_now := get_monotonic_time();

    // Maybe we should have a back-off system.
    RETRANSMISSION_TIME :: #run seconds_to_apollo(1);

    for* info: con.in_flight {
        if time_now - info.last_sent_at > RETRANSMISSION_TIME {
            // Retransmit the segment
            log("TCP retransmit %", info.sequence);
            i8254x_transmit_packet(*net.adapter, info.packet);

            info.last_sent_at = time_now;
            info.attempts += 1;
        }
    }
}

handle_tcp_packet :: (net: *Network_Connection, eth_: *Ethernet_Header) {

    Tcp_Packet :: struct {
        eth: Ethernet_Header;
        ip: Ipv4_Header #align 1;
        tcp: Tcp_Header #align 1;
    }

    using packet := cast(*Tcp_Packet) eth_;

    byte_swap_protocol_header(*tcp);

    con: *Tcp_Connection;
    for* net.tcp_connections {
        if it.port == tcp.destination_port {
            con = it;
            break;
        }
    }

    if !con {
        log_error("Got TCP message for nonexistent connection on port %", tcp.destination_port);
        // Todo: transmit RST
        return;
    }

    if con.handshake_state == .CONNECTION_CLOSED {
        return;
    }

    if tcp.flags == .SYN | .ACK {
        if con.handshake_state == {
          case .COMPLETED;
            // It looks like the server missed the ACK the first time. Todo.
            log("TCP unexpected SYN-ACK.");

          case .SYN_SENT;
            con.ack_number = tcp.sequence_number;
            con.sequence_number += 1;
            transmit_tcp_packet(net, con, .ACK, needs_acknowledgement=false);
            con.handshake_state = .COMPLETED;

            log("TCP connection with %:% successfully established.", format_ip(con.remote_ip), con.remote_port);
        }

        return;
    }

    if tcp.flags & .RST {
        // Todo.
        log_error("Received RST from %:%.", format_ip(con.remote_ip), con.remote_port);
        con.handshake_state = .CONNECTION_CLOSED;
        return;
    }

    // The FIN handling code is spaghetti code and should be refactored at some point.

    if tcp.flags & .FIN && tcp.flags & .ACK {
        // Check if this is acknowledging a client-initiated connection termination.

        for* info: con.in_flight {
            if info.sequence == tcp.ack_number {
                if con.handshake_state == .FIN_TRANSMITTED {
                    if info.flags & .FIN && tcp.flags & .FIN {
                        transmit_tcp_packet(net, con, .ACK, needs_acknowledgement=false);
                        con.handshake_state = .CONNECTION_CLOSED;

                        return;
                    }
                }
            }
        }
    }

    if tcp.flags & .ACK {
        // Handle the fact that something we transmitted was acknowledged.
        for* info: con.in_flight {
            if info.sequence <= tcp.ack_number {
                // Any segment that has been acknowledged (bytes later than it have been received) will never need to be retransmitted.
                free_4k_page(cast(u64, info.packet.data - DIRECT_MAPPING_BASE));
                remove info;
            }
        }
    }

    if tcp.sequence_number == con.ack_number + 1 {
        length := bs16(xx get(ip, .total_length)) - size_of(Ipv4_Header) - size_of(Tcp_Header);

        if length == 0 {
            // It's just an ACK or FIN, handled above.
            return;
        }

        con.ack_number += length.(u32);

        // Transmit ACK
        transmit_tcp_packet(net, con, .ACK, needs_acknowledgement=false);

        packet_data: string;
        packet_data.data = cast(*u8, *tcp + 1);
        packet_data.count = length.(s64);

        array_add(*con.received_segments, packet_data);

        log("Received TCP segment from %:%, (% bytes)", format_ip(con.remote_ip), con.remote_port, length);

        if tcp.flags & .PSH {
            log("%", con.received_segments);
            array_reset(*con.received_segments);
        }
    } else if tcp.sequence_number > con.ack_number + 1 {
        // If we get a greater sequence number than expected, ACK the last packet we received to indicate to the peer that later packets may need to be retransmitted.
        transmit_tcp_packet(net, con, .ACK, needs_acknowledgement=false);
    }

    if tcp.flags & .FIN {
        // Server-initiated connection termination. Acknowledged using a FIN-ACK.
        transmit_tcp_packet(net, con, .FIN | .ACK, needs_acknowledgement=false);
        con.handshake_state = .CONNECTION_CLOSED;
        return;
    }
}

HTTP_SERVER_PORT :: 80;
HTTPS_SERVER_PORT :: 443;



// The TLS protocol includes 24 bit integers. This type will be detected
// by the byteswapping code and be handled correctly.
tls_u24 :: #type,distinct [3]u8;

set :: (u24: *tls_u24, value: u32) {
    array := bit_cast(value, [4]u8);

    assert(array[3] == 0);

    u24.*[0] = array[0];
    u24.*[1] = array[1];
    u24.*[2] = array[2];
}

get :: (u24: *tls_u24) -> u32 {
    result: u32;
    memcpy(*result, u24, 3);
    return result;
}

// We don't do an overload for this, because the #bake_constants at the top of the file don't resolve overloads.
byte_swap_u24 :: (u24: tls_u24) -> tls_u24 {
    result: tls_u24;
    result[0] = u24[2];
    result[1] = u24[1];
    result[2] = u24[0];
    return result;
}



Tls_Record_Header :: struct {
    content_type: enum u8 {
        CHANGE_CIPHER_SPEC :: 20;
        ALERT              :: 21;
        HANDSHAKE          :: 22;
        APPLICATION_DATA   :: 23;
    }

    version: Tls_Version #align 1;
    length: u16 #align 1;
}

Tls_Handshake_Type :: enum u8 {
    HELLO_REQUEST          :: 0;
    CLIENT_HELLO           :: 1;
    SERVER_HELLO           :: 2;
    CERTIFICATE            :: 11;
    SERVER_KEY_EXCHANGE    :: 12;
    CERTIFICATE_REQUEST    :: 13;
    SERVER_HELLO_DONE      :: 14;
    CERTIFICATE_VERIFY     :: 15;
    CLIENT_KEY_EXCHANGE    :: 16;
    FINISHED               :: 20;
}

Tls_Client_Hello :: struct {
    type: Tls_Handshake_Type;
    length: tls_u24;

    client_version: Tls_Version;
    random: Tls_Random #align 1;  @DontByteswap

    session_id: u8;

    num_cipher_suites: u16 #align 1;
    cipher_suites: [1] Tls_Cipher_Suite #align 1;

    num_compression_methods: u8;
    compression_method: u8;

    extensions_length: u16 #align 1;

    extensions: struct {
        supported_groups: [14] u8;
        ec_points_format: [6] u8;
        signature_algorithms: [8] u8;
        sct: [4] u8;
        renegotiation_info: [5] u8;
    } @DontByteswap
}

Tls_Server_Hello :: struct {
    type: Tls_Handshake_Type;
    length: tls_u24;

    version: Tls_Version;
    random: Tls_Random #align 1; @DontByteswap
    session_id: u8;
    cipher_suite: Tls_Cipher_Suite;
    compression_method: u8;
}

Tls_Cipher_Suite :: enum u16 {
    ECDHE_RSA_\ WITH_CHACHA20_POLY1305_SHA256 :: 0xcc_a8;
    ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 :: 0xcc_a9;
    ECDHE_RSA_\ WITH_AES128_GCM_SHA256        :: 0xc0_2f;
    ECDHE_RSA_\ WITH_AES256_GCM_SHA384        :: 0xc0_30;
    ECDHE_ECDSA_WITH_AES128_GCM_SHA256        :: 0xc0_2b;
    ECDHE_ECDSA_WITH_AES256_GCM_SHA384        :: 0xc0_2c;
    ECDHE_RSA_\ WITH_AES128_CBC_SHA           :: 0xc0_13;
    ECDHE_ECDSA_WITH_AES128_CBC_SHA           :: 0xc0_09;
    ECDHE_RSA_\ WITH_AES256_CBC_SHA           :: 0xc0_14;
    ECDHE_ECDSA_WITH_AES256_CBC_SHA           :: 0xc0_0a;
    RSA_\       WITH_AES128_GCM_SHA256        :: 0x00_9c;
    RSA_\       WITH_AES256_GCM_SHA384        :: 0x00_9d;
    DHE_RSA_\   WITH_AES128_GCM_SHA256        :: 0x00_9e;
    RSA_\       WITH_AES128_CBC_SHA           :: 0x00_2f;
    RSA_\       WITH_AES256_CBC_SHA           :: 0x00_35;
    ECDHE_RSA_\ WITH_3DES_EDE_CBC_SHA         :: 0xc0_12;
    RSA_\       WITH_3DES_EDE_CBC_SHA         :: 0x00_0a;
}

Tls_Version :: enum u16 {
    TLS_1_0 :: 0x0301;
    TLS_1_2 :: 0x0303;
}

Tls_Random :: struct {
    random: [4] u64;

#place random;
    unix_time: u32;
}

Tls_Alert :: struct {
    level: enum u8 {
        WARNING :: 1;
        FATAL   :: 2;
    }

    description :: enum u8 {
        CLOSE_NOTIFY                :: 0;
        UNEXPECTED_MESSAGE          :: 10;
        BAD_RECORD_MAC              :: 20;
        DECRYPTION_FAILED_RESERVED  :: 21;
        RECORD_OVERFLOW             :: 22;
        DECOMPRESSION_FAILURE       :: 30;
        HANDSHAKE_FAILURE           :: 40;
        NO_CERTIFICATE_RESERVED     :: 41;
        BAD_CERTIFICATE             :: 42;
        UNSUPPORTED_CERTIFICATE     :: 43;
        CERTIFICATE_REVOKED         :: 44;
        CERTIFICATE_EXPIRED         :: 45;
        CERTIFICATE_UNKNOWN         :: 46;
        ILLEGAL_PARAMETER           :: 47;
        UNKNOWN_CA                  :: 48;
        ACCESS_DENIED               :: 49;
        DECODE_ERROR                :: 50;
        DECRYPT_ERROR               :: 51;
        EXPORT_RESTRICTION_RESERVED :: 60;
        PROTOCOL_VERSION            :: 70;
        INSUFFICIENT_SECURITY       :: 71;
        INTERNAL_ERROR              :: 80;
        USER_CANCELED               :: 90;
        NO_RENEGOTIATION            :: 100;
        UNSUPPORTED_EXTENSION       :: 110;
    }
}

Tls_Connection_State :: struct {
    tcp: *Tcp_Connection;

    handshake_state: enum {
        CLIENT_HELLO_SENT;
    }
}

initiate_tls_connection :: (net: *Network_Connection, con: *Tcp_Connection) -> struct {} {

    if con.handshake_state != .COMPLETED {
        log_error("Trying to create a TLS connection without an established TCP connection.");
        return .{};
    }

    Scoped_Acquire(*net.spinlock);

    // Send TLS client hello.
    packet: Network_Packet;
    packet.data = cast(*void)get_4k_page() + DIRECT_MAPPING_BASE;

    record := Tls_Record_Header.{
        content_type = .HANDSHAKE,
        version      = .TLS_1_0,
        length       = size_of(Tls_Client_Hello),
    };

    byte_swap_protocol_header(*record);
    add_to_packet(*packet, record);

    hello: Tls_Client_Hello;
    hello.type                      = .CLIENT_HELLO;
    hello.client_version            = .TLS_1_2;
    hello.session_id                = 0;
    hello.num_cipher_suites         = size_of(type_of(hello.cipher_suites));
    hello.num_compression_methods   = 1;
    hello.compression_method        = 0;

    hello.extensions_length         = size_of(type_of(hello.extensions));
    hello.extensions.signature_algorithms      = .[0x0, 0xd, 0x0, 0x4, 0x0, 0x2, 0x4, 0x1];
    hello.extensions.sct                       = .[0x0, 0x12, 0x0, 0x0];
    hello.extensions.supported_groups          = .[0x0, 0xa, 0x0, 0xa, 0x0, 0x8, 0x0, 0x1d, 0x0, 0x17, 0x0, 0x18, 0x0, 0x19];
    hello.extensions.ec_points_format          = .[0x0, 0xb, 0x0, 0x2, 0x1, 0x0];
    hello.extensions.renegotiation_info        = .[0xff, 0x1, 0x0, 0x1, 0x0];

    hello.cipher_suites[0] = .ECDHE_RSA_WITH_AES128_CBC_SHA;

    set(*hello.length, size_of(Tls_Client_Hello) - 4);

    for* hello.random.random it.* = random_get();
    ts := to_timespec(get_monotonic_time());
    hello.random.unix_time = bs32(xx ts.tv_sec);

    byte_swap_protocol_header(*hello);
    add_to_packet(*packet, hello);

    payload: string;
    payload.data = packet.data;
    payload.count = packet.length;

    transmit_tcp_packet(net, con, .ACK | .PSH, payload);

    return .{};
}

handle_tls_message :: (net: *Network_Connection, tls: *Tls_Connection_State, record: *Tls_Record_Header) {

}



Dhcp_Message :: struct {
    opcode:        u8;
    hardware_type: u8;
    mac_length:    u8;
    hops:          u8;
    xid:           u32;
    seconds:       u16;
    flags:         u16;

    client_ip:     u32;  @DontByteswap
    your_ip:       u32;  @DontByteswap
    server_ip:     u32;  @DontByteswap
    gateway_ip:    u32;  @DontByteswap

    client_mac:  [6] u8;
    mac_padding: [10] u8;

    boot_file_name: [192] u8;
    magic:         u32;

    MAGIC :: 0x63825363;
}

Dhcp_Message_Type :: enum u8 {
    DISCOVER           :: 1;
    OFFER              :: 2;
    REQUEST            :: 3;
    DECLINE            :: 4;
    ACK                :: 5;
    NAK                :: 6;
    RELEASE            :: 7;
    INFORM             :: 8;
    FORCE_RENEW        :: 9;
    LEASE_QUERY        :: 10;
    LEASE_UNASSIGNED   :: 11;
    LEASE_UNKNOWN      :: 12;
    LEASE_ACTIVE       :: 13;
    BULK_LEASE_QUERY   :: 14;
    LEASE_QUERY_DONE   :: 15;
    ACTIVE_LEASE_QUERY :: 16;
    LEASE_QUERY_STATUS :: 17;
    TLS                :: 18;
}

get_dhcp_message_type :: (dhcp: *Dhcp_Message) -> Dhcp_Message_Type {
    // Todo: Make a general options parser.
    options := cast(*Dhcp_Option_Code, dhcp + 1);

    while options.* != .TERMINATOR {
        if options.* != .MESSAGE_TYPE {
            options += cast(u8) options[1] + 2;
        }

        return cast(Dhcp_Message_Type) options[2];
    }
}

init_dhcp_message :: (net: *Network_Connection) -> Dhcp_Message {
    dhcp: Dhcp_Message;
    dhcp.opcode = 0x1;
    dhcp.hardware_type = 0x1;
    dhcp.mac_length = 0x6;
    dhcp.xid = net.dhcp_xid;
    dhcp.client_mac = net.adapter.mac_address;
    dhcp.server_ip = net.router_ip;
    dhcp.magic = Dhcp_Message.MAGIC;

    byte_swap_protocol_header(*dhcp);

    return dhcp;
}

DHCP_CLIENT_PORT :: 68;
DHCP_SERVER_PORT :: 67;

update_dhcp :: (using net: *Network_Connection) {

    if dhcp_handshake_state == {
      case .NOT_STARTED;

        net.dhcp_xid = cast,trunc(u32) random_get();
        log("Transmitting DHCP discover... (0x%)", hex(dhcp_xid));

        transmit_dhcp_discover(net);

        dhcp_handshake_state = .DISCOVER_TRANSMITTED;
        dhcp_message_transmitted_at = get_monotonic_time();

      case .DISCOVER_TRANSMITTED;
        if dhcp_message_transmitted_at < get_monotonic_time() - DHCP_DISCOVER_INTERVAL {
            dhcp_handshake_state = .NOT_STARTED;
        }

      case .ARP_PROBE_1_TRANSMITTED; #through;
      case .ARP_PROBE_2_TRANSMITTED;
        probe_time_elapsed := dhcp_message_transmitted_at < get_monotonic_time() - DHCP_ARP_PROBE_INTERVAL;

        if probe_time_elapsed {
            transmit_arp_probe(net);

            dhcp_handshake_state += 1;
            dhcp_message_transmitted_at = get_monotonic_time();
        }

      case .ARP_PROBE_3_TRANSMITTED;
        probe_time_elapsed := dhcp_message_transmitted_at < get_monotonic_time() - DHCP_ARP_PROBE_INTERVAL;

        if probe_time_elapsed {
            log("No address conflicts found, accepting DHCP offer.");

            transmit_dhcp_request(net);
            dhcp_request_attempts = 1;

            dhcp_handshake_state = .OFFER_ACCEPTED;
            dhcp_message_transmitted_at = get_monotonic_time();
        }

      case .OFFER_ACCEPTED;
        if dhcp_message_transmitted_at < get_monotonic_time() - DHCP_REQUEST_INTERVAL {
            if dhcp_request_attempts >= MAX_DHCP_REQUEST_ATTEMPTS {
                dhcp_handshake_state = .NOT_STARTED;
                dhcp_request_attempts = 0;
            } else {
                // Retransmit the request for the IP if we don't get an acknowledgement in time.
                log("Retransmitting DHCP request.");
                transmit_dhcp_request(net);
                dhcp_message_transmitted_at = get_monotonic_time();
                dhcp_request_attempts += 1;
            }
        }

      case .COMPLETED;

      case; assert(false, "Invalid DHCP handshake state.");
    }
}

Dhcp_Packet :: struct {
    eth: Ethernet_Header;
    ip: Ipv4_Header #align 1;
    udp: Udp_Header #align 1;
    dhcp: Dhcp_Message #align 1;
}

handle_dhcp_packet :: (using net: *Network_Connection, eth_: *Ethernet_Header) {
    using packet := cast(*Dhcp_Packet) eth_;

    if udp.length < size_of(Dhcp_Message) + size_of(Udp_Header) {
        log_error("Bad DHCP packet, too small.");
        return;
    }

    byte_swap_protocol_header(*dhcp);

    if dhcp.magic != Dhcp_Message.MAGIC {
        log_error("Bad DHCP packet, magic doesn't match.");
        return;
    }

    if _memcmp(dhcp.client_mac.data, adapter.mac_address.data, 6) != 0 {
        return;
    }

    if dhcp.xid != dhcp_xid {
        log_error("Got DHCP message with invalid transaction ID.");
        return;
    }

    if get_dhcp_message_type(*dhcp) == {
      case .OFFER;
        if dhcp_handshake_state != .DISCOVER_TRANSMITTED {
            log_error("Unexpected DHCP offer.");
            return;
        }

        our_ip = dhcp.your_ip;
        router_ip = ip.source_address;
        router_mac_address = eth.source_mac;

        log("Got DHCP offer for IP: %.", format_ip(our_ip));
        log("Server IP: %, server MAC: %.", format_ip(router_ip), format_mac(router_mac_address));

        transmit_arp_probe(net);
        dhcp_message_transmitted_at = get_monotonic_time();

        dhcp_handshake_state = .ARP_PROBE_1_TRANSMITTED;

      case .ACK;
        if dhcp_handshake_state != .OFFER_ACCEPTED {
            log_error("Unexpected DHCP ACK.");
            return;
        }

        dhcp_handshake_state = .COMPLETED;

      case .NAK;
        dhcp_handshake_state = .NOT_STARTED;
        log_error("DHCP NAK.");
    }
}



Dhcp_Option_Code :: enum u8 {
    PADDING      :: 0x0;
    SUBNET_MASK  :: 0x01;
    ROUTER       :: 0x03;
    TIME_SERVER  :: 0x04;
    DNS_SERVER   :: 0x06;
    HOSTNAME     :: 0x0c;
    DOMAIN_NAME  :: 0x0f;
    REQUEST_IP   :: 0x32;
    MESSAGE_TYPE :: 0x35;
    SERVER_IP    :: 0x36;
    PRL          :: 0x37;
    TERMINATOR   :: 0xff;
}

Dhcp_Options_Builder :: struct {
    buffer: [..] u8;
}

add_option :: (options: *Dhcp_Options_Builder, code: Dhcp_Option_Code, data: Any) {
    if !options.buffer.allocator.proc {
        options.buffer.allocator = temp;
    }

    array_add(*options.buffer, cast(u8)code);

    if data.type.type == .STRING {
        bytes := cast(*[]u8, data.value_pointer).*;
        array_add(*options.buffer, cast(u8)bytes.count);
        array_add(*options.buffer, ..bytes);
        return;
    }

    array_add(*options.buffer, cast(u8)data.type.runtime_size);

    bytes: [] u8;
    bytes.data = data.value_pointer;
    bytes.count = data.type.runtime_size;
    array_add(*options.buffer, ..bytes);
}

get_size :: (options: Dhcp_Options_Builder) -> u16 {
    // +1 because we add the terminator when we commit.
    return cast(u16)options.buffer.count + 1;
}

commit_dhcp_options :: (packet: *Network_Packet, options: Dhcp_Options_Builder) {
    array_add(*options.buffer, 0xff);
    add_to_packet(packet, cast(string)options.buffer);
}


// Todo: these three "transmit_dhcp_" routines are basically identical except for the Options.
transmit_dhcp_discover :: (net: *Network_Connection) {
    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    eth: Ethernet_Header;
    eth.destination_mac = BROADCAST_MAC;
    eth.source_mac = net.adapter.mac_address;
    eth.ethertype = .IPv4;

    byte_swap_protocol_header(*eth);
    add_to_packet(*packet, eth);

    options: Dhcp_Options_Builder;
    add_option(*options, .MESSAGE_TYPE, Dhcp_Message_Type.DISCOVER);
    add_option(*options, .PRL, Dhcp_Option_Code.[
        .SUBNET_MASK,
        .ROUTER,
        .TIME_SERVER,
        .DNS_SERVER,
        .DOMAIN_NAME
    ]);

    ip_length := size_of(Ipv4_Header)
        + size_of(Udp_Header)
        + size_of(Dhcp_Message)
        + get_size(options);

    ip := init_ip_header(net, .UDP, 0xff_ff_ff_ff, ip_length);
    add_to_packet(*packet, ip);

    udp: Udp_Header;
    udp.source_port = DHCP_CLIENT_PORT;
    udp.destination_port = DHCP_SERVER_PORT;
    udp.length = size_of(Udp_Header)
        + size_of(Dhcp_Message)
        + get_size(options);

    byte_swap_protocol_header(*udp);
    add_to_packet(*packet, udp);

    dhcp := init_dhcp_message(net);
    add_to_packet(*packet, dhcp);

    commit_dhcp_options(*packet, options);

    i8254x_transmit_packet(*net.adapter, packet);
}

transmit_dhcp_decline :: (net: *Network_Connection) {
    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    eth: Ethernet_Header;
    eth.destination_mac = BROADCAST_MAC;
    eth.source_mac = net.adapter.mac_address;
    eth.ethertype = .IPv4;

    byte_swap_protocol_header(*eth);
    add_to_packet(*packet, eth);

    options: Dhcp_Options_Builder;
    add_option(*options, .MESSAGE_TYPE, Dhcp_Message_Type.DECLINE);

    ip_length := size_of(Ipv4_Header)
        + size_of(Udp_Header)
        + size_of(Dhcp_Message)
        + get_size(options);

    ip := init_ip_header(net, .UDP, 0xff_ff_ff_ff, ip_length);
    add_to_packet(*packet, ip);

    udp: Udp_Header;
    udp.source_port = DHCP_CLIENT_PORT;
    udp.destination_port = DHCP_SERVER_PORT;
    udp.length = size_of(Udp_Header)
        + size_of(Dhcp_Message)
        + get_size(options);

    byte_swap_protocol_header(*udp);
    add_to_packet(*packet, udp);

    dhcp := init_dhcp_message(net);
    add_to_packet(*packet, dhcp);

    commit_dhcp_options(*packet, options);

    i8254x_transmit_packet(*net.adapter, packet);
}

transmit_dhcp_request :: (net: *Network_Connection) {

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    eth: Ethernet_Header;
    eth.destination_mac = BROADCAST_MAC;
    eth.source_mac = net.adapter.mac_address;
    eth.ethertype = .IPv4;

    byte_swap_protocol_header(*eth);
    add_to_packet(*packet, eth);

    options: Dhcp_Options_Builder;
    add_option(*options, .MESSAGE_TYPE, Dhcp_Message_Type.REQUEST);
    add_option(*options, .HOSTNAME, "JaiOS");
    add_option(*options, .SERVER_IP, net.router_ip);
    add_option(*options, .REQUEST_IP, net.our_ip);

    ip_length := size_of(Ipv4_Header)
        + size_of(Udp_Header)
        + size_of(Dhcp_Message)
        + get_size(options);

    ip := init_ip_header(net, .UDP, 0xff_ff_ff_ff, ip_length);
    add_to_packet(*packet, ip);

    udp: Udp_Header;
    udp.source_port = DHCP_CLIENT_PORT;
    udp.destination_port = DHCP_SERVER_PORT;
    udp.length = size_of(Udp_Header)
        + size_of(Dhcp_Message)
        + get_size(options);

    byte_swap_protocol_header(*udp);
    add_to_packet(*packet, udp);

    dhcp := init_dhcp_message(net);
    add_to_packet(*packet, dhcp);

    commit_dhcp_options(*packet, options);

    i8254x_transmit_packet(*net.adapter, packet);
}



Icmp_Header :: struct {
    // Note, the ICMP header doesn't need to be byte-swapped, because of how we happen to represent the fields.

    control_message: enum u16 {
        // Type and code (subtype) combined into one field

        echo_reply   :: 0x00_00;
        echo_request :: 0x00_08;
    }

    checksum: u16;
    data: u32;
}

Icmp_Packet :: struct {
    eth: Ethernet_Header;
    ip: Ipv4_Header #align 1;
    using icmp: Icmp_Header #align 1;
}

handle_icmp_packet :: (net: *Network_Connection, eth: *Ethernet_Header) {
    icmp := cast(*Icmp_Packet) eth;

    if icmp.control_message == {
      case .echo_request;
        log("Got pinged by %, sending pong", format_ip(icmp.ip.source_address));
        transmit_pong(net, icmp);

      case .echo_reply;
        for net.pings_in_flight {
            if it.id == icmp.data {
                time := get_monotonic_time();

                delta_us := to_milliseconds(time - it.sent_at);
                log("Ping % = %ms", format_ip(it.destination_ip), delta_us);

                remove it;
                break;
            }
        }
    }
}

transmit_pong :: (net: *Network_Connection, ping: *Icmp_Packet) {
    packet: Network_Packet;

    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;
    defer free_4k_page(cast(u64, packet.data - DIRECT_MAPPING_BASE));

    using pong: Icmp_Packet;

    eth.destination_mac = ping.eth.source_mac;
    eth.source_mac      = ping.eth.destination_mac;
    eth.ethertype       = .IPv4;

    byte_swap_protocol_header(*eth);

    ip = init_ip_header(net, .ICMP, ping.ip.source_address, size_of(Ipv4_Header) + size_of(Icmp_Header));

    icmp.control_message = .echo_reply;
    icmp.data = ping.icmp.data;
    icmp.checksum = internet_checksum(icmp);
    add_to_packet(*packet, pong);

    i8254x_transmit_packet(*net.adapter, packet);
}

transmit_ping :: (net: *Network_Connection, destination_ip: u32) {
    using ping: Icmp_Packet;

    eth = init_ethernet_header(net);
    ip = init_ip_header(net, .ICMP, destination_ip, size_of(Ipv4_Header) + size_of(Icmp_Header));

    icmp.control_message = .echo_request;
    icmp.data = cast(u32) random_get() & 0xffff;
    icmp.checksum = internet_checksum(icmp);

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    add_to_packet(*packet, ping);

    success := i8254x_transmit_packet(*net.adapter, packet);
    if !success bluescreen();

    time := get_monotonic_time();

    array_add(*net.pings_in_flight, .{
        id = icmp.data,
        destination_ip = destination_ip,
        sent_at = time,
    });
}



Dns_Header :: struct {
    transaction_id: u16;

    flags: enum_flags u16 {
        QR__query :: 0x1;
        RD__recursion_desired :: 0x100;
    }

    questions: u16;
    answers: u16;
    authority_rrs: u16;
    additional_rrs: u16;
}

DNS_SERVER_PORT :: 53;

transmit_dns_query :: (net: *Network_Connection, url: string) -> *Dns_Query {
    Scoped_Acquire(*net.spinlock);

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    xid := cast,trunc(u16) random_get();

    eth := init_ethernet_header(net);
    add_to_packet(*packet, eth);

    ip_length := size_of(Ipv4_Header)
        + size_of(Udp_Header)
        + size_of(Dns_Header)
        + cast(u16) url.count + 6; // 6 because TYPE, CLASS, first label length, and zero terminator. Todo: hardcoded

    ip := init_ip_header(net, .UDP, net.router_ip, ip_length);
    add_to_packet(*packet, ip);

    udp: Udp_Header;
    udp.source_port = allocate_port(net);
    udp.destination_port = DNS_SERVER_PORT;
    udp.length = size_of(Udp_Header)
        + size_of(Dns_Header)
        + cast(u16) url.count + 6;

    byte_swap_protocol_header(*udp);
    add_to_packet(*packet, udp);

    dns: Dns_Header;
    dns.transaction_id = xid;
    dns.flags = .QR__query | .RD__recursion_desired;
    dns.questions = 1;

    byte_swap_protocol_header(*dns);
    add_to_packet(*packet, dns);

    remaining := url;

    while true {
        found, left, right := split_from_left(remaining, #char ".");
        add_to_packet(*packet, left.count.(u8));
        add_to_packet(*packet, left);

        if !found break;

        remaining = right;
    }
    add_to_packet(*packet, (0).(u8));

    add_to_packet(*packet, bs16(Dns_Record_Type.A.(u16)));
    add_to_packet(*packet, bs16(Dns_Class.IN.(u16)));

    i8254x_transmit_packet(*net.adapter, packet);

    // Todo: bucket array.
    new_query := array_add(*net.dns_queries_in_flight);
    new_query.transaction_id = xid;
    new_query.url = copy_string(url);
    new_query.sent_at = get_monotonic_time();

    return new_query;
}

Dns_Query :: struct {
    transaction_id: u16;
    url: string;
    sent_at: Apollo_Time;
    complete: bool;
    answer: u32;
}

Dns_Packet :: struct {
    eth: Ethernet_Header;
    ip: Ipv4_Header #align 1;
    udp: Udp_Header #align 1;
    dns: Dns_Header #align 1;
} #no_padding

Dns_Record_Type :: enum u16 {
    A     :: 0x0001;
    CNAME :: 0x0005;
}

Dns_Class :: enum u16 {
    IN    :: 0x0001;
}

Dns_Response_Code :: enum {
    NOERROR   :: 0;
    FORMERR   :: 1;
    SERVFAIL  :: 2;
    NXDOMAIN  :: 3;
    NOTIMP    :: 4;
    REFUSED   :: 5;
    YXDOMAIN  :: 6;
    XRRSET    :: 7;
    NOTAUTH   :: 8;
    NOTZONE   :: 9;
}

handle_dns_packet :: (net: *Network_Connection, eth_: *Ethernet_Header) {
    using packet := cast(*Dns_Packet) eth_;

    // Todo: parsing DNS records is very hardcoded right now

    byte_swap_protocol_header(*packet.dns);

    for* query: net.dns_queries_in_flight {
        if query.transaction_id != dns.transaction_id {
            continue;
        }

        if query.complete {
            continue;
        }

        result_code := cast(Dns_Response_Code)(dns.flags & 0xf);

        if result_code {
            if result_code == {
                case .NXDOMAIN; log("DNS query regarding domain name \"%\" returned \"No such name\".", query.url);
                case .FORMERR;  log("DNS query regarding domain name \"%\" returned \"Format error\".", query.url);
                case;           log("DNS query regarding domain name \"%\" returned result code %.", query.url, result_code);
            }

            query.complete = true;
            return;
        }

        Skip_Name :: () #expand {
            while cursor.* != 0 {
                cursor += cursor.*;
                cursor += 1;
            }
            cursor += 1;
        }

        cursor := cast(*u8, *dns + 1);

        // Must cast this or it may underflow and loop for very many iterations.
        for 0..cast(s16)dns.questions-1 {

            // Skip all the questions.
            Skip_Name();

            type := cursor.(*Dns_Record_Type).*;
            cursor += 2; // TYPE

            class := cursor.(*u16).*;
            cursor += 2; // CLASS
        }

        // Should now be at the answers. Find a host address.

        for 0..cast(s16)dns.answers-1 {
            // Detect if it's a pointer

            if (cursor[0] >> 6) == 0b11 {
                cursor += 2;
            } else {
                Skip_Name();
            }

            type := cast(Dns_Record_Type) bs16(cursor.(*u16).*);

            cursor += 8; // Class, type, TTL
            data_length := bs16(cursor.(*u16).*);

            cursor += 2; // Data length

            if type == .A {
                if data_length != 4 {
                    log_error("DNS response address is not IPv4");
                    return;
                }

                query.answer = cursor.(*u32).*;

                log("Got DNS response regarding \"%\". IP is %", query.url, format_ip(query.answer));

                query.complete = true;
                return;
            } else {
                cursor += data_length;
            }
        }
    }

    log_error("Got unexpected DNS response from %.", format_ip(ip.source_address));
}



Network_Packet :: struct {
    data: *void;
    length: int;
}

add_to_packet :: (packet: *Network_Packet, data: Any) {
    if data.type.type == .STRING {
        s := data.value_pointer.(*string).*;

        memcpy(packet.data + packet.length, s.data, s.count);
        packet.length += s.count;

        return;
    }

    memcpy(packet.data + packet.length, data.value_pointer, data.type.runtime_size);
    packet.length += data.type.runtime_size;
}



format_mac :: (mac: [6] u8) -> string {
    push_print_style(mac_address_print_style);
    return tprint("%", mac);
}

format_ip :: (ip: u32) -> string {
    ip_array := bit_cast(ip, [4]u8);

    return tprint("%.%.%.%",
        ip_array[0],
        ip_array[1],
        ip_array[2],
        ip_array[3]
    );
}

Network_Connection :: struct {
    router_mac_address: [6] u8;

    our_ip: u32;
    router_ip: u32;

    adapter: I8254x_Network_Interface_Card;

    dhcp_xid: u32;

    dhcp_handshake_state: enum {
        NOT_STARTED;
        DISCOVER_TRANSMITTED;
        ARP_PROBE_1_TRANSMITTED;
        ARP_PROBE_2_TRANSMITTED;
        ARP_PROBE_3_TRANSMITTED;
        OFFER_ACCEPTED;
        COMPLETED;
    }
    dhcp_message_transmitted_at: Apollo_Time;

    dhcp_request_attempts: int;
    MAX_DHCP_REQUEST_ATTEMPTS :: 5;

    DHCP_DISCOVER_INTERVAL  :: #run seconds_to_apollo(10);
    DHCP_ARP_PROBE_INTERVAL :: #run milliseconds_to_apollo(250);
    DHCP_REQUEST_INTERVAL   :: #run milliseconds_to_apollo(1000);

    arp_table: Table(u32, [6]u8);

    pings_in_flight: [..] struct {
        id: u32;
        destination_ip: u32;
        sent_at: Apollo_Time;
    };

    // Todo: bucket array.
    dns_queries_in_flight: [..] Dns_Query;

    tcp_connections: [..] Tcp_Connection;
    next_port: u16;

    spinlock: Spinlock;
}

allocate_port :: (net: *Network_Connection) -> u16 {
    port := net.next_port;
    net.next_port += 1;

    return port;
}

network_thread :: () {

    sleep(5, .seconds);
    log_category("Net");

    using net := *kernel_globals.net;
    next_port = FIRST_EPHEMERAL_PORT;

    // Todo: replace with a call to random_seed when updating to a compiler version newer than 0.2.014
    time := get_monotonic_system_time();
    context.random_state.low = time.low | 1;
    context.random_state.high = cast,no_check(u64) time.high;

    LOG_ALL_RECEIVED_ETHERNET_PACKETS :: false;

    while true  {
        acquire(*spinlock);

        if dhcp_handshake_state != .COMPLETED {
            update_dhcp(net);
        }

        packets := i8254x_get_newly_received_packets(*adapter);

        for packets {
            eth := cast(*Ethernet_Header) it.data;
            byte_swap_protocol_header(eth);

            if LOG_ALL_RECEIVED_ETHERNET_PACKETS {
                push_print_style(mac_address_print_style);
                log("% => % (%)", eth.source_mac, eth.destination_mac, eth.ethertype);
            }

            if eth.ethertype == .ARP {
                handle_arp(net, eth);
                continue;
            }

            if eth.ethertype == 0x88e1 || eth.ethertype == 0x8912 {
                // Related to powerline adapters.
                continue;
            }

            if eth.ethertype != .IPv4 {
                log("Received network packet with unsupported protocol %.", eth.ethertype);
                continue;
            }

            ip := cast(*Ipv4_Header) (eth + 1);
            byte_swap_protocol_header(ip);

            assert(get(ip.*, .ihl) == 5);

            if ip.protocol == {
              case .ICMP;
                handle_icmp_packet(net, eth);

              case .UDP;
                udp := cast(*Udp_Header) (ip + 1);
                byte_swap_protocol_header(udp);

                if udp.destination_port == DHCP_CLIENT_PORT {
                    handle_dhcp_packet(net, eth);
                }

                if udp.source_port == DNS_SERVER_PORT {
                    handle_dns_packet(net, eth);
                }

              case .TCP;
                handle_tcp_packet(net, eth);

              case;
                log("Received IP packet with unsupported protocol %.", ip.protocol);
            }
        }

        release(*spinlock);

        sleep(5, .milliseconds);
    }
}
