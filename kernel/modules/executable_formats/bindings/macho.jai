//
// This file was auto-generated using the following command:
//
// jai modules/executable_formats/generate_macho.jai
//
vm_prot_t :: s32;



CPU_STATE :: enum {
    MAX    :: 4;

    USER   :: 0;
    SYSTEM :: 1;
    IDLE   :: 2;
    NICE   :: 3;
}

CPU_ARCH :: enum {
    MASK     :: 0xff000000;
    ABI64    :: 0x01000000;
    ABI64_32 :: 0x02000000;
}

Cpu_Type :: enum s32 {
    ANY       :: -1;

    VAX       :: 1;

    MC680x0   :: 6;
    X86       :: 7;
    I386      :: X86;
    X86_64    :: X86 | xx CPU_ARCH.ABI64;

    MC98000   :: 10;
    HPPA      :: 11;
    ARM       :: 12;
    ARM64     :: ARM | xx CPU_ARCH.ABI64;
    ARM64_32  :: ARM | xx CPU_ARCH.ABI64_32;
    MC88000   :: 13;
    SPARC     :: 14;
    I860      :: 15;

    POWERPC   :: 18;
    POWERPC64 :: POWERPC | xx CPU_ARCH.ABI64;
}

Cpu_Subtype :: enum s32 {
    MASK                :: 0xff000000;
    LIB64               :: 0x80000000;
    PTRAUTH_ABI         :: 0x80000000;

    ANY                 :: -1;

    MULTIPLE            :: -1;
    LITTLE_ENDIAN       :: 0;
    BIG_ENDIAN          :: 1;

    VAX_ALL             :: 0;
    VAX780              :: 1;
    VAX785              :: 2;
    VAX750              :: 3;
    VAX730              :: 4;
    UVAXI               :: 5;
    UVAXII              :: 6;
    VAX8200             :: 7;
    VAX8500             :: 8;
    VAX8600             :: 9;
    VAX8650             :: 10;
    VAX8800             :: 11;
    UVAXIII             :: 12;

    MC680x0_ALL         :: 1;
    MC68030             :: 1;
    MC68040             :: 2;
    MC68030_ONLY        :: 3;

    INTEL_FAMILY_MAX    :: 15;

    INTEL_MODEL_ALL     :: 0;

    X86_ALL             :: 3;
    X86_64_ALL          :: 3;
    X86_ARCH1           :: 4;
    X86_64_H            :: 8;

    MIPS_ALL            :: 0;
    MIPS_R2300          :: 1;
    MIPS_R2600          :: 2;
    MIPS_R2800          :: 3;
    MIPS_R2000a         :: 4;
    MIPS_R2000          :: 5;
    MIPS_R3000a         :: 6;
    MIPS_R3000          :: 7;

    MC98000_ALL         :: 0;
    MC98601             :: 1;

    HPPA_ALL            :: 0;
    HPPA_7100           :: 0;
    HPPA_7100LC         :: 1;

    MC88000_ALL         :: 0;
    MC88100             :: 1;
    MC88110             :: 2;

    SPARC_ALL           :: 0;

    I860_ALL            :: 0;
    I860_860            :: 1;

    POWERPC_ALL         :: 0;
    POWERPC_601         :: 1;
    POWERPC_602         :: 2;
    POWERPC_603         :: 3;
    POWERPC_603e        :: 4;
    POWERPC_603ev       :: 5;
    POWERPC_604         :: 6;
    POWERPC_604e        :: 7;
    POWERPC_620         :: 8;
    POWERPC_750         :: 9;
    POWERPC_7400        :: 10;
    POWERPC_7450        :: 11;
    POWERPC_970         :: 100;

    ARM_ALL             :: 0;
    ARM_V4T             :: 5;
    ARM_V6              :: 6;
    ARM_V5TEJ           :: 7;
    ARM_XSCALE          :: 8;
    ARM_V7              :: 9;
    ARM_V7F             :: 10;
    ARM_V7S             :: 11;
    ARM_V7K             :: 12;
    ARM_V8              :: 13;
    ARM_V6M             :: 14;
    ARM_V7M             :: 15;
    ARM_V7EM            :: 16;
    ARM_V8M             :: 17;
    ARM_V8M_MAIN        :: ARM_V8M;
    ARM_V8M_BASE        :: 18;
    ARM_V8_1M_MAIN      :: 19;

    ARM64_ALL           :: 0;
    ARM64_V8            :: 1;
    ARM64E              :: 2;

    ARM64_PTR_AUTH_MASK :: 0x0f000000;

    ARM64_32_ALL        :: 0;
    ARM64_32_V8         :: 1;
}

CPU_THREADTYPE_NONE :: cast(cpu_threadtype_t) 0;

CPU_THREADTYPE_INTEL_HTT :: cast(cpu_threadtype_t) 1;

CPUFAMILY :: enum {
    UNKNOWN                :: 0;
    POWERPC_G3             :: 0xcee41549;
    POWERPC_G4             :: 0x77c184ae;
    POWERPC_G5             :: 0xed76d8aa;
    INTEL_6_13             :: 0xaa33392b;
    INTEL_PENRYN           :: 0x78ea4fbc;
    INTEL_NEHALEM          :: 0x6b5a4cd2;
    INTEL_WESTMERE         :: 0x573b5eec;
    INTEL_SANDYBRIDGE      :: 0x5490b78c;
    INTEL_IVYBRIDGE        :: 0x1f65e835;
    INTEL_HASWELL          :: 0x10b282dc;
    INTEL_BROADWELL        :: 0x582ed09c;
    INTEL_SKYLAKE          :: 0x37fc219f;
    INTEL_KABYLAKE         :: 0x0f817246;
    INTEL_ICELAKE          :: 0x38435547;
    INTEL_COMETLAKE        :: 0x1cf8a03e;
    ARM_9                  :: 0xe73283ae;
    ARM_11                 :: 0x8ff620d8;
    ARM_XSCALE             :: 0x53b005f5;
    ARM_12                 :: 0xbd1b0ae9;
    ARM_13                 :: 0x0cc90e64;
    ARM_14                 :: 0x96077ef1;
    ARM_15                 :: 0xa8511bca;
    ARM_SWIFT              :: 0x1e2d6381;
    ARM_CYCLONE            :: 0x37a09642;
    ARM_TYPHOON            :: 0x2c91a47e;
    ARM_TWISTER            :: 0x92fb37c8;
    ARM_HURRICANE          :: 0x67ceee93;
    ARM_MONSOON_MISTRAL    :: 0xe81e7ef6;
    ARM_VORTEX_TEMPEST     :: 0x07d34b9f;
    ARM_LIGHTNING_THUNDER  :: 0x462504d2;
    ARM_FIRESTORM_ICESTORM :: 0x1b588bb3;
    ARM_BLIZZARD_AVALANCHE :: 0xda33d83d;
    ARM_EVEREST_SAWTOOTH   :: 0x8765edea;
    ARM_IBIZA              :: 0xfa33415e;
    ARM_PALMA              :: 0x72015832;
    ARM_COLL               :: 0x2876f5b5;
    ARM_LOBOS              :: 0x5f4dea93;
    ARM_DONAN              :: 0x6f5129ac;
    ARM_BRAVA              :: 0x17d5b93a;
    ARM_TAHITI             :: 0x75d4acb9;
    ARM_TUPAI              :: 0x204526d0;
    ARM_HIDRA              :: 0x1d5a87e8;
    ARM_THERA              :: 0xab345f09;
    ARM_TILOS              :: 0x01d7a72b;

    INTEL_6_23             :: INTEL_PENRYN;
    INTEL_6_26             :: INTEL_NEHALEM;
}

CPUSUBFAMILY :: enum {
    UNKNOWN   :: 0;
    ARM_HP    :: 1;
    ARM_HG    :: 2;
    ARM_M     :: 3;
    ARM_HS    :: 4;
    ARM_HC_HD :: 5;
    ARM_HA    :: 6;
}

MH_MAGIC :: 0xfeedface;
MH_CIGAM :: 0xcefaedfe;

MH_MAGIC_64 :: 0xfeedfacf;
MH_CIGAM_64 :: 0xcffaedfe;

MH_OBJECT :: 0x1;
MH_EXECUTE :: 0x2;
MH_FVMLIB :: 0x3;
MH_CORE :: 0x4;
MH_PRELOAD :: 0x5;
MH_DYLIB :: 0x6;
MH_DYLINKER :: 0x7;
MH_BUNDLE :: 0x8;
MH_DYLIB_STUB :: 0x9;

MH_DSYM :: 0xa;

MH_KEXT_BUNDLE :: 0xb;
MH_FILESET :: 0xc;

MH_GPU_EXECUTE :: 0xd;
MH_GPU_DYLIB :: 0xe;

MH_NOUNDEFS :: 0x1;

MH_INCRLINK :: 0x2;

MH_DYLDLINK :: 0x4;

MH_BINDATLOAD :: 0x8;

MH_PREBOUND :: 0x10;

MH_SPLIT_SEGS :: 0x20;

MH_LAZY_INIT :: 0x40;

MH_TWOLEVEL :: 0x80;

MH_FORCE_FLAT :: 0x100;

MH_NOMULTIDEFS :: 0x200;

MH_NOFIXPREBINDING :: 0x400;

MH_PREBINDABLE :: 0x800;

MH_ALLMODSBOUND :: 0x1000;

MH_SUBSECTIONS_VIA_SYMBOLS :: 0x2000;

MH_CANONICAL :: 0x4000;

MH_WEAK_DEFINES :: 0x8000;

MH_BINDS_TO_WEAK :: 0x10000;

MH_ALLOW_STACK_EXECUTION :: 0x20000;

MH_ROOT_SAFE :: 0x40000;

MH_SETUID_SAFE :: 0x80000;

MH_NO_REEXPORTED_DYLIBS :: 0x100000;

MH_PIE :: 0x200000;

MH_DEAD_STRIPPABLE_DYLIB :: 0x400000;

