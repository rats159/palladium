#+test

package palladium

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:testing"
import "base:intrinsics"

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
	val, val_err := execute_single_expression(t, "1 + 1")
	expect_nil(t, val_err)
	expect_values_equal(t, val, 2)
}

@(test)
test_order_of_operations :: proc(t: ^testing.T) {
	val, val_err := execute_single_expression(t, "1 + 2 * (3 / 4 - 5) * 6")
	expect_nil(t, val_err)
	expect_values_equal(t, val, 1 + 2 * (3 / 4 - 5) * 6)
}

@(test)
test_associativity :: proc(t: ^testing.T) {
	val, val_err := execute_single_expression(t, "1 - 2 - 3 - 4")
	expect_nil(t, val_err)
	expect_values_equal(t, val, 1 - 2 - 3 - 4)
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
test_read_variable :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: int = 10; var y: int = x + 10; var z: int = y * y;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	expect_fine_types(t, ast)
	
	rt := Runtime{}
	defer cleanup_runtime(&rt)
	expect_nil(t, execute_file(&rt, ast))

	val, val_err := read_variable(&rt, "z")
	expect_nil(t, val_err)
	expect_values_equal(t, val, 400)
}

@(test)
test_variable_declaration :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: int = 10;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	expect_fine_types(t, ast)
	
	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	val, read_err := read_variable(&rt, "x")
	expect_nil(t, read_err)
	expect_values_equal(t, val, 10)
}

@(test)
test_variable_read_parsing :: proc(t: ^testing.T) {
	p := make_parser("x + 12")
	expr, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	add := expect_and_unwrap(t, expr, ^Binary_Op_Node)

	_ = expect_and_unwrap(t, add.left, ^Variable_Read_Node)
	_ = expect_and_unwrap(t, add.right, ^Integer_Node)
}

@(test)
test_variable_declaration_parse :: proc(t: ^testing.T) {
	p := make_parser("var xyz1: int = 10 + 20;")
	ast, err := parse_statement(&p)
	testing.expect_value(t, err, nil)

	var := expect_and_unwrap(t, ast, ^Variable_Declaration_Node)
	testing.expect_value(t, var.name, "xyz1")

	value := expect_and_unwrap(t, var.value, ^Binary_Op_Node)

	rt := Runtime{}

	actual_val, eval_err := evaluate_binary_expression(&rt, value)
	expect_nil(t, eval_err)
	expect_values_equal(t, actual_val, 30)
}

@(test)
test_multi_statement :: proc(t: ^testing.T) {
	ast, err := parse_file("1 + 2; 3 + 4; var x: int = 10 - 3;", context.temp_allocator)
	testing.expect_value(t, err, nil)

	expect_fine_types(t, ast)
	
	body := expect_and_unwrap(t, ast, ^Block_Node)
	testing.expect_value(t, len(body.statements), 3)

	_ = expect_and_unwrap(t, body.statements[0], ^Binary_Op_Node)
	_ = expect_and_unwrap(t, body.statements[1], ^Binary_Op_Node)
	_ = expect_and_unwrap(t, body.statements[2], ^Variable_Declaration_Node)
}

@(test)
test_assignment_parse :: proc(t: ^testing.T) {
	ast, err := parse_file("x = 10;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	block := expect_and_unwrap(t, ast, ^Block_Node)
	assignment := expect_and_unwrap(t, block.statements[0], ^Variable_Write_Node)

	testing.expect_value(t, assignment.name, "x")
}

@(test)
test_assignment_run :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x: int = 10; var y: int = 20; y = x; x = 30; var z: int = y + x; x = 15;",
		context.temp_allocator,
	)

	testing.expect_value(t, err, nil)

	expect_fine_types(t, ast)
	
	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 15)
	expect_variable_value(t, &rt, "y", 10)
	expect_variable_value(t, &rt, "z", 40)
}

@(test)
test_string_tokenization :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source(`"foo" "bar" "ba\"z"`, context.temp_allocator)
	testing.expect_value(t, len(tokens), 4)
	testing.expect_value(t, tokens[0], Token{.String_Literal, "foo"})
	testing.expect_value(t, tokens[1], Token{.String_Literal, "bar"})
	testing.expect_value(t, tokens[2], Token{.String_Literal, `ba\"z`})
}

