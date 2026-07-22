package palladium

import "core:container/xar"
import "core:log"
import "core:reflect"
import "core:slice"
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

	ast, err := parse_expression(&p, .None)
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

	ast, err := parse_expression(&p, .None)
	testing.expect_value(t, err, nil)
	bin_op := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	left := expect_and_unwrap(t, bin_op.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, bin_op.right, ^Integer_Node)

	left_left := expect_and_unwrap(t, left.left, ^Integer_Node)
	left_right := expect_and_unwrap(t, left.right, ^Binary_Op_Node)

	left_right_left := expect_and_unwrap(t, left_right.left, ^Integer_Node)
	left_right_right := expect_and_unwrap(t, left_right.right, ^Integer_Node)

	testing.expect(t, bin_op.op == .Addition)
	testing.expect(t, left.op == .Addition)
	testing.expect(t, left_right.op == .Multiplication)

	testing.expect(t, left_left.value == 1)
	testing.expect(t, left_right_left.value == 2)
	testing.expect(t, left_right_right.value == 3)
	testing.expect(t, right.value == 4)
}

@(test)
test_parse_parentheses :: proc(t: ^testing.T) {
	p := make_parser("(1 + 2) * (3 + 4)")
	ast, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	mul := expect_and_unwrap(t, ast, ^Binary_Op_Node)

	testing.expect_value(t, mul.op, Binary_Operation.Multiplication)

	left := expect_and_unwrap(t, mul.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, mul.right, ^Binary_Op_Node)

	testing.expect_value(t, left.op, Binary_Operation.Addition)
	testing.expect_value(t, right.op, Binary_Operation.Addition)
}

@(test)
test_basic_evaluation :: proc(t: ^testing.T) {
	val := execute_single_expression(t, "1 + 1")
	testing.expect_value(t, len(val), 8)
	as_int := slice.to_type(val, i64)
	testing.expect_value(t, as_int, 2)
	delete(val)
}

@(test)
test_order_of_operations :: proc(t: ^testing.T) {
	val := execute_single_expression(t, "1 + 2 * (3 / 4 - 5) * 6")
	testing.expect_value(t, len(val), 8)
	as_int := slice.to_type(val, i64)
	testing.expect_value(t, as_int, 1 + 2 * (3 / 4 - 5) * 6)
	delete(val)
}

@(test)
test_associativity :: proc(t: ^testing.T) {
	val := execute_single_expression(t, "1 - 2 - 3 - 4")
	testing.expect_value(t, len(val), 8)
	as_int := slice.to_type(val, i64)
	testing.expect_value(t, as_int, 1 - 2 - 3 - 4)
	delete(val)
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
	ast, err := parse_file("var x = 10; var y = x + 10; var z = y * y;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.variable_stack)
	defer delete(vm.stack)

	z_slot := find_global_variable_slot(prog, "z")
	testing.expect_value(t, slice.to_type(vm.variable_stack[z_slot:], i64), 400)

}

@(test)
test_variable_declaration :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = 10;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	x := find_global_variable_slot(prog, "x")
	testing.expect_value(t, slice.to_type(vm.variable_stack[x:], i64), 10)
}

@(test)
test_variable_read_parsing :: proc(t: ^testing.T) {
	p := make_parser("x + 12")
	expr, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	add := expect_and_unwrap(t, expr, ^Binary_Op_Node)

	_ = expect_and_unwrap(t, add.left, ^Variable_Read_Node)
	_ = expect_and_unwrap(t, add.right, ^Integer_Node)
}

@(test)
test_variable_declaration_parse :: proc(t: ^testing.T) {
	ast, err := parse_file("var xyz1 = 10 + 20;", context.temp_allocator)
	testing.expect_value(t, err, nil)


	prog := expect_fine_types(t, ast)
	var := expect_and_unwrap(t, xar.get(&prog.statements, 0), ^Checked_Declaration)
	value := expect_and_unwrap(t, var.value.?.variant, ^Checked_Binary_Op)
	testing.expect_value(t, var.name, "xyz1")

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	x := find_global_variable_slot(prog, "xyz1")
	testing.expect_value(t, slice.to_type(vm.variable_stack[x:], i64), 30)
}

