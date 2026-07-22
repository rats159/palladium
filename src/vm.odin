package palladium

import "core:mem"
import "core:slice"
VM :: struct {
	bytecode:            []byte,
	instruction_pointer: int,
	stack:               [dynamic]byte,
	variable_stack:      []byte,
	stack_stack:         [dynamic]Offset,
}

execute_program :: proc(bytecode: []byte) -> VM {
	vm: VM
	vm.bytecode = bytecode
	vm.variable_stack = make([]byte, mem.Megabyte)
	append(&vm.stack_stack, 0)

	for execute_instruction(&vm) {}

	delete(vm.stack_stack)
	return vm
}

execute_instruction :: proc(vm: ^VM) -> bool {
	inst := decode_instruction(vm)
	switch inst {
	case .Invalid:
		panic("Invalid instruction")
	case .Halt:
		return false
	case .Store_With_SP_Offset:
		offset := decode_offset(vm)
		size := decode_size(vm)
		actual_address := vm.stack_stack[len(vm.stack_stack) - 1] + offset
		assert(Size(len(vm.variable_stack[actual_address:])) >= size, "Stack overflow!")
		copy(vm.variable_stack[actual_address:], vm.stack[Size(len(vm.stack)) - size:])
	case .Load_With_SP_Offset:
		offset := decode_offset(vm)
		size := decode_size(vm)
		actual_address := vm.stack_stack[len(vm.stack_stack) - 1] + offset
		data := vm.variable_stack[actual_address:actual_address + Offset(size)]
		append(&vm.stack, ..data)
	case .Compare_Bytes:
		size := decode_size(vm)
		b := pop_bytes(vm, size)
		a := pop_bytes(vm, size)
		push_bool(vm, slice.equal(a, b))
	case .Pop_Bytes:
		unimplemented("Bad instruction")
	case .Push_Bytes:
		size := decode_size(vm)
		bytes := decode_bytes(vm, size)
		push_bytes(vm, bytes)
	case .Jump_If_False:
		destination := decode_offset(vm)
		cond := pop_bool(vm)
		if !cond {vm.instruction_pointer = int(destination)}
	case .Jump:
		destination := decode_offset(vm)
		vm.instruction_pointer = int(destination)
	case .Add_I64:
		b := pop_i64(vm)
		a := pop_i64(vm)
		push_i64(vm, a + b)
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

pop_i64 :: proc(vm: ^VM) -> i64 {
	bytes := vm.stack[len(vm.stack) - size_of(i64):]
	val := slice.to_type(bytes, i64)
	resize(&vm.stack, len(vm.stack) - size_of(i64))
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

push_bool :: proc(vm: ^VM, val: bool) {
	bytes := transmute([1]byte)val
	append(&vm.stack, ..bytes[:])
}

push_bytes :: proc(vm: ^VM, bytes: []byte) {
	append(&vm.stack, ..bytes)
}


decode_instruction :: proc(vm: ^VM) -> Instruction {
	inst := Instruction(vm.bytecode[vm.instruction_pointer])
	vm.instruction_pointer += 1
	return inst
}

decode_size :: proc(vm: ^VM) -> Size {
	bytes := vm.bytecode[vm.instruction_pointer:vm.instruction_pointer + size_of(Size)]
	assert(len(bytes) == size_of(Size))
	vm.instruction_pointer += size_of(Size)
	return slice.to_type(bytes, Size)
}

decode_offset :: proc(vm: ^VM) -> Offset {
	bytes := vm.bytecode[vm.instruction_pointer:vm.instruction_pointer + size_of(Offset)]
	assert(len(bytes) == size_of(Offset))
	vm.instruction_pointer += size_of(Offset)
	return slice.to_type(bytes, Offset)
}


decode_bytes :: proc(vm: ^VM, n: Size) -> []byte {
	bytes := vm.bytecode[vm.instruction_pointer:vm.instruction_pointer + int(n)]
	vm.instruction_pointer += int(n)
	return bytes
}