@(test)
test_string_parsing :: proc(t: ^testing.T) {
	p := make_parser(`var name: string = "rats";`)
	ast, err := parse_statement(&p)

	testing.expect_value(t, err, nil)

	var := expect_and_unwrap(t, ast, ^Variable_Declaration_Node)

	str := expect_and_unwrap(t, var.value, ^String_Node)

	testing.expect_value(t, str.value, "rats")
}

@(test)
test_string_escape_parsing :: proc(t: ^testing.T) {
	p := make_parser(`"\n\"\\abc"`)
	ast, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	str := expect_and_unwrap(t, ast, ^String_Node)

	testing.expect_value(t, str.value, "\n\"\\abc")
}

@(test)
test_string_bad_escape_parsing :: proc(t: ^testing.T) {
	p := make_parser(`"\q\g\p"`)
	_, err := parse_expression(&p)

	testing.expect(t, err != nil)
	testing.expect_value(t, err.?.type, Parser_Error_Type.Invalid_Escape)
}

@(test)
test_string_evaluation :: proc(t: ^testing.T) {
	ast, err := parse_file(`var name: string = "rats";`, context.temp_allocator)

	testing.expect_value(t, err, nil)

	expect_fine_types(t, ast)
	
	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	var, var_err := read_variable(&rt, "name")
	expect_nil(t, var_err)

	expect_values_equal(t, var, "rats")
}

@(test)
test_undeclared_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`x = 10;`, context.temp_allocator)
	expect_nil(t, err)

	rt: Runtime
	defer cleanup_runtime(&rt)
	rt_err := execute_statement(&rt, ast)

	testing.expect_value(t, rt_err.(Runtime_Error).type, Runtime_Error_Type.Undeclared_Variable)
}

@(test)
test_redeclared_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`var x: int = 10; var x: int = 20;`, context.temp_allocator)
	expect_nil(t, err)

	expect_fine_types(t, ast)
	
	rt: Runtime
	defer cleanup_runtime(&rt)
	rt_err := execute_statement(&rt, ast)

	testing.expect_value(t, rt_err.(Runtime_Error).type, Runtime_Error_Type.Redeclared_Variable)
}

@(test)
test_expect_type_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`var x: int = "abc" - "def";`, context.temp_allocator)
	expect_nil(t, err)

	checker_errors := check_program(ast, context.temp_allocator)
	
	testing.expect_value(t, len(checker_errors), 2)
	testing.expect_value(t, checker_errors[0].type, Checker_Error_Type.Bad_Operator) // string - string is disallowed
	testing.expect_value(t, checker_errors[1].type, Checker_Error_Type.Bad_Conversion) // int = <invalid> is disallowed
}

@(test)
test_tokenize_booleans :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("true false atrue falsey", context.temp_allocator)
	testing.expect_value(t, len(tokens), 5)

	testing.expect_value(t, tokens[0].type, Token_Type.True)
	testing.expect_value(t, tokens[1].type, Token_Type.False)
	testing.expect_value(t, tokens[2].type, Token_Type.Identifier)
	testing.expect_value(t, tokens[3].type, Token_Type.Identifier)
}

@(test)
test_parse_booleans :: proc(t: ^testing.T) {
	p := make_parser("true + false")
	ast, err := parse_expression(&p)
	expect_nil(t, err)

	add := expect_and_unwrap(t, ast, ^Binary_Op_Node)

	left := expect_and_unwrap(t, add.left, ^Boolean_Node)
	right := expect_and_unwrap(t, add.right, ^Boolean_Node)

	testing.expect_value(t, left.value, true)
	testing.expect_value(t, right.value, false)
}

@(test)
test_evaluate_booleans :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: bool = true;", context.temp_allocator)

	expect_nil(t, err)

	expect_fine_types(t, ast)
	
	rt: Runtime
	defer cleanup_runtime(&rt)

	rt_err := execute_file(&rt, ast)
	expect_nil(t, rt_err)

	expect_variable_value(t, &rt, "x", true)
}

