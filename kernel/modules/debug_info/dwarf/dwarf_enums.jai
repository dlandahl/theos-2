// Enums macro-generated from LLVM source: include/llvm/BinaryFormat/Dwarf.def

Dwarf_Attribute_Type :: enum u64 {
    SIBLING                         :: 0x01;
    LOCATION                        :: 0x02;
    NAME                            :: 0x03;
    ORDERING                        :: 0x09;
    BYTE_SIZE                       :: 0x0b;
    BIT_OFFSET                      :: 0x0c;
    BIT_SIZE                        :: 0x0d;
    STMT_LIST                       :: 0x10;
    LOW_PC                          :: 0x11;
    HIGH_PC                         :: 0x12;
    LANGUAGE                        :: 0x13;
    DISCR                           :: 0x15;
    DISCR_VALUE                     :: 0x16;
    VISIBILITY                      :: 0x17;
    IMPORT                          :: 0x18;
    STRING_LENGTH                   :: 0x19;
    COMMON_REFERENCE                :: 0x1a;
    COMP_DIR                        :: 0x1b;
    CONST_VALUE                     :: 0x1c;
    CONTAINING_TYPE                 :: 0x1d;
    DEFAULT_VALUE                   :: 0x1e;
    INLINE                          :: 0x20;
    IS_OPTIONAL                     :: 0x21;
    LOWER_BOUND                     :: 0x22;
    PRODUCER                        :: 0x25;
    PROTOTYPED                      :: 0x27;
    RETURN_ADDR                     :: 0x2a;
    START_SCOPE                     :: 0x2c;
    BIT_STRIDE                      :: 0x2e;
    UPPER_BOUND                     :: 0x2f;
    ABSTRACT_ORIGIN                 :: 0x31;
    ACCESSIBILITY                   :: 0x32;
    ADDRESS_CLASS                   :: 0x33;
    ARTIFICIAL                      :: 0x34;
    BASE_TYPES                      :: 0x35;
    CALLING_CONVENTION              :: 0x36;
    COUNT                           :: 0x37;
    DATA_MEMBER_LOCATION            :: 0x38;
    DECL_COLUMN                     :: 0x39;
    DECL_FILE                       :: 0x3a;
    DECL_LINE                       :: 0x3b;
    DECLARATION                     :: 0x3c;
    DISCR_LIST                      :: 0x3d;
    ENCODING                        :: 0x3e;
    EXTERNAL                        :: 0x3f;
    FRAME_BASE                      :: 0x40;
    FRIEND                          :: 0x41;
    IDENTIFIER_CASE                 :: 0x42;
    MACRO_INFO                      :: 0x43;
    NAMELIST_ITEM                   :: 0x44;
    PRIORITY                        :: 0x45;
    SEGMENT                         :: 0x46;
    SPECIFICATION                   :: 0x47;
    STATIC_LINK                     :: 0x48;
    TYPE                            :: 0x49;
    USE_LOCATION                    :: 0x4a;
    VARIABLE_PARAMETER              :: 0x4b;
    VIRTUALITY                      :: 0x4c;
    VTABLE_ELEM_LOCATION            :: 0x4d;

    // New in DWARF v3:
    ALLOCATED                       :: 0x4e;
    ASSOCIATED                      :: 0x4f;
    DATA_LOCATION                   :: 0x50;
    BYTE_STRIDE                     :: 0x51;
    ENTRY_PC                        :: 0x52;
    USE_UTF8                        :: 0x53;
    EXTENSION                       :: 0x54;
    RANGES                          :: 0x55;
    TRAMPOLINE                      :: 0x56;
    CALL_COLUMN                     :: 0x57;
    CALL_FILE                       :: 0x58;
    CALL_LINE                       :: 0x59;
    DESCRIPTION                     :: 0x5a;
    BINARY_SCALE                    :: 0x5b;
    DECIMAL_SCALE                   :: 0x5c;
    SMALL                           :: 0x5d;
    DECIMAL_SIGN                    :: 0x5e;
    DIGIT_COUNT                     :: 0x5f;
    PICTURE_STRING                  :: 0x60;
    MUTABLE                         :: 0x61;
    THREADS_SCALED                  :: 0x62;
    EXPLICIT                        :: 0x63;
    OBJECT_POINTER                  :: 0x64;
    ENDIANITY                       :: 0x65;
    ELEMENTAL                       :: 0x66;
    PURE                            :: 0x67;
    RECURSIVE                       :: 0x68;

    // New in DWARF v4:
    SIGNATURE                       :: 0x69;
    MAIN_SUBPROGRAM                 :: 0x6a;
    DATA_BIT_OFFSET                 :: 0x6b;
    CONST_EXPR                      :: 0x6c;
    ENUM_CLASS                      :: 0x6d;
    LINKAGE_NAME                    :: 0x6e;

    // New in DWARF v5:
    STRING_LENGTH_BIT_SIZE          :: 0x6f;
    STRING_LENGTH_BYTE_SIZE         :: 0x70;
    RANK                            :: 0x71;
    STR_OFFSETS_BASE                :: 0x72;
    ADDR_BASE                       :: 0x73;
    RNGLISTS_BASE                   :: 0x74;
    DWO_ID                          :: 0x75;
    DWO_NAME                        :: 0x76;
    REFERENCE                       :: 0x77;
    RVALUE_REFERENCE                :: 0x78;
    MACROS                          :: 0x79;
    CALL_ALL_CALLS                  :: 0x7a;
    CALL_ALL_SOURCE_CALLS           :: 0x7b;
    CALL_ALL_TAIL_CALLS             :: 0x7c;
    CALL_RETURN_PC                  :: 0x7d;
    CALL_VALUE                      :: 0x7e;
    CALL_ORIGIN                     :: 0x7f;
    CALL_PARAMETER                  :: 0x80;
    CALL_PC                         :: 0x81;
    CALL_TAIL_CALL                  :: 0x82;
    CALL_TARGET                     :: 0x83;
    CALL_TARGET_CLOBBERED           :: 0x84;
    CALL_DATA_LOCATION              :: 0x85;
    CALL_DATA_VALUE                 :: 0x86;
    NORETURN                        :: 0x87;
    ALIGNMENT                       :: 0x88;
    EXPORT_SYMBOLS                  :: 0x89;
    DELETED                         :: 0x8a;
    DEFAULTED                       :: 0x8b;
    LOCLISTS_BASE                   :: 0x8c;

    // Vendor extensions:
    MIPS_LOOP_BEGIN                 :: 0x2002;
    MIPS_TAIL_LOOP_BEGIN            :: 0x2003;
    MIPS_EPILOG_BEGIN               :: 0x2004;
    MIPS_LOOP_UNROLL_FACTOR         :: 0x2005;
    MIPS_SOFTWARE_PIPELINE_DEPTH    :: 0x2006;
    MIPS_LINKAGE_NAME               :: 0x2007;
    MIPS_STRIDE                     :: 0x2008;
    MIPS_ABSTRACT_NAME              :: 0x2009;
    MIPS_CLONE_ORIGIN               :: 0x200a;
    MIPS_HAS_INLINES                :: 0x200b;
    MIPS_STRIDE_BYTE                :: 0x200c;
    MIPS_STRIDE_ELEM                :: 0x200d;
    MIPS_PTR_DOPETYPE               :: 0x200e;
    MIPS_ALLOCATABLE_DOPETYPE       :: 0x200f;
    MIPS_ASSUMED_SHAPE_DOPETYPE     :: 0x2010;

    // This one appears to have only been implemented by Open64 for
    // fortran and may conflict with other extensions.
    MIPS_ASSUMED_SIZE               :: 0x2011;

    // GNU extensions
    SF_NAMES                        :: 0x2101;
    SRC_INFO                        :: 0x2102;
    MAC_INFO                        :: 0x2103;
    SRC_COORDS                      :: 0x2104;
    BODY_BEGIN                      :: 0x2105;
    BODY_END                        :: 0x2106;
    GNU_VECTOR                      :: 0x2107;
    GNU_TEMPLATE_NAME               :: 0x2110;
    GNU_ODR_SIGNATURE               :: 0x210f;
    GNU_CALL_SITE_VALUE             :: 0x2111;
    GNU_CALL_SITE_DATA_VALUE        :: 0x2112;
    GNU_CALL_SITE_TARGET            :: 0x2113;
    GNU_CALL_SITE_TARGET_CLOBBERED  :: 0x2114;
    GNU_TAIL_CALL                   :: 0x2115;
    GNU_ALL_TAIL_CALL_SITES         :: 0x2116;
    GNU_ALL_CALL_SITES              :: 0x2117;
    GNU_ALL_SOURCE_CALL_SITES       :: 0x2118;
    GNU_MACROS                      :: 0x2119;

    // Extensions for Fission proposal.
    GNU_DWO_NAME                    :: 0x2130;
    GNU_DWO_ID                      :: 0x2131;
    GNU_RANGES_BASE                 :: 0x2132;
    GNU_ADDR_BASE                   :: 0x2133;
    GNU_PUBNAMES                    :: 0x2134;
    GNU_PUBTYPES                    :: 0x2135;
    GNU_DISCRIMINATOR               :: 0x2136;

    // Borland extensions.
    BORLAND_PROPERTY_READ           :: 0x3b11;
    BORLAND_PROPERTY_WRITE          :: 0x3b12;
    BORLAND_PROPERTY_IMPLEMENTS     :: 0x3b13;
    BORLAND_PROPERTY_INDEX          :: 0x3b14;
    BORLAND_PROPERTY_DEFAULT        :: 0x3b15;
    BORLAND_DELPHI_UNIT             :: 0x3b20;
    BORLAND_DELPHI_CLASS            :: 0x3b21;
    BORLAND_DELPHI_RECORD           :: 0x3b22;
    BORLAND_DELPHI_METACLASS        :: 0x3b23;
    BORLAND_DELPHI_CONSTRUCTOR      :: 0x3b24;
    BORLAND_DELPHI_DESTRUCTOR       :: 0x3b25;
    BORLAND_DELPHI_ANONYMOUS_METHOD :: 0x3b26;
    BORLAND_DELPHI_INTERFACE        :: 0x3b27;
    BORLAND_DELPHI_ABI              :: 0x3b28;
    BORLAND_DELPHI_RETURN           :: 0x3b29;
    BORLAND_DELPHI_FRAMEPTR         :: 0x3b30;
    BORLAND_CLOSURE                 :: 0x3b31;

    // LLVM project extensions.
    LLVM_INCLUDE_PATH               :: 0x3e00;
    LLVM_CONFIG_MACROS              :: 0x3e01;
    LLVM_ISYSROOT                   :: 0x3e02;
    LLVM_TAG_OFFSET                 :: 0x3e03;

    // Apple extensions.
    APPLE_OPTIMIZED                 :: 0x3fe1;
    APPLE_FLAGS                     :: 0x3fe2;
    APPLE_ISA                       :: 0x3fe3;
    APPLE_BLOCK                     :: 0x3fe4;
    APPLE_MAJOR_RUNTIME_VERS        :: 0x3fe5;
    APPLE_RUNTIME_CLASS             :: 0x3fe6;
    APPLE_OMIT_FRAME_PTR            :: 0x3fe7;
    APPLE_PROPERTY_NAME             :: 0x3fe8;
    APPLE_PROPERTY_GETTER           :: 0x3fe9;
    APPLE_PROPERTY_SETTER           :: 0x3fea;
    APPLE_PROPERTY_ATTRIBUTE        :: 0x3feb;
    APPLE_OBJC_COMPLETE_TYPE        :: 0x3fec;
    APPLE_PROPERTY                  :: 0x3fed;
    APPLE_SDK                       :: 0x3fef;
}

