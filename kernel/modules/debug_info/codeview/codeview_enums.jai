Codeview_Symbol_Section :: enum u32 {
    SYMBOLS              :: 0xF1;
    LINES                :: 0xF2;
    STRING_TABLE         :: 0xF3;
    FILE_CHECKSUMS       :: 0xF4;
    FRAME_DATA           :: 0xF5;
    INLINEELINES         :: 0xF6;
    CROSS_SCOPE_IMPORTS  :: 0xF7;
    CROSS_SCOPE_EXPORTS  :: 0xF8;
    IL_LINES             :: 0xF9;
    FUNC_MDTOKEN_MAP     :: 0xFA;
    TYPE_MDTOKEN_MAP     :: 0xFB;
    MERGED_ASSEMBLYINPUT :: 0xFC;
    COFF_SYMBOL_RVA      :: 0xFD;

    IGNORE               :: 0x80000000;    // if this bit is set in a subsection type then ignore the subsection contents
}

Codeview_Symbol_Type :: enum u16 {
    COMPILE                              :: 0x0001;  // Compile flags symbol
    REGISTER_16t                         :: 0x0002;  // Register variable
    CONSTANT_16t                         :: 0x0003;  // constant symbol
    UDT_16t                              :: 0x0004;  // User defined type
    SSEARCH                              :: 0x0005;  // Start Search
    END                                  :: 0x0006;  // Block, procedure, "with" or thunk end
    SKIP                                 :: 0x0007;  // Reserve symbol space in $$Symbols table
    CVRESERVE                            :: 0x0008;  // Reserved symbol for CV internal use
    OBJNAME_ST                           :: 0x0009;  // path to object file name
    ENDARG                               :: 0x000a;  // end of argument/return list
    COBOLUDT_16t                         :: 0x000b;  // special UDT for cobol that does not symbol pack
    MANYREG_16t                          :: 0x000c;  // multiple register variable
    RETURN                               :: 0x000d;  // return description symbol
    ENTRYTHIS                            :: 0x000e;  // description of this pointer on entry

    BPREL16                              :: 0x0100;  // BP-relative
    LDATA16                              :: 0x0101;  // Module-local symbol
    GDATA16                              :: 0x0102;  // Global data symbol
    PUB16                                :: 0x0103;  // a public symbol
    LPROC16                              :: 0x0104;  // Local procedure start
    GPROC16                              :: 0x0105;  // Global procedure start
    THUNK16                              :: 0x0106;  // Thunk Start
    BLOCK16                              :: 0x0107;  // block start
    WITH16                               :: 0x0108;  // with start
    LABEL16                              :: 0x0109;  // code label
    CEXMODEL16                           :: 0x010a;  // change execution model
    VFTABLE16                            :: 0x010b;  // address of virtual function table
    REGREL16                             :: 0x010c;  // register relative address

    BPREL32_16t                          :: 0x0200;  // BP-relative
    LDATA32_16t                          :: 0x0201;  // Module-local symbol
    GDATA32_16t                          :: 0x0202;  // Global data symbol
    PUB32_16t                            :: 0x0203;  // a public symbol (CV internal reserved)
    LPROC32_16t                          :: 0x0204;  // Local procedure start
    GPROC32_16t                          :: 0x0205;  // Global procedure start
    THUNK32_ST                           :: 0x0206;  // Thunk Start
    BLOCK32_ST                           :: 0x0207;  // block start
    WITH32_ST                            :: 0x0208;  // with start
    LABEL32_ST                           :: 0x0209;  // code label
    CEXMODEL32                           :: 0x020a;  // change execution model
    VFTABLE32_16t                        :: 0x020b;  // address of virtual function table
    REGREL32_16t                         :: 0x020c;  // register relative address
    LTHREAD32_16t                        :: 0x020d;  // local thread storage
    GTHREAD32_16t                        :: 0x020e;  // global thread storage
    SLINK32                              :: 0x020f;  // static link for MIPS EH implementation

    LPROCMIPS_16t                        :: 0x0300;  // Local procedure start
    GPROCMIPS_16t                        :: 0x0301;  // Global procedure start

    // if these ref symbols have names following then the names are in ST format
    PROCREF_ST                           :: 0x0400;  // Reference to a procedure
    DATAREF_ST                           :: 0x0401;  // Reference to data
    ALIGN                                :: 0x0402;  // Used for page alignment of symbols

    LPROCREF_ST                          :: 0x0403;  // Local Reference to a procedure
    OEM                                  :: 0x0404;  // OEM defined symbol

    // sym records with 32-bit types embedded instead of 16-bit
    // all have 0x1000 bit set for easy identification
    // only do the 32-bit target versions since we don't really
    // care about 16-bit ones anymore.
    TI16_MAX                             :: 0x1000;

    REGISTER_ST                          :: 0x1001;  // Register variable
    CONSTANT_ST                          :: 0x1002;  // constant symbol
    UDT_ST                               :: 0x1003;  // User defined type
    COBOLUDT_ST                          :: 0x1004;  // special UDT for cobol that does not symbol pack
    MANYREG_ST                           :: 0x1005;  // multiple register variable
    BPREL32_ST                           :: 0x1006;  // BP-relative
    LDATA32_ST                           :: 0x1007;  // Module-local symbol
    GDATA32_ST                           :: 0x1008;  // Global data symbol
    PUB32_ST                             :: 0x1009;  // a public symbol (CV internal reserved)
    LPROC32_ST                           :: 0x100a;  // Local procedure start
    GPROC32_ST                           :: 0x100b;  // Global procedure start
    VFTABLE32                            :: 0x100c;  // address of virtual function table
    REGREL32_ST                          :: 0x100d;  // register relative address
    LTHREAD32_ST                         :: 0x100e;  // local thread storage
    GTHREAD32_ST                         :: 0x100f;  // global thread storage

    LPROCMIPS_ST                         :: 0x1010;  // Local procedure start
    GPROCMIPS_ST                         :: 0x1011;  // Global procedure start

    FRAMEPROC                            :: 0x1012;  // extra frame and proc information
    COMPILE2_ST                          :: 0x1013;  // extended compile flags and info

    // new symbols necessary for 16-bit enumerates of IA64 registers
    // and IA64 specific symbols

    MANYREG2_ST                          :: 0x1014;  // multiple register variable
    LPROCIA64_ST                         :: 0x1015;  // Local procedure start (IA64)
    GPROCIA64_ST                         :: 0x1016;  // Global procedure start (IA64)

    // Local symbols for IL
    LOCALSLOT_ST                         :: 0x1017;  // local IL sym with field for local slot index
    PARAMSLOT_ST                         :: 0x1018;  // local IL sym with field for parameter slot index

    ANNOTATION                           :: 0x1019;  // Annotation string literals

    // symbols to support managed code debugging
    GMANPROC_ST                          :: 0x101a;  // Global proc
    LMANPROC_ST                          :: 0x101b;  // Local proc
    RESERVED1                            :: 0x101c;  // reserved
    RESERVED2                            :: 0x101d;  // reserved
    RESERVED3                            :: 0x101e;  // reserved
    RESERVED4                            :: 0x101f;  // reserved
    LMANDATA_ST                          :: 0x1020;
    GMANDATA_ST                          :: 0x1021;
    MANFRAMEREL_ST::                     0x1022;
    MANREGISTER_ST::                     0x1023;
    MANSLOT_ST                           :: 0x1024;
    MANMANYREG_ST                        :: 0x1025;
    MANREGREL_ST                         :: 0x1026;
    MANMANYREG2_ST::                     0x1027;
    MANTYPREF                            :: 0x1028;  // Index for type referenced by name from metadata
    UNAMESPACE_ST                        :: 0x1029;  // Using namespace

    // Symbols w/ SZ name fields. All name fields contain utf8 encoded strings.
    ST_MAX                               :: 0x1100;  // starting point for SZ name symbols

    OBJNAME                              :: 0x1101;  // path to object file name
    THUNK32                              :: 0x1102;  // Thunk Start
    BLOCK32                              :: 0x1103;  // block start
    WITH32                               :: 0x1104;  // with start
    LABEL32                              :: 0x1105;  // code label
    REGISTER                             :: 0x1106;  // Register variable
    CONSTANT                             :: 0x1107;  // constant symbol
    UDT                                  :: 0x1108;  // User defined type
    COBOLUDT                             :: 0x1109;  // special UDT for cobol that does not symbol pack
    MANYREG                              :: 0x110a;  // multiple register variable
    BPREL32                              :: 0x110b;  // BP-relative
    LDATA32                              :: 0x110c;  // Module-local symbol
    GDATA32                              :: 0x110d;  // Global data symbol
    PUB32                                :: 0x110e;  // a public symbol (CV internal reserved)
    LPROC32                              :: 0x110f;  // Local procedure start
    GPROC32                              :: 0x1110;  // Global procedure start
    REGREL32                             :: 0x1111;  // register relative address
    LTHREAD32                            :: 0x1112;  // local thread storage
    GTHREAD32                            :: 0x1113;  // global thread storage

    LPROCMIPS                            :: 0x1114;  // Local procedure start
    GPROCMIPS                            :: 0x1115;  // Global procedure start
    COMPILE2                             :: 0x1116;  // extended compile flags and info
    MANYREG2                             :: 0x1117;  // multiple register variable
    LPROCIA64                            :: 0x1118;  // Local procedure start (IA64)
    GPROCIA64                            :: 0x1119;  // Global procedure start (IA64)
    LOCALSLOT                            :: 0x111a;  // local IL sym with field for local slot index
    SLOT                                 :: LOCALSLOT;  // alias for LOCALSLOT
    PARAMSLOT                            :: 0x111b;  // local IL sym with field for parameter slot index

    // symbols to support managed code debugging
    LMANDATA                             :: 0x111c;
    GMANDATA                             :: 0x111d;
    MANFRAMEREL                          :: 0x111e;
    MANREGISTER                          :: 0x111f;
    MANSLOT                              :: 0x1120;
    MANMANYREG                           :: 0x1121;
    MANREGREL                            :: 0x1122;
    MANMANYREG2                          :: 0x1123;
    UNAMESPACE                           :: 0x1124;  // Using namespace

    // ref symbols with name fields
    PROCREF                              :: 0x1125;  // Reference to a procedure
    DATAREF                              :: 0x1126;  // Reference to data
    LPROCREF                             :: 0x1127;  // Local Reference to a procedure
    ANNOTATIONREF                        :: 0x1128;  // Reference to an ANNOTATION symbol
    TOKENREF                             :: 0x1129;  // Reference to one of the many MANPROCSYM's

    // continuation of managed symbols
    GMANPROC                             :: 0x112a;  // Global proc
    LMANPROC                             :: 0x112b;  // Local proc

    // short, light-weight thunks
    TRAMPOLINE                           :: 0x112c;  // trampoline thunks
    MANCONSTANT                          :: 0x112d;  // constants with metadata type info

    // native attributed local/parms
    ATTR_FRAMEREL                        :: 0x112e;  // relative to virtual frame ptr
    ATTR_REGISTER                        :: 0x112f;  // stored in a register
    ATTR_REGREL                          :: 0x1130;  // relative to register (alternate frame ptr)
    ATTR_MANYREG                         :: 0x1131;  // stored in >1 register

    // Separated code (from the compiler) support
    SEPCODE                              :: 0x1132;

    LOCAL_2005                           :: 0x1133;  // defines a local symbol in optimized code
    DEFRANGE_2005                        :: 0x1134;  // defines a single range of addresses in which symbol can be evaluated
    DEFRANGE2_2005                       :: 0x1135;  // defines ranges of addresses in which symbol can be evaluated

    SECTION                              :: 0x1136;  // A COFF section in a PE executable
    COFFGROUP                            :: 0x1137;  // A COFF group
    EXPORT                               :: 0x1138;  // A export

    CALLSITEINFO                         :: 0x1139;  // Indirect call site information
    FRAMECOOKIE                          :: 0x113a;  // Security cookie information

    DISCARDED                            :: 0x113b;  // Discarded by LINK /OPT:REF (experimental, see richards)

    COMPILE3                             :: 0x113c;  // Replacement for COMPILE2
    ENVBLOCK                             :: 0x113d;  // Environment block split off from COMPILE2

    LOCAL                                :: 0x113e;  // defines a local symbol in optimized code
    DEFRANGE                             :: 0x113f;  // defines a single range of addresses in which symbol can be evaluated
    DEFRANGE_SUBFIELD                    :: 0x1140;           // ranges for a subfield

    DEFRANGE_REGISTER                    :: 0x1141;           // ranges for en-registered symbol
    DEFRANGE_FRAMEPOINTER_REL            :: 0x1142;   // range for stack symbol.
    DEFRANGE_SUBFIELD_REGISTER           :: 0x1143;  // ranges for en-registered field of symbol
    DEFRANGE_FRAMEPOINTER_REL_FULL_SCOPE :: 0x1144; // range for stack symbol span valid full scope of function body, gap might apply.
    DEFRANGE_REGISTER_REL                :: 0x1145; // range for symbol address as register + offset.

    // PROC symbols that reference ID instead of type
    LPROC32_ID                           :: 0x1146;
    GPROC32_ID                           :: 0x1147;
    LPROCMIPS_ID                         :: 0x1148;
    GPROCMIPS_ID                         :: 0x1149;
    LPROCIA64_ID                         :: 0x114a;
    GPROCIA64_ID                         :: 0x114b;

    BUILDINFO                            :: 0x114c; // build information.
    INLINESITE                           :: 0x114d; // inlined function callsite.
    INLINESITE_END                       :: 0x114e;
    PROC_ID_END                          :: 0x114f;

    DEFRANGE_HLSL                        :: 0x1150;
    GDATA_HLSL                           :: 0x1151;
    LDATA_HLSL                           :: 0x1152;

    FILESTATIC                           :: 0x1153;

    LOCAL_DPC_GROUPSHARED                :: 0x1154; // DPC groupshared variable
    LPROC32_DPC                          :: 0x1155; // DPC local procedure start
    LPROC32_DPC_ID                       :: 0x1156;
    DEFRANGE_DPC_PTR_TAG                 :: 0x1157; // DPC pointer tag definition range
    DPC_SYM_TAG_MAP                      :: 0x1158; // DPC pointer tag value to symbol record map

    ARMSWITCHTABLE                       :: 0x1159;
    CALLEES                              :: 0x115a;
    CALLERS                              :: 0x115b;
    POGODATA                             :: 0x115c;
    INLINESITE2                          :: 0x115d;      // extended inline site information

    HEAPALLOCSITE                        :: 0x115e;    // heap allocation site

    MOD_TYPEREF                          :: 0x115f;      // only generated at link time

    REF_MINIPDB                          :: 0x1160;      // only generated at link time for mini PDB
    PDBMAP                               :: 0x1161;      // only generated at link time for mini PDB

    GDATA_HLSL32                         :: 0x1162;
    LDATA_HLSL32                         :: 0x1163;

    GDATA_HLSL32_EX                      :: 0x1164;
    LDATA_HLSL32_EX                      :: 0x1165;

    INLINEES                             :: 0x1168;  // Not part of the CodeView documentation repo, but found via https://github.com/Microsoft/microsoft-pdb/issues/29#issuecomment-469529456

    RECTYPE_MAX;                         // one greater than last
    RECTYPE_LAST                         :: RECTYPE_MAX- 1;
    RECTYPE_PAD                          :: RECTYPE_MAX+ 0x100;// Used *only* to verify symbol record types so that current PDB code can potentially read
                                // future PDBs (assuming no format change, etc).
}

