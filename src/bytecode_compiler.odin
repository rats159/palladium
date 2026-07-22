package palladium

import "base:runtime"
import "core:container/xar"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"

Bytecode_Compiler :: struct {
	bytecode:       [dynamic]byte,
	pending_breaks: map[Checked_Statement]int,
	pending_continues: map[Checked_Statement]int,
}

Instruction :: enum u8 {
	Invalid,
	Pop_Bytes,
	Push_Bytes,
	Add_I64,
	Sub_I64,
	Mul_I64,
	Div_I64,
	Invert_Bool,
	Or_Bool,
	And_Bool,
	Store_With_SP_Offset,
	Load_With_SP_Offset,
	Less_Than_I64,
	Less_Than_Or_Equal_To_I64,
	Greater_Than_I64,
	Greater_Than_Or_Equal_To_I64,
	Compare_Bytes,
	Jump,
	Jump_If_False,
	Halt,
}

program_to_bytecode :: proc(program: Checked_Program, allocator: runtime.Allocator) -> []byte {
	program := program
	compiler: Bytecode_Compiler
	compiler.bytecode.allocator = allocator

	for iter := xar.iterator(&program.statements); stmt in xar.iterate_by_val(&iter) {
		statement_to_bytecode(&compiler, stmt)
	}

	emit_instruction(&compiler, .Halt)
	assert(len(compiler.pending_breaks) == 0)
	assert(len(compiler.pending_continues) == 0)
	delete(compiler.pending_breaks)
	delete(compiler.pending_continues)

	return compiler.bytecode[:]
}

statement_to_bytecode :: proc(compiler: ^Bytecode_Compiler, statement: Checked_Statement) {
	switch type in statement {
	case ^Checked_Index_Write:
		checked_index_write_to_bytecode(compiler, type)
	case ^Checked_Variable_Write:
		variable_write_to_bytecode(compiler, type)
	case ^Checked_Expression_Statement:
		checked_expression_statement_to_bytecode(compiler, type)
	case ^Checked_Loop:
		loop_to_bytecode(compiler, type)
	case ^Checked_If:
		if_to_bytecode(compiler, type)
	case ^Checked_Block:
		checked_block_to_bytecode(compiler, type)
	case ^Checked_Declaration:
		declaration_to_bytecode(compiler, type)
	case ^Checked_Break:
		break_to_bytecode(compiler, type)
	case ^Checked_Continue:
		continue_to_bytecode(compiler, type)
	case ^Checked_Return:
		checked_return_to_bytecode(compiler, type)
	}
}

checked_index_write_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Index_Write) {
	unimplemented("Unimplemented expression type")
}

variable_write_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Variable_Write) {
	expression_to_bytecode(compiler, stmt.new_value)
	emit_instruction(compiler, .Store_With_SP_Offset)
	emit_offset(compiler, stmt.target.offset)
	emit_size(compiler, type_size_of(stmt.target.type))
}

checked_expression_statement_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	stmt: ^Checked_Expression_Statement,
) {
	// FUTURE: multi-valued expressions?
	size := expression_to_bytecode(compiler, stmt.expr)
	emit_instruction(compiler, .Pop_Bytes)
	emit_size(compiler, size)
}

loop_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Loop) {
	condition_start := Offset(len(compiler.bytecode))
	expression_to_bytecode(compiler, stmt.condition)
	emit_instruction(compiler, .Jump_If_False)
	loop_end := emit_backpatchable_offset(compiler)
	statement_to_bytecode(compiler, stmt.body)
	emit_instruction(compiler, .Jump)
	emit_offset(compiler, condition_start)
	backpatch_offset(compiler, loop_end)
	end_offset := len(compiler.bytecode)
	for node, offset in compiler.pending_breaks {
		if node == stmt {
			region := compiler.bytecode[offset:offset + size_of(Offset)]
			bytes := transmute([8]byte)end_offset
			copy(region, bytes[:])
			delete_key(&compiler.pending_breaks, node)
		}
	}

	for node, offset in compiler.pending_continues {
		if node == stmt {
			region := compiler.bytecode[offset:offset + size_of(Offset)]
			bytes := transmute([8]byte)condition_start
			copy(region, bytes[:])
			delete_key(&compiler.pending_continues, node)
		}
	}
}