@(test)
test_tokenize_bool_ops :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("|| && !", context.temp_allocator)

	testing.expect_value(t, len(tokens), 4)

	testing.expect_value(t, tokens[0].type, Token_Type.Double_Pipe)
	testing.expect_value(t, tokens[1].type, Token_Type.Double_Amp)
	testing.expect_value(t, tokens[2].type, Token_Type.Exclamation_Point)
}

@(test)
test_parse_bool_ops :: proc(t: ^testing.T) {
	p := make_parser("true || false && false || !false")
	ast, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	and := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, and.op, Token_Type.Double_Amp)

	left := expect_and_unwrap(t, and.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, and.right, ^Binary_Op_Node)

	testing.expect_value(t, left.op, Token_Type.Double_Pipe)
	testing.expect_value(t, right.op, Token_Type.Double_Pipe)

	right_right := expect_and_unwrap(t, right.right, ^Unary_Op_Node)
	testing.expect_value(t, right_right.op, Token_Type.Exclamation_Point)
}

@(test)
test_bool_op_precedence :: proc(t: ^testing.T) {
	p := make_parser("1 + 1 || 2 * 2")
	ast, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	or := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, or.op, Token_Type.Double_Pipe)

	left := expect_and_unwrap(t, or.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, or.right, ^Binary_Op_Node)

	testing.expect_value(t, left.op, Token_Type.Plus)
	testing.expect_value(t, right.op, Token_Type.Star)
}

@(test)
test_bool_op_precedence_2 :: proc(t: ^testing.T) {
	p := make_parser("!a + !b")
	ast, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	or := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, or.op, Token_Type.Plus)

	left := expect_and_unwrap(t, or.left, ^Unary_Op_Node)
	right := expect_and_unwrap(t, or.right, ^Unary_Op_Node)

	testing.expect_value(t, left.op, Token_Type.Exclamation_Point)
	testing.expect_value(t, right.op, Token_Type.Exclamation_Point)
}

@(test)
test_unary_nesting_parse :: proc(t: ^testing.T) {
	p := make_parser("!!!a")
	ast, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	first := expect_and_unwrap(t, ast, ^Unary_Op_Node)
	second := expect_and_unwrap(t, first.node, ^Unary_Op_Node)
	_ = expect_and_unwrap(t, second.node, ^Unary_Op_Node)
}

@(test)
test_single_double_eq_tokenize :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("= == = = =========", context.temp_allocator)
	testing.expect_value(t, len(tokens), 10)

	testing.expect_value(t, tokens[0].type, Token_Type.Equals)
	testing.expect_value(t, tokens[1].type, Token_Type.Double_Equals)
	testing.expect_value(t, tokens[2].type, Token_Type.Equals)
	testing.expect_value(t, tokens[3].type, Token_Type.Equals)
	testing.expect_value(t, tokens[4].type, Token_Type.Double_Equals)
	testing.expect_value(t, tokens[5].type, Token_Type.Double_Equals)
	testing.expect_value(t, tokens[6].type, Token_Type.Double_Equals)
	testing.expect_value(t, tokens[7].type, Token_Type.Double_Equals)
	testing.expect_value(t, tokens[8].type, Token_Type.Equals)
}

@(test)
test_equality_evaluate :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var yes: bool = 1 + 3 == 2 + 2; var no: bool = true || false == false && true;",
		context.temp_allocator,
	)
	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "yes", true)
	expect_variable_value(t, &rt, "no", false)
}

@(test)
test_comparison_op_eval_true :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var l: bool = 2 < 3; var g: bool = 10 > 4; var le: bool = 4 <= 4; var ge: bool = 5 >= 5;",
		context.temp_allocator,
	)
	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "l", true)
	expect_variable_value(t, &rt, "g", true)
	expect_variable_value(t, &rt, "le", true)
	expect_variable_value(t, &rt, "ge", true)
}

@(test)
test_comparison_op_eval_false :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var l: bool = 20 < 5; var g: bool = 12 > 14; var le: bool = 10 <= 4; var ge: bool = 5 >= 60;",
		context.temp_allocator,
	)
	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "l", false)
	expect_variable_value(t, &rt, "g", false)
	expect_variable_value(t, &rt, "le", false)
	expect_variable_value(t, &rt, "ge", false)
}

