package palladium

import "base:runtime"
import "core:unicode/utf8"

Token_Type :: enum {
	Invalid = 0,
	Integer_Literal,
	String_Literal,
	Equals,
	Plus,
	Minus,
	Star,
	Slash,
	Open_Paren,
	Close_Paren,
	Semicolon,
	Var,
	True,
	False,
	Double_Pipe,
	Double_Amp,
	Exclamation_Point,
	Double_Equals,
	Less,
	Greater,
	Less_Equals,
	Greater_Equals,
	Exclamation_Equals,
	Identifier,
	If,
	Else,
	While,
	Open_Curly,
	Close_Curly,
	EOF,
}

keywords := #partial [Token_Type]string {
	.Var   = "var",
	.True  = "true",
	.False = "false",
	.If    = "if",
	.Else  = "else",
	.While = "while"
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

tk_next_rune :: proc(tk: ^Tokenizer, distance: int = 1) -> rune {
	return utf8.rune_at_pos(tk.source[tk.offset:], distance)
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
	case '"':
		emit_string(tk)
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
	case '{':
		emit_basic(tk, .Open_Curly, 1)
	case '}':
		emit_basic(tk, .Close_Curly, 1)
	case ';':
		emit_basic(tk, .Semicolon, 1)
	case '!':
		if tk_next_rune(tk) == '=' {
			emit_basic(tk, .Exclamation_Equals, 2)
		} else {
			emit_basic(tk, .Exclamation_Point, 1)
		}
	case '=':
		if tk_next_rune(tk) == '=' {
			emit_basic(tk, .Double_Equals, 2)
		} else {
			emit_basic(tk, .Equals, 1)
		}
	case '|':
		if tk_next_rune(tk) == '|' {
			emit_basic(tk, .Double_Pipe, 2)
		} else {
			emit_invalid_token(tk)
		}
	case '&':
		if tk_next_rune(tk) == '&' {
			emit_basic(tk, .Double_Amp, 2)
		} else {
			emit_invalid_token(tk)
		}
	case '>':
		if tk_next_rune(tk) == '=' {
			emit_basic(tk, .Greater_Equals, 2)
		} else {
			emit_basic(tk, .Greater, 1)
		}
	case '<':
		if tk_next_rune(tk) == '=' {
			emit_basic(tk, .Less_Equals, 2)
		} else {
			emit_basic(tk, .Less, 1)
		}
	case:
		emit_invalid_token(tk)
	}
}

emit_string :: proc(tk: ^Tokenizer) {
	tk_advance_rune(tk)
	start := tk.offset

	outer: for {
		switch tk_current_rune(tk) {
		case '"':
			break outer
		case '\\':
			// real escape sequences are
			//   handled in the parser.
			// this just catches \"
			tk_advance_rune(tk)
			tk_advance_rune(tk)
		case:
			tk_advance_rune(tk)
		}
	}

	end := tk.offset
	tk_advance_rune(tk)

	str := tk.source[start:end]

	tk.token = {
		type  = .String_Literal,
		value = str,
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
				type  = type,
				value = name,
			}
			return
		}
	}

	tk.token = {
		type  = .Identifier,
		value = name,
	}
}

emit_basic :: proc(tk: ^Tokenizer, type: Token_Type, byte_length: int) {
	tk.token = {
		type  = type,
		value = tk.source[tk.offset:tk.offset + byte_length],
	}
	tk.offset += byte_length
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