Dwarf_Attribute_Format :: enum {
    // Attribute form encodings.
    ADDR           :: 0x01;
    BLOCK2         :: 0x03;
    BLOCK4         :: 0x04;
    DATA2          :: 0x05;
    DATA4          :: 0x06;
    DATA8          :: 0x07;
    STRING         :: 0x08;
    BLOCK          :: 0x09;
    BLOCK1         :: 0x0a;
    DATA1          :: 0x0b;
    FLAG           :: 0x0c;
    SDATA          :: 0x0d;
    STRP           :: 0x0e;
    UDATA          :: 0x0f;
    REF_ADDR       :: 0x10;
    REF1           :: 0x11;
    REF2           :: 0x12;
    REF4           :: 0x13;
    REF8           :: 0x14;
    REF_UDATA      :: 0x15;
    INDIRECT       :: 0x16;

    // New in DWARF v4:
    SEC_OFFSET     :: 0x17;
    EXPRLOC        :: 0x18;
    FLAG_PRESENT   :: 0x19;

    // This was defined out of sequence.
    REF_SIG8       :: 0x20;

    // New in DWARF v5:
    STRX           :: 0x1a;
    ADDRX          :: 0x1b;
    REF_SUP4       :: 0x1c;
    STRP_SUP       :: 0x1d;
    DATA16         :: 0x1e;
    LINE_STRP      :: 0x1f;
    IMPLICIT_CONST :: 0x21;
    LOCLISTX       :: 0x22;
    RNGLISTX       :: 0x23;
    REF_SUP8       :: 0x24;
    STRX1          :: 0x25;
    STRX2          :: 0x26;
    STRX3          :: 0x27;
    STRX4          :: 0x28;
    ADDRX1         :: 0x29;
    ADDRX2         :: 0x2a;
    ADDRX3         :: 0x2b;
    ADDRX4         :: 0x2c;

    // Extensions for Fission proposal
    GNU_ADDR_INDEX :: 0x1f01;
    GNU_STR_INDEX  :: 0x1f02;

    // Alternate debug sections proposal (output of "dwz" tool).
    GNU_REF_ALT    :: 0x1f20;
    GNU_STRP_ALT   :: 0x1f21;
}

