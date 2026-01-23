#assert(OS == .MACOS);

TYPES_TO_OMIT :: string.[
];

#run {
    set_build_options_dc(.{do_output=false});
    if !generate_bindings() {
        compiler_set_workspace_status(.FAILED);
    }
};

generate_bindings :: () -> bool {
    // Always use the system SDK path, not the one set via the environment.
    // We generally want to generate bindings for the oldest macOS version the compiler supports (currently 10.13),
    // So I set MACOS_SDK_PATH to a copy of the 10.13 SDK before running "generate_all.jai".
    // But this module depends on some definitions like CPU_ARCH.ABI64_32 that are only available in later versions.
    //  -rluba, 2023-07-27
    POSIX.setenv("MACOS_SDK_PATH", "\0", 1);
    output_filename: string;
    opts: Generate_Bindings_Options;
    {
        using opts;
	    // generate_library_declarations = false;

        make_directory_if_it_does_not_exist("bindings");
		output_filename          = "bindings/macho.jai";

        libc_path := get_libc_paths();
        array_add(*source_files,
            tprint("%/mach-o/loader.h", libc_path),
            tprint("%/mach-o/reloc.h", libc_path),
            tprint("%/mach-o/stab.h", libc_path),
            tprint("%/mach-o/nlist.h", libc_path),
            tprint("%/mach-o/x86_64/reloc.h", libc_path),
            tprint("%/mach-o/arm64/reloc.h", libc_path),
            tprint("%/mach/machine.h", libc_path),
        );

		array_add(*path_fragments_to_treat_as_non_system_paths, "mach/machine.h");
		array_add(*generate_enums_from_macros_with_prefixes,
			"CPU_STATE",
			"CPU_TYPE",
			"CPU_SUBTYPE",
			"CPU_ARCH",
			"CPUFAMILY",
			"CPUSUBFAMILY",
			"LC_",
			"SG_",
			"S_",
		);
		alias_original_enum_names = false;
        log_stripped_declarations = false;

        array_add(*extra_clang_arguments, "-x", "c");
        header = PREAMBLE;
        generate_compile_time_struct_checks = false;

        visitor = sysctl_visitor;
    }

    return generate_bindings(opts, output_filename);
}

#scope_file

typedef_cpu_subtype_t: *Typedef;

sysctl_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    if !parent_decl {
        if array_find(TYPES_TO_OMIT, decl.name) {
            decl.decl_flags |= .OMIT_FROM_OUTPUT;
            return .STOP;
        }
    }

    if decl.kind == .ENUM {
        if decl.output_name == "LC" {
            decl.output_name = "Load_Command_Type";
            decl.type = context.generator.type_def_u32;
            _enum := cast(*Enum) decl;
            _enum.flags &= ~.MIMIC_SPACING;
        }

        if decl.output_name == "SG" {
            decl.output_name = "Segment_Flags";
            decl.type = context.generator.type_def_u32;
            _enum := cast(*Enum) decl;
            _enum.flags |= .IS_ENUM_FLAGS;
            _enum.flags &= ~.MIMIC_SPACING;
        }

        if decl.output_name == "S" {
            decl.output_name = "Section_Flags";
            decl.type = context.generator.type_def_u32;
            _enum := cast(*Enum) decl;
            _enum.flags |= .IS_ENUM_FLAGS;
            _enum.flags &= ~.MIMIC_SPACING;
        }

        if decl.output_name == "CPU_TYPE" {
            decl.output_name = "Cpu_Type";
            decl.type = context.generator.type_def_s32;
        }

        if decl.output_name == "CPU_SUBTYPE" {
            decl.output_name = "Cpu_Subtype";
            decl.type = context.generator.type_def_s32;
        }

        if decl.output_name == "CPU_SUBTYPE" {
            decl.type = New(CType);
            decl.type.type_of_typedef = cast(*Typedef) find(.TYPEDEF, "cpu_subtype_t");
        }
    }

    return .RECURSE;
}

find :: (kind: C_Kind, name: string) -> *Declaration {
    for context.generator.global_scope.members {
        if it.kind == kind && it.name == name then return it;
    }

    assert(false, "Could not find a global declartion of type % with name %", kind, name);
    return null;
}

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "String";
POSIX :: #import "POSIX";

PREAMBLE :: #string END
vm_prot_t :: s32;
END