MH_HAS_TLV_DESCRIPTORS :: 0x800000;

MH_NO_HEAP_EXECUTION :: 0x1000000;

MH_APP_EXTENSION_SAFE :: 0x02000000;

MH_NLIST_OUTOFSYNC_WITH_DYLDINFO :: 0x04000000;

MH_SIM_SUPPORT :: 0x08000000;

MH_IMPLICIT_PAGEZERO :: 0x10000000;

MH_DYLIB_IN_CACHE :: 0x80000000;

Load_Command_Type :: enum u32 {
    REQ_DYLD                 :: 0x80000000;
    SEGMENT                  :: 0x1;
    SYMTAB                   :: 0x2;
    SYMSEG                   :: 0x3;
    THREAD                   :: 0x4;
    UNIXTHREAD               :: 0x5;
    LOADFVMLIB               :: 0x6;
    IDFVMLIB                 :: 0x7;
    IDENT                    :: 0x8;
    FVMFILE                  :: 0x9;
    PREPAGE                  :: 0xa;
    DYSYMTAB                 :: 0xb;
    LOAD_DYLIB               :: 0xc;
    ID_DYLIB                 :: 0xd;
    LOAD_DYLINKER            :: 0xe;
    ID_DYLINKER              :: 0xf;
    PREBOUND_DYLIB           :: 0x10;
    ROUTINES                 :: 0x11;
    SUB_FRAMEWORK            :: 0x12;
    SUB_UMBRELLA             :: 0x13;
    SUB_CLIENT               :: 0x14;
    SUB_LIBRARY              :: 0x15;
    TWOLEVEL_HINTS           :: 0x16;
    PREBIND_CKSUM            :: 0x17;
    LOAD_WEAK_DYLIB          :: 0x18 | REQ_DYLD;
    SEGMENT_64               :: 0x19;
    ROUTINES_64              :: 0x1a;
    UUID                     :: 0x1b;
    RPATH                    :: 0x1c | REQ_DYLD;
    CODE_SIGNATURE           :: 0x1d;
    SEGMENT_SPLIT_INFO       :: 0x1e;
    REEXPORT_DYLIB           :: 0x1f | REQ_DYLD;
    LAZY_LOAD_DYLIB          :: 0x20;
    ENCRYPTION_INFO          :: 0x21;
    DYLD_INFO                :: 0x22;
    DYLD_INFO_ONLY           :: 0x22|REQ_DYLD;
    LOAD_UPWARD_DYLIB        :: 0x23 | REQ_DYLD;
    VERSION_MIN_MACOSX       :: 0x24;
    VERSION_MIN_IPHONEOS     :: 0x25;
    FUNCTION_STARTS          :: 0x26;
    DYLD_ENVIRONMENT         :: 0x27;
    MAIN                     :: 0x28|REQ_DYLD;
    DATA_IN_CODE             :: 0x29;
    SOURCE_VERSION           :: 0x2A;
    DYLIB_CODE_SIGN_DRS      :: 0x2B;
    ENCRYPTION_INFO_64       :: 0x2C;
    LINKER_OPTION            :: 0x2D;
    LINKER_OPTIMIZATION_HINT :: 0x2E;
    VERSION_MIN_TVOS         :: 0x2F;
    VERSION_MIN_WATCHOS      :: 0x30;
    NOTE                     :: 0x31;
    BUILD_VERSION            :: 0x32;
    DYLD_EXPORTS_TRIE        :: 0x33 | REQ_DYLD;
    DYLD_CHAINED_FIXUPS      :: 0x34 | REQ_DYLD;
    FILESET_ENTRY            :: 0x35 | REQ_DYLD;
    ATOM_INFO                :: 0x36;
    FUNCTION_VARIANTS        :: 0x37;
    FUNCTION_VARIANT_FIXUPS  :: 0x38;
    TARGET_TRIPLE            :: 0x39;
}

Segment_Flags :: enum_flags u32 {
    HIGHVM              :: 0x1;
    FVMLIB              :: 0x2;
    NORELOC             :: 0x4;
    PROTECTED_VERSION_1 :: 0x8;
    READ_ONLY           :: 0x10;
}

SECTION_TYPE :: 0x000000ff;
SECTION_ATTRIBUTES :: 0xffffff00;

Section_Flags :: enum_flags u32 {
    REGULAR                             :: 0x0;
    ZEROFILL                            :: 0x1;
    CSTRING_LITERALS                    :: 0x2;
    _4BYTE_LITERALS                     :: 0x3;
    _8BYTE_LITERALS                     :: 0x4;
    LITERAL_POINTERS                    :: 0x5;
    NON_LAZY_SYMBOL_POINTERS            :: 0x6;
    LAZY_SYMBOL_POINTERS                :: 0x7;
    SYMBOL_STUBS                        :: 0x8;
    MOD_INIT_FUNC_POINTERS              :: 0x9;
    MOD_TERM_FUNC_POINTERS              :: 0xa;
    COALESCED                           :: 0xb;
    GB_ZEROFILL                         :: 0xc;
    INTERPOSING                         :: 0xd;
    _16BYTE_LITERALS                    :: 0xe;
    DTRACE_DOF                          :: 0xf;
    LAZY_DYLIB_SYMBOL_POINTERS          :: 0x10;
    THREAD_LOCAL_REGULAR                :: 0x11;
    THREAD_LOCAL_ZEROFILL               :: 0x12;
    THREAD_LOCAL_VARIABLES              :: 0x13;
    THREAD_LOCAL_VARIABLE_POINTERS      :: 0x14;
    THREAD_LOCAL_INIT_FUNCTION_POINTERS :: 0x15;
    INIT_FUNC_OFFSETS                   :: 0x16;
    ATTR_PURE_INSTRUCTIONS              :: 0x80000000;
    ATTR_NO_TOC                         :: 0x40000000;
    ATTR_STRIP_STATIC_SYMS              :: 0x20000000;
    ATTR_NO_DEAD_STRIP                  :: 0x10000000;
    ATTR_LIVE_SUPPORT                   :: 0x08000000;
    ATTR_SELF_MODIFYING_CODE            :: 0x04000000;
    ATTR_DEBUG                          :: 0x02000000;
    ATTR_SOME_INSTRUCTIONS              :: 0x00000400;
    ATTR_EXT_RELOC                      :: 0x00000200;
    ATTR_LOC_RELOC                      :: 0x00000100;
}

SECTION_ATTRIBUTES_USR :: 0xff000000;

SECTION_ATTRIBUTES_SYS :: 0x00ffff00;

SEG_PAGEZERO :: "__PAGEZERO";

SEG_TEXT :: "__TEXT";
SECT_TEXT :: "__text";

SECT_FVMLIB_INIT0 :: "__fvmlib_init0";

SECT_FVMLIB_INIT1 :: "__fvmlib_init1";

SEG_DATA :: "__DATA";
SECT_DATA :: "__data";

SECT_BSS :: "__bss";

SECT_COMMON :: "__common";

SEG_OBJC :: "__OBJC";
SECT_OBJC_SYMBOLS :: "__symbol_table";
SECT_OBJC_MODULES :: "__module_info";
SECT_OBJC_STRINGS :: "__selector_strs";
SECT_OBJC_REFS :: "__selector_refs";

SEG_ICON :: "__ICON";
SECT_ICON_HEADER :: "__header";
SECT_ICON_TIFF :: "__tiff";

SEG_LINKEDIT :: "__LINKEDIT";

SEG_UNIXSTACK :: "__UNIXSTACK";

SEG_IMPORT :: "__IMPORT";

DYLIB_USE_WEAK_LINK :: 0x01;
DYLIB_USE_REEXPORT :: 0x02;
DYLIB_USE_UPWARD :: 0x04;
DYLIB_USE_DELAYED_INIT :: 0x08;

DYLIB_USE_MARKER :: 0x1a741800;

INDIRECT_SYMBOL_LOCAL :: 0x80000000;
INDIRECT_SYMBOL_ABS :: 0x40000000;

PLATFORM_UNKNOWN :: 0;
PLATFORM_ANY :: 0xFFFFFFFF;
PLATFORM_MACOS :: 1;
PLATFORM_IOS :: 2;
PLATFORM_TVOS :: 3;
PLATFORM_WATCHOS :: 4;
PLATFORM_BRIDGEOS :: 5;
PLATFORM_MACCATALYST :: 6;
PLATFORM_IOSSIMULATOR :: 7;
PLATFORM_TVOSSIMULATOR :: 8;
PLATFORM_WATCHOSSIMULATOR :: 9;
PLATFORM_DRIVERKIT :: 10;
PLATFORM_VISIONOS :: 11;
PLATFORM_VISIONOSSIMULATOR :: 12;

PLATFORM_FIRMWARE :: 13;
PLATFORM_SEPOS :: 14;

PLATFORM_MACOS_EXCLAVECORE :: 15;
PLATFORM_MACOS_EXCLAVEKIT :: 16;
PLATFORM_IOS_EXCLAVECORE :: 17;
PLATFORM_IOS_EXCLAVEKIT :: 18;
PLATFORM_TVOS_EXCLAVECORE :: 19;
PLATFORM_TVOS_EXCLAVEKIT :: 20;
PLATFORM_WATCHOS_EXCLAVECORE :: 21;
PLATFORM_WATCHOS_EXCLAVEKIT :: 22;
PLATFORM_VISIONOS_EXCLAVECORE :: 23;
PLATFORM_VISIONOS_EXCLAVEKIT :: 24;

TOOL_CLANG :: 1;
TOOL_SWIFT :: 2;
TOOL_LD :: 3;
TOOL_LLD :: 4;

TOOL_METAL :: 1024;
TOOL_AIRLLD :: 1025;
TOOL_AIRNT :: 1026;
TOOL_AIRNT_PLUGIN :: 1027;
TOOL_AIRPACK :: 1028;
TOOL_GPUARCHIVER :: 1031;
TOOL_METAL_FRAMEWORK :: 1032;

