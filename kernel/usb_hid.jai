
Mouse_Report :: struct {
    button: enum_flags u8 {
        LEFT;
        RIGHT;
        MIDDLE;
    }

    x: s8;
    y: s8;
    scroll: s8;
}

Keyboard_Report :: struct {
    modifier_keys:  enum_flags u8 {
        LEFT_CONTROL;
        LEFT_SHIFT;
        LEFT_ALT;
        LEFT_GUI; // Meta/Super/Windows key. Whatever this key is, HID calls it GUI.

        RIGHT_CONTROL;
        RIGHT_SHIFT;
        RIGHT_ALT;
        RIGHT_GUI;
    }

    _:              u8;
    keys:      [6]  HID_Keycode;
}

HID_Descriptor :: struct {
    using header: Descriptor_Header;

    release_version:  u16;
    country_code:     u8;
    num_descriptors:  u8;

    // Followed by an array of descriptor types and lengths.
    child_descriptors: void;
}

HID_Device :: struct {
    socket: *USB_Controller.Socket;

    type: enum {
        MOUSE; KEYBOARD;
    }

    input_buffer: [64] union {
        // Aligned because they are DMA targets.
        mouse:    Mouse_Report    #align 16;
        keyboard: Keyboard_Report #align 16;
    };
}

init_hid_device :: (socket: *USB_Controller.Socket) -> *HID_Device {
    log_category("HID");

    if socket.interface_descriptor.sub_class != 1 return null;

    device := New(HID_Device,, global.small_objects);

    if socket.interface_descriptor.protocol == 1 {
        device.type = .KEYBOARD;
    } else if socket.interface_descriptor.protocol == 2 {
        device.type = .MOUSE;
    } else {
        assert(false); // Todo.
    }

    device.socket = socket;

    for socket.endpoints { // Is it spec'd which endpoint is the right one to use?
        if !it.active   continue;
        if it_index < 2 continue;

        physical_base := get_physical_address(device.input_buffer.data);

        for* b: device.input_buffer {
            trb: Normal_TRB;
            trb.data_pointer = physical_base + cast(u64) it_index * 64;
            set(*trb.dword2, .transfer_length, 16);
            set(*trb.dword3, .interrupt_on_short_packet, 1);
            set(*trb.dword3, .interrupt_on_completion, 1);
            set(*trb.dword3, .trb_type, xx TRB_Type.NORMAL);

            queue_command(*it.transfer_ring, trb);
        }

        flush_commands(socket.controller, socket.slot_id, cast(u32) it_index);
    }

    return device;
}

hid_transfer_event :: (device: *HID_Device, event: *Transfer_Event_TRB) {
    log_category("HID");

    socket := device.socket;

    if socket.interface_descriptor.sub_class != 1 return;

    endpoint_id := get(event.dword3, .endpoint_id);
    if endpoint_id < 2 return; // Todo: Transfer events for endpoint 1 are arriving here. But those are control events, so need to be handled differently.

    assert(endpoint_id > 1 && endpoint_id < 32);

    endpoint := *socket.endpoints[endpoint_id];
    assert(endpoint.active);

    completed_trb      := cast(*Normal_TRB)   (event.event_data           + DIRECT_MAPPING_BASE);
    completed_report   := cast(*void) (completed_trb.data_pointer + DIRECT_MAPPING_BASE);

    if device.type == .MOUSE {
        log("Mouse input: %",    completed_report.(*Mouse_Report).*);
    } else {
        log("Keyboard input: %", completed_report.(*Keyboard_Report).*);
    }

    trb: Normal_TRB;
    trb.data_pointer = completed_trb.data_pointer;
    set(*trb.dword2, .transfer_length, 16);
    set(*trb.dword3, .interrupt_on_short_packet, 1);
    set(*trb.dword3, .interrupt_on_completion, 1);
    set(*trb.dword3, .trb_type, xx TRB_Type.NORMAL);

    queue_command(*endpoint.transfer_ring, trb);
    flush_commands(socket.controller, socket.slot_id, endpoint_id);
}



// American English from the HID Usage Tables (HUT) specification. Translated out of the PDF using emacs magic, there may be mistakes.

