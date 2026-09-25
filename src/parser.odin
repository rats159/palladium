#+vet explicit-allocators
package palladium

import "base:runtime"
import "core:container/xar"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Parser :: struct {
	tokenizer:              Tokenizer,
	token:                  Token,
	allocator:              runtime.Allocator,
	errors:                 [dynamic]Parser_Error,
	allow_compound_literal: bool,
}

Write_Node :: struct {
	left:  Node,
	right: Node,
}

Variable_Declaration_Node :: struct {
	name:  string,
	type:  Maybe(Node),
	value: Maybe(Node),
}

Parameter_Node :: struct {
	name: string,
	type: Node,
}

Function_Declaration_Node :: struct {
	name:        string,
	parameters:  xar.Array(Parameter_Node, 2),
	body:        Node,
	return_type: Node,
}

String_Node :: struct {
	value: string,
}

Integer_Node :: struct {
	value: i64,
}

Boolean_Node :: struct {
	value: bool,
}

Variable_Read_Node :: struct {
	name: string,
}

Compound_Node :: struct {
	values: xar.Array(Node, 4),
	type:   Maybe(Node),
}

Array_Type_Node :: struct {
	length: Node,
	elem:   Node,
}

Index_Node :: struct {
	base:  Node,
	index: Node,
}

Binary_Op_Node :: struct {
	left:  Node,
	right: Node,
	op:    Binary_Operation,
}

Unary_Op_Node :: struct {
	node: Node,
	op:   Prefix_Operation,
}

Block_Node :: struct {
	statements: xar.Array(Node, 4),
}

Parser_Error_Type :: enum {
	Invalid_Value,
	Invalid_Escape,
	Failed_Expectation,
	Not_An_Expression,
}

Parser_Error :: struct {
	type:    Parser_Error_Type,
	offset:  int,
	source:  string,
	path:    string,
	message: string,
}

If_Node :: struct {
	condition: Node,
	body:      Node,
	else_body: Maybe(Node),
}

// FUTURE: labels?
Break_Node :: struct {}
Continue_Node :: struct {}

Return_Node :: struct {
	value: Maybe(Node),
}

While_Node :: struct {
	condition: Node,
	body:      Node,
}

For_Node :: struct {
	iteration_variable: string,
	iterand:            Node,
	body:               Node,
}

Call_Node :: struct {
	callee:    Node,
	arguments: xar.Array(Node, 4),
}

Echo_Node :: struct {
	argument: Node,
}


Node :: union {
	^Binary_Op_Node,
	^Unary_Op_Node,
	^Integer_Node,
	^String_Node,
	^Boolean_Node,
	^Block_Node,
	^Variable_Declaration_Node,
	^Variable_Read_Node,
	^Write_Node,
	^If_Node,
	^While_Node,
	^For_Node,
	^Continue_Node,
	^Break_Node,
	^Function_Declaration_Node,
	^Return_Node,
	^Call_Node,
	^Array_Type_Node,
	^Compound_Node,
	^Index_Node,
	^Echo_Node,
}

Binding_Power :: enum {
	None = 0,
	Equality_Left,
	Equality_Right,
	And_Left,
	And_Right,
	Or_Left,
	Or_Right,
	Comparison_Left,
	Comparison_Right,
	Binary_Plus_Minus_Left,
	Binary_Plus_Minus_Right,
	Binary_Mul_Div_Mod_Left,
	Binary_Mul_Div_Mod_Right,
	Unary_Plus_Minus,
	Logical_Not,
	Call,
}

parse_file :: proc(source: string, path: string, allocator: runtime.Allocator) -> (Node, []Parser_Error) {
	p := Parser {
		tokenizer = {source = source, path = path},
		allocator = allocator,
		allow_compound_literal = true,
	}

	parser_advance(&p)

	node, _ := parse_statements_until(&p, .EOF)
	return node, p.errors[:]
}

parse_statements_until :: proc(p: ^Parser, until: Token_Type) -> (_node: Node, _ok: bool) {
	statements: xar.Array(Node, 4)
	xar.array_init(&statements, p.allocator)
	for !parser_match(p, until) {
		statement, parsed_ok := parse_statement(p)
		if parsed_ok {
			xar.append(&statements, statement)
		} else {
			parser_recover(p)
		}
	}

	node := make_node(p, Block_Node)

	node.statements = statements

	return node, true
}

parser_recover :: proc(p: ^Parser) {
	for {
		#partial switch parser_current(p).type {
		case .EOF:
			return
		case .Semicolon:
			parser_advance(p)
			return
		case:
			parser_advance(p)
		}
	}
}