Dwarf_Tag :: enum {
    NULL                         :: 0x0000;
    ARRAY_TYPE                   :: 0x0001;
    CLASS_TYPE                   :: 0x0002;
    ENTRY_POINT                  :: 0x0003;
    ENUMERATION_TYPE             :: 0x0004;
    FORMAL_PARAMETER             :: 0x0005;
    IMPORTED_DECLARATION         :: 0x0008;
    LABEL                        :: 0x000a;
    LEXICAL_BLOCK                :: 0x000b;
    MEMBER                       :: 0x000d;
    POINTER_TYPE                 :: 0x000f;
    REFERENCE_TYPE               :: 0x0010;
    COMPILE_UNIT                 :: 0x0011;
    STRING_TYPE                  :: 0x0012;
    STRUCTURE_TYPE               :: 0x0013;
    SUBROUTINE_TYPE              :: 0x0015;
    TYPEDEF                      :: 0x0016;
    UNION_TYPE                   :: 0x0017;
    UNSPECIFIED_PARAMETERS       :: 0x0018;
    VARIANT                      :: 0x0019;
    COMMON_BLOCK                 :: 0x001a;
    COMMON_INCLUSION             :: 0x001b;
    INHERITANCE                  :: 0x001c;
    INLINED_SUBROUTINE           :: 0x001d;
    MODULE                       :: 0x001e;
    PTR_TO_MEMBER_TYPE           :: 0x001f;
    SET_TYPE                     :: 0x0020;
    SUBRANGE_TYPE                :: 0x0021;
    WITH_STMT                    :: 0x0022;
    ACCESS_DECLARATION           :: 0x0023;
    BASE_TYPE                    :: 0x0024;
    CATCH_BLOCK                  :: 0x0025;
    CONST_TYPE                   :: 0x0026;
    CONSTANT                     :: 0x0027;
    ENUMERATOR                   :: 0x0028;
    FILE_TYPE                    :: 0x0029;
    FRIEND                       :: 0x002a;
    NAMELIST                     :: 0x002b;
    NAMELIST_ITEM                :: 0x002c;
    PACKED_TYPE                  :: 0x002d;
    SUBPROGRAM                   :: 0x002e;
    TEMPLATE_TYPE_PARAMETER      :: 0x002f;
    TEMPLATE_VALUE_PARAMETER     :: 0x0030;
    THROWN_TYPE                  :: 0x0031;
    TRY_BLOCK                    :: 0x0032;
    VARIANT_PART                 :: 0x0033;
    VARIABLE                     :: 0x0034;
    VOLATILE_TYPE                :: 0x0035;

    // New in DWARF v3:
    DWARF_PROCEDURE              :: 0x0036;
    RESTRICT_TYPE                :: 0x0037;
    INTERFACE_TYPE               :: 0x0038;
    NAMESPACE                    :: 0x0039;
    IMPORTED_MODULE              :: 0x003a;
    UNSPECIFIED_TYPE             :: 0x003b;
    PARTIAL_UNIT                 :: 0x003c;
    IMPORTED_UNIT                :: 0x003d;
    CONDITION                    :: 0x003f;
    SHARED_TYPE                  :: 0x0040;

    // New in DWARF v4:
    TYPE_UNIT                    :: 0x0041;
    RVALUE_REFERENCE_TYPE        :: 0x0042;
    TEMPLATE_ALIAS               :: 0x0043;

    // New in DWARF v5:
    COARRAY_TYPE                 :: 0x0044;
    GENERIC_SUBRANGE             :: 0x0045;
    DYNAMIC_TYPE                 :: 0x0046;
    ATOMIC_TYPE                  :: 0x0047;
    CALL_SITE                    :: 0x0048;
    CALL_SITE_PARAMETER          :: 0x0049;
    SKELETON_UNIT                :: 0x004a;
    IMMUTABLE_TYPE               :: 0x004b;

    // Vendor extensions:
    MIPS_LOOP                    :: 0x4081;
    FORMAT_LABEL                 :: 0x4101;
    FUNCTION_TEMPLATE            :: 0x4102;
    CLASS_TEMPLATE               :: 0x4103;
    GNU_TEMPLATE_TEMPLATE_PARAM  :: 0x4106;
    GNU_TEMPLATE_PARAMETER_PACK  :: 0x4107;
    GNU_FORMAL_PARAMETER_PACK    :: 0x4108;
    GNU_CALL_SITE                :: 0x4109;
    GNU_CALL_SITE_PARAMETER      :: 0x410a;
    APPLE_PROPERTY               :: 0x4200;
    BORLAND_PROPERTY             :: 0xb000;
    BORLAND_DELPHI_STRING        :: 0xb001;
    BORLAND_DELPHI_DYNAMIC_ARRAY :: 0xb002;
    BORLAND_DELPHI_SET           :: 0xb003;
    BORLAND_DELPHI_VARIANT       :: 0xb004;
}