@(test)
test_equality_parse :: proc(t: ^testing.T) {
	p := make_parser("1 || 2 == 3 + 4")
	ast, err := parse_expression(&p)

	testing.expect_value(t, err, nil)

	eq := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, eq.op, Token_Type.Double_Equals)
}

@(test)
test_comparison_op_tokens :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("><<=>===!=<==!=<<===", context.temp_allocator)

	testing.expect_value(t, len(tokens), 13)

	types := [13]Token_Type {
		.Greater,
		.Less,
		.Less_Equals,
		.Greater_Equals,
		.Double_Equals,
		.Exclamation_Equals,
		.Less_Equals,
		.Equals,
		.Exclamation_Equals,
		.Less,
		.Less_Equals,
		.Double_Equals,
		.EOF,
	}

	for tk, i in tokens {
		testing.expect_value(t, tk.type, types[i])
	}
}

@(test)
test_comparison_op_parsing :: proc(t: ^testing.T) {
	p := make_parser("a < b || b < c && c >= d")
	ast, err := parse_expression(&p)
	expect_nil(t, err)

	and := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, and.op, Token_Type.Double_Amp)

	right := expect_and_unwrap(t, and.right, ^Binary_Op_Node)

	testing.expect_value(t, right.op, Token_Type.Greater_Equals)
}

@(test)
test_if_tokenizing :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("if {} else", context.temp_allocator)

	testing.expect_value(t, len(tokens), 5)

	testing.expect_value(t, tokens[0].type, Token_Type.If)
	testing.expect_value(t, tokens[1].type, Token_Type.Open_Curly)
	testing.expect_value(t, tokens[2].type, Token_Type.Close_Curly)
	testing.expect_value(t, tokens[3].type, Token_Type.Else)
}

@(test)
test_if_parsing :: proc(t: ^testing.T) {
	p := make_parser("if x > 10 { var a: int = 5; } else { var b: int = 10; }")
	ast, err := parse_statement(&p)
	expect_nil(t, err)
	
	expect_fine_types(t, ast)

	_if := expect_and_unwrap(t, ast, ^If_Node)
	_ = expect_and_unwrap(t, _if.body, ^Block_Node)
	_ = expect_and_unwrap(t, _if.condition, ^Binary_Op_Node)
	_ = expect_and_unwrap(t, _if.else_body.?, ^Block_Node)
}

@(test)
test_if_execution :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: int = 0; if true { x = 1; }", context.temp_allocator)
	expect_nil(t, err)
	
	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 1)
}

@(test)
test_else_execution :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: int = 0; if false { x = 1; } else {x = 2; }", context.temp_allocator)
	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 2)
}

@(test)
test_if_else_chaining :: proc(t: ^testing.T) {
	p := make_parser("if x {} else if y {} else if z {}")

	ast, err := parse_statement(&p)
	expect_nil(t, err)

	first := expect_and_unwrap(t, ast, ^If_Node)
	expect_not_nil(t, first.else_body)
	second := expect_and_unwrap(t, first.else_body.?, ^If_Node)
	expect_not_nil(t, second.else_body)
	_ = expect_and_unwrap(t, second.else_body.?, ^If_Node)
}

@(test)
test_while_parsing :: proc(t: ^testing.T) {
	p := make_parser("while 1 + 1 == 2 { x = 10; }")

	ast, err := parse_statement(&p)
	expect_nil(t, err)

	while := expect_and_unwrap(t, ast, ^While_Node)
}


@(test)
test_while_execution :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x : int = 1; var y: int = 10; while y != 0 { x = x * 2; y = y - 1; }",
		context.temp_allocator,
	)
	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	rt_err := execute_file(&rt, ast)
	expect_nil(t, rt_err)

	expect_variable_value(t, &rt, "x", 1024)
	expect_variable_value(t, &rt, "y", 0)
}

@(test)
test_not_equals_parsing :: proc(t: ^testing.T) {
	p := make_parser("x != y")

	ast, err := parse_expression(&p)
	expect_nil(t, err)

	neq := expect_and_unwrap(t, ast, ^Binary_Op_Node)

	testing.expect_value(t, neq.op, Token_Type.Exclamation_Equals)
}

