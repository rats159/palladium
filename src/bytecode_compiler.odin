package palladium

import "base:runtime"
import "core:container/xar"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"

Bytecode_Compiler :: struct {
	allocator:        runtime.Allocator,
	current_function: ^Function_Chunk,
	chunks:           xar.Array(Function_Chunk, 3),
	globals_top:      Offset,
}

Function_Chunk :: struct {
	bytecode:          [dynamic]byte,
	pending_breaks:    map[Checked_Statement]int,
	pending_continues: map[Checked_Statement]int,
	name: string,
	index: i64,
	stack_frame_size: i64,
}

Instruction :: enum u8 {
	Invalid,
	Pop_Bytes,
	Push_Bytes,
	Add_I64,
	Sub_I64,
	Mul_I64,
	Div_I64,
	Add_Pointer,
	Invert_Bool,
	Or_Bool,
	And_Bool,
	Less_Than_I64,
	Less_Than_Or_Equal_To_I64,
	Greater_Than_I64,
	Greater_Than_Or_Equal_To_I64,
	Compare_Bytes,
	Jump,
	Jump_If_False,
	Memory_Read,
	Memory_Write,
	Get_Register,
	Set_Register,
	Print_I64,
	Print_String,
	Print_Function,
	Call,
	Return,
	Halt,
}

Register :: enum byte {
	Stack_Pointer = 1,
	Function_Top,
	Global_Base,
}

program_to_bytecode :: proc(
	program: Checked_Program,
	allocator: runtime.Allocator,
) -> Bytecode_Compiler {
	program := program
	compiler: Bytecode_Compiler
	compiler.allocator = allocator
	compiler.chunks.allocator = allocator
	compiler.globals_top = program.globals_top
	open_new_function_chunk(&compiler, {
		index = 0,
		name = "$Global",
		stack_frame_size = Size(program.globals_top),
	})

	for iter := xar.iterator(&program.statements); stmt in xar.iterate_by_val(&iter) {
		top_level_declaration_to_bytecode(&compiler, stmt)
	}

	emit_call_main(&compiler, i64(program.main_chunk.?))
	emit_instruction(&compiler, .Halt)

	return compiler
}

emit_call_main :: proc(compiler: ^Bytecode_Compiler, main_chunk_index: i64) {
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, size_of(i64))
	emit_i64(compiler, main_chunk_index)

	total_argument_size: Size = size_of(Return_Address)
	backpatch := emit_return_address(compiler)

	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Function_Top)
	emit_instruction(compiler, .Set_Register)
	emit_register(compiler, .Stack_Pointer)

	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Stack_Pointer)

	emit_instruction(compiler, .Memory_Write)
	emit_size(compiler, total_argument_size)

	emit_instruction(compiler, .Call)
	backpatch_offset(compiler, backpatch)
}

open_new_function_chunk :: proc(compiler: ^Bytecode_Compiler, function: Function) {
	chunk: Function_Chunk
	chunk.bytecode.allocator = compiler.allocator
	chunk.index = function.index
	chunk.stack_frame_size = i64(function.stack_frame_size)
	chunk.name = function.name
	ptr, err := xar.append_and_get_ptr(&compiler.chunks, chunk)
	assert(err == nil, "Allocation error")
	compiler.current_function = ptr
}

end_function_chunk :: proc(compiler: ^Bytecode_Compiler) {
	chunk := compiler.current_function
	compiler.current_function = nil
	assert(len(chunk.pending_breaks) == 0)
	assert(len(chunk.pending_continues) == 0)
	delete(chunk.pending_breaks)
	delete(chunk.pending_continues)
}

top_level_declaration_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	stmt: ^Checked_Declaration,
) {
	assert(stmt.is_global, "Non-global made it into top-level declaration")
	if stmt.value != nil {
		expression_to_bytecode(compiler, stmt.value.?)
	} else {
		emit_zeroes(compiler, type_size_of(stmt.type))
	}

	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Global_Base)
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, Size(size_of(Offset)))
	emit_offset(compiler, stmt.offset)
	emit_instruction(compiler, .Add_I64)
	emit_instruction(compiler, .Memory_Write)
	emit_size(compiler, type_size_of(stmt.type))
}