REBASE_TYPE_POINTER :: 1;
REBASE_TYPE_TEXT_ABSOLUTE32 :: 2;
REBASE_TYPE_TEXT_PCREL32 :: 3;

REBASE_OPCODE_MASK :: 0xF0;
REBASE_IMMEDIATE_MASK :: 0x0F;
REBASE_OPCODE_DONE :: 0x00;
REBASE_OPCODE_SET_TYPE_IMM :: 0x10;
REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB :: 0x20;
REBASE_OPCODE_ADD_ADDR_ULEB :: 0x30;
REBASE_OPCODE_ADD_ADDR_IMM_SCALED :: 0x40;
REBASE_OPCODE_DO_REBASE_IMM_TIMES :: 0x50;
REBASE_OPCODE_DO_REBASE_ULEB_TIMES :: 0x60;
REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB :: 0x70;
REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB :: 0x80;

BIND_TYPE_POINTER :: 1;
BIND_TYPE_TEXT_ABSOLUTE32 :: 2;
BIND_TYPE_TEXT_PCREL32 :: 3;

BIND_SPECIAL_DYLIB_SELF :: 0;
BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE :: -1;
BIND_SPECIAL_DYLIB_FLAT_LOOKUP :: -2;
BIND_SPECIAL_DYLIB_WEAK_LOOKUP :: -3;

BIND_SYMBOL_FLAGS_WEAK_IMPORT :: 0x1;
BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION :: 0x8;

BIND_OPCODE_MASK :: 0xF0;
BIND_IMMEDIATE_MASK :: 0x0F;
BIND_OPCODE_DONE :: 0x00;
BIND_OPCODE_SET_DYLIB_ORDINAL_IMM :: 0x10;
BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB :: 0x20;
BIND_OPCODE_SET_DYLIB_SPECIAL_IMM :: 0x30;
BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM :: 0x40;
BIND_OPCODE_SET_TYPE_IMM :: 0x50;
BIND_OPCODE_SET_ADDEND_SLEB :: 0x60;
BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB :: 0x70;
BIND_OPCODE_ADD_ADDR_ULEB :: 0x80;
BIND_OPCODE_DO_BIND :: 0x90;
BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB :: 0xA0;
BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED :: 0xB0;
BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB :: 0xC0;
BIND_OPCODE_THREADED :: 0xD0;
BIND_SUBOPCODE_THREADED_SET_BIND_ORDINAL_TABLE_SIZE_ULEB :: 0x00;
BIND_SUBOPCODE_THREADED_APPLY :: 0x01;

EXPORT_SYMBOL_FLAGS_KIND_MASK :: 0x03;
EXPORT_SYMBOL_FLAGS_KIND_REGULAR :: 0x00;
EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL :: 0x01;
EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE :: 0x02;
EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION :: 0x04;
EXPORT_SYMBOL_FLAGS_REEXPORT :: 0x08;
EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER :: 0x10;
EXPORT_SYMBOL_FLAGS_STATIC_RESOLVER :: 0x20;

DICE_KIND_DATA :: 0x0001;
DICE_KIND_JUMP_TABLE8 :: 0x0002;
DICE_KIND_JUMP_TABLE16 :: 0x0003;
DICE_KIND_JUMP_TABLE32 :: 0x0004;
DICE_KIND_ABS_JUMP_TABLE32 :: 0x0005;

R_ABS :: 0;

R_SCATTERED :: 0x80000000;

N_GSYM :: 0x20;
N_FNAME :: 0x22;
N_FUN :: 0x24;
N_STSYM :: 0x26;
N_LCSYM :: 0x28;
N_BNSYM :: 0x2e;
N_AST :: 0x32;
N_OPT :: 0x3c;
N_RSYM :: 0x40;
N_SLINE :: 0x44;
N_ENSYM :: 0x4e;
N_SSYM :: 0x60;
N_SO :: 0x64;
N_OSO :: 0x66;

N_LIB :: 0x68;
N_LSYM :: 0x80;
N_BINCL :: 0x82;
N_SOL :: 0x84;
N_PARAMS :: 0x86;
N_VERSION :: 0x88;
N_OLEVEL :: 0x8A;
N_PSYM :: 0xa0;
N_EINCL :: 0xa2;
N_ENTRY :: 0xa4;
N_LBRAC :: 0xc0;
N_EXCL :: 0xc2;
N_RBRAC :: 0xe0;
N_BCOMM :: 0xe2;
N_ECOMM :: 0xe4;
N_ECOML :: 0xe8;
N_LENG :: 0xfe;

N_PC :: 0x30;

N_STAB :: 0xe0;
N_PEXT :: 0x10;
N_TYPE :: 0x0e;
N_EXT :: 0x01;

N_UNDF :: 0x0;
N_ABS :: 0x2;
N_SECT :: 0xe;
N_PBUD :: 0xc;
N_INDR :: 0xa;

NO_SECT :: 0;
MAX_SECT :: 255;

REFERENCE_TYPE :: 0x7;

REFERENCE_FLAG_UNDEFINED_NON_LAZY :: 0;
REFERENCE_FLAG_UNDEFINED_LAZY :: 1;
REFERENCE_FLAG_DEFINED :: 2;
REFERENCE_FLAG_PRIVATE_DEFINED :: 3;
REFERENCE_FLAG_PRIVATE_UNDEFINED_NON_LAZY :: 4;
REFERENCE_FLAG_PRIVATE_UNDEFINED_LAZY :: 5;

REFERENCED_DYNAMICALLY :: 0x0010;

SELF_LIBRARY_ORDINAL :: 0x0;
MAX_LIBRARY_ORDINAL :: 0xfd;
DYNAMIC_LOOKUP_ORDINAL :: 0xfe;
EXECUTABLE_ORDINAL :: 0xff;

N_NO_DEAD_STRIP :: 0x0020;

N_DESC_DISCARDED :: 0x0020;

N_WEAK_REF :: 0x0040;

N_WEAK_DEF :: 0x0080;

N_REF_TO_WEAK :: 0x0080;

N_ARM_THUMB_DEF :: 0x0008;

N_SYMBOL_RESOLVER :: 0x0100;

N_ALT_ENTRY :: 0x0200;

N_COLD_FUNC :: 0x0400;

cpu_type_t :: s32;
cpu_subtype_t :: s32;
cpu_threadtype_t :: s32;

/*
* The 32-bit mach header appears at the very beginning of the object file for
* 32-bit architectures.
*/
mach_header :: struct {
    magic:      u32; /* mach magic number identifier */
    cputype:    s32; /* cpu specifier */
    cpusubtype: s32; /* machine specifier */
    filetype:   u32; /* type of file */
    ncmds:      u32; /* number of load commands */
    sizeofcmds: u32; /* the size of all the load commands */
    flags:      u32; /* flags */
}

/*
* The 64-bit mach header appears at the very beginning of object files for
* 64-bit architectures.
*/
mach_header_64 :: struct {
    magic:      u32; /* mach magic number identifier */
    cputype:    s32; /* cpu specifier */
    cpusubtype: s32; /* machine specifier */
    filetype:   u32; /* type of file */
    ncmds:      u32; /* number of load commands */
    sizeofcmds: u32; /* the size of all the load commands */
    flags:      u32; /* flags */
    reserved:   u32; /* reserved */
}

/*
* The load commands directly follow the mach_header.  The total size of all
* of the commands is given by the sizeofcmds field in the mach_header.  All
* load commands must have as their first two fields cmd and cmdsize.  The cmd
* field is filled in with a constant for that command type.  Each command type
* has a structure specifically for it.  The cmdsize field is the size in bytes
* of the particular load command structure plus anything that follows it that
* is a part of the load command (i.e. section structures, strings, etc.).  To
* advance to the next load command the cmdsize can be added to the offset or
* pointer of the current load command.  The cmdsize for 32-bit architectures
* MUST be a multiple of 4 bytes and for 64-bit architectures MUST be a multiple
* of 8 bytes (these are forever the maximum alignment of any load commands).
* The padded bytes must be zero.  All tables in the object file must also
* follow these rules so the file can be memory mapped.  Otherwise the pointers
* to these tables will not work well or at all on some machines.  With all
* padding zeroed like objects will compare byte for byte.
*/
load_command :: struct {
    cmd:     u32; /* type of load command */
    cmdsize: u32; /* total size of command in bytes */
}

/*
* A variable length string in a load command is represented by an lc_str
* union.  The strings are stored just after the load command structure and
* the offset is from the start of the load command structure.  The size
* of the string is reflected in the cmdsize field of the load command.
* Once again any padded bytes to bring the cmdsize field to a multiple
* of 4 bytes must be zero.
*/
lc_str :: union {
    offset: u32; /* offset to the string */
}

/*
* The segment load command indicates that a part of this file is to be
* mapped into the task's address space.  The size of this segment in memory,
* vmsize, maybe equal to or larger than the amount to map from this file,
* filesize.  The file is mapped starting at fileoff to the beginning of
* the segment in memory, vmaddr.  The rest of the memory of the segment,
* if any, is allocated zero fill on demand.  The segment's maximum virtual
* memory protection and initial virtual memory protection are specified
* by the maxprot and initprot fields.  If the segment has sections then the
* section structures directly follow the segment command and their size is
* reflected in cmdsize.
*/
segment_command :: struct {
    cmd:      u32; /* LC_SEGMENT */
    cmdsize:  u32; /* includes sizeof section structs */
    segname:  [16] u8; /* segment name */
    vmaddr:   u32; /* memory address of this segment */
    vmsize:   u32; /* memory size of this segment */
    fileoff:  u32; /* file offset of this segment */
    filesize: u32; /* amount to map from the file */
    maxprot:  s32; /* maximum VM protection */
    initprot: s32; /* initial VM protection */
    nsects:   u32; /* number of sections in segment */
    flags:    u32; /* flags */
}

