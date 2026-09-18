package palladium

import "core:fmt"

print_parser_error :: proc(err: Parser_Error) {
	fmt.eprintln(err.message)
}

print_checker_error :: proc(err: Type_Error) {
	fmt.eprintln(err.message)
}