package palladium

import "core:fmt"
import "core:reflect"

Runtime :: struct {
	variables: map[string]Value,
}

Value :: union {
	i64,
	string,
}

cleanup_runtime :: proc(rt: ^Runtime) {
	delete(rt.variables)
}

read_variable :: proc(rt: ^Runtime, name: string) -> Value {
	return rt.variables[name]
}

execute_statement :: proc(rt: ^Runtime, statement: Node) {
	#partial switch type in statement {
	case ^Variable_Declaration_Node:
		val := evaluate_expression(rt, type.value)
		rt.variables[type.name] = val
	case ^Block_Node:
		for stmt in type.statements {
			execute_statement(rt, stmt)
		}
	case ^Variable_Write_Node:
		write_variable(rt, type)
	case:
		fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(statement))
	}
}

write_variable :: proc(rt: ^Runtime, node: ^Variable_Write_Node) {
	rt.variables[node.name] = evaluate_expression(rt, node.value)
}

evaluate_expression :: proc(rt: ^Runtime, expr: Node) -> Value {
	#partial switch type in expr {
	case ^Binary_Op_Node:
		return evaluate_binary_expression(rt, type)
	case ^Integer_Node:
		return type.value
	case ^Variable_Read_Node:
		return read_variable(rt, type.name)
	case ^String_Node:
		return type.value
	}

	fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(expr))
}

evaluate_binary_expression :: proc(rt: ^Runtime, expr: ^Binary_Op_Node) -> Value {
	left := evaluate_expression(rt, expr.left)
	right := evaluate_expression(rt, expr.right)
	#partial switch expr.op {
	case .Plus:
		return left.(i64) + right.(i64)
	case .Minus:
		return left.(i64) - right.(i64)
	case .Star:
		return left.(i64) * right.(i64)
	case .Slash:
		return left.(i64) / right.(i64)
	}

	fmt.panicf("Impossible binary expression operator %s", expr.op)
}