@(test)
test_multi_statement :: proc(t: ^testing.T) {
	ast, err := parse_file("1 + 2; 3 + 4; var x = 10 - 3;", context.temp_allocator)
	testing.expect_value(t, err, nil)

	expect_fine_types(t, ast)

	body := expect_and_unwrap(t, ast, ^Block_Node)
	testing.expect_value(t, xar.len(body.statements), 3)

	_ = expect_and_unwrap(t, xar.get(&body.statements, 0), ^Binary_Op_Node)
	_ = expect_and_unwrap(t, xar.get(&body.statements, 1), ^Binary_Op_Node)
	_ = expect_and_unwrap(t, xar.get(&body.statements, 2), ^Variable_Declaration_Node)
}

@(test)
test_assignment_parse :: proc(t: ^testing.T) {
	ast, err := parse_file("x = 10;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	block := expect_and_unwrap(t, ast, ^Block_Node)
	assignment := expect_and_unwrap(t, xar.get(&block.statements, 0), ^Variable_Write_Node)

	testing.expect_value(t, assignment.name, "x")
}

@(test)
test_assignment_run :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x = 10; var y = 20; y = x; x = 30; var z = y + x; x = 15;",
		context.temp_allocator,
	)

	testing.expect_value(t, err, nil)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", 15)
	expect_variable_value(t, prog, vm, "y", 10)
	expect_variable_value(t, prog, vm, "z", 40)
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
	ast, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	str := expect_and_unwrap(t, ast, ^String_Node)

	testing.expect_value(t, str.value, "\n\"\\abc")
}

@(test)
test_string_bad_escape_parsing :: proc(t: ^testing.T) {
	p := make_parser(`"\q\g\p"`)
	_, err := parse_expression(&p, .None)

	testing.expect(t, err != nil)
	testing.expect_value(t, err.?.type, Parser_Error_Type.Invalid_Escape)
}

@(test)
test_string_evaluation :: proc(t: ^testing.T) {
	ast, err := parse_file(`var name: string = "rats";`, context.temp_allocator)

	testing.expect_value(t, err, nil)

	prog := expect_fine_types(t, ast)
	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	name := find_global_variable_slot(prog, "name")
	str_val := slice.to_type(vm.variable_stack[name:], Checked_String)
	testing.expect_value(t, transmute(string)str_val, "rats")
	// var, var_err := read_variable(&rt, "name")
	// expect_nil(t, var_err)

	// expect_values_equal(t, var, "rats")
}

@(test)
test_undeclared_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`x = 10;`, context.temp_allocator)
	expect_nil(t, err)

	_, errs := check_program(ast, context.temp_allocator)
	testing.expect_value(t, len(errs), 1)
	testing.expect_value(t, errs[0].type, Checker_Error_Type.Undeclared)
}

@(test)
test_redeclared_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`var x = 10; var x = 20;`, context.temp_allocator)
	expect_nil(t, err)

	_, errs := check_program(ast, context.temp_allocator)
	testing.expect_value(t, len(errs), 1)
	testing.expect_value(t, errs[0].type, Checker_Error_Type.Redeclaration)
}

@(test)
test_expect_type_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`var x = "abc" - "def";`, context.temp_allocator)
	expect_nil(t, err)

	_, checker_errors := check_program(ast, context.temp_allocator)

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
	ast, err := parse_expression(&p, .None)
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

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", true)
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
	ast, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	and := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, and.op, Binary_Operation.Logical_And)

	left := expect_and_unwrap(t, and.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, and.right, ^Binary_Op_Node)

	testing.expect_value(t, left.op, Binary_Operation.Logical_Or)
	testing.expect_value(t, right.op, Binary_Operation.Logical_Or)

	right_right := expect_and_unwrap(t, right.right, ^Unary_Op_Node)
	testing.expect_value(t, right_right.op, Prefix_Operation.Logical_Not)
}