@(test)
test_blocks_eval :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x: int = 10; {var y: int  = 20; { x = y + x; } { x = x * 2; }}",
		context.temp_allocator,
	)
	expect_nil(t, err)
	
	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 60)
}

@(test)
test_scope_shadowing :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x: int = 10; { var x: int = 20; x = x * 2;} x = x + 1;",
		context.temp_allocator,
	)

	expect_nil(t, err)
	
	expect_fine_types(t, ast)


	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 11)
}

@(test)
test_scoping :: proc(t: ^testing.T) {
	ast, err := parse_file("{var y: int = 10;} var x: int = y;", context.temp_allocator)

	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	rt_err := execute_statement(&rt, ast)

	testing.expect_value(t, rt_err.(Runtime_Error).type, Runtime_Error_Type.Undeclared_Variable)
}

@(test)
test_breaking :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var x: int = 0;
var y: int = 10;

while y != 0 {
    x = x + 1;
    if x == 4 {
        break;
    }
    y = y - 1;
}`,
		context.temp_allocator,
	)

	expect_nil(t, err)
	
	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 4)
	expect_variable_value(t, &rt, "y", 7)
}

@(test)
test_continuing :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var x: int = 0;
var y: int = 10;

while y != 0 {
    y = y - 1;
    if x == 4 {
        continue;
    }
    x = x + 1;
}`,
		context.temp_allocator,
	)

	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 4)
	expect_variable_value(t, &rt, "y", 0)
}

@(test)
test_assignment_tk :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("+==--=**=*/=", context.temp_allocator)

	testing.expect_value(t, len(tokens), 9)
	testing.expect_value(t, tokens[0].type, Token_Type.Plus_Equals)
	testing.expect_value(t, tokens[1].type, Token_Type.Equals)
	testing.expect_value(t, tokens[2].type, Token_Type.Minus)
	testing.expect_value(t, tokens[3].type, Token_Type.Minus_Equals)
	testing.expect_value(t, tokens[4].type, Token_Type.Star)
	testing.expect_value(t, tokens[5].type, Token_Type.Star_Equals)
	testing.expect_value(t, tokens[6].type, Token_Type.Star)
	testing.expect_value(t, tokens[7].type, Token_Type.Slash_Equals)
}

@(test)
test_mut_assignment :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: int = 3; x += 3; x *= 4; x -= 3; x /= 3;", context.temp_allocator)

	expect_nil(t, err)

	expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, ast))

	expect_variable_value(t, &rt, "x", 7)
}

@(test)
test_function_parsing :: proc(t: ^testing.T) {
	p := make_parser("function add(a: int, b: int): int { return a + b; }")
	ast, err := parse_statement(&p)

	expect_nil(t, err)

	func := expect_and_unwrap(t, ast, ^Function_Declaration_Node)

	testing.expect_value(t, len(func.parameters), 2)

	body := expect_and_unwrap(t, func.body, ^Block_Node)

	ret := expect_and_unwrap(t, body.statements[0], ^Return_Node)
}

@(test)
test_function_call_parsing :: proc(t: ^testing.T) {
    p := make_parser("x(y(), a, b())")
    ast, err := parse_expression(&p)
    
    expect_nil(t, err)
    
    call := expect_and_unwrap(t, ast, ^Call_Node)
    testing.expect_value(t, len(call.arguments), 3)
    
    arg_1 := expect_and_unwrap(t, call.arguments[0], ^Call_Node)
    arg_2 := expect_and_unwrap(t, call.arguments[1], ^Variable_Read_Node)
    arg_3 := expect_and_unwrap(t, call.arguments[2], ^Call_Node)
}

@(test)
test_call_chaining :: proc(t: ^testing.T) {
    p := make_parser("x(1)(2)(3)(4)")
    ast, err := parse_expression(&p)
    
    expect_nil(t, err)
    
    first := expect_and_unwrap(t, ast, ^Call_Node)
    second := expect_and_unwrap(t, first.callee, ^Call_Node)
    third := expect_and_unwrap(t, second.callee, ^Call_Node)
    fourth := expect_and_unwrap(t, third.callee, ^Call_Node)
    
    num := expect_and_unwrap(t, first.arguments[0], ^Integer_Node)
    
    testing.expect_value(t, num.value, 4)
}