/*
* The 64-bit segment load command indicates that a part of this file is to be
* mapped into a 64-bit task's address space.  If the 64-bit segment has
* sections then section_64 structures directly follow the 64-bit segment
* command and their size is reflected in cmdsize.
*/
segment_command_64 :: struct {
    cmd:      u32; /* LC_SEGMENT_64 */
    cmdsize:  u32; /* includes sizeof section_64 structs */
    segname:  [16] u8; /* segment name */
    vmaddr:   u64; /* memory address of this segment */
    vmsize:   u64; /* memory size of this segment */
    fileoff:  u64; /* file offset of this segment */
    filesize: u64; /* amount to map from the file */
    maxprot:  s32; /* maximum VM protection */
    initprot: s32; /* initial VM protection */
    nsects:   u32; /* number of sections in segment */
    flags:    u32; /* flags */
}

/*
* A segment is made up of zero or more sections.  Non-MH_OBJECT files have
* all of their segments with the proper sections in each, and padded to the
* specified segment alignment when produced by the link editor.  The first
* segment of a MH_EXECUTE and MH_FVMLIB format file contains the mach_header
* and load commands of the object file before its first section.  The zero
* fill sections are always last in their segment (in all formats).  This
* allows the zeroed segment padding to be mapped into memory where zero fill
* sections might be. The gigabyte zero fill sections, those with the section
* type S_GB_ZEROFILL, can only be in a segment with sections of this type.
* These segments are then placed after all other segments.
*
* The MH_OBJECT format has all of its sections in one segment for
* compactness.  There is no padding to a specified segment boundary and the
* mach_header and load commands are not part of the segment.
*
* Sections with the same section name, sectname, going into the same segment,
* segname, are combined by the link editor.  The resulting section is aligned
* to the maximum alignment of the combined sections and is the new section's
* alignment.  The combined sections are aligned to their original alignment in
* the combined section.  Any padded bytes to get the specified alignment are
* zeroed.
*
* The format of the relocation entries referenced by the reloff and nreloc
* fields of the section structure for mach object files is described in the
* header file <reloc.h>.
*/
section :: struct {
    sectname:  [16] u8; /* name of this section */
    segname:   [16] u8; /* segment this section goes in */
    addr:      u32; /* memory address of this section */
    size:      u32; /* size in bytes of this section */
    offset:    u32; /* file offset of this section */
    align:     u32; /* section alignment (power of 2) */
    reloff:    u32; /* file offset of relocation entries */
    nreloc:    u32; /* number of relocation entries */
    flags:     u32; /* flags (section type and attributes)*/
    reserved1: u32; /* reserved (for offset or index) */
    reserved2: u32; /* reserved (for count or sizeof) */
}

section_64 :: struct {
    sectname:  [16] u8; /* name of this section */
    segname:   [16] u8; /* segment this section goes in */
    addr:      u64; /* memory address of this section */
    size:      u64; /* size in bytes of this section */
    offset:    u32; /* file offset of this section */
    align:     u32; /* section alignment (power of 2) */
    reloff:    u32; /* file offset of relocation entries */
    nreloc:    u32; /* number of relocation entries */
    flags:     u32; /* flags (section type and attributes)*/
    reserved1: u32; /* reserved (for offset or index) */
    reserved2: u32; /* reserved (for count or sizeof) */
    reserved3: u32; /* reserved */
}

/*
* Fixed virtual memory shared libraries are identified by two things.  The
* target pathname (the name of the library as found for execution), and the
* minor version number.  The address of where the headers are loaded is in
* header_addr. (THIS IS OBSOLETE and no longer supported).
*/
fvmlib :: struct {
    name:          lc_str; /* library's target pathname */
    minor_version: u32; /* library's minor version number */
    header_addr:   u32; /* library's header address */
}

/*
* A fixed virtual shared library (filetype == MH_FVMLIB in the mach header)
* contains a fvmlib_command (cmd == LC_IDFVMLIB) to identify the library.
* An object that uses a fixed virtual shared library also contains a
* fvmlib_command (cmd == LC_LOADFVMLIB) for each library it uses.
* (THIS IS OBSOLETE and no longer supported).
*/
fvmlib_command :: struct {
    cmd:     u32; /* LC_IDFVMLIB or LC_LOADFVMLIB */
    cmdsize: u32; /* includes pathname string */
    fvmlib_: fvmlib; /* the library identification */
}

/*
* Dynamically linked shared libraries are identified by two things.  The
* pathname (the name of the library as found for execution), and the
* compatibility version number.  The pathname must match and the compatibility
* number in the user of the library must be greater than or equal to the
* library being used.  The time stamp is used to record the time a library was
* built and copied into user so it can be use to determined if the library used
* at runtime is exactly the same as used to built the program.
*/
dylib :: struct {
    name:                  lc_str; /* library's path name */
    timestamp:             u32; /* library's build time stamp */
    current_version:       u32; /* library's current version number */
    compatibility_version: u32; /* library's compatibility vers number*/
}

/*
* A dynamically linked shared library (filetype == MH_DYLIB in the mach header)
* contains a dylib_command (cmd == LC_ID_DYLIB) to identify the library.
* An object that uses a dynamically linked shared library also contains a
* dylib_command (cmd == LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, or
* LC_REEXPORT_DYLIB) for each library it uses.
*/
dylib_command :: struct {
    /* LC_ID_DYLIB, LC_LOAD_{,WEAK_}DYLIB,
    LC_REEXPORT_DYLIB */
    cmd:     u32;

    cmdsize: u32; /* includes pathname string */
    dylib_:  dylib; /* the library identification */
}

/*
* An alternate encoding for: LC_LOAD_DYLIB.
* The flags field contains independent flags DYLIB_USE_*
* First supported in macOS 15, iOS 18.
*/
dylib_use_command :: struct {
    cmd:             u32; /* LC_LOAD_DYLIB or LC_LOAD_WEAK_DYLIB */
    cmdsize:         u32; /* overall size, including path */
    nameoff:         u32; /* == 28, dylibs's path offset */
    marker:          u32; /* == DYLIB_USE_MARKER */
    current_version: u32; /* dylib's current version number */
    compat_version:  u32; /* dylib's compatibility version number */
    flags:           u32; /* DYLIB_USE_... flags */
}

/*
* A dynamically linked shared library may be a subframework of an umbrella
* framework.  If so it will be linked with "-umbrella umbrella_name" where
* Where "umbrella_name" is the name of the umbrella framework. A subframework
* can only be linked against by its umbrella framework or other subframeworks
* that are part of the same umbrella framework.  Otherwise the static link
* editor produces an error and states to link against the umbrella framework.
* The name of the umbrella framework for subframeworks is recorded in the
* following structure.
*/
sub_framework_command :: struct {
    cmd:      u32; /* LC_SUB_FRAMEWORK */
    cmdsize:  u32; /* includes umbrella string */
    umbrella: lc_str; /* the umbrella framework name */
}

/*
* For dynamically linked shared libraries that are subframework of an umbrella
* framework they can allow clients other than the umbrella framework or other
* subframeworks in the same umbrella framework.  To do this the subframework
* is built with "-allowable_client client_name" and an LC_SUB_CLIENT load
* command is created for each -allowable_client flag.  The client_name is
* usually a framework name.  It can also be a name used for bundles clients
* where the bundle is built with "-client_name client_name".
*/
sub_client_command :: struct {
    cmd:     u32; /* LC_SUB_CLIENT */
    cmdsize: u32; /* includes client string */
    client:  lc_str; /* the client name */
}

/*
* A dynamically linked shared library may be a sub_umbrella of an umbrella
* framework.  If so it will be linked with "-sub_umbrella umbrella_name" where
* Where "umbrella_name" is the name of the sub_umbrella framework.  When
* staticly linking when -twolevel_namespace is in effect a twolevel namespace
* umbrella framework will only cause its subframeworks and those frameworks
* listed as sub_umbrella frameworks to be implicited linked in.  Any other
* dependent dynamic libraries will not be linked it when -twolevel_namespace
* is in effect.  The primary library recorded by the static linker when
* resolving a symbol in these libraries will be the umbrella framework.
* Zero or more sub_umbrella frameworks may be use by an umbrella framework.
* The name of a sub_umbrella framework is recorded in the following structure.
*/
sub_umbrella_command :: struct {
    cmd:          u32; /* LC_SUB_UMBRELLA */
    cmdsize:      u32; /* includes sub_umbrella string */
    sub_umbrella: lc_str; /* the sub_umbrella framework name */
}

/*
* A dynamically linked shared library may be a sub_library of another shared
* library.  If so it will be linked with "-sub_library library_name" where
* Where "library_name" is the name of the sub_library shared library.  When
* staticly linking when -twolevel_namespace is in effect a twolevel namespace
* shared library will only cause its subframeworks and those frameworks
* listed as sub_umbrella frameworks and libraries listed as sub_libraries to
* be implicited linked in.  Any other dependent dynamic libraries will not be
* linked it when -twolevel_namespace is in effect.  The primary library
* recorded by the static linker when resolving a symbol in these libraries
* will be the umbrella framework (or dynamic library). Zero or more sub_library
* shared libraries may be use by an umbrella framework or (or dynamic library).
* The name of a sub_library framework is recorded in the following structure.
* For example /usr/lib/libobjc_profile.A.dylib would be recorded as "libobjc".
*/
sub_library_command :: struct {
    cmd:         u32; /* LC_SUB_LIBRARY */
    cmdsize:     u32; /* includes sub_library string */
    sub_library: lc_str; /* the sub_library name */
}

/*
* A program (filetype == MH_EXECUTE) that is
* prebound to its dynamic libraries has one of these for each library that
* the static linker used in prebinding.  It contains a bit vector for the
* modules in the library.  The bits indicate which modules are bound (1) and
* which are not (0) from the library.  The bit for module 0 is the low bit
* of the first byte.  So the bit for the Nth module is:
* (linked_modules[N/8] >> N%8) & 1
*/
prebound_dylib_command :: struct {
    cmd:            u32; /* LC_PREBOUND_DYLIB */
    cmdsize:        u32; /* includes strings */
    name:           lc_str; /* library's path name */
    nmodules:       u32; /* number of modules in library */
    linked_modules: lc_str; /* bit vector of linked modules */
}