Dwarf_Base_Type :: enum {
    ADDRESS         :: 0x01;
    BOOLEAN         :: 0x02;
    COMPLEX_FLOAT   :: 0x03;
    FLOAT           :: 0x04;
    SIGNED          :: 0x05;
    SIGNED_CHAR     :: 0x06;
    UNSIGNED        :: 0x07;
    UNSIGNED_CHAR   :: 0x08;
    IMAGINARY_FLOAT :: 0x09;
    PACKED_DECIMAL  :: 0x0a;
    NUMERIC_STRING  :: 0x0b;
    EDITED          :: 0x0c;
    SIGNED_FIXED    :: 0x0d;
    UNSIGNED_FIXED  :: 0x0e;
    DECIMAL_FLOAT   :: 0x0f;
    UTF             :: 0x10;
    LO_USER         :: 0x80;
    HI_USER         :: 0xff;
}

Call_Frame_Address_Instruction_Type :: enum u8 {
    // High 2 bits:
    ADVANCE_LOC        :: 0x40;
    OFFSET             :: 0x80;
    RESTORE            :: 0xC0;

    // low 6 bits:
    NOP                :: 0x00;
    SET_LOC            :: 0x01;
    ADVANCE_LOC1       :: 0x02;
    ADVANCE_LOC2       :: 0x03;
    ADVANCE_LOC4       :: 0x04;
    OFFSET_EXTENDED    :: 0x05;
    RESTORE_EXTENDED   :: 0x06;
    UNDEFINED          :: 0x07;
    SAME_VALUE         :: 0x08;
    REGISTER           :: 0x09;
    REMEMBER_STATE     :: 0x0a;
    RESTORE_STATE      :: 0x0b;
    DEF_CFA            :: 0x0c;
    DEF_CFA_REGISTER   :: 0x0d;
    DEF_CFA_OFFSET     :: 0x0e;
    DEF_CFA_EXPRESSION :: 0x0f;
    OFFSET_EXTENDED_SF :: 0x10;
    DEF_CFA_SF         :: 0x11;
    DEF_CFA_OFFSET_SF  :: 0x12;
    VAL_OFFSET         :: 0x13;
    VAL_OFFSET_SF      :: 0x14;
    VAL_EXPRESSION     :: 0x15;
    LO_USER            :: 0x1b;
    HI_USER            :: 0x3e;
}

Dwarf_Registers_x64 :: enum u8 {
    RAX   :: 0;
    RDX   :: 1;
    RCX   :: 2;
    RBX   :: 3;
    RSI   :: 4;
    RDI   :: 5;
    RBP   :: 6;
    RSP   :: 7;
    R8    :: 8;
    R9    :: 9;
    R10   :: 10;
    R11   :: 11;
    R12   :: 12;
    R13   :: 13;
    R14   :: 14;
    R15   :: 15;

    RA    :: 16;

    XMM0  :: 17;
    XMM1  :: 18;
    XMM2  :: 19;
    XMM3  :: 20;
    XMM4  :: 21;
    XMM5  :: 22;
    XMM6  :: 23;
    XMM7  :: 24;

    XMM8  :: 25;
    XMM9  :: 26;
    XMM10 :: 27;
    XMM11 :: 28;
    XMM12 :: 29;
    XMM13 :: 30;
    XMM14 :: 31;
    XMM15 :: 32;

    // @Incomplete
}