// It's worth nothing that MSVC supports __int8, __int16, __int32, and __int64 as built-in types
// which have different type indices as C++ built-in char, short, int, long long types. The
// MSVC debugger however seems to have naming inconsistencies...

Codeview_Leaf_Type :: enum u16 {
    BUILTIN                              :: 0x0000;  // Inserted by me (rluba) to indicate type info we return for builtin types. Not used by CodeView itself.

    // leaf indices starting records but referenced from symbol records
    MODIFIER_16T     :: 0x0001;
    POINTER_16T      :: 0x0002;
    ARRAY_16T        :: 0x0003;
    CLASS_16T        :: 0x0004;
    STRUCTURE_16T    :: 0x0005;
    UNION_16T        :: 0x0006;
    ENUM_16T         :: 0x0007;
    PROCEDURE_16T    :: 0x0008;
    MFUNCTION_16T    :: 0x0009;
    VTSHAPE          :: 0x000a;
    COBOL0_16T       :: 0x000b;
    COBOL1           :: 0x000c;
    BARRAY_16T       :: 0x000d;
    LABEL            :: 0x000e;
    NULL             :: 0x000f;
    NOTTRAN          :: 0x0010;
    DIMARRAY_16T     :: 0x0011;
    VFTPATH_16T      :: 0x0012;
    PRECOMP_16T      :: 0x0013;       // not referenced from symbol
    ENDPRECOMP       :: 0x0014;       // not referenced from symbol
    OEM_16T          :: 0x0015;       // oem definable type string
    TYPESERVER_ST    :: 0x0016;       // not referenced from symbol

    // leaf indices starting records but referenced only from type records

    SKIP_16T         :: 0x0200;
    ARGLIST_16T      :: 0x0201;
    DEFARG_16T       :: 0x0202;
    LIST             :: 0x0203;
    FIELDLIST_16T    :: 0x0204;
    DERIVED_16T      :: 0x0205;
    BITFIELD_16T     :: 0x0206;
    METHODLIST_16T   :: 0x0207;
    DIMCONU_16T      :: 0x0208;
    DIMCONLU_16T     :: 0x0209;
    DIMVARU_16T      :: 0x020a;
    DIMVARLU_16T     :: 0x020b;
    REFSYM           :: 0x020c;

    BCLASS_16T       :: 0x0400;
    VBCLASS_16T      :: 0x0401;
    IVBCLASS_16T     :: 0x0402;
    ENUMERATE_ST     :: 0x0403;
    FRIENDFCN_16T    :: 0x0404;
    INDEX_16T        :: 0x0405;
    MEMBER_16T       :: 0x0406;
    STMEMBER_16T     :: 0x0407;
    METHOD_16T       :: 0x0408;
    NESTTYPE_16T     :: 0x0409;
    VFUNCTAB_16T     :: 0x040a;
    FRIENDCLS_16T    :: 0x040b;
    ONEMETHOD_16T    :: 0x040c;
    VFUNCOFF_16T     :: 0x040d;

// 32-bit type index versions of leaves, all have the 0x1000 bit set
//
    TI16_MAX         :: 0x1000;

    MODIFIER         :: 0x1001;
    POINTER          :: 0x1002;
    ARRAY_ST         :: 0x1003;
    CLASS_ST         :: 0x1004;
    STRUCTURE_ST     :: 0x1005;
    UNION_ST         :: 0x1006;
    ENUM_ST          :: 0x1007;
    PROCEDURE        :: 0x1008;
    MFUNCTION        :: 0x1009;
    COBOL0           :: 0x100a;
    BARRAY           :: 0x100b;
    DIMARRAY_ST      :: 0x100c;
    VFTPATH          :: 0x100d;
    PRECOMP_ST       :: 0x100e;       // not referenced from symbol
    OEM              :: 0x100f;       // oem definable type string
    ALIAS_ST         :: 0x1010;       // alias (typedef) type
    OEM2             :: 0x1011;       // oem definable type string

    // leaf indices starting records but referenced only from type records

    SKIP             :: 0x1200;
    ARGLIST          :: 0x1201;
    DEFARG_ST        :: 0x1202;
    FIELDLIST        :: 0x1203;
    DERIVED          :: 0x1204;
    BITFIELD         :: 0x1205;
    METHODLIST       :: 0x1206;
    DIMCONU          :: 0x1207;
    DIMCONLU         :: 0x1208;
    DIMVARU          :: 0x1209;
    DIMVARLU         :: 0x120a;

    BCLASS           :: 0x1400;
    VBCLASS          :: 0x1401;
    IVBCLASS         :: 0x1402;
    FRIENDFCN_ST     :: 0x1403;
    INDEX            :: 0x1404;
    MEMBER_ST        :: 0x1405;
    STMEMBER_ST      :: 0x1406;
    METHOD_ST        :: 0x1407;
    NESTTYPE_ST      :: 0x1408;
    VFUNCTAB         :: 0x1409;
    FRIENDCLS        :: 0x140a;
    ONEMETHOD_ST     :: 0x140b;
    VFUNCOFF         :: 0x140c;
    NESTTYPEEX_ST    :: 0x140d;
    MEMBERMODIFY_ST  :: 0x140e;
    MANAGED_ST       :: 0x140f;

    // Types w/ SZ names

    ST_MAX           :: 0x1500;

    TYPESERVER       :: 0x1501;       // not referenced from symbol
    ENUMERATE        :: 0x1502;
    ARRAY            :: 0x1503;
    CLASS            :: 0x1504;
    STRUCTURE        :: 0x1505;
    UNION            :: 0x1506;
    ENUM             :: 0x1507;
    DIMARRAY         :: 0x1508;
    PRECOMP          :: 0x1509;       // not referenced from symbol
    ALIAS            :: 0x150a;       // alias (typedef) type
    DEFARG           :: 0x150b;
    FRIENDFCN        :: 0x150c;
    MEMBER           :: 0x150d;
    STMEMBER         :: 0x150e;
    METHOD           :: 0x150f;
    NESTTYPE         :: 0x1510;
    ONEMETHOD        :: 0x1511;
    NESTTYPEEX       :: 0x1512;
    MEMBERMODIFY     :: 0x1513;
    MANAGED          :: 0x1514;
    TYPESERVER2      :: 0x1515;

    STRIDED_ARRAY    :: 0x1516;    // same as ARRAY, but with stride between adjacent elements
    HLSL             :: 0x1517;
    MODIFIER_EX      :: 0x1518;
    INTERFACE        :: 0x1519;
    BINTERFACE       :: 0x151a;
    VECTOR           :: 0x151b;
    MATRIX           :: 0x151c;

    VFTABLE          :: 0x151d;      // a virtual function table
    ENDOFLEAFRECORD  :: VFTABLE;

    TYPE_LAST;                    // one greater than the last type record
    TYPE_MAX         :: TYPE_LAST - 1;

    FUNC_ID          :: 0x1601;    // global func ID
    MFUNC_ID         :: 0x1602;    // member func ID
    BUILDINFO        :: 0x1603;    // build info: tool, version, command line; src/pdb file
    SUBSTR_LIST      :: 0x1604;    // similar to ARGLIST, for list of sub strings
    STRING_ID        :: 0x1605;    // string ID

    UDT_SRC_LINE     :: 0x1606;    // source and line on where an UDT is defined
                                     // only generated by compiler

    UDT_MOD_SRC_LINE :: 0x1607;    // module; source and line on where an UDT is defined
                                     // only generated by linker

    ID_LAST;                      // one greater than the last ID record
    ID_MAX           :: ID_LAST - 1;

    NUMERIC          :: 0x8000;
    CHAR             :: 0x8000;
    SHORT            :: 0x8001;
    USHORT           :: 0x8002;
    LONG             :: 0x8003;
    ULONG            :: 0x8004;
    REAL32           :: 0x8005;
    REAL64           :: 0x8006;
    REAL80           :: 0x8007;
    REAL128          :: 0x8008;
    QUADWORD         :: 0x8009;
    UQUADWORD        :: 0x800a;
    REAL48           :: 0x800b;
    COMPLEX32        :: 0x800c;
    COMPLEX64        :: 0x800d;
    COMPLEX80        :: 0x800e;
    COMPLEX128       :: 0x800f;
    VARSTRING        :: 0x8010;

    OCTWORD          :: 0x8017;
    UOCTWORD         :: 0x8018;

    DECIMAL          :: 0x8019;
    DATE             :: 0x801a;
    UTF8STRING       :: 0x801b;

    REAL16           :: 0x801c;

    PAD0             :: 0xf0;
    PAD1             :: 0xf1;
    PAD2             :: 0xf2;
    PAD3             :: 0xf3;
    PAD4             :: 0xf4;
    PAD5             :: 0xf5;
    PAD6             :: 0xf6;
    PAD7             :: 0xf7;
    PAD8             :: 0xf8;
    PAD9             :: 0xf9;
    PAD10            :: 0xfa;
    PAD11            :: 0xfb;
    PAD12            :: 0xfc;
    PAD13            :: 0xfd;
    PAD14            :: 0xfe;
    PAD15            :: 0xff;
}

