package palladium

import "core:fmt"
import "core:os"

Subcommand :: enum {
	Help,
}

Command_Info :: struct {
	name:  string,
	usage: string,
}

help_messages := [Subcommand]Command_Info {
	.Help = {"help", "Displays this message"},
}

main :: proc() {
	subcommand := parse_args()

	if subcommand == .Help {
		print_help()
	}
}

print_help :: proc() {
	fmt.println("Palladium is a programming language\nAll subcommands:")
	for info in help_messages {
		fmt.printfln("  %s - %s", info.name, info.usage)
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
	}

	print_usage(fmt.tprintf("Unknown subcommand %q", subcommand))
	exit_error(1)
}

exit_error :: proc(code: int) -> ! {
	os.exit(code)
}

print_usage :: proc(hint: string = "") {
	if hint != "" {
		fmt.println(hint, "\n")
	}
	fmt.printfln("Usage: `%s [subcommand]`\n   Use `%[0]s help` for more info", os.args[0])
}

