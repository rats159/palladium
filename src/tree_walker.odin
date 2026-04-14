package palladium

import "core:reflect"
import "core:fmt"

Runtime :: struct {
	variables: map[string]i64,
}

cleanup_runtime :: proc(rt: ^Runtime) {
	delete(rt.variables)
}

read_variable :: proc(rt: ^Runtime, name: string) -> i64 {
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

evaluate_expression :: proc(rt: ^Runtime, expr: Node) -> i64 {
	#partial switch type in expr {
	case ^Binary_Op_Node:
		return evaluate_binary_expression(rt, type)
	case ^Integer_Node:
		return type.value
	case ^Variable_Read_Node:
		return read_variable(rt, type.name)
	}

	fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(expr))
}

evaluate_binary_expression :: proc(rt: ^Runtime, expr: ^Binary_Op_Node) -> i64 {
	left := evaluate_expression(rt, expr.left)
	right := evaluate_expression(rt, expr.right)
	#partial switch expr.op {
	case .Plus:
		return left + right
	case .Minus:
		return left - right
	case .Star:
		return left * right
	case .Slash:
		return left / right
	}

	fmt.panicf("Impossible binary expression operator %s", expr.op)
}