statement_to_bytecode :: proc(compiler: ^Bytecode_Compiler, statement: Checked_Statement) {
	switch type in statement {
	case ^Checked_Write:
		write_to_bytecode(compiler, type)
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
		return_to_bytecode(compiler, type)
	case ^Checked_Echo:
		echo_to_bytecode(compiler, type)
	}
}

echo_to_bytecode :: proc(compiler: ^Bytecode_Compiler, expr: ^Checked_Echo) {
	assert(ECHO_STATEMENT, "Bad echo in AST")
	assert(expr.flavor != .Invalid)

	expression_to_bytecode(compiler, expr.value)

	switch expr.flavor {
	case .Invalid:
		panic("expr.flavor != .Invalid; Bad instruction flavor")
	case .Integer:
		emit_instruction(compiler, .Print_I64)
	case .String:
		emit_instruction(compiler, .Print_String)
	case .Function:
		emit_instruction(compiler, .Print_Function)
	}
}

expression_to_address_bytecode :: proc(compiler: ^Bytecode_Compiler, expr: Checked_Expression) {
	#partial switch type in expr.variant {
	case ^Checked_Variable_Read:
		variable_read_to_address_bytecode(compiler, type)
	case ^Checked_Array_Index:
		array_index_to_address_bytecode(compiler, type, expr.type)
	case:
		panic("Bad expression made it through checker as an lvalue")
	}
}

array_index_to_address_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Checked_Array_Index,
	element_type: ^Type,
) {
	expression_to_address_bytecode(compiler, expr.array)
	expression_to_bytecode(compiler, expr.index)
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, size_of(Size))
	emit_size(compiler, type_size_of(element_type))
	emit_instruction(compiler, .Mul_I64)
	emit_instruction(compiler, .Add_I64)
}

variable_read_to_address_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Checked_Variable_Read,
) {
	emit_instruction(compiler, .Get_Register)
	if expr.is_global {
		emit_register(compiler, .Global_Base)
	} else {
		emit_register(compiler, .Stack_Pointer)
	}
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, Size(size_of(Offset)))
	emit_offset(compiler, expr.decl.offset)
	emit_instruction(compiler, .Add_Pointer)
}

write_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Write) {
	expression_to_bytecode(compiler, stmt.new_value)
	expression_to_address_bytecode(compiler, stmt.target)

	emit_instruction(compiler, .Memory_Write)
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
	condition_start := Offset(len(compiler.current_function.bytecode))
	expression_to_bytecode(compiler, stmt.condition)
	emit_instruction(compiler, .Jump_If_False)
	loop_end := emit_backpatchable_offset(compiler)
	statement_to_bytecode(compiler, stmt.body)
	emit_instruction(compiler, .Jump)
	emit_offset(compiler, condition_start)
	backpatch_offset(compiler, loop_end)
	end_offset := len(compiler.current_function.bytecode)
	for node, offset in compiler.current_function.pending_breaks {
		if node == stmt {
			region := compiler.current_function.bytecode[offset:offset + size_of(Offset)]
			bytes := transmute([8]byte)end_offset
			copy(region, bytes[:])
			delete_key(&compiler.current_function.pending_breaks, node)
		}
	}

	for node, offset in compiler.current_function.pending_continues {
		if node == stmt {
			region := compiler.current_function.bytecode[offset:offset + size_of(Offset)]
			bytes := transmute([8]byte)condition_start
			copy(region, bytes[:])
			delete_key(&compiler.current_function.pending_continues, node)
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
		emit_instruction(compiler, .Push_Bytes)
		emit_size(compiler, type_size_of(stmt.type))
		emit_zeroes(compiler, type_size_of(stmt.type))
	}
	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Stack_Pointer)
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, Size(size_of(Offset)))
	emit_offset(compiler, stmt.offset)
	emit_instruction(compiler, .Add_I64)
	emit_instruction(compiler, .Memory_Write)
	emit_size(compiler, type_size_of(stmt.type))
}

break_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Break) {
	emit_instruction(compiler, .Jump)
	offset := emit_backpatchable_offset(compiler)
	compiler.current_function.pending_breaks[stmt.target] = offset
}

