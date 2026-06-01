package palladium

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

Builtin_Type :: enum {
	Integer_Literal,
	String_Literal,
	Bool_Literal,
}

Type :: union {
	Builtin_Type,
	Function_Type,
}

Parameter_Type :: struct {
	name: string,
	type: ^Type,
}

Function_Type :: struct {
	ret:        ^Type,
	parameters: []Parameter_Type,
}

Checker_Error_Type :: enum {
	Bad_Conversion,
	Bad_Operator,
	Bad_Type_Node,
	Redeclaration,
	Undeclared,
	Wrong_Argument_Count,
}

Type_Error :: struct {
	message: string,
	type:    Checker_Error_Type,
}

Scope :: struct {
	type_registry: Type_Registry,
	variables:     map[string]^Type,
	aliases:       map[string]^Type,
}

Checker :: struct {
	errors:         [dynamic]Type_Error,
	scopes:         [dynamic]Scope,
	function_depth: int,
	loop_depth:     int,
	allocator:      runtime.Allocator,
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

	declare_named_type(&checker, "string", get_type(&checker, Builtin_Type.String_Literal))
	declare_named_type(&checker, "int", get_type(&checker, Builtin_Type.Integer_Literal))
	declare_named_type(&checker, "bool", get_type(&checker, Builtin_Type.Bool_Literal))

	check_statement(&checker, program)

	return checker.errors[:]
}

make_scope :: proc(checker: ^Checker) -> Scope {
	s: Scope
	s.type_registry.allocator = checker.allocator
	s.variables.allocator = checker.allocator
	s.aliases.allocator = checker.allocator
	return s
}

delete_scope :: proc(s: Scope) {
	delete(s.type_registry)
	delete(s.variables)
}

push_type_scope :: proc(checker: ^Checker) {
	append(&checker.scopes, make_scope(checker))
}

pop_type_scope :: proc(checker: ^Checker) {
	scope := pop(&checker.scopes)
	delete_scope(scope)
}

declare_variable_type :: proc(checker: ^Checker, name: string, type: ^Type) {
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

	if !is_convertible_from_to(cond_type, get_type(checker, Builtin_Type.Bool_Literal)) {
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

	if !is_convertible_from_to(cond_type, get_type(checker, Builtin_Type.Bool_Literal)) {
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
        push_type_scope(checker)
		for stmt in type.statements {
			check_statement(checker, stmt)
		}
        pop_type_scope(checker)
	case ^While_Node:
		check_while(checker, type)
	case ^If_Node:
		check_if(checker, type)
	case ^Function_Declaration_Node:
		check_function_declaration(checker, type)
	case:
	    check_expression(checker, stmt)
	}
}

check_function_declaration :: proc(checker: ^Checker, node: ^Function_Declaration_Node) {
	declare_variable_type(checker, node.name, evaluate_type(checker, node))
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

is_convertible_from_to :: proc(from: ^Type, to: ^Type) -> bool {
	from := unwrap_type(from)
	to := unwrap_type(to)
	if types_are_equivalent(from, to) {
		return true
	}

	return false
}

unwrap_type :: proc(t: ^Type) -> ^Type {
	return t
	// t := t
	// for {
	// 	#partial switch type in t {
	// 	case Alias_Type:
	// 		t = type.core^
	// 	case:
	// 		return t
	// 	}
	// }
}

type_to_string :: proc(type: ^Type, allocator: runtime.Allocator) -> string {
	builder := strings.builder_make(allocator)
	write_type(type, &builder)
	return strings.to_string(builder)
}

write_type :: proc(type: ^Type, builder: ^strings.Builder) {
	assert(type != nil, "Nil type pointer is bad")
	type := type^
	if type == nil {
		strings.write_string(builder, "<invalid type>")
		return
	}

	switch variant in type {
	case Builtin_Type:
		fmt.sbprint(builder, variant)
		return
	case Function_Type:
		fmt.sbprint(builder, "function(")
		for arg, i in variant.parameters {
			if i != 0 {
				strings.write_string(builder, ", ")
			}
			write_type(arg.type, builder)
		}
		fmt.sbprint(builder, "): ")
		write_type(variant.ret, builder)
		return
	}

	fmt.panicf("Very bad type %s", type)
}

// resolve_type :: proc(checker: ^Checker, name: string) -> (^Type, bool) {
// 	#reverse for &scope in checker.scopes {
// 		val, ok := &scope.types[name]
// 		if ok do return val, true
// 	}

// 	return nil, false
// }

resolve_variable_type :: proc(checker: ^Checker, name: string) -> (^Type, bool) {
	#reverse for scope in checker.scopes {
		val, ok := scope.variables[name]
		if ok do return val, true
	}

	return &invalid_type, false
}

evaluate_type :: proc(checker: ^Checker, node: Node) -> ^Type {
	#partial switch variant in node {
	case ^Named_Type_Node:
		type, ok := find_type_by_name(checker, variant.name)
		if !ok {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Type_Node,
					message = fmt.tprintf("Undeclared type %s", variant.name),
				},
			)
			return &invalid_type
		} else {
			return type
		}
	case ^Function_Declaration_Node:
		ret := evaluate_type(checker, variant.return_type)

		params := make([]Parameter_Type, len(variant.parameters), checker.allocator)
		for &param, i in params {
			param.name = variant.parameters[i].name
			param.type = evaluate_type(checker, variant.parameters[i].type)
		}
		return get_type(checker, Function_Type{parameters = params, ret = ret})
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

	return &invalid_type
}