@(test)
test_bool_op_precedence :: proc(t: ^testing.T) {
	p := make_parser("1 + 1 || 2 * 2")
	ast, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	or := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, or.op, Binary_Operation.Logical_Or)

	left := expect_and_unwrap(t, or.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, or.right, ^Binary_Op_Node)

	testing.expect_value(t, left.op, Binary_Operation.Addition)
	testing.expect_value(t, right.op, Binary_Operation.Multiplication)
}

@(test)
test_bool_op_precedence_2 :: proc(t: ^testing.T) {
	p := make_parser("!a + !b")
	ast, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	or := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, or.op, Binary_Operation.Addition)

	left := expect_and_unwrap(t, or.left, ^Unary_Op_Node)
	right := expect_and_unwrap(t, or.right, ^Unary_Op_Node)

	testing.expect_value(t, left.op, Prefix_Operation.Logical_Not)
	testing.expect_value(t, right.op, Prefix_Operation.Logical_Not)
}

@(test)
test_unary_nesting_parse :: proc(t: ^testing.T) {
	p := make_parser("!!!a")
	ast, err := parse_expression(&p, .None)

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

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)

	expect_variable_value(t, prog, vm, "yes", true)
	expect_variable_value(t, prog, vm, "no", false)
	delete(vm.variable_stack)
	delete(vm.stack)
}

@(test)
test_comparison_op_eval_true :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var l: bool = 2 < 3; var g: bool = 10 > 4; var le: bool = 4 <= 4; var ge: bool = 5 >= 5;",
		context.temp_allocator,
	)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "l", true)
	expect_variable_value(t, prog, vm, "g", true)
	expect_variable_value(t, prog, vm, "le", true)
	expect_variable_value(t, prog, vm, "ge", true)
}

@(test)
test_comparison_op_eval_false :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var l: bool = 20 < 5; var g: bool = 12 > 14; var le: bool = 10 <= 4; var ge: bool = 5 >= 60;",
		context.temp_allocator,
	)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "l", false)
	expect_variable_value(t, prog, vm, "g", false)
	expect_variable_value(t, prog, vm, "le", false)
	expect_variable_value(t, prog, vm, "ge", false)
}

@(test)
test_equality_parse :: proc(t: ^testing.T) {
	p := make_parser("1 || 2 == 3 + 4")
	ast, err := parse_expression(&p, .None)

	testing.expect_value(t, err, nil)

	eq := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, eq.op, Binary_Operation.Equal_To)
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
	ast, err := parse_expression(&p, .None)
	expect_nil(t, err)

	and := expect_and_unwrap(t, ast, ^Binary_Op_Node)
	testing.expect_value(t, and.op, Binary_Operation.Logical_And)

	left := expect_and_unwrap(t, and.left, ^Binary_Op_Node)
	right := expect_and_unwrap(t, and.right, ^Binary_Op_Node)

	testing.expect_value(t, right.op, Binary_Operation.Greater_Than_Or_Equal_To)
	testing.expect_value(t, left.op, Binary_Operation.Logical_Or)
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
	ast, err := parse_file("if true { var a = 5; } else { var b = 10; }", context.temp_allocator)
	expect_nil(t, err)

	expect_fine_types(t, ast)

	body := expect_and_unwrap(t, ast, ^Block_Node)
	_if := expect_and_unwrap(t, xar.get(&body.statements, 0), ^If_Node)
	_ = expect_and_unwrap(t, _if.body, ^Block_Node)
	_ = expect_and_unwrap(t, _if.condition, ^Boolean_Node)
	_ = expect_and_unwrap(t, _if.else_body.?, ^Block_Node)
}

@(test)
test_if_execution :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = 0; if true { x = 1; }", context.temp_allocator)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.variable_stack)
	defer delete(vm.stack)

	expect_variable_value(t, prog, vm, "x", 1)
}