Codeview_Access :: enum u16 {
    NONE :: 0;
    PUBLIC :: 3;// 0b11
}


Struct_Properties :: enum_flags u16 {
    PACKED              :: 0x0001; // true if structure is packed
    CTOR                :: 0x0002; // true if constructors or destructors present
    OVLOPS              :: 0x0004; // true if overloaded operators present
    IS_NESTED           :: 0x0008; // true if this is a nested class
    NESTED_TYPES        :: 0x0010; // true if this class contains nested types
    OP_ASSIGN           :: 0x0020; // true if overloaded assignment (=)
    OP_CAST             :: 0x0040; // true if casting methods
    FWDREF              :: 0x0080; // true if forward reference (incomplete defn)
    SCOPED              :: 0x0100; // scoped definition
    UNIQUE_NAME         :: 0x0200; // true if there is a decorated name following the regular name
    SEALED              :: 0x0400; // true if class cannot be used as a base class

    // 2-bit enum mixed into these flags: 0 == HFA_NONE
    HFA_OTHER           :: 0x1800;
    HFA_FLOAT           :: 0x0800;
    HFA_DOUBLE          :: 0x1000;

    INTRINSIC           :: 0x2000; // true if class is an intrinsic type (e.g. __m128d)

    // 2-bit enum mixed into these flags: 0 == MOCOM_UDT_NONE
    MOCOM_UDT_INTERFACE :: 0xC000;
    MOCOM_UDT_REF       :: 0x4000;
    MOCOM_UDT_VALUE     :: 0x8000;
}