check_expression :: proc(checker: ^Checker, node: Node) -> ^Type {
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
			return &invalid_type
		}
		return var_type
	case ^Call_Node:
		return check_call(checker, type)
	case ^String_Node:
		return get_type(checker, Builtin_Type.String_Literal)
	case ^Integer_Node:
		return get_type(checker, Builtin_Type.Integer_Literal)
	case ^Boolean_Node:
		return get_type(checker, Builtin_Type.Bool_Literal)
	case:
		fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(node))

	}
}

type_is_function :: proc(t: ^Type) -> bool {
	t := unwrap_type(t)
	_, is_func := t.(Function_Type)
	return is_func
}

type_is_integer :: proc(t: ^Type) -> bool {
	t := unwrap_type(t)
	builtin, is_builtin := t.(Builtin_Type)
	if !is_builtin do return false
	return builtin == .Integer_Literal
}

type_is_boolean :: proc(t: ^Type) -> bool {
	t := unwrap_type(t)
	builtin, is_builtin := t.(Builtin_Type)
	if !is_builtin do return false
	return builtin == .Bool_Literal
}

check_call :: proc(checker: ^Checker, node: ^Call_Node) -> ^Type {
	call_type := check_expression(checker, node.callee)

	if !type_is_function(call_type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Expected a function type for call expression, got %s",
					type_to_string(call_type, context.temp_allocator),
				),
			},
		)

		return &invalid_type
	}

	func_type := call_type.(Function_Type)
	if len(func_type.parameters) != len(node.arguments) {
		append(
			&checker.errors,
			Type_Error {
				type = .Wrong_Argument_Count,
				message = fmt.tprintf(
					"Wrong number of arguments for call! Expected %d but received %d",
					len(func_type.parameters),
					len(node.arguments),
				),
			},
		)

		return &invalid_type
	}

	for i in 0 ..< len(node.arguments) {
		arg_type := check_expression(checker, node.arguments[i])
		param := func_type.parameters[i]

		if !types_are_equivalent(arg_type, param.type) {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Conversion,
					message = fmt.tprintf(
						"Unable to assign type %s to parameter %s with type %s",
						type_to_string(arg_type, context.temp_allocator),
						param.name,
						type_to_string(param.type, context.temp_allocator),
					),
				},
			)
		}
	}

	return func_type.ret
}

// Strict equivalence, no implicit conversions
types_are_equivalent :: proc(a_ptr, b_ptr: ^Type, loc := #caller_location) -> bool {
	if a_ptr == b_ptr {
		return true
	}

	a := unwrap_type(a_ptr)^
	b := unwrap_type(b_ptr)^

	if a == nil || b == nil {
		return false
	}


	if reflect.get_union_variant_raw_tag(a) != reflect.get_union_variant_raw_tag(b) {
		return false
	}

	switch type in a {
	case Builtin_Type:
		return a.(Builtin_Type) == b.(Builtin_Type)
	case Function_Type:
		afunc := a.(Function_Type)
		bfunc := b.(Function_Type)

		if (afunc.ret != nil) != (bfunc.ret != nil) {
			return false // one has returns, one doesnt
		}

		if len(afunc.parameters) != len(bfunc.parameters) {
			return false
		}

		eq := true
		for i in 0 ..< len(afunc.parameters) {
			assert(afunc.parameters[i].type != nil, "Function has nil type pointers")
			assert(bfunc.parameters[i].type != nil, "Function has nil type pointers")

			eq &&= types_are_equivalent(afunc.parameters[i].type, bfunc.parameters[i].type)
		}
		return eq
	}

	panic("Bad type type")
}

converts_to :: proc(t: ^Type, target: ^Type) -> bool {
	if t == nil {
		return false
	}

	if target == nil {
		return false
	}

	if types_are_equivalent(unwrap_type(t), unwrap_type(target)) {
		return true
	}

	return false
}

check_binary_expression :: proc(checker: ^Checker, left, right: ^Type, op: Token_Type) -> ^Type {
	if type_is_integer(left) && type_is_integer(right) {
		#partial switch op {
		case .Plus, .Minus, .Star, .Slash:
			return left
		}
	}

	if type_is_boolean(left) && type_is_boolean(right) {
	    return get_type(checker, Builtin_Type.Bool_Literal)
	}
	
	if types_are_equivalent(left, right) {
		if op == .Double_Equals || op == .Exclamation_Equals {
			return get_type(checker, Builtin_Type.Bool_Literal)
		}

		if type_is_integer(left) {
			if op == .Less || op == .Greater || op == .Less_Equals || op == .Greater_Equals {
				return get_type(checker, Builtin_Type.Bool_Literal)
			}
		}
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
	return &invalid_type
}

make_type :: proc(
	checker: ^Checker,
	$T: typeid,
) -> ^T where intrinsics.type_is_variant_of(Type, ^T) {
	type := new(T, checker.allocator)
	return type
}