@(test)
test_else_execution :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = 0; if false { x = 1; } else {x = 2; }", context.temp_allocator)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", 2)
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
		"var x  = 1; var y = 10; while y != 0 { x = x * 2; y = y - 1; }",
		context.temp_allocator,
	)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", 1024)
	expect_variable_value(t, prog, vm, "y", 0)
}

@(test)
test_not_equals_parsing :: proc(t: ^testing.T) {
	p := make_parser("x != y")

	ast, err := parse_expression(&p, .None)
	expect_nil(t, err)

	neq := expect_and_unwrap(t, ast, ^Binary_Op_Node)

	testing.expect_value(t, neq.op, Binary_Operation.Not_Equal_To)
}

@(test)
test_blocks_eval :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x = 10; {var y  = 20; { x = y + x; } { x = x * 2; }}",
		context.temp_allocator,
	)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.variable_stack)
	defer delete(vm.stack)

	expect_variable_value(t, prog, vm, "x", 60)
}

@(test)
test_scope_shadowing :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x = 10; { var x = 20; x = x * 2;} x = x + 1;",
		context.temp_allocator,
	)

	expect_nil(t, err)
	prog := expect_fine_types(t, ast)
	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", 11)
}

@(test)
test_scoping :: proc(t: ^testing.T) {
	ast, err := parse_file("{var y = 10;} var x = y;", context.temp_allocator)

	expect_nil(t, err)

	_, errs := check_program(ast, context.temp_allocator)
	testing.expect_value(t, len(errs), 2)
	testing.expect_value(t, errs[0].type, Checker_Error_Type.Undeclared) // Y isn't in the outer scope
	testing.expect_value(t, errs[1].type, Checker_Error_Type.Bad_Conversion) // Invalid type
}

@(test)
test_breaking :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var x = 0;
var y = 10;

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

	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)

	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", 4)
	expect_variable_value(t, prog, vm, "y", 7)
}

@(test)
test_continuing :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var x = 0;
var y = 10;

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

	prog := expect_fine_types(t, ast)
	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)
	defer delete(vm.stack)
	defer delete(vm.variable_stack)

	expect_variable_value(t, prog, vm, "x", 4)
	expect_variable_value(t, prog, vm, "y", 0)
}

@(test)
test_assignment_tk :: proc(t: ^testing.T) {
	tokens := tokenize_entire_source("+==--=**=*/=", context.temp_allocator)

	testing.expect_value(t, len(tokens), 12)
	testing.expect_value(t, tokens[0].type, Token_Type.Plus)
	testing.expect_value(t, tokens[1].type, Token_Type.Double_Equals)
	testing.expect_value(t, tokens[2].type, Token_Type.Minus)
	testing.expect_value(t, tokens[3].type, Token_Type.Minus)
	testing.expect_value(t, tokens[4].type, Token_Type.Equals)
	testing.expect_value(t, tokens[5].type, Token_Type.Star)
	testing.expect_value(t, tokens[6].type, Token_Type.Star)
	testing.expect_value(t, tokens[7].type, Token_Type.Equals)
	testing.expect_value(t, tokens[8].type, Token_Type.Star)
	testing.expect_value(t, tokens[9].type, Token_Type.Slash)
	testing.expect_value(t, tokens[10].type, Token_Type.Equals)
}

@(test)
test_function_parsing :: proc(t: ^testing.T) {
	p := make_parser("function add(a: int, b: int): int { return a + b; }")
	ast, err := parse_statement(&p)

	expect_nil(t, err)

	func := expect_and_unwrap(t, ast, ^Function_Declaration_Node)

	testing.expect_value(t, xar.len(func.parameters), 2)

	body := expect_and_unwrap(t, func.body, ^Block_Node)

	ret := expect_and_unwrap(t, xar.get(&body.statements, 0), ^Return_Node)
}