Function_Attributes :: enum_flags u8 {
    CXX_RETURN_UDT :: 0x01; // true if C++ style ReturnUDT
    CTOR           :: 0x02; // true if func is an instance constructor
    CTOR_V_BASE    :: 0x03; // true if func is an instance constructor of a class with virtual bases
}

Codeview_Inlinee_Source_Variant :: enum u32 {
    NORMAL :: 0;
    EX     :: 1;
}

// BinaryAnnotations ::= BinaryAnnotationInstruction+
// BinaryAnnotationInstruction ::= BinaryAnnotationOpcode Operand+
//
// The binary annotation mechanism supports recording a list of annotations
// in an instruction stream.  The X64 unwind code and the DWARF standard have
// similar design.
//
// One annotation contains opcode and a number of 32bits operands.
//
// The initial set of annotation instructions are for line number table
// encoding only.  These annotations append to INLINESITE record, and
// operands are unsigned except for BA_OP_ChangeLineOffset.

Codeview_Binary_Annotation_Opcode :: enum u8 {
    INVALID                            :: 0x00; // link time pdb contains PADDINGs
    CODE_OFFSET                        :: 0x01; // param : start offset
    CHANGE_CODE_OFFSET_BASE            :: 0x02; // param : nth separated code chunk (main code chunk == 0)
    CHANGE_CODE_OFFSET                 :: 0x03; // param : delta of offset => generates a new line record!
    CHANGE_CODE_LENGTH                 :: 0x04; // param : length of code, default next start
    CHANGE_FILE                        :: 0x05; // param : fileId
    CHANGE_LINE_OFFSET                 :: 0x06; // param : line offset (signed)
    CHANGE_LINE_END_DELTA              :: 0x07; // param : how many lines, default 1
    CHANGE_RANGE_KIND                  :: 0x08; // param : either 1 (default, for statement) or 0 (for expression)

    CHANGE_COLUMN_START                :: 0x09; // param : start column number, 0 means no column info
    CHANGE_COLUMN_END_DELTA            :: 0x0a; // param : end column number delta (signed)

    // Combo opcodes for smaller encoding size.
    CHANGE_CODE_OFFSET_AND_LINE_OFFSET :: 0x0b; // param : ((sourceDelta << 4) | CodeDelta) => generates a new line record!
    CHANGE_CODE_LENGTH_AND_CODE_OFFSET :: 0x0c; // param : codeLength, codeOffset => generates a new line record!

    CHANGE_COLUMN_END                  :: 0x0d; // param : end column number
}