HID_Keycode :: enum u8 {
    RESERVED                   :: 0x00;
    ERROR_ROLLOVER             :: 0x01;
    POST_FAIL                  :: 0x02;
    ERROR_UNDEFINED            :: 0x03;
    A                          :: 0x04;
    B                          :: 0x05;
    C                          :: 0x06;
    D                          :: 0x07;
    E                          :: 0x08;
    F                          :: 0x09;
    G                          :: 0x0A;
    H                          :: 0x0B;
    I                          :: 0x0C;
    J                          :: 0x0D;
    K                          :: 0x0E;
    L                          :: 0x0F;
    M                          :: 0x10;
    N                          :: 0x11;
    O                          :: 0x12;
    P                          :: 0x13;
    Q                          :: 0x14;
    R                          :: 0x15;
    S                          :: 0x16;
    T                          :: 0x17;
    U                          :: 0x18;
    V                          :: 0x19;
    W                          :: 0x1A;
    X                          :: 0x1B;
    Y                          :: 0x1C;
    Z                          :: 0x1D;
    NUMBER_ROW_1               :: 0x1E; // Also "!"
    NUMBER_ROW_2               :: 0x1F; // Also "@"
    NUMBER_ROW_3               :: 0x20; // Also "#"
    NUMBER_ROW_4               :: 0x21; // Also "$"
    NUMBER_ROW_5               :: 0x22; // Also "%"
    NUMBER_ROW_6               :: 0x23; // Also "∧"
    NUMBER_ROW_7               :: 0x24; // Also "&"
    NUMBER_ROW_8               :: 0x25; // Also "*"
    NUMBER_ROW_9               :: 0x26; // Also "("
    NUMBER_ROW_0               :: 0x27; // Also ")"
    ENTER                      :: 0x28;
    ESCAPE                     :: 0x29;
    BACKSPACE                  :: 0x2A;
    TAB                        :: 0x2B;
    SPACEBAR                   :: 0x2C;
    MINUS                      :: 0x2D; // Also "("
    EQUALS                     :: 0x2E; // Also "+"
    OPEN_SQUARE_BRACKET        :: 0x2F; // Also "{"
    CLOSED_SQUARE_BRACKET      :: 0x30; // Also "}"
    BACKSLASH                  :: 0x31; // Also "|"
    NON_US_HASH_SYMBOL         :: 0x32; // Also "˜"
    SEMICOLON                  :: 0x33; // Also ":"
    APOSTROPHE                 :: 0x34; // Also "“"
    GRAVE_ACCENT               :: 0x35; // Also "TILDE"
    COMMA                      :: 0x36; // Also "<"
    PERIOD                     :: 0x37; // Also ">"
    FORWARD_SLASH              :: 0x38; // Also "?"
    CAPS_LOCK                  :: 0x39;
    F1                         :: 0x3A;
    F2                         :: 0x3B;
    F3                         :: 0x3C;
    F4                         :: 0x3D;
    F5                         :: 0x3E;
    F6                         :: 0x3F;
    F7                         :: 0x40;
    F8                         :: 0x41;
    F9                         :: 0x42;
    F10                        :: 0x43;
    F11                        :: 0x44;
    F12                        :: 0x45;
    PRINT_SCREEN               :: 0x46;
    SCROLL_LOCK                :: 0x47;
    PAUSE                      :: 0x48;
    INSERT                     :: 0x49;
    HOME                       :: 0x4A;
    PAGEUP                     :: 0x4B;
    DELETE_FORWARD             :: 0x4C;
    END                        :: 0x4D;
    PAGE_DOWN                  :: 0x4E;
    RIGHT_ARROW                :: 0x4F;
    LEFT_ARROW                 :: 0x50;
    DOWN_ARROW                 :: 0x51;
    UPARROW                    :: 0x52;
    KEYPAD_NUM_LOCK            :: 0x53; // Also "Clear"
    KEYPAD_FORWARDSLASH        :: 0x54;
    KEYPAD_ASTERISK            :: 0x55;
    KEYPAD_MINUS               :: 0x56;
    KEYPAD_PLUS                :: 0x57;
    KEYPAD_ENTER3              :: 0x58;
    KEYPAD_1                   :: 0x59; // Also "End"
    KEYPAD_2                   :: 0x5A; // Also "Down Arrow"
    KEYPAD_3                   :: 0x5B; // Also "Page Down"
    KEYPAD_4                   :: 0x5C; // Also "Left Arrow"
    KEYPAD_5                   :: 0x5D;
    KEYPAD_6                   :: 0x5E; // Also "Right Arrow"
    KEYPAD_7                   :: 0x5F; // Also "Home"
    KEYPAD_8                   :: 0x60; // Also "Up Arrow"
    KEYPAD_9                   :: 0x61; // Also "Page Up"
    KEYPAD_0                   :: 0x62; // Also "Insert"
    KEYPAD_PERIOD              :: 0x63; // Also "Delete"
    NON_US_BACKSLASH           :: 0x64; // Also "|"
    APPLICATION                :: 0x65;
    POWER                      :: 0x66;
    KEYPAD_EQUALS              :: 0x67;
    F13                        :: 0x68;
    F14                        :: 0x69;
    F15                        :: 0x6A;
    F16                        :: 0x6B;
    F17                        :: 0x6C;
    F18                        :: 0x6D;
    F19                        :: 0x6E;
    F20                        :: 0x6F;
    F21                        :: 0x70;
    F22                        :: 0x71;
    F23                        :: 0x72;
    F24                        :: 0x73;
    EXECUTE                    :: 0x74;
    HELP                       :: 0x75;
    MENU                       :: 0x76;
    SELECT                     :: 0x77;
    STOP                       :: 0x78;
    AGAIN                      :: 0x79;
    UNDO                       :: 0x7A;
    CUT                        :: 0x7B;
    COPY                       :: 0x7C;
    PASTE                      :: 0x7D;
    FIND                       :: 0x7E;
    MUTE                       :: 0x7F;
    VOLUME_UP                  :: 0x80;
    VOLUME_DOWN                :: 0x81;
    LOCKING_CAPS_LOCK          :: 0x82;
    LOCKING_NUM_LOCK           :: 0x83;
    LOCKING_SCROLL_LOCK        :: 0x84;
    KEYPAD_COMMA               :: 0x85;
    KEYPAD_EQUAL_SIGN          :: 0x86;
    INTERNATIONAL1             :: 0x87;
    INTERNATIONAL2             :: 0x88;
    INTERNATIONAL3             :: 0x89;
    INTERNATIONAL4             :: 0x8A;
    INTERNATIONAL5             :: 0x8B;
    INTERNATIONAL6             :: 0x8C;
    INTERNATIONAL7             :: 0x8D;
    INTERNATIONAL8             :: 0x8E;
    INTERNATIONAL9             :: 0x8F;
    LANG1                      :: 0x90;
    LANG2                      :: 0x91;
    LANG3                      :: 0x92;
    LANG4                      :: 0x93;
    LANG5                      :: 0x94;
    LANG6                      :: 0x95;
    LANG7                      :: 0x96;
    LANG8                      :: 0x97;
    LANG9                      :: 0x98;
    ALTERNATE_ERASE            :: 0x99;
    SYSREQ_ATTENTION           :: 0x9A;
    CANCEL                     :: 0x9B;
    CLEAR                      :: 0x9C;
    PRIOR                      :: 0x9D;
    RETURN                     :: 0x9E;
    SEPARATOR                  :: 0x9F;
    OUT                        :: 0xA0;
    OPER                       :: 0xA1;
    CLEAR_AGAIN                :: 0xA2;
    CRSEL                      :: 0xA3;
    EXSEL                      :: 0xA4;
    AF_RESERVED                :: 0xA5;
    KEYPAD_00                  :: 0xB0;
    KEYPAD_000                 :: 0xB1;
    THOUSANDS_SEPARATOR        :: 0xB2;
    DECIMAL_SEPARATOR          :: 0xB3;
    CURRENCY_UNIT              :: 0xB4;
    CURRENCY_SUB_UNIT          :: 0xB5;
    KEYPAD_OPEN_PARENTHESIS    :: 0xB6;
    KEYPAD_CLOSED_PARENTHESIS  :: 0xB7;
    KEYPAD_OPEN_CURLY_BRACE    :: 0xB8;
    KEYPAD_CLOSED_CURLY_BRACE  :: 0xB9;
    KEYPAD_TAB                 :: 0xBA;
    KEYPAD_BACKSPACE           :: 0xBB;
    KEYPAD_A                   :: 0xBC;
    KEYPAD_B                   :: 0xBD;
    KEYPAD_C                   :: 0xBE;
    KEYPAD_D                   :: 0xBF;
    KEYPAD_E                   :: 0xC0;
    KEYPAD_F                   :: 0xC1;
    KEYPAD_XOR                 :: 0xC2;
    KEYPAD_CARET               :: 0xC3;
    KEYPAD_PERCENT             :: 0xC4;
    KEYPAD_LESS_THAN           :: 0xC5;
    KEYPAD_GREATER_THAN        :: 0xC6;
    KEYPAD_AMPERSAND           :: 0xC7;
    KEYPAD_DOUBLE_AMPERSAND    :: 0xC8;
    KEYPAD_VERTICAL_BAR        :: 0xC9;
    KEYPAD_DOUBLE_VERTICAL_BAR :: 0xCA;
    KEYPAD_COLON               :: 0xCB;
    KEYPAD_HASH_SYMBOL         :: 0xCC;
    KEYPAD_SPACE               :: 0xCD;
    KEYPAD_AT                  :: 0xCE;
    KEYPAD_EXCLAMATION         :: 0xCF;
    KEYPAD_MEMORY_STORE        :: 0xD0;
    KEYPAD_MEMORY_RECALL       :: 0xD1;
    KEYPAD_MEMORY_CLEAR        :: 0xD2;
    KEYPAD_MEMORY_ADD          :: 0xD3;
    KEYPAD_MEMORY_SUBTRACT     :: 0xD4;
    KEYPAD_MEMORY_MULTIPLY     :: 0xD5;
    KEYPAD_MEMORY_DIVIDE       :: 0xD6;
    KEYPAD_PLUS_SLASH_MINUS    :: 0xD7;
    KEYPAD_CLEAR               :: 0xD8;
    KEYPAD_CLEAR_ENTRY         :: 0xD9;
    KEYPAD_BINARY              :: 0xDA;
    KEYPAD_OCTAL               :: 0xDB;
    KEYPAD_DECIMAL             :: 0xDC;
    KEYPAD_HEXADECIMAL         :: 0xDD;
    // DE - DF are reserved.
    LEFT_CONTROL               :: 0xE0;
    LEFT_SHIFT                 :: 0xE1;
    LEFT_ALT                   :: 0xE2;
    LEFT_GUI                   :: 0xE3;
    RIGHT_CONTROL              :: 0xE4;
    RIGHT_SHIFT                :: 0xE5;
    RIGHT_ALT                  :: 0xE6;
    RIGHT_GUI                  :: 0xE7;
}
