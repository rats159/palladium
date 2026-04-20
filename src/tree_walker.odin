package palladium

import "core:fmt"
import "core:reflect"
import "vendor:portmidi"

CHECKED_RUNTIME :: #config(CHECKED_RUNTIME, false)


Runtime :: struct {
	scopes: [dynamic]map[string]Value,
}

Value :: union {
	i64,
	string,
	bool,
	Function,
}

Runtime_Error_Type :: enum {
	Undeclared_Variable,
	Redeclared_Variable,
	Type_Error,
	Bad_Control_Flow,
	Bad_Call,
}

Runtime_Error :: struct {
	type:    Runtime_Error_Type,
	message: string,
}

Function :: struct {
	parameters: []Parameter_Node,
	body:       Node,
}

Continue :: struct {}
Break :: struct {}
Return :: struct {
	val: Maybe(Value),
}

Runtime_Propagation :: union {
	Runtime_Error,
	Continue,
	Break,
	Return,
}

cleanup_runtime :: proc(rt: ^Runtime) {
	for scope in rt.scopes {
		delete(scope)
	}
	delete(rt.scopes)
}

resolve_variable :: proc(rt: ^Runtime, name: string) -> ^Value {
	#reverse for &scope in rt.scopes {
		val, ok := &scope[name]
		if ok do return val
	}

	return nil
}

@(require_results)
read_variable :: proc(rt: ^Runtime, name: string) -> (_val: Value, _err: Runtime_Propagation) {
	var := resolve_variable(rt, name)

	if var == nil {
		return {}, Runtime_Error{type = .Undeclared_Variable, message = fmt.tprintf("Undeclared variable '%s'", name)}
	}

	return var^, nil
}

execute_file :: proc(rt: ^Runtime, file: Node) -> Maybe(Runtime_Error) {
	// no pop so we can read variables in tests
	push_scope(rt)

	for statement in file.(^Block_Node).statements {
		res := execute_statement(rt, statement)
		switch type in res {
		case Runtime_Error:
			return type
		case Return:
			return Runtime_Error {
				type = .Bad_Control_Flow,
				message = fmt.tprint("Cannot return at file scope"),
			}
		case Continue:
			return Runtime_Error {
				type = .Bad_Control_Flow,
				message = fmt.tprint("Cannot continue at file scope"),
			}
		case Break:
			return Runtime_Error {
				type = .Bad_Control_Flow,
				message = fmt.tprint("Cannot break at file scope"),
			}
		}
	}

	return nil
}

@(require_results)
execute_statement :: proc(rt: ^Runtime, statement: Node) -> Runtime_Propagation {
	#partial switch type in statement {
	case ^Variable_Declaration_Node:
		declare_variable(rt, type) or_return
	case ^Block_Node:
		push_scope(rt)
		defer pop_scope(rt)
		for stmt in type.statements {
			execute_statement(rt, stmt) or_return
		}
	case ^Variable_Write_Node:
		write_variable(rt, type) or_return
	case ^If_Node:
		execute_if(rt, type) or_return
	case ^While_Node:
		execute_while(rt, type) or_return
	case ^Break_Node:
		return Break{}
	case ^Continue_Node:
		return Continue{}
	case ^Function_Declaration_Node:
		declare_function(rt, type) or_return
	case ^Return_Node:
		ret: Return
		if node, ok := type.value.?; ok {
			ret.val = evaluate_expression(rt, node) or_return
		}

		return ret
	case:
		fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(statement))
	}

	return nil
}

push_scope :: proc(rt: ^Runtime) {
	// resize(&rt.scopes, len(rt.scopes) + 1)
	append(&rt.scopes, map[string]Value{})
}

pop_scope :: proc(rt: ^Runtime) {
	scope := pop(&rt.scopes)
	delete(scope)
}

