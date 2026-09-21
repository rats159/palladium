package palladium

import "core:container/xar"
import "core:fmt"
import "core:mem"
import "core:slice"

VM :: struct {
	active_bytecode:     []byte,
	instruction_pointer: i64,
	stack:               [dynamic]byte,
	variable_stack:      []byte,
	stack_pointer:       uintptr,
	function_top:        uintptr,
	compiler:            Bytecode_Compiler,
}

Return_Address :: struct {
	chunk_idx:       i64,
	instruction_ptr: i64,
	stack_ptr:       uintptr,
}

Function :: struct {
	parameters:       xar.Array(^Checked_Declaration, 2),
	body:             Checked_Statement,
	stack_frame_size: Size,
	index:            i64,
	name:             string,
}

execute_program :: proc(main_bytecode: []byte, compiler: Bytecode_Compiler) -> VM {
	vm: VM
	vm.active_bytecode = main_bytecode
	vm.compiler = compiler
	vm.variable_stack = make([]byte, mem.Megabyte)
	vm.stack_pointer = uintptr(raw_data(vm.variable_stack))
	vm.function_top = uintptr(raw_data(vm.variable_stack)) + uintptr(compiler.globals_top)

	for execute_instruction(&vm) {}

	return vm
}

execute_instruction :: proc(vm: ^VM) -> bool {
	inst := decode_instruction(vm)
	switch inst {
	case .Invalid:
		panic("Invalid instruction")
	case .Return:
		ret_bytes := pop_bytes(vm, size_of(Return_Address))
		ret := slice.to_type(ret_bytes, Return_Address)
		vm.active_bytecode = xar.get(&vm.compiler.chunks, ret.chunk_idx).bytecode[:]
		vm.instruction_pointer = ret.instruction_ptr
		vm.stack_pointer = ret.stack_ptr
		vm.function_top =
			ret.stack_ptr + uintptr(xar.get(&vm.compiler.chunks, ret.chunk_idx).stack_frame_size)
	case .Halt:
		return false
	case .Call:
		func_id := pop_i64(vm)
		chunk := xar.get(&vm.compiler.chunks, func_id)
		vm.instruction_pointer = 0
		vm.active_bytecode = chunk.bytecode[:]

	case .Memory_Write:
		size := decode_size(vm)
		address := pop_uintptr(vm)
		data := pop_bytes(vm, size)
		mem.copy(rawptr(address), raw_data(data), int(size))
	case .Memory_Read:
		size := decode_size(vm)
		address := pop_uintptr(vm)
		bytes := slice.from_ptr((^byte)(address), int(size))
		append(&vm.stack, ..bytes)
	case .Get_Register:
		reg := decode_register(vm)
		switch reg {
		case .Stack_Pointer:
			push_uintptr(vm, vm.stack_pointer)
		case .Function_Top:
			push_uintptr(vm, vm.function_top)
		case .Global_Base:
			push_uintptr(vm, uintptr(raw_data(vm.variable_stack)))
		case:
			panic("Impossible register")
		}
	case .Set_Register:
		reg := decode_register(vm)
		switch reg {
		case .Stack_Pointer:
			vm.stack_pointer = pop_uintptr(vm)
		case .Function_Top:
			vm.function_top = pop_uintptr(vm)
		case .Global_Base:
			panic("Global base should never be set ??")
		case:
			panic("Impossible register")
		}
	case .Compare_Bytes:
		size := decode_size(vm)
		b := pop_bytes(vm, size)
		a := pop_bytes(vm, size)
		push_bool(vm, slice.equal(a, b))
	case .Pop_Bytes:
		size := decode_size(vm)
		pop_bytes(vm, size)
	case .Push_Bytes:
		size := decode_size(vm)
		bytes := decode_bytes(vm, size)
		push_bytes(vm, bytes)
	case .Jump_If_False:
		destination := decode_offset(vm)
		cond := pop_bool(vm)
		if !cond {vm.instruction_pointer = i64(destination)}
	case .Jump:
		destination := decode_offset(vm)
		vm.instruction_pointer = i64(destination)
	case .Print_I64:
		x := pop_i64(vm)
		fmt.println(x)
	case .Print_String:
		str := pop_string(vm)
		fmt.println(string(str.data[:str.len]))
	case .Print_Function:
		id := pop_i64(vm)
		func := xar.get(&vm.compiler.chunks, id)
		fmt.printfln("<Function '%s' in chunk %d>", func.name, func.index)
	case .Add_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_i64(vm, a + b)
	case .Add_Pointer:
		b := pop_uintptr(vm)
		a := pop_uintptr(vm)
		push_uintptr(vm, a + b)
	case .Sub_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_i64(vm, a - b)
	case .Mul_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_i64(vm, a * b)
	case .Div_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_i64(vm, a / b)
	case .Negate_I64:
		a := pop_i64(vm)
		push_i64(vm, -a)
	case .Or_Bool:
		b := pop_bool(vm)
		a := pop_bool(vm)
		push_bool(vm, a || b)
	case .Invert_Bool:
		a := pop_bool(vm)
		push_bool(vm, !a)
	case .And_Bool:
		b := pop_bool(vm)
		a := pop_bool(vm)
		push_bool(vm, a && b)
	case .Less_Than_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_bool(vm, a < b)
	case .Less_Than_Or_Equal_To_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_bool(vm, a <= b)
	case .Greater_Than_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_bool(vm, a > b)
	case .Greater_Than_Or_Equal_To_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_bool(vm, a >= b)
	}
	return true
}

