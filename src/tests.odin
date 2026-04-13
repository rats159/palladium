package palladium

import "core:fmt"
import "core:testing"

@(test)
tokenize_numbers_test :: proc(t: ^testing.T) {
	source := "123 456 789"
	tokens := tokenize_entire_source(source, context.temp_allocator)
	testing.expect(t, len(tokens) == 4)

	for token in tokens[:3] {
		testing.expect(t, token.type == .Integer_Literal)
	}

	testing.expect(t, tokens[len(tokens) - 1].type == .EOF)
}

@(test)
tokenize_eof_test :: proc(t: ^testing.T) {
	source := ""
	tokens := tokenize_entire_source(source, context.temp_allocator)
	testing.expect(t, len(tokens) == 1)
	testing.expect(t, tokens[0].type == .EOF)
}

@(test)
tokenize_invalid_test :: proc(t: ^testing.T) {
	source := "@@123@"
	
	tokens := tokenize_entire_source(source, context.temp_allocator)
	
	testing.expect(t, len(tokens) == 5)
	
	testing.expect(t, tokens[0].type == .Invalid)
	testing.expect(t, tokens[1].type == .Invalid)
	testing.expect(t, tokens[2].type == .Integer_Literal)
	testing.expect(t, tokens[3].type == .Invalid)
	testing.expect(t, tokens[4].type == .EOF)
}