declare_function :: proc(rt: ^Runtime, stmt: ^Function_Declaration_Node) -> Runtime_Propagation {
	scope := &rt.scopes[len(rt.scopes) - 1]

	if stmt.name in scope {
		return Runtime_Error {
			type = .Redeclared_Variable,
			message = fmt.tprintf("Redeclared variable '%s'", stmt.name),
		}
	}
	scope[stmt.name] = Function {
		body       = stmt.body,
		parameters = stmt.parameters,
	}

	return nil
}

declare_variable :: proc(rt: ^Runtime, stmt: ^Variable_Declaration_Node) -> Runtime_Propagation {
	val := evaluate_expression(rt, stmt.value) or_return

	scope := &rt.scopes[len(rt.scopes) - 1]

	if stmt.name in scope {
		return Runtime_Error {
			type = .Redeclared_Variable,
			message = fmt.tprintf("Redeclared variable '%s'", stmt.name),
		}
	}
	scope[stmt.name] = val

	return nil
}

declare_parameter :: proc(rt: ^Runtime, name: string, value: Value) -> Runtime_Propagation {
	scope := &rt.scopes[len(rt.scopes) - 1]

	if name in scope {
		return Runtime_Error {
			type = .Redeclared_Variable,
			message = fmt.tprintf("Duplicate parameter name '%s'", name),
		}
	}
	scope[name] = value

	return nil
}

execute_while :: proc(rt: ^Runtime, stmt: ^While_Node) -> Runtime_Propagation {

	loop: for {
		cond_node := evaluate_expression(rt, stmt.condition) or_return
		cond := unwrap_value(cond_node, bool) or_return

		if !cond do break

		prop := execute_statement(rt, stmt.body)
		switch type in prop {
		case Runtime_Error, Return:
			return type
		case Continue:
			continue loop
		case Break:
			break loop
		}
	}
	return nil
}

execute_if :: proc(rt: ^Runtime, stmt: ^If_Node) -> Runtime_Propagation {
	cond_value := evaluate_expression(rt, stmt.condition) or_return
	cond := unwrap_value(cond_value, bool) or_return

	if cond {
		return execute_statement(rt, stmt.body)
	} else if else_body, exists := stmt.else_body.?; exists {
		return execute_statement(rt, else_body)
	}

	return nil
}

@(require_results)
write_variable :: proc(rt: ^Runtime, node: ^Variable_Write_Node) -> Runtime_Propagation {
	var := resolve_variable(rt, node.name)

	if var == nil {
		return Runtime_Error {
			type = .Undeclared_Variable,
			message = fmt.tprintf("Undeclared variable '%s'", node.name),
		}
	}

	var^ = evaluate_expression(rt, node.value) or_return

	return nil
}

evaluate_expression :: proc(rt: ^Runtime, expr: Node) -> (Value, Runtime_Propagation) {
	#partial switch type in expr {
	case ^Binary_Op_Node:
		return evaluate_binary_expression(rt, type)
	case ^Integer_Node:
		return type.value, nil
	case ^Boolean_Node:
		return type.value, nil
	case ^Variable_Read_Node:
		return read_variable(rt, type.name)
	case ^String_Node:
		return type.value, nil
	case ^Call_Node:
		return call_function(rt, type)
	}

	fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(expr))
}

call_function :: proc(rt: ^Runtime, call: ^Call_Node) -> (_val: Value, _ret: Runtime_Propagation) {
	callee := evaluate_expression(rt, call.callee) or_return
	function := unwrap_value(callee, Function) or_return

	if len(function.parameters) != len(call.arguments) {
		return {}, Runtime_Error{type = .Bad_Call, message = fmt.tprintf("Bad argument count for function. Expected %d but recieved %d", len(function.parameters), len(call.arguments))}
	}

	push_scope(rt)
	defer pop_scope(rt)

	for arg, i in call.arguments {
		name := function.parameters[i]
		value := evaluate_expression(rt, arg) or_return
		declare_parameter(rt, name.name, value) or_return
	}

	res := execute_statement(rt, function.body)
	if ret, is_ret := res.(Return); is_ret {
		return (ret.val.? or_else nil), nil
	}

	return {}, res
}

