package palladium

import "core:fmt"
evaluate_expression :: proc(expr: Node) -> i64 {
	#partial switch type in expr {
	case ^Binary_Op_Node:
		return evaluate_binary_expression(type)
	case ^Integer_Node:
		return type.value
	}
	
	panic("Impossible expression type")
}

evaluate_binary_expression :: proc(expr: ^Binary_Op_Node) -> i64 {
	left := evaluate_expression(expr.left)
	right := evaluate_expression(expr.right)
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