@(test)
test_function_call_parsing :: proc(t: ^testing.T) {
	p := make_parser("x(y(), a, b())")
	ast, err := parse_expression(&p, .None)

	expect_nil(t, err)

	call := expect_and_unwrap(t, ast, ^Call_Node)
	testing.expect_value(t, xar.len(call.arguments), 3)

	arg_1 := expect_and_unwrap(t, xar.get(&call.arguments, 0), ^Call_Node)
	arg_2 := expect_and_unwrap(t, xar.get(&call.arguments, 1), ^Variable_Read_Node)
	arg_3 := expect_and_unwrap(t, xar.get(&call.arguments, 2), ^Call_Node)
}

@(test)
test_call_chaining :: proc(t: ^testing.T) {
	p := make_parser("x(1)(2)(3)(4)")
	ast, err := parse_expression(&p, .None)

	expect_nil(t, err)

	first := expect_and_unwrap(t, ast, ^Call_Node)
	second := expect_and_unwrap(t, first.callee, ^Call_Node)
	third := expect_and_unwrap(t, second.callee, ^Call_Node)
	fourth := expect_and_unwrap(t, third.callee, ^Call_Node)

	num := expect_and_unwrap(t, xar.get(&first.arguments, 0), ^Integer_Node)

	testing.expect_value(t, num.value, 4)
}

/*@(test)
test_function_definition :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"function add(a: int, b: int): int { return a + b;}",
		context.temp_allocator,
	)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, prog))

	add, read_err := read_variable(&rt, "add")
	expect_nil(t, read_err)
	func := expect_and_unwrap(t, add, Function)
	testing.expect_value(t, xar.len(func.parameters), 2)
	}*/

/*@(test)
test_function_call :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"function add(a: int, b: int): int { return a + b;} var x = add(2,3);",
		context.temp_allocator,
	)
	expect_nil(t, err)

	prog := expect_fine_types(t, ast)

	rt: Runtime
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, prog))

	x, read_err := read_variable(&rt, "x")
	expect_nil(t, read_err)
	expect_values_equal(t, x, 5)
	}*/

@(test)
test_no_inference :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x: int = 1; var y: int = 2; var z: int = x + y;",
		context.temp_allocator,
	)
	expect_nil(t, err)
	expect_fine_types(t, ast)
}

@(test)
test_inference :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = 1; var y = 2; var z = x + y;", context.temp_allocator)
	expect_nil(t, err)
	expect_fine_types(t, ast)
}

@(test)
test_type_disagreement :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var x: int = \"hello\"; var y = 2; var z = x + y;",
		context.temp_allocator,
	)
	expect_nil(t, err)

	_, errs := check_program(ast, context.temp_allocator)
	// x is still treated as int, despite assignment failure
	//  so the rest of the program is fine
	testing.expect_value(t, len(errs), 1)
	testing.expect_value(t, errs[0].type, Checker_Error_Type.Bad_Conversion) // string -> int
}

@(test)
test_compound_parsing :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = {1, 2, 3, 4};", context.temp_allocator)
	expect_nil(t, err)

	block := expect_and_unwrap(t, ast, ^Block_Node)
	decl := expect_and_unwrap(t, xar.get(&block.statements, 0), ^Variable_Declaration_Node)
	comp := expect_and_unwrap(t, decl.value, ^Compound_Node)
	testing.expect_value(t, xar.len(comp.values), 4)
}

@(test)
test_compound_types_failing :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = {1, 2, 3, 4};", context.temp_allocator)
	expect_nil(t, err)

	_, type_errs := check_program(ast, context.temp_allocator)
	testing.expect_value(t, len(type_errs), 2)
	testing.expect_value(t, type_errs[0].type, Checker_Error_Type.Unknowable_Type) // no types
	testing.expect_value(t, type_errs[1].type, Checker_Error_Type.Bad_Conversion) // invalid -> invalid
}

@(test)
test_compound_types_var_type :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: [4]int = {1, 2, 3, 4};", context.temp_allocator)
	expect_nil(t, err)

	expect_fine_types(t, ast)
}

@(test)
test_compound_types_literal_type :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = [4]int{1, 2, 3, 4};", context.temp_allocator)
	expect_nil(t, err)

	expect_fine_types(t, ast)
}