parse_statement :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	#partial switch parser_current(p).type {
	case .Var:
		return parse_variable_declaration(p)
	case .If:
		return parse_if_statement(p)
	case .While:
		return parse_while_statement(p)
	case .For:
		return parse_for_statement(p)
	case .Continue:
		_ = parser_expect(p, .Continue) or_return
		_ = parser_expect(p, .Semicolon) or_return
		return make_node(p, Continue_Node), true
	case .Break:
		_ = parser_expect(p, .Break) or_return
		_ = parser_expect(p, .Semicolon) or_return
		return make_node(p, Break_Node), true
	case .Open_Curly:
		_ = parser_expect(p, .Open_Curly) or_return
		return parse_statements_until(p, .Close_Curly)
	case .Echo:
		_ = parser_expect(p, .Echo) or_return
		val := parse_expression(p, .None) or_return
		_ = parser_expect(p, .Semicolon) or_return
		node := make_node(p, Echo_Node)
		node.argument = val
		return node, true
	case .Return:
		_ = parser_expect(p, .Return) or_return
		val: Maybe(Node)
		if !parser_match(p, .Semicolon) {
			val = parse_expression(p, .None) or_return
			_ = parser_expect(p, .Semicolon) or_return
		}
		node := make_node(p, Return_Node)
		node.value = val
		return node, true
	case .Function:
		return parse_function_declaration(p)
	}

	return parse_expression_statement(p)
}

parse_type :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	token := parser_current(p)
	if token.type == .Identifier {
		_ = parser_expect(p, .Identifier) or_return
		node := make_node(p, Variable_Read_Node)
		node.name = token.value
		return node, true
	}

	if token.type == .Open_Bracket {
		_ = parser_expect(p, .Open_Bracket) or_return
		// FUTURE: slices
		length := parse_expression(p, .None) or_return
		_ = parser_expect(p, .Close_Bracket) or_return
		element := parse_type(p) or_return
		node := make_node(p, Array_Type_Node)
		node.elem = element
		node.length = length
		return node, true
	}

	parser_error(p, .Invalid_Value, token.position, fmt.tprintf("Token %s cannot begin a type", token.type))
	return {}, false
}

parse_function_declaration :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .Function) or_return
	name := parser_expect(p, .Identifier) or_return

	parameters: xar.Array(Parameter_Node, 2)
	xar.array_init(&parameters, p.allocator)

	_ = parser_expect(p, .Open_Paren) or_return

	for !parser_match(p, .Close_Paren) {
		parameter_name := parser_expect(p, .Identifier) or_return
		_ = parser_expect(p, .Colon) or_return
		type := parse_type(p) or_return
		xar.append(&parameters, Parameter_Node{parameter_name.value, type})
		if parser_match(p, .Close_Paren) {
			break
		}
		_ = parser_expect(p, .Comma) or_return
	}

	_ = parser_expect(p, .Colon) or_return
	type := parse_type(p) or_return

	_ = parser_expect(p, .Open_Curly) or_return
	body := parse_statements_until(p, .Close_Curly) or_return
	// _ = parser_expect(p, .Close_Paren) or_return
	node := make_node(p, Function_Declaration_Node)

	node.body = body
	node.name = name.value
	node.parameters = parameters
	node.return_type = type

	return node, true
}

parse_if_statement :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .If) or_return
	condition: Node
	{
		old_compound_rule := p.allow_compound_literal
		defer p.allow_compound_literal = old_compound_rule
		p.allow_compound_literal = false
		condition = parse_expression(p, .None) or_return
	}

	_ = parser_expect(p, .Open_Curly) or_return
	body := parse_statements_until(p, .Close_Curly) or_return

	else_body: Maybe(Node)

	if parser_match(p, .Else) {
		#partial switch parser_current(p).type {
		case .If:
			else_body = parse_if_statement(p) or_return
		case .Open_Curly:
			_ = parser_expect(p, .Open_Curly) or_return
			else_body = parse_statements_until(p, .Close_Curly) or_return
		case:
			parser_error(
				p,
				.Failed_Expectation,
				parser_current(p).position,
				fmt.tprintf("Token %s does not begin an else block", parser_current(p).type),
			)
			return {}, false
		}
	}

	node := make_node(p, If_Node)

	node.condition = condition
	node.body = body
	node.else_body = else_body

	return node, true
}