/*
* A program that uses a dynamic linker contains a dylinker_command to identify
* the name of the dynamic linker (LC_LOAD_DYLINKER).  And a dynamic linker
* contains a dylinker_command to identify the dynamic linker (LC_ID_DYLINKER).
* A file can have at most one of these.
* This struct is also used for the LC_DYLD_ENVIRONMENT load command and
* contains string for dyld to treat like environment variable.
*/
dylinker_command :: struct {
    /* LC_ID_DYLINKER, LC_LOAD_DYLINKER or
    LC_DYLD_ENVIRONMENT */
    cmd:     u32;

    cmdsize: u32; /* includes pathname string */
    name:    lc_str; /* dynamic linker's path name */
}

/*
* Thread commands contain machine-specific data structures suitable for
* use in the thread state primitives.  The machine specific data structures
* follow the struct thread_command as follows.
* Each flavor of machine specific data structure is preceded by an uint32_t
* constant for the flavor of that data structure, an uint32_t that is the
* count of uint32_t's of the size of the state data structure and then
* the state data structure follows.  This triple may be repeated for many
* flavors.  The constants for the flavors, counts and state data structure
* definitions are expected to be in the header file <machine/thread_status.h>.
* These machine specific data structures sizes must be multiples of
* 4 bytes.  The cmdsize reflects the total size of the thread_command
* and all of the sizes of the constants for the flavors, counts and state
* data structures.
*
* For executable objects that are unix processes there will be one
* thread_command (cmd == LC_UNIXTHREAD) created for it by the link-editor.
* This is the same as a LC_THREAD, except that a stack is automatically
* created (based on the shell's limit for the stack size).  Command arguments
* and environment variables are copied onto that stack.
*/
thread_command :: struct {
    cmd:     u32; /* LC_THREAD or  LC_UNIXTHREAD */
    cmdsize: u32; /* total size of this command */
}

/*
* The routines command contains the address of the dynamic shared library
* initialization routine and an index into the module table for the module
* that defines the routine.  Before any modules are used from the library the
* dynamic linker fully binds the module that defines the initialization routine
* and then calls it.  This gets called before any module initialization
* routines (used for C++ static constructors) in the library.
*/
routines_command :: struct {
    cmd:          u32; /* LC_ROUTINES */
    cmdsize:      u32; /* total size of this command */
    init_address: u32; /* address of initialization routine */
    init_module:  u32; /* index into the module table that */

    /*  the init routine is defined in */
    reserved1:    u32;
    reserved2:    u32;
    reserved3:    u32;
    reserved4:    u32;
    reserved5:    u32;
    reserved6:    u32;
}

/*
* The 64-bit routines command.  Same use as above.
*/
routines_command_64 :: struct {
    cmd:          u32; /* LC_ROUTINES_64 */
    cmdsize:      u32; /* total size of this command */
    init_address: u64; /* address of initialization routine */
    init_module:  u64; /* index into the module table that */

    /*  the init routine is defined in */
    reserved1:    u64;
    reserved2:    u64;
    reserved3:    u64;
    reserved4:    u64;
    reserved5:    u64;
    reserved6:    u64;
}

/*
* The symtab_command contains the offsets and sizes of the link-edit 4.3BSD
* "stab" style symbol table information as described in the header files
* <nlist.h> and <stab.h>.
*/
symtab_command :: struct {
    cmd:     u32; /* LC_SYMTAB */
    cmdsize: u32; /* sizeof(struct symtab_command) */
    symoff:  u32; /* symbol table offset */
    nsyms:   u32; /* number of symbol table entries */
    stroff:  u32; /* string table offset */
    strsize: u32; /* string table size in bytes */
}

/*
* This is the second set of the symbolic information which is used to support
* the data structures for the dynamically link editor.
*
* The original set of symbolic information in the symtab_command which contains
* the symbol and string tables must also be present when this load command is
* present.  When this load command is present the symbol table is organized
* into three groups of symbols:
*	local symbols (static and debugging symbols) - grouped by module
*	defined external symbols - grouped by module (sorted by name if not lib)
*	undefined external symbols (sorted by name if MH_BINDATLOAD is not set,
*	     			    and in order the were seen by the static
*				    linker if MH_BINDATLOAD is set)
* In this load command there are offsets and counts to each of the three groups
* of symbols.
*
* This load command contains a the offsets and sizes of the following new
* symbolic information tables:
*	table of contents
*	module table
*	reference symbol table
*	indirect symbol table
* The first three tables above (the table of contents, module table and
* reference symbol table) are only present if the file is a dynamically linked
* shared library.  For executable and object modules, which are files
* containing only one module, the information that would be in these three
* tables is determined as follows:
* 	table of contents - the defined external symbols are sorted by name
*	module table - the file contains only one module so everything in the
*		       file is part of the module.
*	reference symbol table - is the defined and undefined external symbols
*
* For dynamically linked shared library files this load command also contains
* offsets and sizes to the pool of relocation entries for all sections
* separated into two groups:
*	external relocation entries
*	local relocation entries
* For executable and object modules the relocation entries continue to hang
* off the section structures.
*/
dysymtab_command :: struct {
    cmd:            u32; /* LC_DYSYMTAB */
    cmdsize:        u32; /* sizeof(struct dysymtab_command) */

    ilocalsym:      u32; /* index to local symbols */
    nlocalsym:      u32; /* number of local symbols */

    iextdefsym:     u32; /* index to externally defined symbols */
    nextdefsym:     u32; /* number of externally defined symbols */

    iundefsym:      u32; /* index to undefined symbols */
    nundefsym:      u32; /* number of undefined symbols */

    tocoff:         u32; /* file offset to table of contents */
    ntoc:           u32; /* number of entries in table of contents */

    modtaboff:      u32; /* file offset to module table */
    nmodtab:        u32; /* number of module table entries */

    extrefsymoff:   u32; /* offset to referenced symbol table */
    nextrefsyms:    u32; /* number of referenced symbol table entries */

    indirectsymoff: u32; /* file offset to the indirect symbol table */
    nindirectsyms:  u32; /* number of indirect symbol table entries */

    extreloff:      u32; /* offset to external relocation entries */
    nextrel:        u32; /* number of external relocation entries */

    locreloff:      u32; /* offset to local relocation entries */
    nlocrel:        u32; /* number of local relocation entries */
}

/* a table of contents entry */
dylib_table_of_contents :: struct {
    /* the defined external symbol
    (index into the symbol table) */
    symbol_index: u32;

    /* index into the module table this symbol
    is defined in */
    module_index: u32;
}

/* a module table entry */
dylib_module :: struct {
    module_name:           u32; /* the module name (index into string table) */

    iextdefsym:            u32; /* index into externally defined symbols */
    nextdefsym:            u32; /* number of externally defined symbols */
    irefsym:               u32; /* index into reference symbol table */
    nrefsym:               u32; /* number of reference symbol table entries */
    ilocalsym:             u32; /* index into symbols for local symbols */
    nlocalsym:             u32; /* number of local symbols */

    iextrel:               u32; /* index into external relocation entries */
    nextrel:               u32; /* number of external relocation entries */

    /* low 16 bits are the index into the init
    section, high 16 bits are the index into
    the term section */
    iinit_iterm:           u32;

    /* low 16 bits are the number of init section
    entries, high 16 bits are the number of
    term section entries */
    ninit_nterm:           u32;

    objc_module_info_addr: u32; /*  the (__OBJC,__module_info) section */

    objc_module_info_size: u32; /*  the (__OBJC,__module_info) section */
}

/* a 64-bit module table entry */
dylib_module_64 :: struct {
    module_name:           u32; /* the module name (index into string table) */

    iextdefsym:            u32; /* index into externally defined symbols */
    nextdefsym:            u32; /* number of externally defined symbols */
    irefsym:               u32; /* index into reference symbol table */
    nrefsym:               u32; /* number of reference symbol table entries */
    ilocalsym:             u32; /* index into symbols for local symbols */
    nlocalsym:             u32; /* number of local symbols */

    iextrel:               u32; /* index into external relocation entries */
    nextrel:               u32; /* number of external relocation entries */

    /* low 16 bits are the index into the init
    section, high 16 bits are the index into
    the term section */
    iinit_iterm:           u32;

    /* low 16 bits are the number of init section
    entries, high 16 bits are the number of
    term section entries */
    ninit_nterm:           u32;

    objc_module_info_size: u32; /*  the (__OBJC,__module_info) section */

    objc_module_info_addr: u64; /*  the (__OBJC,__module_info) section */
}

/*
* The entries in the reference symbol table are used when loading the module
* (both by the static and dynamic link editors) and if the module is unloaded
* or replaced.  Therefore all external symbols (defined and undefined) are
* listed in the module's reference table.  The flags describe the type of
* reference that is being made.  The constants for the flags are defined in
* <mach-o/nlist.h> as they are also used for symbol table entries.
*/
dylib_reference :: struct {
    __bitfield: u32;
    /* 
        isym: u32; /* 24 bits */ /* index into the symbol table */
        flags: u32; /* 8 bits */ /* flags to indicate the type of reference */;
    */
}

/*
* The twolevel_hints_command contains the offset and number of hints in the
* two-level namespace lookup hints table.
*/
twolevel_hints_command :: struct {
    cmd:     u32; /* LC_TWOLEVEL_HINTS */
    cmdsize: u32; /* sizeof(struct twolevel_hints_command) */
    offset:  u32; /* offset to the hint table */
    nhints:  u32; /* number of hints in the hint table */
}

