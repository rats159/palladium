package palladium

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Parser :: struct {
	tokenizer: Tokenizer,
	allocator: runtime.Allocator,
}

Variable_Write_Node :: struct {
	name:  string,
	value: Node,
}

Variable_Declaration_Node :: struct {
	name:  string,
	value: Node,
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

Binary_Op_Node :: struct {
	left:  Node,
	right: Node,
	op:    Token_Type,
}

Block_Node :: struct {
	statements: []Node,
}

Parser_Error_Type :: enum {
	Invalid_Value,
	Invalid_Escape,
	Failed_Expectation,
	Bad_Assignment_Target,
}

Parser_Error :: struct {
	type:    Parser_Error_Type,
	message: string,
}

Node :: union {
	^Binary_Op_Node,
	^Integer_Node,
	^String_Node,
	^Boolean_Node,
	^Block_Node,
	^Variable_Declaration_Node,
	^Variable_Read_Node,
	^Variable_Write_Node,
}

parse_file :: proc(
	source: string,
	allocator: runtime.Allocator,
) -> (
	node: Node,
	err: Maybe(Parser_Error),
) {
	p := Parser {
		tokenizer = {source = source},
		allocator = allocator,
	}

	tk_scan(&p.tokenizer)

	return parse_statement_list(&p, .EOF)
}

parse_statement_list :: proc(
	p: ^Parser,
	until: Token_Type,
) -> (
	_node: Node,
	_err: Maybe(Parser_Error),
) {
	statements := make([dynamic]Node, p.allocator)
	for !parser_match(p, until) {
		statement := parse_statement(p) or_return
		append(&statements, statement)
	}

	node := make_node(p, Block_Node)
	node.statements = statements[:]

	return node, nil
}

parse_statement :: proc(p: ^Parser) -> (_node: Node, _err: Maybe(Parser_Error)) {
	#partial switch parser_current(p).type {
	case .Var:
		return parse_variable_declaration(p)
	}

	return parse_expression_statement(p)
}

parse_variable_declaration :: proc(p: ^Parser) -> (_node: Node, _err: Maybe(Parser_Error)) {
	_ = parser_expect(p, .Var) or_return
	name := parser_expect(p, .Identifier) or_return
	_ = parser_expect(p, .Equals) or_return
	value := parse_expression(p) or_return
	_ = parser_expect(p, .Semicolon) or_return

	node := make_node(p, Variable_Declaration_Node)
	node.name = name.value
	node.value = value

	return node, nil
}

parse_expression_statement :: proc(p: ^Parser) -> (_node: Node, _err: Maybe(Parser_Error)) {
	expr := parse_expression(p) or_return

	if parser_match(p, .Equals) {
		value := parse_expression(p) or_return

		#partial switch type in expr {
		case ^Variable_Read_Node:
			node := make_node(p, Variable_Write_Node)
			node.name = type.name
			node.value = value
			expr = node
		case:
			return {}, Parser_Error{type = .Bad_Assignment_Target, message = fmt.tprintf("Cannot assign to '%s' expressions", reflect.union_variant_typeid(expr))}
		}
	}

	_ = parser_expect(p, .Semicolon) or_return

	return expr, nil
}

make_node :: proc(p: ^Parser, $T: typeid) -> ^T {
	return new(T, p.allocator)
}

// Alias for the lowest-precedence expression
parse_expression :: parse_add

parse_assignment :: proc(p: ^Parser) -> (_node: Node, _err: Maybe(Parser_Error)) {
	assignee := parse_expression(p) or_return

	if parser_match(p, .Equals) {

	}

	return assignee, nil
}

parse_add :: proc(p: ^Parser) -> (node: Node, err: Maybe(Parser_Error)) {
	left := parse_mul(p) or_return

	for op in parser_match_any(p, .Plus, .Minus) {
		right := parse_mul(p) or_return
		new_node := make_node(p, Binary_Op_Node)
		new_node.left = left
		new_node.right = right
		new_node.op = op
		left = new_node
	}

	return left, nil
}

parse_mul :: proc(p: ^Parser) -> (node: Node, err: Maybe(Parser_Error)) {
	left := parse_value(p) or_return

	for op in parser_match_any(p, .Star, .Slash) {
		right := parse_value(p) or_return
		new_node := make_node(p, Binary_Op_Node)
		new_node.left = left
		new_node.right = right
		new_node.op = op
		left = new_node
	}

	return left, nil
}

// leaks on error. use an arena or be okay with leaks
parse_string :: proc(p: ^Parser, value: string) -> (string, Maybe(Parser_Error)) {
	buf := strings.builder_make(0, len(value), p.allocator)

	for i := 0; i < len(value);  /**/{
		char := utf8.rune_at(value, i)
		if char == '\\' {
			i += 1
			escape_char := utf8.rune_at(value, i)
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
				return "", Parser_Error {
					type = .Invalid_Escape,
					message = fmt.tprintf("Invalid escape sequence '\\%c'", escape_char),
				}
			}
		} else {
			size, _ := strings.write_rune(&buf, char)
			i += size
		}
	}

	return strings.to_string(buf), nil
}

parse_integer :: proc(value: string) -> i64 {
	num, ok := strconv.parse_i64(value)
	assert(ok, "Invalid integer literal not caught by parser")
	return num
}

parse_value :: proc(p: ^Parser) -> (node: Node, err: Maybe(Parser_Error)) {
	tok := parser_advance(p)
	#partial switch tok.type {
	case .Integer_Literal:
		num := parse_integer(tok.value)
		node := make_node(p, Integer_Node)
		node.value = num
		return node, nil
	case .True:
		node := make_node(p, Boolean_Node)
		node.value = true
		return node, nil
	case .False:
		node := make_node(p, Boolean_Node)
		node.value = false
		return node, nil
	case .String_Literal:
		str := parse_string(p, tok.value) or_return
		node := make_node(p, String_Node)
		node.value = str
		return node, nil
	case .Identifier:
		node := make_node(p, Variable_Read_Node)
		node.name = tok.value
		return node, nil
	case .Open_Paren:
		expr := parse_expression(p) or_return
		parser_expect(p, .Close_Paren) or_return
		return expr, nil
	}

	return {}, Parser_Error{type = .Invalid_Value, message = fmt.aprintf("Token %s has no value", tok.type)}
}

parser_expect :: proc(p: ^Parser, type: Token_Type) -> (tok: Token, err: Maybe(Parser_Error)) {
	tk := parser_advance(p)
	if tk.type != type {
		return tk, Parser_Error {
			type = .Failed_Expectation,
			message = fmt.tprintf("Expected %s but recieved %s", type, tk.type),
		}
	}

	return tk, nil
}

parser_match_any :: proc(p: ^Parser, types: ..Token_Type) -> (Token_Type, bool) {
	token := parser_current(p)
	for type in types {
		if token.type == type {
			parser_advance(p)
			return type, true
		}
	}

	return {}, false
}

parser_match :: proc(p: ^Parser, type: Token_Type) -> bool {
	token := parser_current(p)
	if token.type == type {
		parser_advance(p)
		return true
	}

	return false
}

parser_advance :: proc(p: ^Parser) -> Token {
	tok := p.tokenizer.token
	tk_scan(&p.tokenizer)
	return tok
}

parser_current :: proc(p: ^Parser) -> Token {
	return p.tokenizer.token
}

