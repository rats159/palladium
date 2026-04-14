package palladium

import "base:runtime"
import "core:fmt"
import "core:strconv"

Parser :: struct {
	tokenizer: Tokenizer,
	allocator: runtime.Allocator,
}

Variable_Declaration_Node :: struct {
	name: string,
	value: Node
}

Integer_Node :: struct {
	value: i64,
}

Variable_Read_Node :: struct {
	name: string
}

Binary_Op_Node :: struct {
	left:  Node,
	right: Node,
	op:    Token_Type,
}

Block_Node :: struct {
	statements: []Node
}

Parser_Error_Type :: enum {
	Invalid_Value,
	Failed_Expectation,
}

Parser_Error :: struct {
	type:    Parser_Error_Type,
	message: string,
}

Node :: union {
	^Binary_Op_Node,
	^Integer_Node,
	^Block_Node,
	^Variable_Declaration_Node,
	^Variable_Read_Node
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

parse_statement_list :: proc(p: ^Parser, until: Token_Type) -> (_node: Node, _err: Maybe(Parser_Error)) {
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
	_ = parser_expect(p, .Semicolon) or_return
	
	return expr, nil
} 

make_node :: proc(p: ^Parser, $T: typeid) -> ^T {
	return new(T, p.allocator)
}

// Alias for the lowest-precedence expression
parse_expression :: parse_add

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
		return tk, Parser_Error{
			type = .Failed_Expectation,
			message = fmt.tprintf("Expected %s but recieved %s", type, tk.type)
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