/*
* The entries in the two-level namespace lookup hints table are twolevel_hint
* structs.  These provide hints to the dynamic link editor where to start
* looking for an undefined symbol in a two-level namespace image.  The
* isub_image field is an index into the sub-images (sub-frameworks and
* sub-umbrellas list) that made up the two-level image that the undefined
* symbol was found in when it was built by the static link editor.  If
* isub-image is 0 the the symbol is expected to be defined in library and not
* in the sub-images.  If isub-image is non-zero it is an index into the array
* of sub-images for the umbrella with the first index in the sub-images being
* 1. The array of sub-images is the ordered list of sub-images of the umbrella
* that would be searched for a symbol that has the umbrella recorded as its
* primary library.  The table of contents index is an index into the
* library's table of contents.  This is used as the starting point of the
* binary search or a directed linear search.
*/
twolevel_hint :: struct {
    __bitfield: u32;
    /* 
        isub_image: u32; /* 8 bits */ /* index into the sub images */
        itoc: u32; /* 24 bits */ /* index into the table of contents */;
    */
}

/*
* The prebind_cksum_command contains the value of the original check sum for
* prebound files or zero.  When a prebound file is first created or modified
* for other than updating its prebinding information the value of the check sum
* is set to zero.  When the file has it prebinding re-done and if the value of
* the check sum is zero the original check sum is calculated and stored in
* cksum field of this load command in the output file.  If when the prebinding
* is re-done and the cksum field is non-zero it is left unchanged from the
* input file.
*/
prebind_cksum_command :: struct {
    cmd:     u32; /* LC_PREBIND_CKSUM */
    cmdsize: u32; /* sizeof(struct prebind_cksum_command) */
    cksum:   u32; /* the check sum or zero */
}

/*
* The uuid load command contains a single 128-bit unique random number that
* identifies an object produced by the static link editor.
*/
uuid_command :: struct {
    cmd:     u32; /* LC_UUID */
    cmdsize: u32; /* sizeof(struct uuid_command) */
    uuid:    [16] u8; /* the 128-bit uuid */
}

/*
* The rpath_command contains a path which at runtime should be added to
* the current run path used to find @rpath prefixed dylibs.
*/
rpath_command :: struct {
    cmd:     u32; /* LC_RPATH */
    cmdsize: u32; /* includes string */
    path:    lc_str; /* path to add to run path */
}

/*
* The target_triple_command contains a string which specifies the
* target triple (e.g. "arm64e-apple-macosx15.0.0") used to compile the code.
*/
target_triple_command :: struct {
    cmd:     u32; /* LC_TARGET_TRIPLE */
    cmdsize: u32; /* including string */
    triple:  lc_str; /* target triple string */
}

/*
* The linkedit_data_command contains the offsets and sizes of a blob
* of data in the __LINKEDIT segment.
*/
linkedit_data_command :: struct {
    /* LC_CODE_SIGNATURE, LC_SEGMENT_SPLIT_INFO,
    LC_FUNCTION_STARTS, LC_DATA_IN_CODE,
    LC_DYLIB_CODE_SIGN_DRS, LC_ATOM_INFO,
    LC_LINKER_OPTIMIZATION_HINT,
    LC_DYLD_EXPORTS_TRIE,
    LC_FUNCTION_VARIANTS, LC_FUNCTION_VARIANT_FIXUPS, or
    LC_DYLD_CHAINED_FIXUPS. */
    cmd:      u32;

    cmdsize:  u32; /* sizeof(struct linkedit_data_command) */
    dataoff:  u32; /* file offset of data in __LINKEDIT segment */
    datasize: u32; /* file size of data in __LINKEDIT segment  */
}

/*
* The encryption_info_command contains the file offset and size of an
* of an encrypted segment.
*/
encryption_info_command :: struct {
    cmd:       u32; /* LC_ENCRYPTION_INFO */
    cmdsize:   u32; /* sizeof(struct encryption_info_command) */
    cryptoff:  u32; /* file offset of encrypted range */
    cryptsize: u32; /* file size of encrypted range */
    /* which enryption system,
    0 means not-encrypted yet */
    cryptid:   u32;
}

/*
* The encryption_info_command_64 contains the file offset and size of an
* of an encrypted segment (for use in x86_64 targets).
*/
encryption_info_command_64 :: struct {
    cmd:       u32; /* LC_ENCRYPTION_INFO_64 */
    cmdsize:   u32; /* sizeof(struct encryption_info_command_64) */
    cryptoff:  u32; /* file offset of encrypted range */
    cryptsize: u32; /* file size of encrypted range */
    /* which enryption system,
    0 means not-encrypted yet */
    cryptid:   u32;

    /* padding to make this struct's size a multiple
    of 8 bytes */
    pad:       u32;
}

/*
* The version_min_command contains the min OS version on which this
* binary was built to run.
*/
version_min_command :: struct {
    /* LC_VERSION_MIN_MACOSX or
    LC_VERSION_MIN_IPHONEOS or
    LC_VERSION_MIN_WATCHOS or
    LC_VERSION_MIN_TVOS */
    cmd:     u32;

    cmdsize: u32; /* sizeof(struct min_version_command) */
    version: u32; /* X.Y.Z is encoded in nibbles xxxx.yy.zz */
    sdk:     u32; /* X.Y.Z is encoded in nibbles xxxx.yy.zz */
}

/*
* The build_version_command contains the min OS version on which this
* binary was built to run for its platform.  The list of known platforms and
* tool values following it.
*/
build_version_command :: struct {
    cmd:      u32; /* LC_BUILD_VERSION */
    cmdsize:  u32; /* sizeof(struct build_version_command) plus */

    platform: u32; /* platform */
    minos:    u32; /* X.Y.Z is encoded in nibbles xxxx.yy.zz */
    sdk:      u32; /* X.Y.Z is encoded in nibbles xxxx.yy.zz */
    ntools:   u32; /* number of tool entries following this */
}

build_tool_version :: struct {
    tool:    u32; /* enum for the tool */
    version: u32; /* version number of the tool */
}

/*
* The dyld_info_command contains the file offsets and sizes of
* the new compressed form of the information dyld needs to
* load the image.  This information is used by dyld on Mac OS X
* 10.6 and later.  All information pointed to by this command
* is encoded using byte streams, so no endian swapping is needed
* to interpret it.
*/
dyld_info_command :: struct {
    cmd:            u32; /* LC_DYLD_INFO or LC_DYLD_INFO_ONLY */
    cmdsize:        u32; /* sizeof(struct dyld_info_command) */

    rebase_off:     u32; /* file offset to rebase info  */
    rebase_size:    u32; /* size of rebase info   */

    bind_off:       u32; /* file offset to binding info   */
    bind_size:      u32; /* size of binding info  */

    weak_bind_off:  u32; /* file offset to weak binding info   */
    weak_bind_size: u32; /* size of weak binding info  */

    lazy_bind_off:  u32; /* file offset to lazy binding info */
    lazy_bind_size: u32; /* size of lazy binding infs */

    export_off:     u32; /* file offset to lazy binding info */
    export_size:    u32; /* size of lazy binding infs */
}

/*
* The linker_option_command contains linker options embedded in object files.
*/
linker_option_command :: struct {
    cmd:     u32; /* LC_LINKER_OPTION only used in MH_OBJECT filetypes */
    cmdsize: u32;
    count:   u32; /* number of strings */
}

/*
* The symseg_command contains the offset and size of the GNU style
* symbol table information as described in the header file <symseg.h>.
* The symbol roots of the symbol segments must also be aligned properly
* in the file.  So the requirement of keeping the offsets aligned to a
* multiple of a 4 bytes translates to the length field of the symbol
* roots also being a multiple of a long.  Also the padding must again be
* zeroed. (THIS IS OBSOLETE and no longer supported).
*/
symseg_command :: struct {
    cmd:     u32; /* LC_SYMSEG */
    cmdsize: u32; /* sizeof(struct symseg_command) */
    offset:  u32; /* symbol segment offset */
    size:    u32; /* symbol segment size in bytes */
}

/*
* The ident_command contains a free format string table following the
* ident_command structure.  The strings are null terminated and the size of
* the command is padded out with zero bytes to a multiple of 4 bytes/
* (THIS IS OBSOLETE and no longer supported).
*/
ident_command :: struct {
    cmd:     u32; /* LC_IDENT */
    cmdsize: u32; /* strings that follow this command */
}

/*
* The fvmfile_command contains a reference to a file to be loaded at the
* specified virtual address.  (Presently, this command is reserved for
* internal use.  The kernel ignores this command when loading a program into
* memory).
*/
fvmfile_command :: struct {
    cmd:         u32; /* LC_FVMFILE */
    cmdsize:     u32; /* includes pathname string */
    name:        lc_str; /* files pathname */
    header_addr: u32; /* files virtual address */
}

/*
* The entry_point_command is a replacement for thread_command.
* It is used for main executables to specify the location (file offset)
* of main().  If -stack_size was used at link time, the stacksize
* field will contain the stack size need for the main thread.
*/
entry_point_command :: struct {
    cmd:       u32; /* LC_MAIN only used in MH_EXECUTE filetypes */
    cmdsize:   u32; /* 24 */
    entryoff:  u64; /* file (__TEXT) offset of main() */
    stacksize: u64; /* if not zero, initial stack size */
}

/*
* The source_version_command is an optional load command containing
* the version of the sources used to build the binary.
*/
source_version_command :: struct {
    cmd:     u32; /* LC_SOURCE_VERSION */
    cmdsize: u32; /* 16 */
    version: u64; /* A.B.C.D.E packed as a24.b10.c10.d10.e10 */
}

/*
* The LC_DATA_IN_CODE load commands uses a linkedit_data_command
* to point to an array of data_in_code_entry entries. Each entry
* describes a range of data in a code section.
*/
data_in_code_entry :: struct {
    offset: u32; /* from mach_header to start of data range*/
    length: u16; /* number of bytes in data range */
    kind:   u16; /* a DICE_KIND_* value  */
}

/*
* Sections of type S_THREAD_LOCAL_VARIABLES contain an array
* of tlv_descriptor structures.
*/
tlv_descriptor :: struct {
    thunk:  #type (unknown0: *tlv_descriptor) -> *void #c_call;
    key:    u64;
    offset: u64;
}

