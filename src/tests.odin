package palladium

import "core:fmt"
import "core:reflect"
import "core:testing"

@(test)
test_tokenize_numbers :: proc(t: ^testing.T) {
	source := "123 456 789"
	tokens := tokenize_entire_source(source, context.temp_allocator)
	testing.expect(t, len(tokens) == 4)

	for token in tokens[:3] {
		testing.expect(t, token.type == .Integer_Literal)
	}

	testing.expect(t, tokens[len(tokens) - 1].type == .EOF)
}

@(test)
test_tokenize_eof :: proc(t: ^testing.T) {
	source := ""
	tokens := tokenize_entire_source(source, context.temp_allocator)
	testing.expect(t, len(tokens) == 1)
	testing.expect(t, tokens[0].type == .EOF)
}

@(test)
test_tokenize_operators :: proc(t: ^testing.T) {
	source := "1 + 2 +- */"
	tokens := tokenize_entire_source(source, context.temp_allocator)

	testing.expect(t, len(tokens) == 8)
	testing.expect(t, tokens[0].type == .Integer_Literal)
	testing.expect(t, tokens[1].type == .Plus)
	testing.expect(t, tokens[2].type == .Integer_Literal)
	testing.expect(t, tokens[3].type == .Plus)
	testing.expect(t, tokens[4].type == .Minus)
	testing.expect(t, tokens[5].type == .Star)
	testing.expect(t, tokens[6].type == .Slash)
}


@(test)
test_tokenize_invalid :: proc(t: ^testing.T) {
	source := "@@123@"

	tokens := tokenize_entire_source(source, context.temp_allocator)

	testing.expect(t, len(tokens) == 5)

	testing.expect(t, tokens[0].type == .Invalid)
	testing.expect(t, tokens[1].type == .Invalid)
	testing.expect(t, tokens[2].type == .Integer_Literal)
	testing.expect(t, tokens[3].type == .Invalid)
	testing.expect(t, tokens[4].type == .EOF)
}

@(test)
test_parse_valid_expression :: proc(t: ^testing.T) {
	source := "1 + 2 + 3"

	ast, err := parse_file(source, context.temp_allocator)
	testing.expect(t, err == nil)
	bin_op := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	left := expect_and_unwrap(t, bin_op.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, bin_op.right, ^Integer_Node)
	left_left := expect_and_unwrap(t, left.left, ^Integer_Node)
	left_right := expect_and_unwrap(t, left.right, ^Integer_Node)

	testing.expect(t, right.value + left_left.value + left_right.value == 6)
}

@(test)
test_parse_expression_precedence :: proc(t: ^testing.T) {
	source := "1 + 2 * 3 + 4"

	ast, err := parse_file(source, context.temp_allocator)
	testing.expect(t, err == nil)
	bin_op := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	left := expect_and_unwrap(t, bin_op.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, bin_op.right, ^Integer_Node)

	left_left := expect_and_unwrap(t, left.left, ^Integer_Node)
	left_right := expect_and_unwrap(t, left.right, ^Binary_Op_Node)

	left_right_left := expect_and_unwrap(t, left_right.left, ^Integer_Node)
	left_right_right := expect_and_unwrap(t, left_right.right, ^Integer_Node)

	testing.expect(t, bin_op.op == .Plus)
	testing.expect(t, left.op == .Plus)
	testing.expect(t, left_right.op == .Star)

	testing.expect(t, left_left.value == 1)
	testing.expect(t, left_right_left.value == 2)
	testing.expect(t, left_right_right.value == 3)
	testing.expect(t, right.value == 4)
}

@(test)
test_parse_parentheses :: proc(t: ^testing.T) {
	source := "(1 + 2) * (3 + 4)"
	ast, err := parse_file(source, context.temp_allocator)

	testing.expect_value(t, err, nil)

	mul := expect_and_unwrap(t, ast, ^Binary_Op_Node)

	testing.expect_value(t, mul.op, Token_Type.Star)

	left := expect_and_unwrap(t, mul.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, mul.right, ^Binary_Op_Node)

	testing.expect_value(t, left.op, Token_Type.Plus)
	testing.expect_value(t, right.op, Token_Type.Plus)
}

@(test)
test_basic_evaluation :: proc(t: ^testing.T) {
	val := execute_from_source(t, "1 + 1")
	testing.expect_value(t, val, 2)
}

@(test)
test_order_of_operations :: proc(t: ^testing.T) {
	val := execute_from_source(t, "1 + 2 * (3 / 4 - 5) * 6")
	testing.expect_value(t, val, 1 + 2 * (3 / 4 - 5) * 6)
}

@(test)
test_associativity :: proc(t: ^testing.T) {
	val := execute_from_source(t, "1 - 2 - 3 - 4")
	testing.expect_value(t, val, 1 - 2 - 3 - 4)
}

@(test)
identifier_tokenizing :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("var xyz 123 foo_bar variable", context.temp_allocator)
	
	testing.expect_value(t, len(tokens), 6)
	testing.expect_value(t, tokens[0].type, Token_Type.Var)
	testing.expect_value(t, tokens[1].type, Token_Type.Identifier)
	testing.expect_value(t, tokens[2].type, Token_Type.Integer_Literal)
	testing.expect_value(t, tokens[3].type, Token_Type.Identifier)
	testing.expect_value(t, tokens[4].type, Token_Type.Identifier)
}

@(private = "file")
expect_and_unwrap :: proc(t: ^testing.T, v: $U, $T: typeid, loc := #caller_location) -> T {
	variant, ok := v.(T)
	
	testing.expect_value(t, reflect.union_variant_typeid(v), typeid_of(T), loc = loc)
	return variant
}

@(private = "file")
execute_from_source :: proc(t: ^testing.T, source: string) -> i64 {
	ast, err := parse_file(source, context.temp_allocator)
	testing.expect_value(t, err, nil)
	return evaluate_expression(ast)
} 
