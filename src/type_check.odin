package palladium

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"

Named_Type :: struct {
	name: string,
	core: ^Type,
}

Builtin_Type :: enum {
	Integer_Literal,
	String_Literal,
	Bool_Literal,
}

Type :: union {
	Named_Type,
	Builtin_Type,
	Function_Type,
}

Function_Type :: struct {
	ret: ^Type,
	parameters: []^Type
}

Checker_Error_Type :: enum {
	Bad_Conversion,
	Bad_Operator,
	Bad_Type_Node,
	Redeclaration,
	Undeclared,
}

Type_Error :: struct {
	message: string,
	type:    Checker_Error_Type,
}

Operator_Type :: enum {
	Postfix = 0b01,
	Prefix  = 0b10,
	Binary  = 0b11,
}

Scope :: struct {
	types:     map[string]Type,
	variables: map[string]Type,
}

Checker :: struct {
	errors:            [dynamic]Type_Error,
	scopes:            [dynamic]Scope,
	function_depth:    int,
	loop_depth:        int,
	allocator:         runtime.Allocator,
}

make_checker :: proc(allocator: runtime.Allocator) -> Checker {
	checker: Checker
	checker.allocator = allocator
	checker.errors = make([dynamic]Type_Error, allocator)
	checker.scopes.allocator = allocator

	return checker
}

check_program :: proc(program: Node, allocator: runtime.Allocator) -> []Type_Error {
	checker := make_checker(allocator)
	// superglobal builtins
	push_type_scope(&checker)

	declare_named_type(&checker, "string", Builtin_Type.String_Literal)
	declare_named_type(&checker, "int", Builtin_Type.Integer_Literal)
	declare_named_type(&checker, "bool", Builtin_Type.Bool_Literal)

	check_statement(&checker, program)

	return checker.errors[:]
}

make_scope :: proc(checker: ^Checker) -> Scope {
	s: Scope
	s.types.allocator = checker.allocator
	s.variables.allocator = checker.allocator
	return s
}

delete_scope :: proc(s: Scope) {
	delete(s.types)
	delete(s.variables)
}

push_type_scope :: proc(checker: ^Checker) {
	append(&checker.scopes, make_scope(checker))
}

pop_type_scope :: proc(checker: ^Checker) {
	scope := pop(&checker.scopes)
	delete_scope(scope)
}

declare_variable_type :: proc(checker: ^Checker, name: string, type: Type) {
	scope := &checker.scopes[len(checker.scopes) - 1]

	if name in scope.variables {
		append(
			&checker.errors,
			Type_Error {
				type = .Redeclaration,
				message = fmt.tprintf("Redeclaration of variable %s in this scope", name),
			},
		)
	} else {
		scope.variables[name] = type
	}
}

declare_named_type :: proc(checker: ^Checker, name: string, type: Type) {
	scope := &checker.scopes[len(checker.scopes) - 1]

	if name in scope.types {
		append(
			&checker.errors,
			Type_Error {
				type = .Redeclaration,
				message = fmt.tprintf("Redeclaration of type %s in this scope", name),
			},
		)
	} else {
		scope.types[name] = type
	}
}

check_variable_write :: proc(checker: ^Checker, node: ^Variable_Write_Node) {
	var_type, found := resolve_variable_type(checker, node.name)

	if !found {
		append(
			&checker.errors,
			Type_Error {
				type = .Undeclared,
				message = fmt.tprintf("Undeclared variable '%s'", node.name),
			},
		)
		return
	}

	expr_type := check_expression(checker, node.value)


	if !is_convertible_from_to(expr_type, var_type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to assign type %s to variable %s with type %s",
					type_to_string(expr_type, context.temp_allocator),
					node.name,
					type_to_string(var_type, context.temp_allocator),
				),
			},
		)
	}
}

check_while :: proc(checker: ^Checker, stmt: ^While_Node) {
	cond_type := check_expression(checker, stmt.condition)

	if !is_convertible_from_to(cond_type, Builtin_Type.Bool_Literal) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to convert from %s to boolean in a while loop condition",
					type_to_string(cond_type, context.temp_allocator),
				),
			},
		)
	}

	check_statement(checker, stmt.body)
}

check_if :: proc(checker: ^Checker, stmt: ^If_Node) {
	cond_type := check_expression(checker, stmt.condition)

	if !is_convertible_from_to(cond_type, Builtin_Type.Bool_Literal) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to convert from %s to boolean in an if statement condition",
					type_to_string(cond_type, context.temp_allocator),
				),
			},
		)
	}

}

check_statement :: proc(checker: ^Checker, stmt: Node) {
	#partial switch type in stmt {
	case ^Variable_Declaration_Node:
		check_declaration(checker, type)
	case ^Variable_Write_Node:
		check_variable_write(checker, type)
	case ^Block_Node:
		for stmt in type.statements {
			check_statement(checker, stmt)
		}
	case ^While_Node:
		check_while(checker, type)
	case ^If_Node:
		check_if(checker, type)
	case ^Function_Declaration_Node:
		check_function_declaration(checker, type)
	case:
		fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(stmt))
	}
}

check_function_declaration :: proc(checker: ^Checker, node: ^Function_Declaration_Node) {

}

check_declaration :: proc(checker: ^Checker, node: ^Variable_Declaration_Node) {
	expr_type := check_expression(checker, node.value)
	declared_type := evaluate_type(checker, node.type)

	declare_variable_type(checker, node.name, declared_type)

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
	from := unwrap_type(from)
	to := unwrap_type(to)
	if types_are_equivalent(from, to) {
		return true
	}

	return false
}