continue_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Continue) {
	emit_instruction(compiler, .Jump)
	offset := emit_backpatchable_offset(compiler)
	compiler.current_function.pending_continues[stmt.target] = offset
}

return_to_bytecode :: proc(compiler: ^Bytecode_Compiler, stmt: ^Checked_Return) {
	if stmt.val != nil {
		expression_to_bytecode(compiler, stmt.val.?)
	}

	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Stack_Pointer)
	emit_instruction(compiler, .Memory_Read)
	emit_size(compiler, size_of(Return_Address))
	emit_instruction(compiler, .Return)
}

expression_to_bytecode :: proc(compiler: ^Bytecode_Compiler, expr: Checked_Expression) -> Size {
	switch type in expr.variant {
	case ^Checked_Binary_Op:
		binary_expression_to_bytecode(compiler, type, expr.type)
	case ^Checked_Array_Index:
		array_index_to_bytecode(compiler, type, expr.type)
	case ^Boolean_Node:
		boolean_literal_to_bytecode(compiler, type, expr.type)
	case ^Integer_Node:
		integer_literal_to_bytecode(compiler, type, expr.type)
	case ^Checked_String:
		string_literal_to_bytecode(compiler, type, expr.type)
	case Function:
		function_to_bytecode(compiler, type)
	case ^Checked_Variable_Read:
		variable_read_to_bytecode(compiler, type, expr.type)
	case ^Checked_Call:
		call_to_bytecode(compiler, type, expr.type)
	case ^Array_Literal:
		array_literal_to_bytecode(compiler, type, expr.type)
	}

	return type_size_of(expr.type)
}

emit_return_address :: proc(compiler: ^Bytecode_Compiler) -> int {
	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, 16)
	emit_i64(compiler, compiler.current_function.index)
	backpatch_offset := emit_backpatchable_offset(compiler)
	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Stack_Pointer)
	
	return backpatch_offset
}

call_to_bytecode :: proc(compiler: ^Bytecode_Compiler, call: ^Checked_Call, return_type: ^Type) {
	expression_to_bytecode(compiler, call.callee)

	total_argument_size: Size
	backpatch := emit_return_address(compiler)
	total_argument_size += size_of(Return_Address)


	for iter := xar.iterator(&call.arguments); argument in xar.iterate_by_val(&iter) {
		total_argument_size += expression_to_bytecode(compiler, argument)
	}

	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Function_Top)
	emit_instruction(compiler, .Set_Register)
	emit_register(compiler, .Stack_Pointer)

	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Stack_Pointer)

	emit_instruction(compiler, .Memory_Write)
	emit_size(compiler, total_argument_size)

	emit_instruction(compiler, .Call)
	backpatch_offset(compiler, backpatch)
}

function_to_bytecode :: proc(compiler: ^Bytecode_Compiler, func: Function) {
	bod, is_block := func.body.(^Checked_Block)
	assert(is_block, "Function body is not a block?")
	last_func := compiler.current_function

	open_new_function_chunk(compiler, func)
	emit_instruction(compiler, .Get_Register)
	emit_register(compiler, .Stack_Pointer)

	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, Size(size_of(Size)))
	emit_size(compiler, func.stack_frame_size)

	emit_instruction(compiler, .Add_Pointer)

	emit_instruction(compiler, .Set_Register)
	emit_register(compiler, .Function_Top)

	statement_to_bytecode(compiler, func.body)

	end_function_chunk(compiler)
	compiler.current_function = last_func

	emit_instruction(compiler, .Push_Bytes)
	emit_size(compiler, size_of(i64))
	emit_i64(compiler, func.index)
}

array_index_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	node: ^Checked_Array_Index,
	type: ^Type,
) {
	array_index_to_address_bytecode(compiler, node, type)
	emit_instruction(compiler, .Memory_Read)
	emit_size(compiler, type_size_of(type))
}

array_literal_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	node: ^Array_Literal,
	type: ^Type,
) {
	for iter := xar.iterator(&node.body); item in xar.iterate_by_val(&iter) {
		expression_to_bytecode(compiler, item)
	}
}

