package palladium

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

Token_Type :: enum {
	Invalid = 0,
	Integer_Literal,
	EOF,
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
			type = .EOF,
			value = "<EOF>"
		}
	case '0' ..= '9':
		emit_number(tk)
	case:
		emit_invalid_token(tk)
	}
	
	
}

tk_is_done :: proc(tk: ^Tokenizer) -> bool {
	return tk.offset > len(tk.source)
}

emit_number :: proc(tk: ^Tokenizer) {
	start := tk.offset
	outer: for {
		switch tk_current_rune(tk) {
		case '0'..='9':
			tk_advance_rune(tk)
		case:
			break outer
		}
	}
	
	str := tk.source[start:tk.offset]
	
	tk.token = {
		type = .Integer_Literal,
		value = str
	}
}

emit_invalid_token :: proc(tk: ^Tokenizer) {
	start := tk.offset
	tk_advance_rune(tk)
	str := tk.source[start:tk.offset]
	
	tk.token = {
		type = .Invalid,
		value = str
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