parse_for_statement :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .For) or_return
	// FUTURE: C-style for loops

	loop_variable := parser_expect(p, .Identifier) or_return
	_ = parser_expect(p, .In) or_return

	iterand: Node
	{
		old_compound_rule := p.allow_compound_literal
		defer p.allow_compound_literal = old_compound_rule
		p.allow_compound_literal = false
		iterand = parse_expression(p, .None) or_return
	}

	_ = parser_expect(p, .Open_Curly) or_return
	body := parse_statements_until(p, .Close_Curly) or_return

	node := make_node(p, For_Node)

	node.iteration_variable = loop_variable.value
	node.iterand = iterand
	node.body = body

	return node, true
}

parse_while_statement :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .While) or_return
	condition: Node
	{
		old_compound_rule := p.allow_compound_literal
		defer p.allow_compound_literal = old_compound_rule
		p.allow_compound_literal = false
		condition = parse_expression(p, .None) or_return
	}

	_ = parser_expect(p, .Open_Curly) or_return
	body := parse_statements_until(p, .Close_Curly) or_return

	node := make_node(p, While_Node)

	node.condition = condition
	node.body = body

	return node, true
}

parse_variable_declaration :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .Var) or_return
	name := parser_expect(p, .Identifier) or_return

	type: Maybe(Node)
	if parser_match(p, .Colon) {
		type = parse_type(p) or_return
	}

	value: Maybe(Node)
	if parser_match(p, .Equals) {
		value = parse_expression(p, .None) or_return
	}
	_ = parser_expect(p, .Semicolon) or_return

	node := make_node(p, Variable_Declaration_Node)
	node.name = name.value
	node.type = type
	node.value = value

	return node, true
}

parse_expression_statement :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	expr := parse_expression(p, .None) or_return

	if parser_match(p, .Equals) {
		value := parse_expression(p, .None) or_return
		node := make_node(p, Write_Node)
		node.left = expr
		node.right = value
		expr = node
	}

	_ = parser_expect(p, .Semicolon) or_return

	return expr, true
}

make_node :: proc(p: ^Parser, $T: typeid) -> ^T {
	return new(T, p.allocator)
}

is_binary_op :: proc(tt: Token_Type) -> bool {
	@(static, rodata)
	binops := bit_set[Token_Type] {
		.Plus,
		.Minus,
		.Star,
		.Slash,
		.Less,
		.Less_Equals,
		.Greater,
		.Greater_Equals,
		.Double_Equals,
		.Exclamation_Equals,
		.Double_Pipe,
		.Double_Amp,
	}

	return tt in binops
}

is_prefix_op :: proc(tt: Token_Type) -> bool {
	@(static, rodata)
	preops := bit_set[Token_Type]{.Plus, .Minus, .Exclamation_Point}

	return tt in preops
}

Binary_Operation :: enum {
	Invalid = 0,
	Addition,
	Subtraction,
	Multiplication,
	Division,
	Less_Than,
	Less_Than_Or_Equal_To,
	Greater_Than,
	Greater_Than_Or_Equal_To,
	Equal_To,
	Not_Equal_To,
	Logical_And,
	Logical_Or,
}

Prefix_Operation :: enum {
	Invalid = 0,
	Nothingation, // +x does nothing
	Negation,
	Logical_Not,
}

binary_op_types := #partial [Token_Type]Binary_Operation {
	.Plus               = .Addition,
	.Minus              = .Subtraction,
	.Star               = .Multiplication,
	.Slash              = .Division,
	.Less               = .Less_Than,
	.Less_Equals        = .Less_Than_Or_Equal_To,
	.Greater            = .Greater_Than,
	.Greater_Equals     = .Greater_Than_Or_Equal_To,
	.Double_Equals      = .Equal_To,
	.Exclamation_Equals = .Not_Equal_To,
	.Double_Pipe        = .Logical_Or,
	.Double_Amp         = .Logical_And,
}

prefix_op_types := #partial [Token_Type]Prefix_Operation {
	.Plus              = .Nothingation,
	.Minus             = .Negation,
	.Exclamation_Point = .Logical_Not,
}

binary_operator_bp :: proc(op: Binary_Operation) -> (Binding_Power, Binding_Power) {
	switch op {
	case .Invalid:
		panic("Invalid operator")
	case .Addition, .Subtraction:
		return .Binary_Plus_Minus_Left, .Binary_Plus_Minus_Right
	case .Multiplication, .Division:
		return .Binary_Mul_Div_Mod_Left, .Binary_Mul_Div_Mod_Right
	case .Less_Than, .Less_Than_Or_Equal_To, .Greater_Than, .Greater_Than_Or_Equal_To:
		return .Comparison_Left, .Comparison_Right
	case .Equal_To, .Not_Equal_To:
		return .Equality_Left, .Equality_Right
	case .Logical_Or:
		return .Or_Left, .Or_Right
	case .Logical_And:
		return .And_Left, .And_Right
	}
	panic("Invalid operator")
}