if_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_If) {
	expression_to_bytecode(compiler, stmt.condition)
	emit_instruction(compiler, .Jump_If_False)
	if_end := emit_backpatchable_offset(compiler)
	statement_to_bytecode(compiler, stmt.body)
	if stmt.else_body != nil {
		emit_instruction(compiler, .Jump)
		else_end := emit_backpatchable_offset(compiler)
		backpatch_offset(compiler, if_end)
		statement_to_bytecode(compiler, stmt.else_body.?)
		backpatch_offset(compiler, else_end)
	} else {
		backpatch_offset(compiler, if_end)
	}
}

checked_block_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Block) {
	for iter := xar.iterator(&stmt.statements); substmt in xar.iterate_by_val(&iter) {
		statement_to_bytecode(compiler, substmt)
	}
}

declaration_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Declaration) {
	if stmt.value != nil {
		expression_to_bytecode(compiler, stmt.value.?)
	} else {
		emit_zeroes(compiler, type_size_of(stmt.type))
	}
	emit_instruction(compiler, .Store_With_SP_Offset)
	emit_offset(compiler, stmt.offset)
	emit_size(compiler, type_size_of(stmt.type))
}

break_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Break) {
	emit_instruction(compiler, .Jump)
	offset := emit_backpatchable_offset(compiler)
	compiler.pending_breaks[stmt.target] = offset
}

continue_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Continue) {
	emit_instruction(compiler, .Jump)
	offset := emit_backpatchable_offset(compiler)
	compiler.pending_continues[stmt.target] = offset
}

checked_return_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Return) {
	unimplemented("Unimplemented expression type")
}

expression_to_bytecode :: proc(compiler: ^Bytecode_Compiler, expr: Checked_Expression) -> Size {
	switch type in expr.variant {
	case ^Checked_Binary_Op:
		binary_expression_to_bytecode(compiler, type, expr.type)
	case ^Checked_Array_Index:
		unimplemented("Unhandled expression type")
	case ^Boolean_Node:
		boolean_literal_to_bytecode(compiler, type, expr.type)
	case ^Integer_Node:
		integer_literal_to_bytecode(compiler, type, expr.type)
	case ^Checked_String:
		string_literal_to_bytecode(compiler, type, expr.type)
	case Function:
		unimplemented("Unhandled expression type")
	case ^Checked_Variable_Read:
		variable_read_to_bytecode(compiler, type, expr.type)
	case ^Checked_Call:
		unimplemented("Unhandled expression type")
	case ^Array_Literal:
		array_literal_to_bytecode(compiler, type, expr.type)

	}

	return type_size_of(expr.type)
}

array_literal_to_bytecode :: proc(compiler: ^Compiler, node: ^Array_Literal, type: ^Type) {
	
}

variable_read_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Checked_Variable_Read,
	type: ^Type,
) {
	assert(types_are_equivalent(type, expr.decl.type))
	emit_instruction(compiler, .Load_With_SP_Offset)
	emit_offset(compiler, expr.decl.offset)
	emit_size(compiler, type_size_of(type))
}

string_literal_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Checked_String,
	type: ^Type,
) {
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, size_of(Checked_String))
	emit_checked_string(compiler, expr^)
}


integer_literal_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Integer_Node,
	type: ^Type,
) {
	assert(type_is_integer(type))
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, size_of(i64))
	emit_i64(compiler, expr.value)
}

boolean_literal_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Boolean_Node,
	type: ^Type,
) {
	assert(type_is_boolean(type))
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, size_of(bool))
	emit_bool(compiler, expr.value)
}

binary_expression_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Checked_Binary_Op,
	type: ^Type,
) {
	expression_to_bytecode(compiler, expr.left)
	expression_to_bytecode(compiler, expr.right)

	switch expr.op {
	case .Invalid:
		panic("Invalid operation")
	case .Add_I64:
		emit_instruction(compiler, .Add_I64)
	case .Sub_I64:
		emit_instruction(compiler, .Sub_I64)
	case .Mul_I64:
		emit_instruction(compiler, .Mul_I64)
	case .Div_I64:
		emit_instruction(compiler, .Div_I64)
	case .Less_Than_I64:
		emit_instruction(compiler, .Less_Than_I64)
	case .Less_Than_Or_Equal_To_I64:
		emit_instruction(compiler, .Less_Than_Or_Equal_To_I64)
	case .Greater_Than_I64:
		emit_instruction(compiler, .Greater_Than_I64)
	case .Greater_Than_Or_Equal_To_I64:
		emit_instruction(compiler, .Greater_Than_Or_Equal_To_I64)
	case .Byte_Compare:
		emit_instruction(compiler, .Compare_Bytes)
		emit_size(compiler, type_size_of(expr.left.type))
	case .Negate_Byte_Compare:
		emit_instruction(compiler, .Compare_Bytes)
		emit_size(compiler, type_size_of(expr.left.type))
		emit_instruction(compiler, .Invert_Bool)
	case .Boolean_And:
		emit_instruction(compiler, .And_Bool)
	case .Boolean_Or:
		emit_instruction(compiler, .Or_Bool)
	}
}

