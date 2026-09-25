package palladium

import "base:runtime"
import "core:fmt"

print_parser_error :: proc(err: Parser_Error) {
	line, column := find_line_col_from_offset(err.offset, err.source)
	fmt.eprintfln("[%s:%2d:%2d] %s", err.path, line, column, err.message)
}

print_checker_error :: proc(err: Type_Error) {
	fmt.eprintln(err.message)
}

token_to_string :: proc(token: Token, allocator: runtime.Allocator) -> string {
	#partial switch token.type {
		case .Identifier, .Integer_Literal, .String_Literal, .Invalid:
			return fmt.aprintf("%s[%s]", token.type, token.value, allocator = allocator)
		case:
			return fmt.aprint(token.type, allocator = allocator)
	}
}

find_line_col_from_offset :: proc(offset: int, source: string) -> (int, int) {
	line, col := 1, 1
	for char in source[:offset] {
		if char == '\n' {
			col = 0
			line += 1
		}
		col += 1
	}

	return line, col
}