prefix_precedence :: proc(t: Prefix_Operation) -> Binding_Power {
	switch t {
	case .Invalid:
		panic("Invalid operator")
	case .Negation, .Nothingation:
		return .Unary_Plus_Minus
	case .Logical_Not:
		return .Logical_Not
	}
	panic("Invalid operator")
}

parse_expression :: proc(p: ^Parser, min_bp: Binding_Power) -> (_node: Node, _ok: bool) {
	lhs := parse_prefix(p, min_bp) or_return

	for {
		op_token := parser_current(p)
		if !is_binary_op(op_token.type) {
			break
		}

		operator := binary_op_types[op_token.type]
		left_bp, right_bp := binary_operator_bp(operator)
		if left_bp < min_bp {
			break
		}
		parser_advance(p)
		rhs := parse_expression(p, right_bp) or_return
		new_left := make_node(p, Binary_Op_Node)
		new_left.left = lhs
		new_left.right = rhs
		new_left.op = operator
		lhs = new_left
	}

	return lhs, true
}

parse_prefix :: proc(p: ^Parser, bp: Binding_Power) -> (_node: Node, _ok: bool) {
	tok := parser_current(p)
	lhs: Node

	if is_prefix_op(tok.type) {
		parser_advance(p)
		op := prefix_op_types[tok.type]
		op_prec := prefix_precedence(op)
		rhs := parse_expression(p, op_prec) or_return
		node := make_node(p, Unary_Op_Node)
		node.op = op
		node.node = rhs
		lhs = node
	} else {
		lhs = parse_value(p) or_return
	}

	return parse_postfix(p, lhs, bp)
}

parse_postfix :: proc(p: ^Parser, lhs: Node, bp: Binding_Power) -> (_node: Node, _ok: bool) {
	lhs := lhs

	for {
		tok := parser_current(p)
		#partial switch tok.type {
		case .Open_Paren:
			lhs = parse_call(p, lhs) or_return
		case .Open_Bracket:
			lhs = parse_index(p, lhs) or_return
		case:
			return lhs, true
		}
	}
}

parse_index :: proc(p: ^Parser, base: Node) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .Open_Bracket) or_return
	old_allow_compound := p.allow_compound_literal
	defer p.allow_compound_literal = old_allow_compound
	p.allow_compound_literal = true

	index := parse_expression(p, .None) or_return
	_ = parser_expect(p, .Close_Bracket) or_return

	new_node := make_node(p, Index_Node)
	new_node.index = index
	new_node.base = base

	return new_node, true
}

parse_call :: proc(p: ^Parser, callee: Node) -> (_node: Node, _ok: bool) {
	_ = parser_expect(p, .Open_Paren) or_return
	arguments: xar.Array(Node, 4)
	xar.array_init(&arguments, p.allocator)
	old_allow_compound := p.allow_compound_literal
	defer p.allow_compound_literal = old_allow_compound
	p.allow_compound_literal = true
	for !parser_match(p, .Close_Paren) {
		name := parse_expression(p, .None) or_return
		xar.append(&arguments, name)
		if parser_match(p, .Close_Paren) {
			break
		}
		_ = parser_expect(p, .Comma) or_return
	}

	new_node := make_node(p, Call_Node)
	new_node.arguments = arguments
	new_node.callee = callee

	return new_node, true
}

// leaks on error. use an arena or be okay with leaks
parse_string :: proc(p: ^Parser, token: Token) -> (_val: string, _ok: bool) {
	buf := strings.builder_make(0, len(token.value), p.allocator)

	for i := 0; i < len(token.value);  /**/{
		char := utf8.rune_at(token.value, i)
		if char == '\\' {
			i += 1
			escape_char := utf8.rune_at(token.value, i)
			switch escape_char {
			case 'n':
				strings.write_byte(&buf, '\n')
				i += 1
			case 't':
				strings.write_byte(&buf, '\t')
				i += 1
			case 'r':
				strings.write_byte(&buf, '\r')
				i += 1
			case '"':
				strings.write_byte(&buf, '"')
				i += 1
			case '\\':
				strings.write_byte(&buf, '\\')
				i += 1
			case:
				parser_error(
					p,
					.Invalid_Escape,
					token.position + i,
					fmt.tprintf("Invalid escape sequence '\\%c'", escape_char),
				)
				return "", false
			}
		} else {
			size, _ := strings.write_rune(&buf, char)
			i += size
		}
	}

	return strings.to_string(buf), true
}

