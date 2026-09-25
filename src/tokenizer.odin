package palladium

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
	Echo,
	If,
	Else,
	While,
	Continue,
	Break,
	For,
	In,
	Open_Curly,
	Close_Curly,
	Open_Bracket,
	Close_Bracket,
	Function,
	Return,
	Comma,
	Colon,
	EOF,
}

keywords := #partial [Token_Type]string {
	.Var      = "var",
	.True     = "true",
	.False    = "false",
	.If       = "if",
	.Else     = "else",
	.While    = "while",
	.Continue = "continue",
	.Break    = "break",
	.Function = "function",
	.Return   = "return",
	.Echo     = "echo",
	.For      = "for",
	.In       = "in",
}

Token :: struct {
	type:     Token_Type,
	value:    string,
	position: int,
}

Tokenizer :: struct {
	source: string,
	offset: int,
}

tk_current_rune :: proc(tk: ^Tokenizer) -> rune {
	return utf8.rune_at(tk.source, tk.offset)
}

tk_next_rune :: proc(tk: ^Tokenizer, distance: int = 1) -> rune {
	return utf8.rune_at_pos(tk.source[tk.offset:], distance)
}

scan_next_token :: proc(tk: ^Tokenizer) -> Token {
	skip_whitespace(tk)

	if tk.offset >= len(tk.source) {
		return {type = .EOF, value = "<EOF>", position = tk.offset}
	}

	switch tk_current_rune(tk) {
	case 'A' ..= 'Z', 'a' ..= 'z', '_':
		return scan_word_token(tk)
	case '"':
		return scan_string_token(tk)
	case '0' ..= '9':
		return scan_number_token(tk)
	case '+':
		return scan_simple_token(tk, .Plus, 1)
	case '-':
		return scan_simple_token(tk, .Minus, 1)
	case '*':
		return scan_simple_token(tk, .Star, 1)
	case '/':
		return scan_simple_token(tk, .Slash, 1)
	case '(':
		return scan_simple_token(tk, .Open_Paren, 1)
	case ')':
		return scan_simple_token(tk, .Close_Paren, 1)
	case '{':
		return scan_simple_token(tk, .Open_Curly, 1)
	case '}':
		return scan_simple_token(tk, .Close_Curly, 1)
	case '[':
		return scan_simple_token(tk, .Open_Bracket, 1)
	case ']':
		return scan_simple_token(tk, .Close_Bracket, 1)
	case ';':
		return scan_simple_token(tk, .Semicolon, 1)
	case ':':
		return scan_simple_token(tk, .Colon, 1)
	case ',':
		return scan_simple_token(tk, .Comma, 1)
	case '!':
		if tk_next_rune(tk) == '=' {
			return scan_simple_token(tk, .Exclamation_Equals, 2)
		} else {
			return scan_simple_token(tk, .Exclamation_Point, 1)
		}
	case '=':
		if tk_next_rune(tk) == '=' {
			return scan_simple_token(tk, .Double_Equals, 2)
		} else {
			return scan_simple_token(tk, .Equals, 1)
		}
	case '|':
		if tk_next_rune(tk) == '|' {
			return scan_simple_token(tk, .Double_Pipe, 2)
		} else {
			return scan_invalid_token(tk)
		}
	case '&':
		if tk_next_rune(tk) == '&' {
			return scan_simple_token(tk, .Double_Amp, 2)
		} else {
			return scan_invalid_token(tk)
		}
	case '>':
		if tk_next_rune(tk) == '=' {
			return scan_simple_token(tk, .Greater_Equals, 2)
		} else {
			return scan_simple_token(tk, .Greater, 1)
		}
	case '<':
		if tk_next_rune(tk) == '=' {
			return scan_simple_token(tk, .Less_Equals, 2)
		} else {
			return scan_simple_token(tk, .Less, 1)
		}
	case:
		return scan_invalid_token(tk)
	}
}

scan_string_token :: proc(tk: ^Tokenizer) -> Token {
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

	return {type = .String_Literal, value = str, position = start}
}

scan_word_token :: proc(tk: ^Tokenizer) -> Token {
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
			return {type = type, value = name, position = start}
		}
	}

	return {type = .Identifier, value = name, position = start}
}

scan_simple_token :: proc(tk: ^Tokenizer, type: Token_Type, byte_length: int) -> Token {
	defer tk.offset += byte_length
	return {
		type = type,
		value = tk.source[tk.offset:tk.offset + byte_length],
		position = tk.offset,
	}
}

scan_number_token :: proc(tk: ^Tokenizer) -> Token {
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

	return {type = .Integer_Literal, value = str, position = start}
}

scan_invalid_token :: proc(tk: ^Tokenizer) -> Token {
	start := tk.offset
	tk_advance_rune(tk)
	str := tk.source[start:tk.offset]

	return {type = .Invalid, value = str, position = start}
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
		case '/':
			if tk_next_rune(tk) == '/' {
				skip_comment(tk)
			}
		case:
			return
		}
	}
}

skip_comment :: proc(tk: ^Tokenizer) {
	outer: for {
		switch tk_current_rune(tk) {
		case '\r', '\n', utf8.RUNE_ERROR:
			break outer
		case:
			tk_advance_rune(tk)
		}
	}
}
