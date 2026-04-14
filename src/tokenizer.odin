package palladium

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

Token_Type :: enum {
	Invalid = 0,
	Integer_Literal,
	Plus,
	Minus,
	Star,
	Slash,
	Open_Paren,
	Close_Paren,
	Var,
	Identifier,
	EOF,
}

keywords := #partial [Token_Type]string {
	.Var = "var"
}

Token :: struct {
	type:  Token_Type,
	value: string,
}

Tokenizer :: struct {
	token:  Token,
	source: string,
	offset: int,
}

tokenize_entire_source :: proc(source: string, allocator: runtime.Allocator) -> []Token {
	tk := Tokenizer {
		source = source,
	}
	tokens := make([dynamic]Token, allocator)
	for {
		tk_scan(&tk)
		token := tk.token
		append(&tokens, token)
		if token.type == .EOF {
			break
		}
	}

	return tokens[:]
}

tk_current_rune :: proc(tk: ^Tokenizer) -> rune {
	return utf8.rune_at(tk.source, tk.offset)
}

tk_scan :: proc(tk: ^Tokenizer) {
	skip_whitespace(tk)
	switch tk_current_rune(tk) {
	case utf8.RUNE_ERROR:
		tk.token = {
			type  = .EOF,
			value = "<EOF>",
		}
	case 'A' ..= 'Z', 'a' ..= 'z':
		emit_named(tk)
	case '0' ..= '9':
		emit_number(tk)
	case '+':
		emit_basic(tk, .Plus, 1)
	case '-':
		emit_basic(tk, .Minus, 1)
	case '*':
		emit_basic(tk, .Star, 1)
	case '/':
		emit_basic(tk, .Slash, 1)
	case '(':
		emit_basic(tk, .Open_Paren, 1)
	case ')':
		emit_basic(tk, .Close_Paren, 1)
	case:
		emit_invalid_token(tk)
	}
}

emit_named :: proc(tk: ^Tokenizer) {
	start := tk.offset

	outer: for {
		switch tk_current_rune(tk) {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '_':
			tk_advance_rune(tk)
		case:
			break outer
		}
	}
	
	name := tk.source[start:tk.offset]
	
	for kwd, type in keywords {
		if kwd == name {
			tk.token = {
				type = type,
				value = name
			}
			return 
		}
	} 
	
	tk.token = {
		type = .Identifier,
		value = name
	}
}

emit_basic :: proc(tk: ^Tokenizer, type: Token_Type, byte_length: int) {
	tk.token = {
		type  = type,
		value = tk.source[tk.offset:tk.offset + byte_length],
	}
	tk.offset += byte_length
}

tk_is_done :: proc(tk: ^Tokenizer) -> bool {
	return tk.offset > len(tk.source)
}

emit_number :: proc(tk: ^Tokenizer) {
	start := tk.offset
	outer: for {
		switch tk_current_rune(tk) {
		case '0' ..= '9':
			tk_advance_rune(tk)
		case:
			break outer
		}
	}

	str := tk.source[start:tk.offset]

	tk.token = {
		type  = .Integer_Literal,
		value = str,
	}
}

emit_invalid_token :: proc(tk: ^Tokenizer) {
	start := tk.offset
	tk_advance_rune(tk)
	str := tk.source[start:tk.offset]

	tk.token = {
		type  = .Invalid,
		value = str,
	}
}

tk_advance_rune :: proc(tk: ^Tokenizer) {
	_, length := utf8.encode_rune(tk_current_rune(tk))
	tk.offset += length
}

skip_whitespace :: proc(tk: ^Tokenizer) {
	for {
		switch tk_current_rune(tk) {
		case ' ', '\t', '\r', '\n':
			tk_advance_rune(tk)
		case:
			return
		}
	}
}