parse_integer :: proc(value: string) -> i64 {
	num, ok := strconv.parse_i64(value)
	assert(ok, "Invalid integer literal not caught by parser")
	return num
}

parse_value :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	tok := parser_current(p)
	parser_advance(p)
	#partial switch tok.type {
	case .Integer_Literal:
		num := parse_integer(tok.value)
		node := make_node(p, Integer_Node)
		node.value = num
		return node, true
	case .True:
		node := make_node(p, Boolean_Node)
		node.value = true
		return node, true
	case .False:
		node := make_node(p, Boolean_Node)
		node.value = false
		return node, true
	case .String_Literal:
		str := parse_string(p, tok) or_return
		node := make_node(p, String_Node)
		node.value = str
		return node, true
	case .Identifier:
		node := make_node(p, Variable_Read_Node)
		node.name = tok.value
		if p.allow_compound_literal && parser_match(p, .Open_Curly) {
			body := parse_compound(p) or_return
			body.(^Compound_Node).type = node
			return body, true
		} else {
			return node, true
		}
	case .Open_Bracket:
		// FUTURE: slices
		length := parse_expression(p, .None) or_return
		_ = parser_expect(p, .Close_Bracket) or_return
		elem_type := parse_type(p) or_return
		if !p.allow_compound_literal {
			parser_error(
				p,
				.Not_An_Expression,
				tok.position,
				fmt.tprint("Found a type where an expression was expected"),
			)
			return {}, false
		}
		_ = parser_expect(p, .Open_Curly) or_return
		body := parse_compound(p) or_return
		type := make_node(p, Array_Type_Node)
		type.elem = elem_type
		type.length = length
		body.(^Compound_Node).type = type
		return body, true

	case .Open_Paren:
		old_allow_compound := p.allow_compound_literal
		defer p.allow_compound_literal = old_allow_compound
		p.allow_compound_literal = true
		expr := parse_expression(p, .None) or_return
		_ = parser_expect(p, .Close_Paren) or_return
		return expr, true
	case .Open_Curly:
		return parse_compound(p)
	}

	if tok.type == .EOF {
		parser_error(
			p,
			.Invalid_Value,
			tok.position,
			fmt.tprintf("Unexpected end of file when parsing expression"),
		)
	} else {
		parser_error(
			p,
			.Invalid_Value,
			tok.position,
			fmt.tprintf("Cannot create a value expression from '%s'", tok.value),
		)
	}

	return {}, false
}

parse_compound :: proc(p: ^Parser) -> (_node: Node, _ok: bool) {
	expressions: xar.Array(Node, 4)
	xar.init(&expressions, p.allocator)

	for !parser_match(p, .Close_Curly) {
		expr := parse_expression(p, .None) or_return
		xar.append(&expressions, expr)
		if parser_match(p, .Close_Curly) {
			break
		}
		_ = parser_expect(p, .Comma) or_return
	}

	node := make_node(p, Compound_Node)
	node.type = nil
	node.values = expressions

	return node, true
}

@(require_results)
parser_expect :: proc(p: ^Parser, type: Token_Type) -> (Token, bool) {
	tk := parser_current(p)
	if tk.type != type {
		parser_error(
			p,
			.Failed_Expectation,
			tk.position,
			fmt.tprintf(
				"Expected %s but recieved %s",
				type,
				token_to_string(tk, context.temp_allocator),
			),
		)
		return tk, false
	}
	parser_advance(p)
	return tk, true
}

parser_match :: proc(p: ^Parser, type: Token_Type) -> bool {
	token := parser_current(p)
	if token.type == type {
		parser_advance(p)
		return true
	}

	return false
}

parser_advance :: proc(p: ^Parser) {
	tok := scan_next_token(&p.tokenizer)
	p.token = tok
}

parser_current :: proc(p: ^Parser) -> Token {
	return p.token
}

parser_error :: proc(p: ^Parser, type: Parser_Error_Type, offset: int, message: string) {
	error := Parser_Error {
		type    = type,
		message = message,
		source = p.tokenizer.source,
		path = p.tokenizer.path,
		offset = offset
	}

	append(&p.errors, error)
}