unwrap_type :: proc(t: Type) -> Type {
	t := t
	for {
		#partial switch type in t {
		case Named_Type:
			t = type.core^
		case:
			return t
		}
	}
}

type_to_string :: proc(type: Type, allocator: runtime.Allocator) -> string {
	builder := strings.builder_make(allocator)
	write_type(type, &builder)
	return strings.to_string(builder)
}

write_type :: proc(type: Type, builder: ^strings.Builder) {
	if type == nil {
		strings.write_string(builder, "<invalid type>")
	}

	switch variant in type {
	case Named_Type:
		strings.write_string(builder, variant.name)
	case Builtin_Type:
		fmt.sbprint(builder, variant)
	case Function_Type:
		fmt.sbprint(builder, "function(")
		for arg, i in variant.parameters {
			if i != 0 {
				strings.write_string(builder, ", ")
			}
			write_type(arg^, builder)
		}
		fmt.sbprint(builder, "): ")
		write_type(variant.ret^, builder)
	}

	fmt.panicf("Very bad type %s", type)
}

resolve_type :: proc(checker: ^Checker, name: string) -> (^Type, bool) {
	#reverse for &scope in checker.scopes {
		val, ok := &scope.types[name]
		if ok do return val, true
	}

	return nil, false
}

resolve_variable_type :: proc(checker: ^Checker, name: string) -> (Type, bool) {
	#reverse for scope in checker.scopes {
		val, ok := scope.variables[name]
		if ok do return val, true
	}

	return nil, false
}

evaluate_type :: proc(checker: ^Checker, node: Node) -> Type {
	#partial switch variant in node {
	case ^Named_Type_Node:
		type, ok := resolve_type(checker, variant.name)
		if !ok {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Type_Node,
					message = fmt.tprintf("Undeclared type %s", variant.name),
				},
			)
			return nil
		} else {
			return Named_Type{name = variant.name, core = type}
		}
	}

	append(
		&checker.errors,
		Type_Error {
			type = .Bad_Type_Node,
			message = fmt.tprintf(
				"Unable to make a type from %s",
				reflect.union_variant_typeid(node),
			),
		},
	)

	return nil
}

check_expression :: proc(checker: ^Checker, node: Node) -> Type {
	#partial switch type in node {
	case ^Binary_Op_Node:
		left := check_expression(checker, type.left)
		right := check_expression(checker, type.right)
		return check_binary_expression(checker, left, right, type.op)
	case ^Variable_Read_Node:
		var_type, found := resolve_variable_type(checker, type.name)
		if !found {
			append(
				&checker.errors,
				Type_Error {
					type = .Undeclared,
					message = fmt.tprintf("Undeclared variable '%s'", type.name),
				},
			)
			return nil
		}
		return var_type
	case ^Call_Node:
		return check_call(checker, type)
	case ^String_Node:
		return Builtin_Type.String_Literal
	case ^Integer_Node:
		return Builtin_Type.Integer_Literal
	case ^Boolean_Node:
		return Builtin_Type.Bool_Literal
	case:
		fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(node))

	}
}

check_call :: proc(checker: ^Checker, node: ^Call_Node) -> Type {
	call_type := check_expression(checker, node.callee)
	
	if function_type, is_func := call_type.(Function_Type); is_func {
		
	}
	
}

types_are_equivalent :: proc(a, b: Type) -> bool {
	if a == nil || b == nil {
		return false
	}

	return a == b
}

converts_to :: proc(t: Type, target: Type) -> bool {
	if t == nil {
		return false
	}

	if target == nil {
		return false
	}

	if t == target {
		return true
	}

	
	if types_are_equivalent(unwrap_type(t), unwrap_type(target)) {
		return true
	}

	return false
}

check_binary_expression :: proc(checker: ^Checker, left, right: Type, op: Token_Type) -> Type {
	#partial switch op {
	case .Plus:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return left
		}
	case .Star:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return left
		}
	case .Slash:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return left
		}
	case .Minus:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return left
		}
	case .Less:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return Builtin_Type.Bool_Literal
		}
	case .Greater:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return Builtin_Type.Bool_Literal
		}
	case .Less_Equals:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return Builtin_Type.Bool_Literal
		}
	case .Greater_Equals:
		if converts_to(left, Builtin_Type.Integer_Literal) &&
		   converts_to(right, Builtin_Type.Integer_Literal) {
			return Builtin_Type.Bool_Literal
		}
	case .Double_Equals:
		if converts_to(left, right) {
			return Builtin_Type.Bool_Literal
		}
	case .Exclamation_Equals:
		if converts_to(left, right) {
			return Builtin_Type.Bool_Literal
		}
	case .Double_Pipe:
		if converts_to(left, Builtin_Type.Bool_Literal) &&
		   converts_to(right, Builtin_Type.Bool_Literal) {
			return Builtin_Type.Bool_Literal
		}
	case .Double_Amp:
		if converts_to(left, Builtin_Type.Bool_Literal) &&
		   converts_to(right, Builtin_Type.Bool_Literal) {
			return Builtin_Type.Bool_Literal
		}
	case:
		fmt.panicf("impossible operator %s", op)
	}

	append(
		&checker.errors,
		Type_Error {
			type = .Bad_Operator,
			message = fmt.tprintf(
				"Unable to use operator %s on types %s and %s",
				op,
				type_to_string(left, context.temp_allocator),
				type_to_string(right, context.temp_allocator),
			),
		},
	)
	return nil
}

make_type :: proc(
	checker: ^Checker,
	$T: typeid,
) -> ^T where intrinsics.type_is_variant_of(Type, ^T) {
	type := new(T, checker.allocator)
	return type
}