/*
* LC_NOTE commands describe a region of arbitrary data included in a Mach-O
* file.  Its initial use is to record extra data in MH_CORE files.
*/
note_command :: struct {
    cmd:        u32; /* LC_NOTE */
    cmdsize:    u32; /* sizeof(struct note_command) */
    data_owner: [16] u8; /* owner name for this LC_NOTE */
    offset:     u64; /* file offset of this data */
    size:       u64; /* length of data region */
}

/*
* LC_FILESET_ENTRY commands describe constituent Mach-O files that are part
* of a fileset. In one implementation, entries are dylibs with individual
* mach headers and repositionable text and data segments. Each entry is
* further described by its own mach header.
*/
fileset_entry_command :: struct {
    cmd:      u32; /* LC_FILESET_ENTRY */
    cmdsize:  u32; /* includes entry_id string */
    vmaddr:   u64; /* memory address of the entry */
    fileoff:  u64; /* file offset of the entry */
    entry_id: lc_str; /* contained entry id */
    reserved: u32; /* reserved */
}

/*
* Format of a relocation entry of a Mach-O file.  Modified from the 4.3BSD
* format.  The modifications from the original format were changing the value
* of the r_symbolnum field for "local" (r_extern == 0) relocation entries.
* This modification is required to support symbols in an arbitrary number of
* sections not just the three sections (text, data and bss) in a 4.3BSD file.
* Also the last 4 bits have had the r_type tag added to them.
*/
relocation_info :: struct {
    /* offset in the section to what is being
    relocated */
    r_address:  s32;

    __bitfield: u32;
    /* 
        /* symbol index if r_extern == 1 or section
        ordinal if r_extern == 0 */
        r_symbolnum: u32; /* 24 bits */
        r_pcrel: u32; /* 1 bits */ /* was relocated pc relative already */
        r_length: u32; /* 2 bits */ /* 0=byte, 1=word, 2=long, 3=quad */
        r_extern: u32; /* 1 bits */ /* does not include value of sym referenced */
        r_type: u32; /* 4 bits */ /* if not 0, machine specific relocation type */;
    */
}

scattered_relocation_info :: struct {
    __bitfield: u32;
    /* 
        /* offset in the section to what is being
        relocated */
        r_address: u32; /* 24 bits */
        r_type: u32; /* 4 bits */ /* if not 0, machine specific relocation type */
        r_length: u32; /* 2 bits */ /* 0=byte, 1=word, 2=long, 3=quad */
        r_pcrel: u32; /* 1 bits */ /* was relocated pc relative already */
        r_scattered: u32; /* 1 bits */ /* 1=scattered, 0=non-scattered (see above) */;
    */

    /* the value the item to be relocated is
    refering to (without any offset added) */
    r_value:    s32;
}

/*
* Relocation types used in a generic implementation.  Relocation entries for
* normal things use the generic relocation as discribed above and their r_type
* is GENERIC_RELOC_VANILLA (a value of zero).
*
* Another type of generic relocation, GENERIC_RELOC_SECTDIFF, is to support
* the difference of two symbols defined in different sections.  That is the
* expression "symbol1 - symbol2 + constant" is a relocatable expression when
* both symbols are defined in some section.  For this type of relocation the
* both relocations entries are scattered relocation entries.  The value of
* symbol1 is stored in the first relocation entry's r_value field and the
* value of symbol2 is stored in the pair's r_value field.
*
* A special case for a prebound lazy pointer is needed to beable to set the
* value of the lazy pointer back to its non-prebound state.  This is done
* using the GENERIC_RELOC_PB_LA_PTR r_type.  This is a scattered relocation
* entry where the r_value feild is the value of the lazy pointer not prebound.
*/
reloc_type_generic :: enum u32 {
    VANILLA        :: 0;
    PAIR           :: 1;
    SECTDIFF       :: 2;
    PB_LA_PTR      :: 3;
    LOCAL_SECTDIFF :: 4;
    TLV            :: 5;
}

/*
* Format of a symbol table entry of a Mach-O file for 32-bit architectures.
* Modified from the BSD format.  The modifications from the original format
* were changing n_other (an unused field) to n_sect and the addition of the
* N_SECT type.  These modifications are required to support symbols in a larger
* number of sections not just the three sections (text, data and bss) in a BSD
* file.
*/
nlist :: struct {
    n_un:    union {
        n_strx: u32; /* index into the string table */
    };

    n_type:  u8; /* type flag, see below */
    n_sect:  u8; /* section number or NO_SECT */
    n_desc:  s16; /* see <mach-o/stab.h> */
    n_value: u32; /* value of this symbol (or stab offset) */
}

/*
* This is the symbol table entry structure for 64-bit architectures.
*/
nlist_64 :: struct {
    n_un:    union {
        n_strx: u32; /* index into the string table */
    };

    n_type:  u8; /* type flag, see below */
    n_sect:  u8; /* section number or NO_SECT */
    n_desc:  u16; /* see <mach-o/stab.h> */
    n_value: u64; /* value of this symbol (or stab offset) */
}

/*
* Relocations for x86_64 are a bit different than for other architectures in
* Mach-O: Scattered relocations are not used.  Almost all relocations produced
* by the compiler are external relocations.  An external relocation has the
* r_extern bit set to 1 and the r_symbolnum field contains the symbol table
* index of the target label.
*
* When the assembler is generating relocations, if the target label is a local
* label (begins with 'L'), then the previous non-local label in the same
* section is used as the target of the external relocation.  An addend is used
* with the distance from that non-local label to the target label.  Only when
* there is no previous non-local label in the section is an internal
* relocation used.
*
* The addend (i.e. the 4 in _foo+4) is encoded in the instruction (Mach-O does
* not have RELA relocations).  For PC-relative relocations, the addend is
* stored directly in the instruction.  This is different from other Mach-O
* architectures, which encode the addend minus the current section offset.
*
* The relocation types are:
*
* 	X86_64_RELOC_UNSIGNED	// for absolute addresses
* 	X86_64_RELOC_SIGNED		// for signed 32-bit displacement
* 	X86_64_RELOC_BRANCH		// a CALL/JMP instruction with 32-bit displacement
* 	X86_64_RELOC_GOT_LOAD	// a MOVQ load of a GOT entry
* 	X86_64_RELOC_GOT		// other GOT references
* 	X86_64_RELOC_SUBTRACTOR	// must be followed by a X86_64_RELOC_UNSIGNED
*
* The following are sample assembly instructions, followed by the relocation
* and section content they generate in an object file:
*
* 	call _foo
* 		r_type=X86_64_RELOC_BRANCH, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		E8 00 00 00 00
*
* 	call _foo+4
* 		r_type=X86_64_RELOC_BRANCH, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		E8 04 00 00 00
*
* 	movq _foo@GOTPCREL(%rip), %rax
* 		r_type=X86_64_RELOC_GOT_LOAD, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		48 8B 05 00 00 00 00
*
* 	pushq _foo@GOTPCREL(%rip)
* 		r_type=X86_64_RELOC_GOT, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		FF 35 00 00 00 00
*
* 	movl _foo(%rip), %eax
* 		r_type=X86_64_RELOC_SIGNED, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		8B 05 00 00 00 00
*
* 	movl _foo+4(%rip), %eax
* 		r_type=X86_64_RELOC_SIGNED, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		8B 05 04 00 00 00
*
* 	movb  $0x12, _foo(%rip)
* 		r_type=X86_64_RELOC_SIGNED, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		C6 05 FF FF FF FF 12
*
* 	movl  $0x12345678, _foo(%rip)
* 		r_type=X86_64_RELOC_SIGNED, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
* 		C7 05 FC FF FF FF 78 56 34 12
*
* 	.quad _foo
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		00 00 00 00 00 00 00 00
*
* 	.quad _foo+4
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		04 00 00 00 00 00 00 00
*
* 	.quad _foo - _bar
* 		r_type=X86_64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_bar
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		00 00 00 00 00 00 00 00
*
* 	.quad _foo - _bar + 4
* 		r_type=X86_64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_bar
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		04 00 00 00 00 00 00 00
*
* 	.long _foo - _bar
* 		r_type=X86_64_RELOC_SUBTRACTOR, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_bar
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		00 00 00 00
*
* 	lea L1(%rip), %rax
* 		r_type=X86_64_RELOC_SIGNED, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_prev
* 		48 8d 05 12 00 00 00
* 		// assumes _prev is the first non-local label 0x12 bytes before L1
*
* 	lea L0(%rip), %rax
* 		r_type=X86_64_RELOC_SIGNED, r_length=2, r_extern=0, r_pcrel=1, r_symbolnum=3
* 		48 8d 05 56 00 00 00
*		// assumes L0 is in third section and there is no previous non-local label.
*		// The rip-relative-offset of 0x00000056 is L0-address_of_next_instruction.
*		// address_of_next_instruction is the address of the relocation + 4.
*
*     add     $6,L0(%rip)
*             r_type=X86_64_RELOC_SIGNED_1, r_length=2, r_extern=0, r_pcrel=1, r_symbolnum=3
*		83 05 18 00 00 00 06
*		// assumes L0 is in third section and there is no previous non-local label.
*		// The rip-relative-offset of 0x00000018 is L0-address_of_next_instruction.
*		// address_of_next_instruction is the address of the relocation + 4 + 1.
*		// The +1 comes from SIGNED_1.  This is used because the relocation is not
*		// at the end of the instruction.
*
* 	.quad L1
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_prev
* 		12 00 00 00 00 00 00 00
* 		// assumes _prev is the first non-local label 0x12 bytes before L1
*
* 	.quad L0
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=0, r_pcrel=0, r_symbolnum=3
* 		56 00 00 00 00 00 00 00
* 		// assumes L0 is in third section, has an address of 0x00000056 in .o
* 		// file, and there is no previous non-local label
*
* 	.quad _foo - .
* 		r_type=X86_64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_prev
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		EE FF FF FF FF FF FF FF
* 		// assumes _prev is the first non-local label 0x12 bytes before this
* 		// .quad
*
* 	.quad _foo - L1
* 		r_type=X86_64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_prev
* 		r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
* 		EE FF FF FF FF FF FF FF
* 		// assumes _prev is the first non-local label 0x12 bytes before L1
*
* 	.quad L1 - _prev
* 		// No relocations.  This is an assembly time constant.
* 		12 00 00 00 00 00 00 00
* 		// assumes _prev is the first non-local label 0x12 bytes before L1
*
*
*
* In final linked images, there are only two valid relocation kinds:
*
*     r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_pcrel=0, r_extern=1, r_symbolnum=sym_index
*	This tells dyld to add the address of a symbol to a pointer sized (8-byte)
*  piece of data (i.e on disk the 8-byte piece of data contains the addend). The
*  r_symbolnum contains the index into the symbol table of the target symbol.
*
*     r_type=X86_64_RELOC_UNSIGNED, r_length=3, r_pcrel=0, r_extern=0, r_symbolnum=0
* This tells dyld to adjust the pointer sized (8-byte) piece of data by the amount
* the containing image was loaded from its base address (e.g. slide).
*
*/
reloc_type_x86_64 :: enum u32 {
    UNSIGNED   :: 0;
    SIGNED     :: 1;
    BRANCH     :: 2;
    GOT_LOAD   :: 3;
    GOT        :: 4;
    SUBTRACTOR :: 5;
    SIGNED_1   :: 6;
    SIGNED_2   :: 7;
    SIGNED_4   :: 8;
    TLV        :: 9;
}