emit_instruction :: proc(compiler: ^Bytecode_Compiler, inst: Instruction) {
	append(&compiler.bytecode, byte(inst))
}

emit_size :: proc(compiler: ^Bytecode_Compiler, size: Size) {
	bytes := transmute([8]byte)size
	append(&compiler.bytecode, ..bytes[:])
}

emit_offset :: proc(compiler: ^Bytecode_Compiler, offset: Offset) {
	bytes := transmute([8]byte)offset
	append(&compiler.bytecode, ..bytes[:])
}

emit_backpatchable_offset :: proc(compiler: ^Bytecode_Compiler) -> int {
	at := len(compiler.bytecode)
	bytes := transmute([8]byte)max(Offset)
	append(&compiler.bytecode, ..bytes[:])
	return at
}

backpatch_offset :: proc(compiler: ^Bytecode_Compiler, at: int) {
	region := compiler.bytecode[at:at + size_of(Offset)]
	bytes := transmute([8]byte)len(compiler.bytecode)
	copy(region, bytes[:])
}

emit_i64 :: proc(compiler: ^Bytecode_Compiler, num: i64) {
	bytes := transmute([8]byte)num
	append(&compiler.bytecode, ..bytes[:])
}

emit_bool :: proc(compiler: ^Bytecode_Compiler, val: bool) {
	bytes := transmute([1]byte)val
	append(&compiler.bytecode, ..bytes[:])
}

emit_zeroes :: proc(compiler: ^Bytecode_Compiler, size: Size) {
	resize(&compiler.bytecode, len(compiler.bytecode) + int(size))
}

emit_checked_string :: proc(compiler: ^Bytecode_Compiler, val: Checked_String) {
	bytes := transmute([16]byte)val
	append(&compiler.bytecode, ..bytes[:])
} 

disassemble_bytecode :: proc(bytecode: []byte) {
	vm := VM {
		bytecode = bytecode,
	}
	buffer: strings.Builder
	defer strings.builder_destroy(&buffer)

	fmt.sbprintln(&buffer, ">>> BYTECODE START <<<")
	for vm.instruction_pointer < len(bytecode) {
		inst := decode_instruction(&vm)
		fmt.sbprintf(&buffer, "%03x | %s ", vm.instruction_pointer - 1, inst)
		switch inst {
		case .Invalid:
			panic("Invalid Instruction")
		case .Halt: /*nothing*/
		case .Pop_Bytes:
			fmt.sbprintf(&buffer, "Size: %d", decode_size(&vm))
		case .Push_Bytes:
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Size: %d, Bytes : %v", size, decode_bytes(&vm, size))
		case .Store_With_SP_Offset:
			offset := decode_offset(&vm)
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Offset: %d, Size: %d", offset, size)
		case .Load_With_SP_Offset:
			offset := decode_offset(&vm)
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Offset: %d, Size: %d", offset, size)
		case .Compare_Bytes:
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Size: %d", size)
		case .Jump, .Jump_If_False:
			offset := decode_offset(&vm)
			fmt.sbprintf(&buffer, "Offset: %04x", offset)
		case .Add_I64: /*nothing*/
		case .Sub_I64: /*nothing*/
		case .Mul_I64: /*nothing*/
		case .Div_I64: /*nothing*/
		case .Or_Bool: /*nothing*/
		case .And_Bool: /*nothing*/
		case .Less_Than_I64: /*nothing*/
		case .Less_Than_Or_Equal_To_I64: /*nothing*/
		case .Greater_Than_I64: /*nothing*/
		case .Greater_Than_Or_Equal_To_I64: /*nothing*/
		case .Invert_Bool: /*nothing*/

		}
		fmt.sbprintln(&buffer)
	}
	fmt.sbprintln(&buffer, ">>> BYTECODE END <<<")
	fmt.println(strings.to_string(buffer))
}

