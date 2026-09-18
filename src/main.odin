package palladium

import "core:container/xar"
import "core:fmt"
import "core:mem/virtual"
import "core:os"

Subcommand :: enum {
	Help,
	Run,
	Disassemble,
}

Command_Info :: struct {
	name:  string,
	usage: string,
}

help_messages := [Subcommand]Command_Info {
	.Help = {"help      ", "Displays this message"},
	.Run  = {"run <path>", "Compiles and runs the code at <path>"},
	.Disassemble  = {"disassemble <path>", "Compiles the code at <path> and prints its bytecode"},
}

main :: proc() {
	subcommand := parse_args()

	switch subcommand {
	case .Help:
		print_help()
	case .Run:
		run_program(os.args[2])
	case .Disassemble:
		disassemble_program(os.args[2])
	case:
		panic("Invalid subcommand")
	}
}

run_program :: proc(filepath: string) {
	arena: virtual.Arena
	virtual.arena_init_growing(&arena) or_else panic("Failed to initialize memory for arena")
	alloc := virtual.arena_allocator(&arena)
	file_source, read_error := os.read_entire_file(filepath, alloc)

	if read_error != nil {
		switch read_error {
		case .Not_Exist:
			fmt.eprintfln("There is no file at '%s'", filepath)
		case:
			fmt.eprintfln("Failed to read the file at '%s', %v", filepath, read_error)
		}
		return
	}

	ast, parser_error := parse_file(string(file_source), alloc)
	
	if parser_error != nil {
		print_parser_error(parser_error.?)
		return
	}

	typed_ast, type_errors := check_program(ast, alloc)

	for err in type_errors {
		print_checker_error(err)
	}

	if type_errors != nil {
		return
	}

	compiler := program_to_bytecode(typed_ast, alloc)

	global_chunk := xar.get(&compiler.chunks, 0)
	execute_program(global_chunk.bytecode[:], compiler)
}

disassemble_program :: proc(filepath: string) {
	arena: virtual.Arena
	virtual.arena_init_growing(&arena) or_else panic("Failed to initialize memory for arena")
	alloc := virtual.arena_allocator(&arena)
	file_source, read_error := os.read_entire_file(filepath, alloc)

	if read_error != nil {
		switch read_error {
		case .Not_Exist:
			fmt.eprintfln("There is no file at '%s'", filepath)
		case:
			fmt.eprintfln("Failed to read the file at '%s', %v", filepath, read_error)
		}
		return
	}

	ast, parser_error := parse_file(string(file_source), alloc)
	
	if parser_error != nil {
		print_parser_error(parser_error.?)
		return
	}

	typed_ast, type_errors := check_program(ast, alloc)

	for err in type_errors {
		print_checker_error(err)
	}

	if type_errors != nil {
		return
	}

	compiler := program_to_bytecode(typed_ast, alloc)
	for iter := xar.iterator(&compiler.chunks); chunk in xar.iterate_by_val(&iter) {
		disassemble_bytecode(chunk)
	}
}

print_help :: proc() {
	fmt.eprintln("Palladium is a programming language\nAll subcommands:")
	for info in help_messages {
		fmt.eprintfln("  %s - %s", info.name, info.usage)
	}
}

parse_args :: proc() -> Subcommand {
	if len(os.args) < 2 {
		print_usage()
		exit_error(1)
	}
	subcommand := os.args[1]

	switch subcommand {
	case "help":
		return .Help
	case "run":
		return .Run
	case "disassemble":
		return .Disassemble
	}

	print_usage(fmt.tprintf("Unknown subcommand %q", subcommand))
	exit_error(1)
}

exit_error :: proc(code: int) -> ! {
	os.exit(code)
}

print_usage :: proc(hint: string = "") {
	if hint != "" {
		fmt.eprintln(hint, "\n")
	}
	fmt.eprintfln("Usage: `%s [subcommand]`\n   Use `%[0]s help` for more info", os.args[0])
}

