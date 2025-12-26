
byte_swap_in_place :: (value: *$T) {
    ti :: type_info(T);

    #if ti.type == .STRUCT {
        byte_swap_protocol_header(value);
    } else #if ti.type == .ARRAY {
        for* value.* byte_swap_in_place(it);
    } else {
        value.* = byte_swap(value.*);
    }
}

byte_swap_protocol_header :: (header: *$T) #modify {
    ti := cast(*Type_Info) T;
    return ti.type == .STRUCT;
} {
    #insert -> string {
        builder: String_Builder;
        info := type_info(T);

        for* info.members {
            if it.flags & .CONSTANT                 continue;
            if it.type.runtime_size < 2             continue;
            if array_find(it.notes, "DontByteswap") continue;

            if it.type == type_info(tls_u24) {
                print(*builder, "    header.%1 = byte_swap(header.%1);\n", it.name);
                continue;
            }

            if it.type.type == {
              case .ENUM; #through;
              case .INTEGER;
                print(*builder, "    header.%1 = byte_swap(header.%1);\n", it.name);
                
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

    return ~byte_swap(cast(u16) sum);
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
    set(*ip, .total_length, byte_swap(cast(u16) total_length));

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

init_tcp_header :: (tcp: *Tcp_Connection, flags: Tcp_Header.Flags, payload := "") -> Tcp_Header {
    h: Tcp_Header;
    h.source_port = tcp.port;
    h.destination_port = tcp.remote_port;
    h.sequence_number = tcp.sequence_number;
    h.ack_number = tcp.ack_number;
    h.data_offset = 5 << 4;
    h.flags = flags;
    h.window = 4096 * 4;

    byte_swap_protocol_header(*h);
    h.checksum = tcp_checksum(h, tcp.net.our_ip, tcp.remote_ip, payload);

    return h;
}

tcp_checksum :: (tcp: Tcp_Header, source: u32, dest: u32, payload := "") -> u16 {
    Pseudo_Header :: struct {
        source_address: u32;
        destination_address: u32;
        zeroes: u8;
        protocol: type_of(Ipv4_Header.protocol);
        tcp_length: u16;

        tcp: Tcp_Header;

        payload: [0x300] u8;
    }

    pseudo: Pseudo_Header;
    pseudo.tcp = tcp;
    pseudo.source_address = source;
    pseudo.destination_address = dest;
    pseudo.protocol = .TCP;
    pseudo.tcp_length = byte_swap(cast(u16) (size_of(Tcp_Header) + payload.count));

    memcpy(pseudo.payload.data, payload.data, payload.count);

    count := payload.count;
    if count % 2 count += 1;

    return internet_checksum(cast(*u8, *pseudo), size_of(Pseudo_Header) + count - 0x300);
}

Tcp_Connection :: struct {
    net: *Network_Connection;

    port: u16;

    remote_port: u16;
    remote_ip: u32;

    // Todo: This only does client side currently.
    handshake_state: enum {
        NOT_STARTED;
        SYN_SENT;
        ESTABLISHED;
        FIN_SENT;
        FIN_RECEIVED;
        CLOSED;
    }

    sequence_number: u32;
    ack_number: u32;

    in_flight: [..] Tcp_Transmission_Info;

    in_stream: Ring_Buffer;
    in_data: Semaphore;

    out_stream: Ring_Buffer;
    out_data: Semaphore;

    do_flush: bool;
    do_close: bool;
}

blocking_read_tcp :: (tcp: *Tcp_Connection, bytes: int, timeout := INFINITE_TIMEOUT) -> []u8 {

    buffer := talloc(bytes);
    cursor: int;

    while true {
        cursor += read_ring_buffer(*tcp.in_stream, buffer + cursor, bytes - cursor);

        if cursor == bytes break;

        if !wait_for(*tcp.in_data, timeout) {
            return .{};
        }
    }

    return .{bytes, buffer};
}

blocking_write_tcp :: (tcp: *Tcp_Connection, bytes: []u8, timeout := INFINITE_TIMEOUT) -> bool {
    cursor: int;

    while true {
        to_write := string.{bytes.count - cursor, bytes.data + cursor};

        cursor += write_ring_buffer(*tcp.out_stream, to_write);

        if cursor == bytes.count break;

        if !wait_for(*tcp.out_data, timeout) {
            return false;
        }
    }

    return true;
}

tcp_flush :: (tcp: *Tcp_Connection) {
    tcp.do_flush = true;
    signal(*tcp.net.work_to_do);
}

tcp_close :: (tcp: *Tcp_Connection) {
    tcp.do_close = true;
    signal(*tcp.net.work_to_do);
}



Tcp_Transmission_Info :: struct {
    // There should be an instance of this for each unacknowledged transmitted packet in a connection.
    // Except for ACKs sent by us, as we don't expect to receive an ACK for those.

    packet: Network_Packet;
    sequence: u32;

    // This value is stored in the packet header, but it seems cleaner to keep a separate copy of it rather than parsing it out of the packet.
    flags: Tcp_Header.Flags;

    last_sent_at: Apollo_Time; // To detect if we need to retransmit
    attempts: int;
}

record_tcp_packet_for_potential_retransmission :: (tcp: *Tcp_Connection, packet: Network_Packet, flags: Tcp_Header.Flags) {

    bytes_to_transmit := packet.length - (size_of(Ethernet_Header) + size_of(Ipv4_Header) + size_of(Tcp_Header));
    if bytes_to_transmit == 0 bytes_to_transmit = 1;
    tcp.sequence_number += cast(u32) bytes_to_transmit;

    info := array_add(*tcp.in_flight);
    info.last_sent_at = get_monotonic_time();
    info.packet = packet;

    // The sequence number in the ACK will include the bytes transmitted in this packet, so store that.
    // The sequence number of the packet we're transmitting right now does not match this sequence number, as it describes the first byte being transmitted in that packet.
    info.sequence = tcp.sequence_number;
    info.flags = flags;
}

transmit_tcp_segment :: (tcp: *Tcp_Connection, header_flags: Tcp_Header.Flags, payload := "", loc := #caller_location) {

    if tcp.handshake_state == .CLOSED {
        log_error("Trying to transmit TCP packet over a connection that has already been closed.");
        return;
    }

    packet: Network_Packet;
    packet.data = cast(*void) get_4k_page() + DIRECT_MAPPING_BASE;

    eth := init_ethernet_header(tcp.net);
    add_to_packet(*packet, eth);

    datagram_length := size_of(Ipv4_Header) + size_of(Tcp_Header) + payload.count;
    ip := init_ip_header(tcp.net, .TCP, tcp.remote_ip, datagram_length);
    add_to_packet(*packet, ip);

    header := init_tcp_header(tcp, header_flags, payload);
    add_to_packet(*packet, header);

    add_to_packet(*packet, payload);

    if payload.count {
        record_tcp_packet_for_potential_retransmission(tcp, packet, header_flags);
    }

    i8254x_transmit_packet(*tcp.net.adapter, packet);
}

initiate_tcp_connection :: (net: *Network_Connection, remote_ip: u32, remote_port: u16) -> *Tcp_Connection {

    log("Initating TCP connection with %:%", format_ip(remote_ip), remote_port);

    port := cast,trunc(u16)random_get(); // Todo

    // Clear the high bit to ensure we have at least a couple gigabytes of headroom until we add code to handle overflow.
    sequence_number := cast(u32, random_get() & 0x7fff_ffff);

    // Todo: Bucket_Array for pointer stability.
    tcp := array_add(*net.tcp_connections);
    tcp.net = net;
    tcp.port = port;
    tcp.remote_port = remote_port;
    tcp.remote_ip = remote_ip;
    tcp.handshake_state = .NOT_STARTED;
    tcp.sequence_number = sequence_number;
    tcp.ack_number = 0;

    tcp.in\_stream.buffer = NewArray(0x4000, u8);
    tcp.out_stream.buffer = NewArray(0x4000, u8);

    tcp.in\_data.counter_max = 1;
    tcp.out_data.counter_max = 1;

    return tcp;
}

update_tcp_connection :: (tcp: *Tcp_Connection) {
    // Todo: FIN, SYN, ACK should also be retransmitted if necessary.

    if tcp.handshake_state == .NOT_STARTED {
        transmit_tcp_segment(tcp, .SYN);
        tcp.sequence_number += 1;
        tcp.handshake_state = .SYN_SENT;
    }

    if tcp.handshake_state != .ESTABLISHED {
        return;
    }

    // Periodically check if something needs to be retransmitted.
    time_now := get_monotonic_time();
    retransmission_period := seconds_to_apollo(1);

    for* tcp.in_flight {
        if time_now - it.last_sent_at > retransmission_period {
            log("TCP retransmit %", it.sequence);
            i8254x_transmit_packet(*tcp.net.adapter, it.packet);

            it.last_sent_at = time_now;
            it.attempts += 1;
        }
    }

    // Auto flush if the user thread wants us to close the connection.
    tcp.do_flush ||= tcp.do_close;

    if tcp.do_flush {
        bytes_per_packet :: 512;

        while true {
            tcp.do_flush = false;

            payload: string;
            payload.data = talloc(bytes_per_packet);

            bytes := read_ring_buffer(*tcp.out_stream, payload.data, bytes_per_packet);
            payload.count = bytes;

            if bytes {
                transmit_tcp_segment(tcp, .ACK, payload);
            }

            if bytes < bytes_per_packet break;
        }
    }

    if tcp.do_close {
        // Make sure all queued data has been transmitted before actually closing.
        waiting_for_retransmission := tcp.in_flight.count > 0;

        if !waiting_for_retransmission {
            transmit_tcp_segment(tcp, .FIN | .ACK);
            tcp.handshake_state = .FIN_SENT;
        }
    }
}

update_tcp_handshake :: (tcp: *Tcp_Connection, segment: *Tcp_Header) {
    // Maybe it would be easier to write this simply, by doing a switch statement over the current handshake state, and responding to the flags in each case statement.

    if segment.flags == .SYN | .ACK {
        // In theory SYN-ACK are allowed to be separate segments but it isn't done in practice.

        if tcp.handshake_state != .SYN_SENT {
            log_error("Unexpected SYN-ACK.");

            transmit_tcp_segment(tcp, .RST);
            tcp.handshake_state = .CLOSED;

            return;
        }

        tcp.ack_number = segment.sequence_number + 1;
        transmit_tcp_segment(tcp, .ACK);

        tcp.handshake_state = .ESTABLISHED;
        log("TCP connection with %:% successfully established.", format_ip(tcp.remote_ip), tcp.remote_port);

        return;
    }

    if segment.flags & .FIN {
        // Todo: Handle simultaneous close.

        if tcp.handshake_state == {
          case .ESTABLISHED;
            // Remote-initiated FIN.
            transmit_tcp_segment(tcp, .FIN | .ACK);
            tcp.handshake_state = .CLOSED;

          case .FIN_SENT;
            // Locally initiated FIN.
            transmit_tcp_segment(tcp, .ACK);
            tcp.handshake_state = .CLOSED;
        }

        return;
    }

    if segment.flags & .RST {
        log_error("RST received.");
        tcp.handshake_state = .CLOSED;
        return;
    }

    if segment.flags & .ACK {
        if tcp.handshake_state == .FIN_SENT {
            tcp.handshake_state = .CLOSED;
        }
        return;
    }

    log_error("TCP flags not understood: %", segment.flags);
    transmit_tcp_segment(tcp, .RST);
    tcp.handshake_state = .CLOSED;
}

receive_tcp_segment :: (tcp: *Tcp_Connection, segment: *Tcp_Header, bytes: int) {

    update_tcp_handshake(tcp, segment);

    if tcp.handshake_state == .CLOSED {
        return;
    }

    // Remove segments that have been acknowledged from the retransmit buffer.
    for* tcp.in_flight {
        if it.sequence <= segment.ack_number {
            free_4k_page(cast(u64)it.packet.data - DIRECT_MAPPING_BASE);
            remove it;
        }
    }

    if bytes == 0 {
        return;
    }

    if segment.sequence_number < tcp.ack_number {
        // Todo.
        return;
    }

    if segment.sequence_number > tcp.ack_number {
        // We don't support receiving data out of order yet. ACK to ask the server to retransmit the data we missed.
        log("Received packets out of order.");
        transmit_tcp_segment(tcp, .ACK);
        return;
    }

    log("Received TCP segment from %:%, (% bytes)", format_ip(tcp.remote_ip), tcp.remote_port, bytes);

    packet_data: string;
    packet_data.data = cast(*u8) (segment + 1);
    packet_data.count = bytes;

    written := write_ring_buffer(*tcp.in_stream, packet_data);

    signal(*tcp.in_data);

    tcp.ack_number += cast(u32)written;
    transmit_tcp_segment(tcp, .ACK);
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

byte_swap :: (u24: tls_u24) -> tls_u24 {
    result: tls_u24;
    result[0] = u24[2];
    result[1] = u24[1];
    result[2] = u24[0];
    return result;
}



Tls_Record_Header :: struct {
    content_type: Tls_Content_Type;
    version: Tls_Version #align 1;
    length: u16 #align 1;
}

Tls_Content_Type :: enum u8 {
    CHANGE_CIPHER_SPEC :: 20;
    ALERT              :: 21;
    HANDSHAKE          :: 22;
    APPLICATION_DATA   :: 23;
}

Tls_Handshake_Header :: struct {
    type: Tls_Handshake_Type;
    length: tls_u24;
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

Tls_Named_Curve :: enum u16 {
    SECP256R1  :: 23;
    SECP384R1  :: 24;
    SECP521R1  :: 25;
    X25519     :: 29;
    X448       :: 30;
}

Tls_Extension :: enum u16 {
    server_name :: 0x00_00;
    status_request :: 0x00_05;
    supported_groups :: 0x00_0a;
    ec_points_format :: 0x00_0b;
    signature_algorithms :: 0x00_0d;
    renegotiation_info :: 0xff_01;
    signed_certificate_timestamp :: 0x00_12;
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
    qwords: [4] u64; @DontByteswap

#overlay(qwords)
    bytes:  [32] u8; @DontByteswap

    // Some implementations/RFCs put a unix timestamp in the low bits of random, but apparently this is not recommended anymore.
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

Tls_Connection :: struct {
    tcp: *Tcp_Connection;

    using encryption_keys: struct {
        client_write_key: i128;
        server_write_key: i128;
        client_write_iv:  [4]u8;
        server_write_iv:  [4]u8;
    }

    sequence_number: u64;
    server_sequence_number: u64;
}

Tls_Client_Hello :: struct {
    client_version: Tls_Version;
    random: Tls_Random #align 1;  @DontByteswap

    session_id: u8;

    num_cipher_suites: u16 #align 1;
    cipher_suites: [1] Tls_Cipher_Suite #align 1;

    num_compression_methods: u8;
    compression_method: u8;

    extensions_length: u16 #align 1;

    // Todo: hardcoded.
    extensions: struct {
        supported_groups:      [8] u8;
        ec_points_format:      [6] u8;
        signature_algorithms:  [8] u8;
        sct:                   [4] u8;
        renegotiation_info:    [5] u8;
    } @DontByteswap
}

establish_tls_connection :: (tcp: *Tcp_Connection) -> Tls_Connection {
    push_print_style().default_format_int.base = 16;

    if tcp.handshake_state != .ESTABLISHED {
        log_error("Trying to create a TLS connection without an established TCP connection.");
        return .{};
    }


    // Near the end of the handshake we need to transmit a hash of all handshake messages up to that point.
    all_handshake_payload: String_Builder;
    hashing_enabled := true;

    // Todo: Doing many small writes to the ring buffer instead of fewer large writes.
    send :: (value: $T) #expand {
        #if type_info(T).type != .ARRAY {
            stack_value := value;
            byte_swap_in_place(*stack_value);

            buffer := []u8.{size_of(T), cast(*u8) *stack_value};
        } else {
            buffer := cast([]u8)value;
        }

        blocking_write_tcp(tls.tcp, buffer);

        // Todo: The way they probably expect you to structure the code is to have a function that adds the record header to an already constructed message, which would make hashing and length calculation easier.
        if hashing_enabled && T != Tls_Record_Header {
            append(*all_handshake_payload, cast(string)buffer);
        }
    }

    receive :: ($ type: Type) -> type #expand {
        buffer := blocking_read_tcp(tls.tcp, size_of(type));

        if hashing_enabled && type != Tls_Record_Header {
            append(*all_handshake_payload, cast(string)buffer);
        }

        item := cast(*type) buffer.data;
        byte_swap_in_place(item);
        return item.*;
    }

    receive :: (count: int) -> []u8 #expand {
        buffer := blocking_read_tcp(tls.tcp, count);

        if hashing_enabled {
            append(*all_handshake_payload, cast(string)buffer);
        }

        return buffer;
    }


    // Key exchange parameters:

    our_secret_key: [32] u8;
    our_public_key: [32] u8;

    server_public_key: [32] u8;

    client_random: Tls_Random;
    server_random: Tls_Random;

    Master_Secret: [48] u8;


    tls: Tls_Connection;
    tls.tcp = tcp;

    {
        // Send ClientHello.

        record: Tls_Record_Header;
        record.content_type = .HANDSHAKE;
        record.version      = .TLS_1_0;
        record.length       = size_of(Tls_Client_Hello) + size_of(Tls_Handshake_Header);
        send(record);

        handshake: Tls_Handshake_Header;
        handshake.type = .CLIENT_HELLO;
        set(*handshake.length, size_of(Tls_Client_Hello));
        send(handshake);

        {
            using hello: Tls_Client_Hello;

            client_version           = .TLS_1_2;
            num_cipher_suites        = size_of(Tls_Cipher_Suite);
            cipher_suites[0]         = .ECDHE_RSA_WITH_AES128_GCM_SHA256;
            num_compression_methods  = 1;
            extensions_length        = size_of(type_of(extensions));

            // Todo: Hardcoded.
            extensions.signature_algorithms = .[0x0,  0xd,  0x0,  0x4, 0x0, 0x2, 0x4, 0x1];
            extensions.sct                  = .[0x0,  0x12, 0x0,  0x0];
            extensions.supported_groups     = .[0x0,  0xa,  0x0,  0x4, 0x0,  0x2, 0x0, 0x1d];
            extensions.ec_points_format     = .[0x0,  0xb,  0x0,  0x2, 0x1, 0x0];
            extensions.renegotiation_info   = .[0xff, 0x1,  0x0,  0x1, 0x0];

            for* client_random.qwords it.* = random_get();
            random = client_random;

            send(hello);
        }

        tcp_flush(tcp);
    }

    {
        // Receive ServerHello.

        // Todo: Should detect TLS alerts wherever record headers are received.
        record    := receive(Tls_Record_Header);
        handshake := receive(Tls_Handshake_Header);

        version := receive(Tls_Version);
        random  := receive(Tls_Random);

        server_random = random;

        session_id_size := receive(u8);
        session_id      := receive(session_id_size);

        push_print_style().default_format_int.base = 16;
        log("Got session ID: %", session_id);

        cipher_suite := receive(Tls_Cipher_Suite);
        log("Requested cipher suite: %", cipher_suite);

        compression_method := receive(u8);
        assert(compression_method == 0);

        extensions_length := receive(u16);

        while extensions_length > 0 {
            extension_type := receive(Tls_Extension);
            extensions_length -= size_of(Tls_Extension);

            log("Server hello provided extension %", extension_type);

            extension_size := receive(u16);
            extensions_length -= size_of(u16);

            extension_bytes := receive(extension_size);
            extensions_length -= extension_size;
        }
    }

    {
        // Receive security certificate.

        receive(Tls_Record_Header);
        receive(Tls_Handshake_Header);

        all_certificates_length := get(*receive(tls_u24));

        while all_certificates_length > 0 {
            certificate_length := get(*receive(tls_u24));
            certificate := receive(certificate_length);

            success, cert := parse_x509_certificate(certificate);

            assert(success);

            all_certificates_length -= size_of(tls_u24);
            all_certificates_length -= certificate_length;
        }
    }

    {
        // Server Key Exchange.

        record := receive(Tls_Record_Header);
        header := receive(Tls_Handshake_Header);

        assert(record.content_type == .HANDSHAKE);
        assert(header.type == .SERVER_KEY_EXCHANGE);

        assert(receive(u8) == 3); // named_curve
        assert(receive(Tls_Named_Curve) == .X25519);

        key_length := receive(u8);
        assert(key_length == 32);

        key := receive(key_length);
        memcpy(server_public_key.data, key.data, 32);

        log("Got public key %", key);

        // Todo: validate key against security certificate.

        signature_type := receive(u16);
        signature_length := receive(u16);

        signature := receive(signature_length);
    }

    {
        // Server Hello Done.

        receive(Tls_Record_Header);
        receive(Tls_Handshake_Header);

        // Generate our secret key.
        random_bytes: [32]u8;
        fill_random(random_bytes);

        our_public_key, our_secret_key = Curve25519.generate_keypair(random_bytes);

        log("Our secret key: %", our_secret_key);
        log("Our public key: %", our_public_key);
    }

    {
        // Transmit Client Key Exchange.

        KEY_EXCHANGE_SIZE :: size_of([32]u8) + size_of(u8);

        record: Tls_Record_Header;
        record.content_type = .HANDSHAKE;
        record.version = .TLS_1_2;
        record.length = KEY_EXCHANGE_SIZE + size_of(Tls_Handshake_Header);
        send(record);

        cke: Tls_Handshake_Header;
        cke.type = .CLIENT_KEY_EXCHANGE;
        set(*cke.length, KEY_EXCHANGE_SIZE);
        send(cke);

        send(cast(u8) 32);
        send(our_public_key);

        tcp_flush(tls.tcp);
    }

    {
        // Calculate encryption keys.

        premaster_secret := cast(string)Curve25519.x25519(
            *server_public_key,
            *our_secret_key,
        );

        cr := cast(string)client_random.bytes;
        sr := cast(string)server_random.bytes;

        seed := join("master secret", cr, sr,, temp);

        a0 := seed;
        a1 := cast(string)hmac_sha256(premaster_secret, a0);
        a2 := cast(string)hmac_sha256(premaster_secret, a1);
        p1 := cast(string)hmac_sha256(premaster_secret, join(a1, seed,, temp));
        p2 := cast(string)hmac_sha256(premaster_secret, join(a2, seed,, temp));

        memcpy(Master_Secret.data,      p1.data, 32);
        memcpy(Master_Secret.data + 32, p2.data, 16);

        ms := cast(string)Master_Secret;

        seed = join("key expansion", sr, cr,, temp);

        a0  = seed;
        a1  = cast(string)hmac_sha256(ms, a0);
        a2  = cast(string)hmac_sha256(ms, a1);
        a3 := cast(string)hmac_sha256(ms, a2);
        a4 := cast(string)hmac_sha256(ms, a3);

        p1  = cast(string)hmac_sha256(ms, join(a1, seed,, temp));
        p2  = cast(string)hmac_sha256(ms, join(a2, seed,, temp));
        p3 := cast(string)hmac_sha256(ms, join(a3, seed,, temp));
        p4 := cast(string)hmac_sha256(ms, join(a4, seed,, temp));

        buffer := join(p1, p2, p3, p4,, temp);

        memcpy(*tls.encryption_keys, buffer.data, size_of(type_of(tls.encryption_keys)));
    }

    verify_data_input := builder_to_string(*all_handshake_payload);
    hashing_enabled = false;

    {
        // Client Change Cipher Spec.

        record: Tls_Record_Header;
        record.content_type = .CHANGE_CIPHER_SPEC;
        record.version = .TLS_1_2;
        record.length = 1;

        send(record);
        send(cast(u8) 0x1);

        tcp_flush(tls.tcp);
    }

    {
        // Client Handshake Finished.

        message: struct {
            header: Tls_Handshake_Header;
            verify_data: [12]u8;
        }

        message.header.type = .FINISHED;
        set(*message.header.length, 12);
        byte_swap_in_place(*message.header);

        {
            // Calculate verify_data.

            sha_all_messages := cast,force([32]u8)sha256_base_flipped(verify_data_input);

            seed := join("client finished", cast(string)sha_all_messages,, temp);
            a0   := seed;
            a1   := cast(string)hmac_sha256(cast(string)Master_Secret, a0);
            p1   := cast(string)hmac_sha256(cast(string)Master_Secret, join(a1, seed,, temp));

            memcpy(message.verify_data.data, p1.data, 12);
        }

        text: []u8;
        text.data = cast(*u8) *message;
        text.count = size_of(type_of(message));

        ciphertext := tls_encrypt_message(*tls, text, .HANDSHAKE);

        record: Tls_Record_Header;
        record.content_type = .HANDSHAKE;
        record.version = .TLS_1_2;
        record.length = cast(u16) ciphertext.count;

        send(record);
        send(ciphertext);
        tcp_flush(tls.tcp);
    }

    {
        // Server Change Cipher Spec.

        receive(Tls_Record_Header);
        assert(receive(u8) == 1);
    }

    {
        // Server Hanshake Finished.

        record := receive(Tls_Record_Header);
        text   := receive(record.length);

        success, plaintext := tls_decrypt_message(*tls, text, .HANDSHAKE);
        assert(success);

        // Todo: Verify server handshake hash.
    }

    return tls;
}

tls_transmit_application_data :: (tls: *Tls_Connection, plaintext: string) {

    ciphertext := tls_encrypt_message(tls, cast([]u8)plaintext, .APPLICATION_DATA);

    buffer := NewArray(ciphertext.count + size_of(Tls_Record_Header), u8,, temp);

    record: Tls_Record_Header;
    record.content_type = .APPLICATION_DATA;
    record.version = .TLS_1_2;
    record.length = cast(u16) ciphertext.count;
    byte_swap_in_place(*record);

    memcpy(buffer.data, *record, size_of(Tls_Record_Header));
    memcpy(buffer.data + size_of(Tls_Record_Header), ciphertext.data, ciphertext.count);

    blocking_write_tcp(tls.tcp, buffer);
    tcp_flush(tls.tcp);
}

tls_receive_application_data :: (tls: *Tls_Connection) -> string {
    buffer := blocking_read_tcp(tls.tcp, size_of(Tls_Record_Header));

    record := cast(*Tls_Record_Header) buffer.data;
    byte_swap_in_place(record);

    assert(record.content_type == .APPLICATION_DATA);

    ciphertext := blocking_read_tcp(tls.tcp, record.length);
    success, plaintext := tls_decrypt_message(tls, ciphertext, record.content_type);
    assert(success);

    return cast(string)plaintext;
}

tls_encrypt_message :: (tls: *Tls_Connection, text: []u8, content_type: Tls_Content_Type) -> []u8 {

    bytes := text.count + 8 + size_of(i128); // Add room for explicit IV and auth tag.

    result: []u8;
    result.data = talloc(bytes);
    result.count = bytes;

    sequence_be := byte_swap(tls.sequence_number);

    iv: [12]u8;
    memcpy(iv.data, tls.client_write_iv.data, 4);
    memcpy(iv.data + 4, *sequence_be, 8);
    memcpy(result.data, iv.data + 4, 8);

    aad: [13]u8;
    {
        // Fill in Additional Authenticated Data.

        memcpy(aad.data, *sequence_be, size_of(u64));

        aad[8] = cast(u8) content_type;
        aad[9] = 0x03; aad[10] = 0x03;

        text_size := byte_swap(cast(u16) text.count);
        memcpy(aad.data + 11, *text_size, 2);
    }

    memcpy(result.data + 8, text.data, text.count);

    plaintext := result;
    plaintext.data += 8;
    plaintext.count = text.count;

    auth_tag := aes128_gcm_encrypt_stream(plaintext, tls.client_write_key, iv, aad);

    memcpy(result.data + 8 + text.count, auth_tag.bytes.data, 16);

    tls.sequence_number += 1;
    return result;
}

tls_decrypt_message :: (tls: *Tls_Connection, text: []u8, content_type: Tls_Content_Type) -> bool, []u8 {
    // Note this destructively modifies 'text'. 

    aad: [13]u8;

    {
        // Fill in Additional Authenticated Data.

        sequence_be := byte_swap(tls.server_sequence_number);
        memcpy(aad.data, *sequence_be, size_of(u64));

        aad[8] = cast(u8) content_type;
        aad[9] = 0x03; aad[10] = 0x03;

        text_size := byte_swap(cast(u16) text.count - 8 - size_of(i128));
        memcpy(aad.data + 11, *text_size, 2);
    }

    iv: [12]u8;
    memcpy(iv.data, tls.server_write_iv.data, 4);
    memcpy(iv.data + 4, text.data, 8);

    ciphertext: []u8;
    ciphertext.count = text.count - 8 - size_of(i128);
    ciphertext.data = text.data + 8;

    auth_tag: i128;
    memcpy(*auth_tag, text.data + 8 + ciphertext.count, size_of(i128));

    success := aes128_gcm_decrypt_stream(ciphertext, tls.server_write_key, iv, aad, auth_tag);

    tls.server_sequence_number += 1;
    return success, ciphertext;
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
    dhcp.opcode        = 0x1;
    dhcp.hardware_type = 0x1;
    dhcp.mac_length    = 0x6;
    dhcp.xid           = net.dhcp_xid;
    dhcp.client_mac    = net.adapter.mac_address;
    dhcp.server_ip     = net.router_ip;
    dhcp.magic         = Dhcp_Message.MAGIC;

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
        log_error("DHCP packet too small.");
        return;
    }

    byte_swap_protocol_header(*dhcp);

    if dhcp.magic != Dhcp_Message.MAGIC {
        log_error("DHCP packet magic doesn't match.");
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
        bytes := (.*) cast(*[]u8) data.value_pointer;
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
    return cast(u16) options.buffer.count + 1;
}

commit_dhcp_options :: (packet: *Network_Packet, options: Dhcp_Options_Builder) {
    array_add(*options.buffer, 0xff);
    add_to_packet(packet, cast(string) options.buffer);
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

                delta_ms := to_milliseconds(time - it.sent_at);
                log("Ping % = %ms", format_ip(it.destination_ip), delta_ms);

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
    // Todo: User thread version of this.

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
    udp.source_port = net.dns_client_port;
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
        add_to_packet(*packet, cast(u8) left.count);
        add_to_packet(*packet, left);

        if !found break;

        remaining = right;
    }
    add_to_packet(*packet, cast(u8) 0);

    add_to_packet(*packet, byte_swap(Dns_Record_Type.A));
    add_to_packet(*packet, byte_swap(Dns_Class.IN));

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

        Read :: ($T: Type) -> T #expand {
            defer cursor += size_of(T);
            return byte_swap((.*) cast(*T) cursor);
        }

        cursor := cast(*u8) (*dns + 1);

        // Must cast this or it may underflow and loop for very many iterations.
        for 0..cast(s16)dns.questions-1 {

            // Skip all the questions.
            Skip_Name();

            Read(Dns_Record_Type);
            Read(Dns_Class);
        }

        // Should now be at the answers. Find a host address.

        for 0..cast(s16)dns.answers-1 {

            // Detect if it's a pointer.
            if (cursor[0] >> 6) == 0b11 {
                cursor += 2;
            } else {
                Skip_Name();
            }

            type := Read(Dns_Record_Type);

            cursor += 4; // Class, TTL

            data_length := Read(u16);

            if type == .A {
                if data_length != 4 {
                    log_error("DNS response address is not IPv4");
                    return;
                }

                query.answer = Read(u32);

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
        assert(packet.length + s.count <= 4096); // Todo

        memcpy(packet.data + packet.length, s.data, s.count);
        packet.length += s.count;

        return;
    }

    assert(packet.length + data.type.runtime_size <= 4096); // Todo

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

    SKIP_ARP_PROBES :: true;

    arp_table: Table(u32, [6]u8);

    pings_in_flight: [..] struct {
        id: u32;
        destination_ip: u32;
        sent_at: Apollo_Time;
    };

    // Todo: bucket array.
    dns_queries_in_flight: [..] Dns_Query;
    dns_client_port: u16;

    tcp_connections: [..] Tcp_Connection;
    next_port: u16;

    work_to_do: Semaphore;
}

allocate_port :: (net: *Network_Connection) -> u16 {
    port := net.next_port;
    net.next_port += 1;

    return port;
}

network_thread :: () {

    log_category("Net");

    time := get_monotonic_system_time();
    random_seed(cast(S128)time);

    using net := *global.network_connection;
    next_port = FIRST_EPHEMERAL_PORT;

    dns_client_port = allocate_port(net);

    work_to_do.counter_max = 1;

    while true  {
        timeout := seconds_to_apollo(10);

        if dhcp_handshake_state != .COMPLETED {
            update_dhcp(net);

            // The network thread needs to keep updating while trying to connect to the local network.
            timeout = milliseconds_to_apollo(50);
        }

        for* net.tcp_connections {
            update_tcp_connection(it);
        }

        wait_for(*net.work_to_do, timeout);

        packets := i8254x_get_newly_received_packets(*adapter);

        for packet: packets {
            eth := cast(*Ethernet_Header) packet.data;
            byte_swap_protocol_header(eth);

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

            ip_length := byte_swap(cast(u16) get(ip.*, .total_length)) - size_of(Ipv4_Header);

            // Todo: properly validate the IP packet (size, IHL, etc.)

            if ip.protocol == {
              case .ICMP;
                handle_icmp_packet(net, eth);

              case .UDP;
                udp := cast(*Udp_Header) (ip + 1);
                byte_swap_protocol_header(udp);

                if udp.destination_port == DHCP_CLIENT_PORT {
                    handle_dhcp_packet(net, eth);
                    continue;
                }

                if udp.destination_port == net.dns_client_port {
                    handle_dns_packet(net, eth);
                    continue;
                }

                if udp.destination_port == 137 {
                    // NetBIOS Name Service.
                    continue;
                }

                log("UDP packet for port % unhandled.\n", udp.destination_port);

              case .TCP;
                header := cast(*Tcp_Header) (ip + 1);
                byte_swap_protocol_header(header);

                for* net.tcp_connections {
                    if it.port != header.destination_port {
                        continue;
                    }

                    bytes := ip_length - size_of(Tcp_Header);

                    receive_tcp_segment(it, header, bytes);

                    continue packet;
                }

                log_error("Got TCP message for nonexistent connection on port %", header.destination_port);

              case;
                log("Received IP packet with unsupported protocol %.", ip.protocol);
            }
        }
    }
}