@(test)
test_compound_types_length_mismatch :: proc(t: ^testing.T) {
	ast, err := parse_file("var x: [4]int = {1, 2, 3, 4, 5};", context.temp_allocator)
	expect_nil(t, err)

	_, errs := check_program(ast, context.temp_allocator)
	testing.expect_value(t, len(errs), 1)
	testing.expect_value(t, errs[0].type, Checker_Error_Type.Wrong_Argument_Count) // 5 items to a [4]int
}

@(test)
test_array_type_in_if_parsing :: proc(t: ^testing.T) {
	_, err1 := parse_file("if [2]int {} {1, 2, 3}", context.temp_allocator)
	expect_not_nil(t, err1)
	testing.expect_value(t, err1.?.type, Parser_Error_Type.Not_An_Expression) // the {} are caught by the if

	_, err2 := parse_file("if ([2]int {1, 2}) {}", context.temp_allocator) // parens make it ok
	expect_nil(t, err2)
}

@(test)
test_array_indexing_parsing :: proc(t: ^testing.T) {
	p := make_parser("x[1];")
	ast, err := parse_statement(&p)

	expect_nil(t, err)
	indexer := expect_and_unwrap(t, ast, ^Index_Node)
	target := expect_and_unwrap(t, indexer.base, ^Variable_Read_Node)
	index := expect_and_unwrap(t, indexer.index, ^Integer_Node)
}

@(test)
test_array_indexing_chaining_parsing :: proc(t: ^testing.T) {
	p := make_parser("x[1][2][3];")
	ast, err := parse_statement(&p)

	expect_nil(t, err)
	indexer := expect_and_unwrap(t, ast, ^Index_Node)
	target := expect_and_unwrap(t, indexer.base, ^Index_Node)
	index_1 := expect_and_unwrap(t, indexer.index, ^Integer_Node)
	target_2 := expect_and_unwrap(t, target.base, ^Index_Node)
	index_2 := expect_and_unwrap(t, target.index, ^Integer_Node)
	index_3 := expect_and_unwrap(t, target_2.index, ^Integer_Node)

	testing.expect_value(t, index_1.value, 3)
	testing.expect_value(t, index_2.value, 2)
	testing.expect_value(t, index_3.value, 1)
}

@(test)
test_array_indexing_types :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var double_arr = [4][4]int {
    {1, 2, 3, 4},
    {5, 6, 7, 8},
    {9, 10, 11, 12},
    {13, 14, 15, 16}
};

var row: [4]int = double_arr[0];
var item: int = row[0];`,
		context.temp_allocator,
	)
	expect_nil(t, err)

	expect_fine_types(t, ast)
}

@(test)
test_hint_conversion :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
function first(items: [4]int): int {
    return items[0];
}

var x = first({1, 2, 3, 4});`,
		context.temp_allocator,
	)

	expect_nil(t, err)
	expect_fine_types(t, ast)
}

@(test)
test_indexing_eval :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var double_arr = [4][4]int {
    {1, 2, 3, 4},
    {5, 6, 7, 8},
    {9, 10, 11, 12},
    {13, 14, 15, 16}
};

var row: [4]int = double_arr[0];
var item: int = row[0];`,
		context.temp_allocator,
	)

	expect_nil(t, err)
	prog := expect_fine_types(t, ast)

	bytecode := program_to_bytecode(prog, context.temp_allocator)
	vm := execute_program(bytecode)

	expect_variable_value(t, prog, vm, "item", 1)
}

/*@(test)
test_array_index_assign :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var x = [4]int{1, 2, 3, 4};
x[2] = 5;
var z = x[2];`,
		context.temp_allocator,
	)
	expect_nil(t, err)
	prog := expect_fine_types(t, ast)

	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_file(&rt, prog))

	expect_variable_value(t, &rt, "z", 5)
	}*/