@(test)
test_function_definition :: proc(t: ^testing.T) {
    ast, err := parse_file("function add(a: int, b: int): int { return a + b;}", context.temp_allocator)
    expect_nil(t, err)
    
   	expect_fine_types(t, ast)

    rt: Runtime
    defer cleanup_runtime(&rt)
    
    expect_nil(t, execute_file(&rt, ast))
    
    add, read_err := read_variable(&rt, "add")
    expect_nil(t, read_err)
    func := expect_and_unwrap(t, add, Function)
    testing.expect_value(t, len(func.parameters), 2)
}

@(test)
test_function_call :: proc(t: ^testing.T) {
    ast, err := parse_file("function add(a: int, b: int): int { return a + b;} var x: int = add(2,3);", context.temp_allocator)
    expect_nil(t, err)
    
   	expect_fine_types(t, ast)

    rt: Runtime
    defer cleanup_runtime(&rt)
    
    expect_nil(t, execute_file(&rt, ast))
    
    x, read_err := read_variable(&rt, "x")
    expect_nil(t, read_err)
    expect_values_equal(t, x, 5)
}

@(private = "file", require_results)
expect_and_unwrap :: proc(t: ^testing.T, v: $U, $T: typeid, loc := #caller_location) -> T {
	variant, _ := v.(T)

	testing.expect_value(t, reflect.union_variant_typeid(v), typeid_of(T), loc = loc)
	return variant
}

@(private = "file")
execute_single_expression :: proc(
	t: ^testing.T,
	source: string,
	loc := #caller_location,
) -> (
	Value,
	Runtime_Propagation,
) {
	p := make_parser(source)
	ast, err := parse_expression(&p)
	testing.expect_value(t, err, nil, loc = loc)
	
	checker := make_checker(context.temp_allocator)
	check_expression(&checker, ast)
	if len(checker.errors) != 0 {
		log.errorf("expected 0 type errors, got %v:", len(checker.errors), location=loc)
		for error in checker.errors {
			log.error("    ", error)
		}
	}
	
	rt := Runtime{}
	defer cleanup_runtime(&rt)
	push_scope(&rt)
	defer pop_scope(&rt)
	return evaluate_expression(&rt, ast)
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

@(private = "file")
expect_nil :: proc(
	t: ^testing.T,
	val: $T,
	loc := #caller_location,
	value_expr := #caller_expression(val),
) {
    ok := val == nil
	if !ok {
		log.errorf("expected %v to be nil, recieved %v", value_expr, val, location = loc)
	}
}

@(private = "file")
expect_not_nil :: proc(
	t: ^testing.T,
	value: $T,
	loc := #caller_location,
	value_expr := #caller_expression(value),
) -> bool {
	ok := value != nil
	if !ok {
		log.errorf("expected %v to be non-nil", value_expr, location = loc)
	}
	return ok
}

@(private = "file")
expect_variable_value :: proc(
	t: ^testing.T,
	rt: ^Runtime,
	name: string,
	expected_value: Value,
	loc := #caller_location,
) {
	val, err := read_variable(rt, name)
	expect_nil(t, err, loc = loc)
	expect_values_equal(t, val, expected_value, loc = loc, value_expr = name)
}

@(private = "file")
expect_values_equal :: proc(t: ^testing.T, value, expected: Value, loc := #caller_location, value_expr := #caller_expression(value)) -> bool {
	ok, err := values_equal(value, expected)
	expect_nil(t, err, loc=loc)
	if !ok {
		log.errorf("expected %v to be %v, got %v", value_expr, expected, value, location=loc)
	}
	return ok
}

@(private = "file")
expect_fine_types :: proc(t: ^testing.T, node: Node, loc := #caller_location) {
	errs := check_program(node, context.temp_allocator)
	if len(errs) != 0 {
		log.errorf("expected 0 type errors, got %v:", len(errs), location=loc)
		for error in errs {
			fmt.eprintln("    ", error)
		}
	}
}