/*
* Relocations for arm64 are a bit different than for other architectures in
* Mach-O: Scattered relocations are not used.  Almost all relocations produced
* by the compiler are external relocations.  An external relocation has the
* r_extern bit set to 1 and the r_symbolnum field contains the symbol table
* index of the target label.
*
* When the assembler is generating relocations, if the target label is a local
* label (begins with 'L'), then the previous non-local label in the same
* section is used as the target of the external relocation.  An addend is used
* with the distance from that non-local label to the target label.  Only when
* there is no previous non-local label in the section is an internal
* relocation used.
*
* The addend (i.e. the 4 in _foo+4) is encoded either in the instruction or
* in the r_symbolnum of ARM64_RELOC_ADDEND.
* For ARM64_RELOC_UNSIGNED and ARM64_RELOC_AUTHENTICATED_POINTER, the addend
* is stored in the instruction.  ARM64_RELOC_PAGE21, ARM64_RELOC_PAGEOFF12 and
* ARM64_RELOC_BRANCH26 must be preceded by an ARM64_RELOC_ADDEND if they need
* an addend.  No other relocations support addends.
*
* The relocation types are:
*
*     ARM64_RELOC_UNSIGNED                 // For pointer sized fixups
*     ARM64_RELOC_SUBTRACTOR               // must be followed by a ARM64_RELOC_UNSIGNED
*     ARM64_RELOC_BRANCH26                 // a BL instruction with pc-relative +-128MB displacement
*     ARM64_RELOC_PAGE21                   // pc-rel distance to page of target
*     ARM64_RELOC_PAGEOFF12                // offset within page, scaled by r_length
*     ARM64_RELOC_GOT_LOAD_PAGE21          // load with a pc-rel distance to page of a GOT entry
*     ARM64_RELOC_GOT_LOAD_PAGEOFF12       // load with an offset within page, scaled by r_length, of GOT entry
*     ARM64_RELOC_POINTER_TO_GOT           // 32-bit pc-rel (or 64-bit absolute) offset to a GOT entry
*     ARM64_RELOC_TLVP_LOAD_PAGE21         // tlv load with a pc-rel distance to page of a GOT entry
*     ARM64_RELOC_TLVP_LOAD_PAGEOFF12      // tlv load with an offset within page, scaled by r_length, of GOT entry
*     ARM64_RELOC_ADDEND                   // must be followed by ARM64_RELOC_BRANCH26/ARM64_RELOC_PAGE21/ARM64_RELOC_PAGEOFF12
*     ARM64_RELOC_AUTHENTICATED_POINTER    // 64-bit pointer with authentication
*
* The following are sample assembly instructions, followed by the relocation
* and section content they generate in an object file:
*
*     (arm64_32 only)
*     .long _foo
*         r_type=ARM64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00
*
*     (arm64_32 only)
*     .long _foo + 4
*         r_type=ARM64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         04 00 00 00
*
*     .quad _foo
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00 00 00 00 00
*
*     .quad _foo + 16
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         10 00 00 00 00 00 00 00
*
*     .quad L1
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_prev
*         10 00 00 00 00 00 00 00
*         // assumes _prev is the first non-local label 0x10 bytes before L1
*         10 00 00 00 00 00 00 00
*
*     (arm64_32 only)
*     .long _foo - _bar
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_bar
*         r_type=ARM64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00
*
*     (arm64_32 only)
*     .long _foo - _bar + 4
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_bar
*         r_type=ARM64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         04 00 00 00
*
*     .quad _foo - _bar
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_bar
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00 00 00 00 00
*
*     .quad _foo - _bar + 4
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_bar
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         04 00 00 00 00 00 00 00
*
*     .long _foo - .
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_prev
*         r_type=ARM64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         f8 ff ff ff
*         // assumes _prev is the first non-local label 0x8 bytes before this
*         // .quad
*
*     .long _foo - L1
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_prev
*         r_type=ARM64_RELOC_UNSIGNED, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         f8 ff ff ff
*         // assumes _prev is the first non-local label 0x8 bytes before L1
*
*     .quad _foo - .
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_prev
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         f8 ff ff ff ff ff ff ff
*         // assumes _prev is the first non-local label 0x8 bytes before this
*         // .quad
*
*     .quad _foo - L1
*         r_type=ARM64_RELOC_SUBTRACTOR, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_prev
*         r_type=ARM64_RELOC_UNSIGNED, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         f8 ff ff ff ff ff ff ff
*         // assumes _prev is the first non-local label 0x8 bytes before L1
*
*     .long L1 - _prev
*         // No relocations.  This is an assembly time constant.
*         12 00 00 00 00 00 00 00
*         // assumes _prev is the first non-local label 0x12 bytes before L1
*
*     .quad L1 - _prev
*         // No relocations.  This is an assembly time constant.
*         12 00 00 00 00 00 00 00
*         // assumes _prev is the first non-local label 0x12 bytes before L1
*
*     bl _foo
*         r_type=ARM64_RELOC_BRANCH26, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         0x14000000
*
*     bl _foo + 4
*         r_type=ARM64_RELOC_ADDEND, r_length=2, r_extern=0, r_pcrel=0, r_symbolnum=0x000004
*         r_type=ARM64_RELOC_BRANCH26, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         0x14000000
*
*     adrp x0, _foo@PAGE
*         r_type=ARM64_RELOC_PAGE21, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         0x90000000
*
*     ldr x0, [x0, _foo@PAGEOFF]
*         r_type=ARM64_RELOC_PAGEOFF12, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         0xf9400000
*
*     adrp x0, _foo@PAGE + 0x24
*         r_type=ARM64_RELOC_ADDEND, r_length=2, r_extern=0, r_pcrel=0, r_symbolnum=0x000024
*         r_type=ARM64_RELOC_PAGE21, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         0x90000000
*
*     ldr x0, [x0, _foo@PAGEOFF + 0x24]
*         r_type=ARM64_RELOC_ADDEND, r_length=2, r_extern=0, r_pcrel=0, r_symbolnum=0x000024
*         r_type=ARM64_RELOC_PAGEOFF12, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         0xf9400000
*
*     adrp x0, _foo@GOTPAGE
*         r_type=ARM64_RELOC_GOT_LOAD_PAGE21, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         0x90000000
*
*     ldr x0, [x0, _foo@GOTPAGEOFF]
*         r_type=ARM64_RELOC_GOT_LOAD_PAGEOFF12, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         0xf9400000
*
*     adrp x0, _foo@TLVPPAGE
*         r_type=ARM64_RELOC_TLVP_LOAD_PAGE21, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         0x90000000
*
*     ldr x0, [x0, _foo@TLVPPAGEOFF]
*         r_type=ARM64_RELOC_TLVP_LOAD_PAGEOFF12, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         0xf9400000
*
*     .long _foo@GOT - .
*         r_type=ARM64_RELOC_POINTER_TO_GOT, r_length=2, r_extern=1, r_pcrel=1, r_symbolnum=_foo
*         00 00 00 00
*
*     (arm64_32 only)
*     .long _foo@GOT
*         r_type=ARM64_RELOC_POINTER_TO_GOT, r_length=2, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00
*
*     .quad _foo@GOT
*         r_type=ARM64_RELOC_POINTER_TO_GOT, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00 00 00 00 00
*
*     (arm64e only)
*     .quad _foo@AUTH(da,5,addr)
*         r_type=ARM64_RELOC_AUTHENTICATED_POINTER, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         00 00 00 00 05 00 05 80
*
*     (arm64e only)
*     .quad (_foo + 0x10)@AUTH(da,5,addr)
*         r_type=ARM64_RELOC_AUTHENTICATED_POINTER, r_length=3, r_extern=1, r_pcrel=0, r_symbolnum=_foo
*         10 00 00 00 05 00 05 80
*
*
*/
reloc_type_arm64 :: enum u32 {
    UNSIGNED              :: 0;
    SUBTRACTOR            :: 1;
    BRANCH26              :: 2;
    PAGE21                :: 3;
    PAGEOFF12             :: 4;
    GOT_LOAD_PAGE21       :: 5;
    GOT_LOAD_PAGEOFF12    :: 6;

    POINTER_TO_GOT        :: 7;
    TLVP_LOAD_PAGE21      :: 8;
    TLVP_LOAD_PAGEOFF12   :: 9;

    ADDEND                :: 10;

    AUTHENTICATED_POINTER :: 11;
}

#scope_file

