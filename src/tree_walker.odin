package palladium

import "core:fmt"
import "core:reflect"


Runtime :: struct {
	scopes: [dynamic]map[string]Value,
}

Value :: union {
	i64,
	string,
	bool,
}

Runtime_Error_Type :: enum {
	Undeclared_Variable,
	Redeclared_Variable,
	Type_Error,
	Bad_Control_Flow,
}

Runtime_Error :: struct {
	type:    Runtime_Error_Type,
	message: string,
}

Continue :: struct {}
Break :: struct {}

Runtime_Propagation :: union {
	Runtime_Error,
	Continue,
	Break,
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

execute_while :: proc(rt: ^Runtime, stmt: ^While_Node) -> Runtime_Propagation {

	loop: for {
		cond_node := evaluate_expression(rt, stmt.condition) or_return
		cond := unwrap_value(cond_node, bool) or_return

		if !cond do break

		prop := execute_statement(rt, stmt.body)
		switch type in prop {
		case Runtime_Error:
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
	}

	fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(expr))
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
		return left == right, nil
	case .Exclamation_Equals:
		return left != right, nil
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

short_circuits :: proc(op: Token_Type) -> bool {
	#partial switch op {
	case .Double_Pipe, .Double_Amp:
		return true
	case:
		return false
	}
}

unwrap_value :: proc(val: Value, $T: typeid) -> (T, Runtime_Propagation) {
	unwrapped, ok := val.(T)

	if ok {
		return unwrapped, nil
	}

	return {}, Runtime_Error{type = .Type_Error, message = fmt.tprintf("Expected a %s but recieved a %s", reflect.union_variant_typeid(val), typeid_of(T))}
}