// The base types:
Codeview_Builtin_Type :: enum {
    NOTYPE  :: 0x0000;
    ABS     :: 0x0002; // absolute symbol
    SEGMENT :: 0x0002; // segment type
    VOID    :: 0x0003;
    HRESULT :: 0x0008;
    CHAR    :: 0x0010;
    SHORT   :: 0x0011;
    LONG    :: 0x0012;
    QUAD    :: 0x0013;
    UCHAR   :: 0x0020;
    USHORT  :: 0x0021;
    ULONG   :: 0x0022;
    UQUAD   :: 0x0023;
    FLOAT32 :: 0x0040;
    FLOAT64 :: 0x0041;
    FLOAT16 :: 0x0046;
    S8      :: 0x0068;
    U8      :: 0x0069;
    RCHAR   :: 0x0070; // really a char
    WCHAR   :: 0x0071; // wide char
    CHAR16  :: 0x007a; // 16-bit unicode char
    CHAR32  :: 0x007b; // 16-bit unicode char
    S16     :: 0x0072;
    U16     :: 0x0073;
    S32     :: 0x0074;
    U32     :: 0x0075;
    S64     :: 0x0076;
    U64     :: 0x0077;
    BOOL8   :: 0x0030;
    BOOL16  :: 0x0031;
    BOOL32  :: 0x0032;
    BOOL64  :: 0x0033;
    // MSVC also supports bool types up to register width (64-bits)
}

// :CodeViewPointers:
// For pointers to built-in primitive types, the pointer and the base type can be
// and should be folded into a single type. It seems the format to do this is:
// ((ptr_type << 8) | base_type). Where the valid ptr_types are:
Codeview_Pointer_Type :: enum u8 {
    NEAR         :: 0x00; // 16 bit pointer
    FAR          :: 0x01; // 16:16 far pointer
    HUGE         :: 0x02; // 16:16 huge pointer
    BASE_SEG     :: 0x03; // based on segment
    BASE_VAL     :: 0x04; // based on value of base
    BASE_SEGVAL  :: 0x05; // based on segment value of base
    BASE_ADDR    :: 0x06; // based on address of base
    BASE_SEGADDR :: 0x07; // based on segment address of base
    BASE_TYPE    :: 0x08; // based on type
    BASE_SELF    :: 0x09; // based on self
    NEAR32       :: 0x0a; // 32 bit pointer
    FAR32        :: 0x0b; // 16:32 pointer
    _64          :: 0x0c; // 64 bit pointer
    UNUSEDPTR    :: 0x0d; // first unused pointer type
}
