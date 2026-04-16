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
	val, val_err := execute_single_expression(t, "1 + 1")
	expect_nil(t, val_err)
	testing.expect_value(t, val, 2)
}

@(test)
test_order_of_operations :: proc(t: ^testing.T) {
	val, val_err := execute_single_expression(t, "1 + 2 * (3 / 4 - 5) * 6")
	expect_nil(t, val_err)
	testing.expect_value(t, val, 1 + 2 * (3 / 4 - 5) * 6)
}

@(test)
test_associativity :: proc(t: ^testing.T) {
	val, val_err := execute_single_expression(t, "1 - 2 - 3 - 4")
	expect_nil(t, val_err)
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
test_read_variable :: proc(t: ^testing.T) {
	ast, err := parse_file("var x = 10; var y = x + 10; var z = y * y;", context.temp_allocator)

	testing.expect_value(t, err, nil)

	rt := Runtime{}
	defer cleanup_runtime(&rt)
	expect_nil(t, execute_statement(&rt, ast))

	val, val_err := read_variable(&rt, "z")
	expect_nil(t, val_err)
	testing.expect_value(t, val, 400)
}

@(test)
test_variable_declaration :: proc(t: ^testing.T) {
	p := make_parser("var x = 10;")
	ast, err := parse_statement(&p)

	testing.expect_value(t, err, nil)

	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_statement(&rt, ast))

	val, read_err := read_variable(&rt, "x")
	expect_nil(t, read_err)
	testing.expect_value(t, val, 10)
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
test_variable_declaration_parse :: proc(t: ^testing.T) {
	p := make_parser("var xyz1 = 10 + 20;")
	ast, err := parse_statement(&p)
	testing.expect_value(t, err, nil)

	var := expect_and_unwrap(t, ast, ^Variable_Declaration_Node)
	testing.expect_value(t, var.name, "xyz1")

	value := expect_and_unwrap(t, var.value, ^Binary_Op_Node)

	rt := Runtime{}

	actual_val, eval_err := evaluate_binary_expression(&rt, value)
	expect_nil(t, eval_err)
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
		"var x = 10; var y = 20; y = x; x = 30; var z = y + x; x = 15;",
		context.temp_allocator,
	)

	testing.expect_value(t, err, nil)

	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_statement(&rt, ast))

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
	p := make_parser(`var name = "rats";`)
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
	ast, err := parse_expression(&p)

	testing.expect(t, err != nil)
	testing.expect_value(t, err.?.type, Parser_Error_Type.Invalid_Escape)
}

@(test)
test_string_evaluation :: proc(t: ^testing.T) {
	ast, err := parse_file(`var name = "rats";`, context.temp_allocator)

	testing.expect_value(t, err, nil)

	rt := Runtime{}
	defer cleanup_runtime(&rt)

	expect_nil(t, execute_statement(&rt, ast))

	var, var_err := read_variable(&rt, "name")
	testing.expect_value(t, var_err, nil)

	testing.expect_value(t, var, "rats")
}

@(test)
test_undeclared_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`x = 10;`, context.temp_allocator)
	expect_nil(t, err)
	
	rt: Runtime
	rt_err := execute_statement(&rt, ast)
	
	testing.expect_value(t, rt_err.?.type, Runtime_Error_Type.Undeclared_Variable)
}

@(test)
test_redeclared_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`var x = 10; var x = 20;`, context.temp_allocator)
	expect_nil(t, err)
	
	rt: Runtime
	defer cleanup_runtime(&rt)
	rt_err := execute_statement(&rt, ast)
	
	testing.expect_value(t, rt_err.?.type, Runtime_Error_Type.Redeclared_Variable)
}

@(test)
test_expect_type_error :: proc(t: ^testing.T) {
	ast, err := parse_file(`var x = "abc" - "def";`, context.temp_allocator)
	expect_nil(t, err)
	
	rt: Runtime
	rt_err := execute_statement(&rt, ast)
	
	testing.expect_value(t, rt_err.?.type, Runtime_Error_Type.Type_Error)
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
    ast, err := parse_file("var x = true;", context.temp_allocator)
    
    expect_nil(t, err)
    
    rt: Runtime
    defer cleanup_runtime(&rt)
    
    rt_err := execute_statement(&rt, ast)
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
    
    left := expect_and_unwrap(t,and.left, ^Binary_Op_Node)
    right := expect_and_unwrap(t,and.right, ^Binary_Op_Node)
    
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
    
    left := expect_and_unwrap(t,or.left, ^Binary_Op_Node)
    right := expect_and_unwrap(t,or.right, ^Binary_Op_Node)
    
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
    
    left := expect_and_unwrap(t,or.left, ^Unary_Op_Node)
    right := expect_and_unwrap(t,or.right, ^Unary_Op_Node)
    
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
    third := expect_and_unwrap(t, second.node, ^Unary_Op_Node)
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
    ast, err := parse_file("var yes = 1 + 3 == 2 + 2; var no = true || false == false && true;", context.temp_allocator)
    expect_nil(t, err)
    
    rt: Runtime
    defer cleanup_runtime(&rt)
    
    expect_nil(t, execute_statement(&rt, ast))
    
    expect_variable_value(t, &rt, "yes", true)
    expect_variable_value(t, &rt, "no", false)
}

@(test)
test_equality_parse :: proc(t: ^testing.T) {
    p := make_parser("1 || 2 == 3 + 4")
    ast, err := parse_expression(&p)
    
    testing.expect_value(t, err, nil)
    
    eq := expect_and_unwrap(t, ast, ^Binary_Op_Node)
    testing.expect_value(t, eq.op, Token_Type.Double_Equals)
}

@(private = "file", require_results)
expect_and_unwrap :: proc(t: ^testing.T, v: $U, $T: typeid, loc := #caller_location) -> T {
	variant, ok := v.(T)

	testing.expect_value(t, reflect.union_variant_typeid(v), typeid_of(T), loc = loc)
	return variant
}

@(private = "file")
execute_single_expression :: proc(
	t: ^testing.T,
	source: string,
	loc := #caller_location,
) -> (Value, Maybe(Runtime_Error)) {
	p := make_parser(source)
	ast, err := parse_expression(&p)
	testing.expect_value(t, err, nil, loc = loc)
	rt := Runtime{}
	defer cleanup_runtime(&rt)
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
expect_nil :: proc(t: ^testing.T, val: $T, loc := #caller_location) {
	testing.expect_value(t, val, nil, loc = loc)
}

@(private = "file")
expect_variable_value :: proc(t: ^testing.T, rt: ^Runtime, name: string, expected_value: Value, loc := #caller_location) {
	val, err := read_variable(rt, name)
	testing.expect_value(t, val, expected_value, loc = loc)
}