@(test)
test_variable_slots :: proc(t: ^testing.T) {
	ast, err := parse_file(
		"var a = 1; var b = true; var c = true; var d = 1;",
		context.temp_allocator,
	)

	testing.expect_value(t, err, nil)

	prog := expect_fine_types(t, ast)

	a_slot := find_global_variable_slot(prog, "a")
	b_slot := find_global_variable_slot(prog, "b")
	c_slot := find_global_variable_slot(prog, "c")
	d_slot := find_global_variable_slot(prog, "d")
	testing.expect_value(t, a_slot, 0)
	testing.expect_value(t, b_slot, 8)
	testing.expect_value(t, c_slot, 9)
	testing.expect_value(t, d_slot, 16)
}

@(test)
test_variable_slots_with_func :: proc(t: ^testing.T) {
	ast, err := parse_file(
		`
var a = 1; 
var b = true;
var c = true;
function test(): int {
	var a = 1;
	var b = 2;
	var c = 1000;
	return a + b;
} 
var d = 1;
`,
		context.temp_allocator,
	)

	testing.expect_value(t, err, nil)

	prog := expect_fine_types(t, ast)

	a_slot := find_global_variable_slot(prog, "a")
	b_slot := find_global_variable_slot(prog, "b")
	c_slot := find_global_variable_slot(prog, "c")
	test_slot := find_global_variable_slot(prog, "test")
	d_slot := find_global_variable_slot(prog, "d")
	testing.expect_value(t, a_slot, 0)
	testing.expect_value(t, b_slot, 8)
	testing.expect_value(t, c_slot, 9)
	testing.expect_value(t, test_slot, 16)
	testing.expect_value(t, d_slot, 24)
}


@(private = "file")
find_global_variable_slot :: proc(program: Checked_Program, name: string) -> Offset {
	program := program
	for iter := xar.iterator(&program.statements); stmt in xar.iterate_by_val(&iter) {
		decl := stmt.(^Checked_Declaration) or_continue
		if decl.name == name {
			return decl.offset
		}
	}
	log.errorf("No global variable '%s' found", name)
	return max(Offset)
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
) -> []byte {
	p := make_parser(source)
	ast, err := parse_expression(&p, .None)
	testing.expect_value(t, err, nil, loc = loc)

	checker := make_checker(context.temp_allocator)

	push_checker_scope(&checker)

	declare_named_type(&checker, "string", get_type(&checker, Builtin_Type.String_Literal))
	declare_named_type(&checker, "int", get_type(&checker, Builtin_Type.Integer_Literal))
	declare_named_type(&checker, "bool", get_type(&checker, Builtin_Type.Bool_Literal))

	expr := check_expression(&checker, ast, nil)
	if len(checker.errors) != 0 {
		log.errorf("expected 0 type errors, got %v:", len(checker.errors), location = loc)
		for error in checker.errors {
			log.error("    ", error)
		}
	}

	compiler: Bytecode_Compiler
	compiler.bytecode.allocator = context.temp_allocator
	expression_to_bytecode(&compiler, expr)
	append(&compiler.bytecode, byte(Instruction.Halt))
	vm := execute_program(compiler.bytecode[:])
	delete(vm.variable_stack)
	return vm.stack[:]
}

@(private = "file")
make_parser :: proc(source: string) -> Parser {
	parser := Parser {
		tokenizer = {source = source},
		allocator = context.temp_allocator,
		allow_compound_literal = true,
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
	program: Checked_Program,
	vm: VM,
	name: string,
	expected_value: $T,
	loc := #caller_location,
) {
	x := find_global_variable_slot(program, name)
	testing.expect_value(t, slice.to_type(vm.variable_stack[x:], T), expected_value)
}

@(private = "file")
expect_fine_types :: proc(t: ^testing.T, node: Node, loc := #caller_location) -> Checked_Program {
	prog, errs := check_program(node, context.temp_allocator)
	if len(errs) != 0 {
		log.errorf("expected 0 type errors, got %v:", len(errs), location = loc)
		for error in errs {
			log.info(error)
		}

	}
	return prog
}

