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
	p := make_parser("1 + 2 + 3")

	ast, err := parse_expression(&p)
	testing.expect_value(t, err, nil)
	bin_op := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	left := expect_and_unwrap(t, bin_op.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, bin_op.right, ^Integer_Node)
	left_left := expect_and_unwrap(t, left.left, ^Integer_Node)
	left_right := expect_and_unwrap(t, left.right, ^Integer_Node)

	testing.expect(t, right.value + left_left.value + left_right.value == 6)
}

@(test)
test_parse_expression_precedence :: proc(t: ^testing.T) {
	p := make_parser("1 + 2 * 3 + 4")

	ast, err := parse_expression(&p)
	testing.expect_value(t, err, nil)
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
	p := make_parser("(1 + 2) * (3 + 4)")
	ast, err := parse_expression(&p)

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
	val := execute_single_expression(t, "1 + 1")
	testing.expect_value(t, val, 2)
}

@(test)
test_order_of_operations :: proc(t: ^testing.T) {
	val := execute_single_expression(t, "1 + 2 * (3 / 4 - 5) * 6")
	testing.expect_value(t, val, 1 + 2 * (3 / 4 - 5) * 6)
}

@(test)
test_associativity :: proc(t: ^testing.T) {
	val := execute_single_expression(t, "1 - 2 - 3 - 4")
	testing.expect_value(t, val, 1 - 2 - 3 - 4)
}

@(test)
test_identifier_tokenizing :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("var xyz 123 foo123_bar variable", context.temp_allocator)

	testing.expect_value(t, len(tokens), 6)
	testing.expect_value(t, tokens[0].type, Token_Type.Var)
	testing.expect_value(t, tokens[1].type, Token_Type.Identifier)
	testing.expect_value(t, tokens[2].type, Token_Type.Integer_Literal)
	testing.expect_value(t, tokens[3].type, Token_Type.Identifier)
	testing.expect_value(t, tokens[4].type, Token_Type.Identifier)
}

@(test)
test_variable_read_parsing :: proc(t: ^testing.T) {
	p := make_parser("x + 12")
	expr, err := parse_expression(&p)
	
	testing.expect_value(t, err, nil)
	
	add := expect_and_unwrap(t, expr, ^Binary_Op_Node)
	
	left := expect_and_unwrap(t, add.left, ^Variable_Read_Node)
	right := expect_and_unwrap(t, add.right, ^Integer_Node)
}

@(test)
test_variable_declaration :: proc(t: ^testing.T) {
	p := make_parser("var xyz1 = 10 + 20;")
	ast, err := parse_statement(&p)
	testing.expect_value(t, err, nil)
	
	var := expect_and_unwrap(t, ast, ^Variable_Declaration_Node)
	testing.expect_value(t, var.name, "xyz1")
	
	value := expect_and_unwrap(t, var.value, ^Binary_Op_Node)
	
	actual_val := evaluate_binary_expression(value)
	testing.expect_value(t, actual_val, 30)
}

@(test)
test_multi_statement :: proc(t: ^testing.T) {
	ast, err := parse_file("1 + 2; 3 + 4; var x = 10 - 3;", context.temp_allocator)
	testing.expect_value(t, err, nil)

	body := expect_and_unwrap(t, ast, ^Block_Node)
	testing.expect_value(t, len(body.statements), 3)
	
	first := expect_and_unwrap(t, body.statements[0], ^Binary_Op_Node)
	second := expect_and_unwrap(t, body.statements[1], ^Binary_Op_Node)
	third := expect_and_unwrap(t, body.statements[2], ^Variable_Declaration_Node)
}

@(private = "file")
expect_and_unwrap :: proc(t: ^testing.T, v: $U, $T: typeid, loc := #caller_location) -> T {
	variant, ok := v.(T)

	testing.expect_value(t, reflect.union_variant_typeid(v), typeid_of(T), loc = loc)
	return variant
}

@(private = "file")
execute_single_expression :: proc(t: ^testing.T, source: string, loc := #caller_location) -> i64 {
	p := make_parser(source)
	ast, err := parse_expression(&p)
	testing.expect_value(t, err, nil, loc = loc)
	return evaluate_expression(ast)
}

@(private = "file")
make_parser :: proc(source: string) -> Parser {
	parser := Parser {
		tokenizer = {source = source},
		allocator = context.temp_allocator,
	}

	parser_advance(&parser)

	return parser
}

