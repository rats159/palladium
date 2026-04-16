package palladium

import "core:fmt"
import "core:reflect"

Runtime :: struct {
	variables: map[string]Value,
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
}

Runtime_Error :: struct {
	type:    Runtime_Error_Type,
	message: string,
}

cleanup_runtime :: proc(rt: ^Runtime) {
	delete(rt.variables)
}

@(require_results)
read_variable :: proc(rt: ^Runtime, name: string) -> (_val: Value, _err: Maybe(Runtime_Error)) {
	val, ok := rt.variables[name]
	if ok do return val, nil

	return {}, Runtime_Error{type = .Undeclared_Variable, message = fmt.tprintf("Undeclared variable '%s'", name)}
}

@(require_results)
execute_statement :: proc(rt: ^Runtime, statement: Node) -> Maybe(Runtime_Error) {
	#partial switch type in statement {
	case ^Variable_Declaration_Node:
		val := evaluate_expression(rt, type.value) or_return
		var, exists := &rt.variables[type.name]

		if exists {
			return Runtime_Error {
				type = .Redeclared_Variable,
				message = fmt.tprintf("Redeclared variable '%s'", type.name),
			}
		}
		rt.variables[type.name] = val

	case ^Block_Node:
		for stmt in type.statements {
			execute_statement(rt, stmt) or_return
		}
	case ^Variable_Write_Node:
		write_variable(rt, type) or_return
	case:
		fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(statement))
	}

	return nil
}

@(require_results)
write_variable :: proc(rt: ^Runtime, node: ^Variable_Write_Node) -> Maybe(Runtime_Error) {
	var, exists := &rt.variables[node.name]

	if !exists {
		return Runtime_Error {
			type = .Undeclared_Variable,
			message = fmt.tprintf("Undeclared variable '%s'", node.name),
		}
	}

	var^ = evaluate_expression(rt, node.value) or_return

	return nil
}

evaluate_expression :: proc(rt: ^Runtime, expr: Node) -> (Value, Maybe(Runtime_Error)) {
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
		_err: Maybe(Runtime_Error),
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
	_err: Maybe(Runtime_Error),
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
		_err: Maybe(Runtime_Error),
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

unwrap_value :: proc(val: Value, $T: typeid) -> (T, Maybe(Runtime_Error)) {
	unwrapped, ok := val.(T)

	if ok {
		return unwrapped, nil
	}

	return {}, Runtime_Error{type = .Type_Error, message = fmt.tprintf("Expected a %s but recieved a %s", reflect.union_variant_typeid(val), typeid_of(T))}
}