evaluate_short_circuiting_binary_expression :: proc(
	rt: ^Runtime,
	expr: ^Binary_Op_Node,
) -> (
	_val: Value,
	_err: Runtime_Propagation,
) {
	left := evaluate_expression(rt, expr.left) or_return
	#partial switch expr.op {
	case .Double_Pipe:
		left := unwrap_value(left, bool) or_return

		if left do return true, nil

		right := evaluate_expression(rt, expr.right) or_return
		right_raw := unwrap_value(right, bool) or_return

		if right_raw do return true, nil

		return false, nil
	case .Double_Amp:
		left := unwrap_value(left, bool) or_return

		if !left do return false, nil

		right := evaluate_expression(rt, expr.right) or_return
		right_raw := unwrap_value(right, bool) or_return

		if !right_raw do return false, nil

		return true, nil
	}

	fmt.panicf("Impossible binary expression operator %s", expr.op)
}

evaluate_binary_expression :: proc(
	rt: ^Runtime,
	expr: ^Binary_Op_Node,
) -> (
	_val: Value,
	_err: Runtime_Propagation,
) {
	if short_circuits(expr.op) {
		return evaluate_short_circuiting_binary_expression(rt, expr)
	} else {
		return evaluate_regular_binary_expression(rt, expr)
	}
}

evaluate_regular_binary_expression :: proc(
	rt: ^Runtime,
	expr: ^Binary_Op_Node,
) -> (
	_val: Value,
	_err: Runtime_Propagation,
) {
	left := evaluate_expression(rt, expr.left) or_return
	right := evaluate_expression(rt, expr.right) or_return
	#partial switch expr.op {
	case .Plus:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left + right, nil
	case .Minus:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left - right, nil
	case .Star:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left * right, nil
	case .Slash:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left / right, nil
	case .Double_Equals:
		return values_equal(left, right)
	case .Exclamation_Equals:
		return !(values_equal(left, right) or_return), nil
	case .Less:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left < right, nil
	case .Greater:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left > right, nil
	case .Less_Equals:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left <= right, nil
	case .Greater_Equals:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left >= right, nil
	}

	fmt.panicf("Impossible binary expression operator %s", expr.op)
}

values_equal :: proc(a, b: Value) -> (bool, Runtime_Propagation) {
	a_type := reflect.union_variant_typeid(a)
	b_type := reflect.union_variant_typeid(b)

	if a_type != b_type {
		return false, Runtime_Error {
			type = .Type_Error,
			message = fmt.tprintf(
				"Expected both sides of equality to be the same type, but but recieved %s and %s",
				a_type,
				b_type,
			),
		}
	}

	switch type in a {
	case i64:
		return a.(i64) == b.(i64), nil
	case bool:
		return a.(bool) == b.(bool), nil
	case string:
		return a.(string) == b.(string), nil
	case Function:
		return a.(Function).body == b.(Function).body, nil
	}

	fmt.panicf("Impossible value type %s", a_type)
}

short_circuits :: proc(op: Token_Type) -> bool {
	#partial switch op {
	case .Double_Pipe, .Double_Amp:
		return true
	case:
		return false
	}
}


when CHECKED_RUNTIME {
	unwrap_value :: proc(val: Value, $T: typeid) -> (T, Runtime_Propagation) {
		unwrapped, ok := val.(T)

		if ok {
			return unwrapped, nil
		}

		return {}, Runtime_Error{type = .Type_Error, message = fmt.tprintf("Expected a %s but recieved a %s", reflect.union_variant_typeid(val), typeid_of(T))}
	}

} else {
	unwrap_value :: proc(val: Value, $T: typeid, loc := #caller_location) -> (T, Runtime_Propagation) {
		unwrapped, ok := val.(T)
		assert(ok, loc=loc)
		return unwrapped, nil
	}
}