variable_read_to_bytecode :: proc(
	compiler: ^Bytecode_Compiler,
	expr: ^Checked_Variable_Read,
	type: ^Type,
) {
	assert(types_are_equivalent(type, expr.decl.type))
	variable_read_to_address_bytecode(compiler, expr)

	emit_instruction(compiler, .Memory_Read)
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
	append(&compiler.current_function.bytecode, byte(inst))
}

emit_register :: proc(compiler: ^Bytecode_Compiler, reg: Register) {
	append(&compiler.current_function.bytecode, byte(reg))
}


emit_size :: proc(compiler: ^Bytecode_Compiler, size: Size) {
	bytes := transmute([8]byte)size
	append(&compiler.current_function.bytecode, ..bytes[:])
}

emit_offset :: proc(compiler: ^Bytecode_Compiler, offset: Offset) {
	bytes := transmute([8]byte)offset
	append(&compiler.current_function.bytecode, ..bytes[:])
}

emit_backpatchable_offset :: proc(compiler: ^Bytecode_Compiler) -> int {
	at := len(compiler.current_function.bytecode)
	bytes := transmute([8]byte)max(Offset)
	append(&compiler.current_function.bytecode, ..bytes[:])
	return at
}

backpatch_offset :: proc(compiler: ^Bytecode_Compiler, at: int) {
	region := compiler.current_function.bytecode[at:at + size_of(Offset)]
	bytes := transmute([8]byte)len(compiler.current_function.bytecode)
	copy(region, bytes[:])
}

emit_i64 :: proc(compiler: ^Bytecode_Compiler, num: i64) {
	bytes := transmute([8]byte)num
	append(&compiler.current_function.bytecode, ..bytes[:])
}

emit_bool :: proc(compiler: ^Bytecode_Compiler, val: bool) {
	bytes := transmute([1]byte)val
	append(&compiler.current_function.bytecode, ..bytes[:])
}

emit_zeroes :: proc(compiler: ^Bytecode_Compiler, size: Size) {
	resize(
		&compiler.current_function.bytecode,
		len(compiler.current_function.bytecode) + int(size),
	)
}

emit_checked_string :: proc(compiler: ^Bytecode_Compiler, val: Checked_String) {
	bytes := transmute([16]byte)val
	append(&compiler.current_function.bytecode, ..bytes[:])
}

disassemble_bytecode :: proc(chunk: Function_Chunk) {
	vm := VM {
		active_bytecode = chunk.bytecode[:],
	}
	buffer: strings.Builder
	defer strings.builder_destroy(&buffer)

	fmt.sbprintfln(&buffer, "[[ Function '%s' start ]]", chunk.name)
	for vm.instruction_pointer < i64(len(chunk.bytecode)) {
		inst := decode_instruction(&vm)
		fmt.sbprintf(&buffer, "%03x | %s ", vm.instruction_pointer - 1, inst)
		switch inst {
		case .Invalid: /*nothing*/
		case .Halt: /*nothing*/
		case .Get_Register:
			fmt.sbprintf(&buffer, ": %s", decode_register(&vm))
		case .Set_Register:
			fmt.sbprintf(&buffer, ": %s", decode_register(&vm))
		case .Pop_Bytes:
			fmt.sbprintf(&buffer, "Size: %d", decode_size(&vm))
		case .Push_Bytes:
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Size: %d, Bytes : %v", size, decode_bytes(&vm, size))
		case .Memory_Write:
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Size: %d", size)
		case .Memory_Read:
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Size: %d", size)
		case .Compare_Bytes:
			size := decode_size(&vm)
			fmt.sbprintf(&buffer, "Size: %d", size)
		case .Jump, .Jump_If_False:
			offset := decode_offset(&vm)
			fmt.sbprintf(&buffer, "Offset: %04x", offset)
		case .Call: /*nothing*/
		case .Return: /*nothing*/
		case .Add_I64: /*nothing*/
		case .Sub_I64: /*nothing*/
		case .Mul_I64: /*nothing*/
		case .Div_I64: /*nothing*/
		case .Print_I64: /*nothing*/
		case .Print_String: /*nothing*/
		case .Print_Function: /*nothing*/
		case .Add_Pointer: /*nothing*/
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
	fmt.sbprintln(&buffer, "[[ Function end ]]")
	fmt.eprintln(strings.to_string(buffer))
}