pop_string :: proc(vm: ^VM) -> Checked_String {
	bytes := vm.stack[len(vm.stack) - size_of(Checked_String):]
	val := slice.to_type(bytes, Checked_String)
	resize(&vm.stack, len(vm.stack) - size_of(Checked_String))
	return val
}

pop_i64 :: proc(vm: ^VM) -> i64 {
	bytes := vm.stack[len(vm.stack) - size_of(i64):]
	val := slice.to_type(bytes, i64)
	resize(&vm.stack, len(vm.stack) - size_of(i64))
	return val
}

pop_uintptr :: proc(vm: ^VM) -> uintptr {
	bytes := vm.stack[len(vm.stack) - size_of(uintptr):]
	val := slice.to_type(bytes, uintptr)
	resize(&vm.stack, len(vm.stack) - size_of(uintptr))
	return val
}


pop_bool :: proc(vm: ^VM) -> bool {
	bytes := vm.stack[len(vm.stack) - size_of(bool):]
	val := slice.to_type(bytes, bool)
	resize(&vm.stack, len(vm.stack) - size_of(bool))
	return val
}

pop_bytes :: proc(vm: ^VM, size: Size) -> []byte {
	bytes := vm.stack[Size(len(vm.stack)) - size:]
	resize(&vm.stack, Size(len(vm.stack)) - size)
	return bytes
}

push_i64 :: proc(vm: ^VM, val: i64) {
	bytes := transmute([8]byte)val
	append(&vm.stack, ..bytes[:])
}

push_uintptr :: proc(vm: ^VM, val: uintptr) {
	bytes := transmute([size_of(uintptr)]byte)val
	append(&vm.stack, ..bytes[:])
}

push_bool :: proc(vm: ^VM, val: bool) {
	bytes := transmute([1]byte)val
	append(&vm.stack, ..bytes[:])
}

push_bytes :: proc(vm: ^VM, bytes: []byte) {
	append(&vm.stack, ..bytes)
}


decode_instruction :: proc(vm: ^VM) -> Instruction {
	inst := Instruction(vm.active_bytecode[vm.instruction_pointer])
	vm.instruction_pointer += 1
	return inst
}

decode_size :: proc(vm: ^VM) -> Size {
	bytes := vm.active_bytecode[vm.instruction_pointer:vm.instruction_pointer + size_of(Size)]
	assert(len(bytes) == size_of(Size))
	vm.instruction_pointer += size_of(Size)
	return slice.to_type(bytes, Size)
}

decode_register :: proc(vm: ^VM) -> Register {
	reg := Register(vm.active_bytecode[vm.instruction_pointer])
	vm.instruction_pointer += 1
	return reg
}

decode_offset :: proc(vm: ^VM) -> Offset {
	bytes := vm.active_bytecode[vm.instruction_pointer:vm.instruction_pointer + size_of(Offset)]
	assert(len(bytes) == size_of(Offset))
	vm.instruction_pointer += size_of(Offset)
	return slice.to_type(bytes, Offset)
}


decode_bytes :: proc(vm: ^VM, n: Size) -> []byte {
	bytes := vm.active_bytecode[vm.instruction_pointer:vm.instruction_pointer + i64(n)]
	vm.instruction_pointer += i64(n)
	return bytes
}

