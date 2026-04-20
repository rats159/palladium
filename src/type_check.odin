package palladium

import "core:strings"
import "base:runtime"
import "core:fmt"
import "core:reflect"

Named_Type :: struct {
    name: string, 
    core: Type
}

Builtin_Type :: enum {
    Integer,
    String,
    Bool,
}

Type :: union {
    ^Named_Type,
    ^Builtin_Type,
}

Type_Error_Type :: enum {
	Bad_Conversion,
	Bad_Operator,
}

Type_Error :: struct {
	message: string,
	type:    Type_Error_Type,
}

Checker :: struct {
	errors:         [dynamic]Type_Error,
	function_depth: int,
	loop_depth:     int,
	allocator: runtime.Allocator
}

check_program :: proc(program: Node, allocator: runtime.Allocator) -> []Type_Error {
	block := program.(^Block_Node)
	checker: Checker
	checker.allocator = allocator
	checker.errors = make([dynamic]Type_Error, allocator)


	for stmt in block.statements {
		check_statement(&checker, stmt)
	}

	return checker.errors[:]
}

check_statement :: proc(checker: ^Checker, stmt: Node) {
	#partial switch type in stmt {
	case ^Variable_Declaration_Node:
		check_declaration(checker, type)
	case:
		fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(stmt))
	}
}

check_declaration :: proc(checker: ^Checker, node: ^Variable_Declaration_Node) {
	expr_type := check_expression(checker, node.value)
	declared_type := evaluate_type(node.type)

	if !is_convertible_from_to(expr_type, declared_type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to assign type %s to variable %s with type %s",
					type_to_string(expr_type, context.temp_allocator),
					node.name,
					type_to_string(declared_type, context.temp_allocator),
				),
			},
		)
	}
}

is_convertible_from_to :: proc(from: Type, to: Type) -> bool {
    return false
}

type_to_string :: proc(type: Type, allocator: runtime.Allocator) -> string {
    if type == nil {
        return strings.clone("<invalid type>", allocator)
    }
    
    switch variant in type {
        case ^Named_Type:
            return strings.clone(variant.name, allocator)
        case ^Builtin_Type:
            return fmt.aprint(variant^, allocator = allocator)
    }
    
    fmt.panicf("Very bad type %s", type)
}

evaluate_type :: proc(node: Node) -> Type {
	return {}
}

check_expression :: proc(checker: ^Checker, node: Node) -> Type {
	#partial switch type in node {
	case ^Binary_Op_Node:
	    left := check_expression(checker, type.left)
	    right := check_expression(checker, type.right)
		return check_binary_expression(checker, left, right, type.op)
	case ^String_Node:
	    return new_clone(Builtin_Type.String, checker.allocator)
	case:
		fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(node))

	}
}

types_are_equivalent :: proc(a, b: Type) -> bool {
    if a == nil || b == nil {
        return false
    }
    
    return a == b
}

check_binary_expression :: proc(checker: ^Checker, left, right: Type, op: Token_Type) -> Type {
    if types_are_equivalent(left, right) {
        return left
    }
    
    append(&checker.errors, Type_Error{
        type = .Bad_Operator,
        message = fmt.tprintf("Unable to use operator %s on types %s and %s", op, type_to_string(left, context.temp_allocator), type_to_string(right, context.temp_allocator))
    })
    return nil
}