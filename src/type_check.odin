package palladium

import "base:intrinsics"
import "base:runtime"
import "core:container/xar"
import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"

Size :: distinct u64
Offset :: distinct u64

Builtin_Type :: enum {
	Integer_Literal,
	String_Literal,
	Bool_Literal,
}

Checked_String :: struct {
	data: [^]byte,
	len:  int,
}

Type :: union {
	Builtin_Type,
	Function_Type,
	Array_Type,
}

Array_Type :: struct {
	elem_type: ^Type,
	length:    int,
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
	Bad_Value,
	Redeclaration,
	Undeclared,
	Wrong_Argument_Count,
	Unknowable_Type,
	Bad_Control_Flow,
	Internal_Error,
}

Type_Error :: struct {
	message: string,
	type:    Checker_Error_Type,
}

Scope :: struct {
	type_registry: Type_Registry,
	variables:     map[string]^Checked_Declaration,
	aliases:       map[string]^Type,
}

Checker :: struct {
	errors:                   [dynamic]Type_Error,
	scopes:                   [dynamic]Scope,
	function_depth:           int,
	current_function:         ^Function,
	current_stack_frame_size: Size,
	loop_stack:               [dynamic]^Checked_Loop,
	allocator:                runtime.Allocator,
	// CONSIDER: this thing's lifetime is weird
	//           it can just leak for now
	string_interner:          strings.Intern,
}

Checked_Program :: struct {
	statements: xar.Array(Checked_Statement, 4),
}
Checked_Statement :: union {
	^Checked_Index_Write,
	^Checked_Variable_Write,
	^Checked_Expression_Statement,
	^Checked_Loop,
	^Checked_If,
	^Checked_Block,
	^Checked_Declaration,
	^Checked_Break,
	^Checked_Continue,
	^Checked_Return,
}
Checked_Return :: struct {
	val: Maybe(Checked_Expression),
}
Checked_Break :: struct {
	target: Checked_Statement,
}

Checked_Continue :: struct {
	target: Checked_Statement,
}

Checked_Declaration :: struct {
	name:   string,
	offset: Offset,
	type:   ^Type,
	value:  Maybe(Checked_Expression),
}

Checked_Block :: struct {
	statements: xar.Array(Checked_Statement, 4),
}

Checked_If :: struct {
	condition: Checked_Expression,
	body:      Checked_Statement,
	else_body: Maybe(Checked_Statement),
}

Checked_Loop :: struct {
	body:      Checked_Statement,
	condition: Checked_Expression,
}

Checked_Expression_Statement :: struct {
	expr: Checked_Expression,
}

Checked_Variable_Write :: struct {
	target:    ^Checked_Declaration,
	new_value: Checked_Expression,
}

Checked_Index_Write :: struct {
	target:    Checked_Expression,
	new_value: Checked_Expression,
}

invalid_expression := Checked_Expression {
	type    = &invalid_type,
	variant = nil,
}

Checked_Expression :: struct {
	type:    ^Type,
	variant: union {
		^Checked_Binary_Op,
		^Checked_Array_Index,
		// FUTURE: other bool/int/string types
		^Boolean_Node,
		^Integer_Node,
		^Checked_String,
		Function,
		^Checked_Variable_Read,
		^Checked_Call,
		^Array_Literal,
	},
}

Array_Literal :: struct {
	elem_type: ^Type,
	body:      xar.Array(Checked_Expression, 3),
}

Checked_Call :: struct {
	callee:    Checked_Expression,
	arguments: xar.Array(Checked_Expression, 3),
}

Checked_Variable_Read :: struct {
	decl: ^Checked_Declaration,
}

Checked_Array_Index :: struct {
	array: Checked_Expression,
	index: Checked_Expression,
}

Checked_Binary_Op :: struct {
	left:  Checked_Expression,
	right: Checked_Expression,
	op:    Checked_Binary_Operation,
}

Checked_Binary_Operation :: enum {
	Invalid = 0,
	Add_I64,
	Sub_I64,
	Mul_I64,
	Div_I64,
	Byte_Compare,
	Negate_Byte_Compare,
	Less_Than_I64,
	Greater_Than_I64,
	Less_Than_Or_Equal_To_I64,
	Greater_Than_Or_Equal_To_I64,
	Boolean_Or,
	Boolean_And,
}

make_checker :: proc(allocator: runtime.Allocator) -> Checker {
	checker: Checker
	checker.allocator = allocator
	checker.errors = make([dynamic]Type_Error, allocator)
	checker.scopes.allocator = allocator
	checker.loop_stack.allocator = context.temp_allocator
	return checker
}

check_program :: proc(
	root: Node,
	allocator: runtime.Allocator,
) -> (
	Checked_Program,
	[]Type_Error,
) {
	checker := make_checker(allocator)
	program: Checked_Program
	xar.array_init(&program.statements, checker.allocator)
	// superglobal builtins
	push_checker_scope(&checker)

	declare_named_type(&checker, "string", get_type(&checker, Builtin_Type.String_Literal))
	declare_named_type(&checker, "int", get_type(&checker, Builtin_Type.Integer_Literal))
	declare_named_type(&checker, "bool", get_type(&checker, Builtin_Type.Bool_Literal))

	body_block, is_block := root.(^Block_Node)
	assert(is_block, "malformed program")

	for iter := xar.iterator(&body_block.statements); stmt in xar.iterate_by_val(&iter) {
		xar.append(&program.statements, check_statement(&checker, stmt))
	}

	return program, checker.errors[:]
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

push_checker_scope :: proc(checker: ^Checker) {
	append(&checker.scopes, make_scope(checker))
}

pop_checker_scope :: proc(checker: ^Checker) {
	scope := pop(&checker.scopes)
	delete_scope(scope)
}

declare_variable_type :: proc(checker: ^Checker, decl: ^Checked_Declaration) {
	scope := &checker.scopes[len(checker.scopes) - 1]

	if decl.name in scope.variables {
		append(
			&checker.errors,
			Type_Error {
				type = .Redeclaration,
				message = fmt.tprintf("Redeclaration of variable %s in this scope", decl.name),
			},
		)
	} else {
		current_offset := Offset(checker.current_stack_frame_size)
		alignment := Offset(type_align_of(decl.type))
		size := Offset(type_size_of(decl.type))
		decl.offset = ((current_offset + (alignment - 1)) & ~(alignment - 1))
		checker.current_stack_frame_size = Size(decl.offset + size)
		scope.variables[decl.name] = decl
	}
}

check_index_write :: proc(checker: ^Checker, node: ^Index_Write_Node) -> Checked_Statement {
	target := check_index(checker, node.target)

	new_value := check_expression(checker, node.value, target.type)

	statement := checker_new(Checked_Index_Write, checker)
	statement.new_value = new_value
	statement.target = target

	if !is_convertible_from_to(new_value.type, target.type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to assign type %s to type %s",
					type_to_string(new_value.type, context.temp_allocator),
					type_to_string(target.type, context.temp_allocator),
				),
			},
		)
	}

	return statement
}

check_variable_write :: proc(checker: ^Checker, node: ^Variable_Write_Node) -> Checked_Statement {
	var, found := checker_resolve_variable(checker, node.name)

	stmt := checker_new(Checked_Variable_Write, checker)
	stmt.target = var

	if !found {
		append(
			&checker.errors,
			Type_Error {
				type = .Undeclared,
				message = fmt.tprintf("Undeclared variable '%s'", node.name),
			},
		)
		return stmt
	}

	expr := check_expression(checker, node.value, var.type)
	stmt.new_value = expr

	if !is_convertible_from_to(expr.type, var.type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to assign type %s to variable %s with type %s",
					type_to_string(expr.type, context.temp_allocator),
					node.name,
					type_to_string(var.type, context.temp_allocator),
				),
			},
		)
	}

	return stmt
}

check_while :: proc(checker: ^Checker, node: ^While_Node) -> Checked_Statement {
	stmt := checker_new(Checked_Loop, checker)
	cond := check_expression(checker, node.condition, get_type(checker, Builtin_Type.Bool_Literal))

	stmt.condition = cond

	if !is_convertible_from_to(cond.type, get_type(checker, Builtin_Type.Bool_Literal)) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to convert from %s to boolean in a while loop condition",
					type_to_string(cond.type, context.temp_allocator),
				),
			},
		)
	}

	append(&checker.loop_stack, stmt)
	stmt.body = check_statement(checker, node.body)
	pop(&checker.loop_stack)
	return stmt
}

check_if :: proc(checker: ^Checker, node: ^If_Node) -> Checked_Statement {
	stmt := checker_new(Checked_If, checker)
	cond := check_expression(checker, node.condition, get_type(checker, Builtin_Type.Bool_Literal))
	stmt.condition = cond

	if !is_convertible_from_to(cond.type, get_type(checker, Builtin_Type.Bool_Literal)) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to convert from %s to boolean in an if statement condition",
					type_to_string(cond.type, context.temp_allocator),
				),
			},
		)
	}

	stmt.body = check_statement(checker, node.body)

	if node.else_body != nil {
		stmt.else_body = check_statement(checker, node.else_body.?)
	}

	return stmt
}

check_statement :: proc(checker: ^Checker, stmt: Node) -> Checked_Statement {
	#partial switch type in stmt {
	case ^Variable_Declaration_Node:
		return check_variable_declaration(checker, type)
	case ^Variable_Write_Node:
		return check_variable_write(checker, type)
	case ^Index_Write_Node:
		return check_index_write(checker, type)
	case ^Block_Node:
		return check_block(checker, type)
	case ^While_Node:
		return check_while(checker, type)
	case ^If_Node:
		return check_if(checker, type)
	case ^Function_Declaration_Node:
		return check_function_declaration(checker, type)
	case ^Break_Node:
		return check_break(checker, type)
	case ^Continue_Node:
		return check_continue(checker, type)
	case ^Return_Node:
		return check_return(checker, type)
	case:
		return check_expression_statement(checker, stmt)
	}
}

check_return :: proc(checker: ^Checker, node: ^Return_Node) -> Checked_Statement {
	stmt := checker_new(Checked_Return, checker)

	if node.value != nil {
		// FUTURE: track curent function for return based hints?
		stmt.val = check_expression(checker, node.value.?, nil)
	}

	if checker.function_depth <= 0 {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Control_Flow,
				message = "`return` can only be used inside functions!",
			},
		)
	}

	return stmt
}

check_break :: proc(checker: ^Checker, node: ^Break_Node) -> Checked_Statement {
	stmt := checker_new(Checked_Break, checker)

	if len(checker.loop_stack) <= 0 {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Control_Flow,
				message = "`break` can only be used inside loops!",
			},
		)
	} else {
		stmt.target = checker.loop_stack[len(checker.loop_stack) - 1]
	}

	return stmt
}

check_continue :: proc(checker: ^Checker, node: ^Continue_Node) -> Checked_Statement {
	stmt := checker_new(Checked_Continue, checker)

	if len(checker.loop_stack) <= 0 {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Control_Flow,
				message = "`continue` can only be used inside loops!",
			},
		)
	} else {
		stmt.target = checker.loop_stack[len(checker.loop_stack) - 1]
	}

	return stmt
}


check_block :: proc(checker: ^Checker, node: ^Block_Node) -> Checked_Statement {
	block := checker_new(Checked_Block, checker)
	xar.init(&block.statements, checker.allocator)

	push_checker_scope(checker)
	for iter := xar.iterator(&node.statements); stmt in xar.iterate_by_val(&iter) {
		xar.append(&block.statements, check_statement(checker, stmt))
	}
	pop_checker_scope(checker)

	return block
}

check_function_declaration :: proc(
	checker: ^Checker,
	node: ^Function_Declaration_Node,
) -> Checked_Statement {
	decl := checker_new(Checked_Declaration, checker)
	decl.name = node.name
	decl.type = evaluate_type(checker, node)
	declare_variable_type(checker, decl)
	push_checker_scope(checker)
	checker.function_depth += 1


	params: xar.Array(^Checked_Declaration, 2)
	xar.init(&params, checker.allocator)
	func := Function {
		parameters = params,
	}
	// CONSIDER: disallow nested functions?
	last_func := checker.current_function
	last_sfs := checker.current_stack_frame_size
	checker.current_function = &func
	checker.current_stack_frame_size = 0
	for param in decl.type.(Function_Type).parameters {
		param_decl := checker_new(Checked_Declaration, checker)
		param_decl.name = param.name
		param_decl.type = param.type
		declare_variable_type(checker, param_decl)
		xar.append(&func.parameters, param_decl)
	}

	body := check_block(checker, node.body.(^Block_Node))

	checker.function_depth -= 1
	pop_checker_scope(checker)
	checker.current_function = last_func
	checker.current_stack_frame_size = last_sfs

	decl.value = Checked_Expression {
		variant = func,
		type    = decl.type,
	}
	return decl
}

check_variable_declaration :: proc(
	checker: ^Checker,
	node: ^Variable_Declaration_Node,
) -> Checked_Statement {
	decl := checker_new(Checked_Declaration, checker)
	if t, not_inferred := node.type.?; not_inferred {
		decl.type = evaluate_type(checker, t)
	}
	decl.name = node.name
	expr := check_expression(checker, node.value, decl.type)
	decl.value = expr

	if decl.type == nil {
		decl.type = expr.type
	}
	if !is_convertible_from_to(expr.type, decl.type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Unable to assign type %s to variable %s with type %s",
					type_to_string(expr.type, context.temp_allocator),
					node.name,
					type_to_string(decl.type, context.temp_allocator),
				),
			},
		)

	}

	declare_variable_type(checker, decl)

	return decl
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
	case Array_Type:
		fmt.sbprintf(builder, "[%d]", variant.length)
		write_type(variant.elem_type, builder)
		return
	}

	fmt.panicf("Very bad type %s", type)
}

checker_resolve_variable :: proc(checker: ^Checker, name: string) -> (^Checked_Declaration, bool) {
	#reverse for scope in checker.scopes {
		val, ok := scope.variables[name]
		if ok do return val, true
	}

	return nil, false
}

evaluate_type :: proc(checker: ^Checker, node: Node) -> ^Type {
	#partial switch variant in node {
	case ^Variable_Read_Node:
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

		params := make([]Parameter_Type, xar.len(variant.parameters), checker.allocator)
		for &param, i in params {
			param.name = xar.get(&variant.parameters, i).name
			param.type = evaluate_type(checker, xar.get(&variant.parameters, i).type)
		}
		return get_type(checker, Function_Type{parameters = params, ret = ret})
	case ^Array_Type_Node:
		length := check_expression(checker, variant.length, nil)
		if !type_is_integer(length.type) {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Conversion,
					message = fmt.tprintf(
						"Expected an integer length for an array, but recieved %s",
						type_to_string(length.type, context.temp_allocator),
					),
				},
			)
			return &invalid_type
		}

		// FUTURE: compile-time length evaluation.
		//          big can of worms :(
		if _, is_int := variant.length.(^Integer_Node); !is_int {
			append(
				&checker.errors,
				Type_Error {
					type = .Internal_Error,
					message = "Non-literal array lengths are currently unsupported, but planned!",
				},
			)
			return &invalid_type
		}

		length_val := variant.length.(^Integer_Node).value
		// CONSIDER: 0-length arrays? that's probably fine?
		//           but sizeless values are a bit odd
		if length_val < 0 {
			append(
				&checker.errors,
				Type_Error{type = .Bad_Value, message = "Array lengths cannot be negative"},
			)
			return &invalid_type
		}

		elem_type := evaluate_type(checker, variant.elem)

		return get_type(checker, Array_Type{elem_type = elem_type, length = int(length_val)})
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

check_expression_statement :: proc(checker: ^Checker, node: Node) -> Checked_Statement {
	stmt := checker_new(Checked_Expression_Statement, checker)

	stmt.expr = check_expression(checker, node, nil)

	return stmt
}

check_expression :: proc(
	checker: ^Checker,
	node: Node,
	type_hint: Maybe(^Type),
) -> Checked_Expression {
	#partial switch type in node {
	case ^Binary_Op_Node:
		return check_binary_expression(checker, type)
	case ^Variable_Read_Node:
		return check_variable_read(checker, type)
	case ^Compound_Node:
		return check_compound(checker, type, type_hint)
	case ^Call_Node:
		return check_call(checker, type)
	case ^Index_Node:
		return check_index(checker, type)
	case ^String_Node:
		return check_string_literal(checker, type)
	case ^Integer_Node:
		return {type = get_type(checker, Builtin_Type.Integer_Literal), variant = type}
	case ^Boolean_Node:
		return {type = get_type(checker, Builtin_Type.Bool_Literal), variant = type}
	case:
		fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(node))

	}
}

check_string_literal :: proc(checker: ^Checker, node: ^String_Node) -> Checked_Expression {
	interned, _ := strings.intern_get(&checker.string_interner, node.value)
	expr := checker_new(Checked_String, checker)
	expr.data = raw_data(interned)
	expr.len = len(interned)
	return Checked_Expression{
		variant = expr,
		type = get_type(checker, Builtin_Type.String_Literal)
	}
}

check_variable_read :: proc(checker: ^Checker, node: ^Variable_Read_Node) -> Checked_Expression {
	var, found := checker_resolve_variable(checker, node.name)
	read := checker_new(Checked_Variable_Read, checker)
	read.decl = var
	expr := Checked_Expression {
		variant = read,
		type    = &invalid_type,
	}
	if !found {
		append(
			&checker.errors,
			Type_Error {
				type = .Undeclared,
				message = fmt.tprintf("Undeclared variable '%s'", node.name),
			},
		)
		return expr
	}
	expr.type = var.type
	return expr
}

check_compound :: proc(
	checker: ^Checker,
	compound: ^Compound_Node,
	type_hint: Maybe(^Type),
) -> Checked_Expression {
	target_type: ^Type

	if compound.type != nil {
		target_type = evaluate_type(checker, compound.type.?)
	}
	if target_type == nil {
		target_type = type_hint.? or_else nil
	}

	if target_type == nil {
		append(
			&checker.errors,
			Type_Error{type = .Unknowable_Type, message = "This compound literal has no type."},
		)

		return invalid_expression
	}


	if type_is_array(target_type) {
		array := checker_new(Array_Literal, checker)
		expr := Checked_Expression {
			type    = target_type,
			variant = array,
		}
		arr_type := target_type.(Array_Type)
		array.elem_type = arr_type.elem_type
		xar.init(&array.body, checker.allocator)
		if arr_type.length != xar.len(compound.values) {
			append(
				&checker.errors,
				Type_Error {
					type = .Wrong_Argument_Count,
					message = fmt.tprintf(
						"Wrong number of values for array literal! Expected %d but received %d",
						arr_type.length,
						xar.len(compound.values),
					),
				},
			)
		}

		for iter := xar.iterator(&compound.values); expr in xar.iterate_by_val(&iter) {
			elem := check_expression(checker, expr, arr_type.elem_type)
			xar.append(&array.body, elem)
			if !is_convertible_from_to(elem.type, arr_type.elem_type) {
				append(
					&checker.errors,
					Type_Error {
						type = .Bad_Conversion,
						message = fmt.tprintf(
							"Cannot convert from %s to %s",
							type_to_string(elem.type, context.temp_allocator),
							type_to_string(arr_type.elem_type, context.temp_allocator),
						),
					},
				)
			}
		}

		return expr
	}

	// FUTURE: Slices, Structs
	append(
		&checker.errors,
		Type_Error {
			type = .Bad_Conversion,
			message = fmt.tprintf(
				"Cannot create a compound literal for type `%s`.",
				type_to_string(target_type, context.temp_allocator),
			),
		},
	)
	return invalid_expression
}

type_is_array :: proc(t: ^Type) -> bool {
	t := unwrap_type(t)
	_, is_arr := t.(Array_Type)
	return is_arr
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

check_index :: proc(checker: ^Checker, node: ^Index_Node) -> Checked_Expression {
	array := check_expression(checker, node.base, nil)

	checked_index := checker_new(Checked_Array_Index, checker)
	checked_index.array = array
	expr := Checked_Expression {
		variant = checked_index,
		type    = &invalid_type,
	}

	if !type_is_array(array.type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Expected an array type for index expression, got %s",
					type_to_string(array.type, context.temp_allocator),
				),
			},
		)
		return expr
	}

	arr_type := array.type.(Array_Type)

	index := check_expression(checker, node.index, nil)
	checked_index.index = index
	if !type_is_integer(index.type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Expected integer for index type, recieved %s",
					type_to_string(index.type, context.temp_allocator),
				),
			},
		)
	}

	expr.type = arr_type.elem_type
	return expr
}

check_call :: proc(checker: ^Checker, node: ^Call_Node) -> Checked_Expression {
	call := checker_new(Checked_Call, checker)
	callee := check_expression(checker, node.callee, nil)
	call.callee = callee
	xar.init(&call.arguments, checker.allocator)
	expr := Checked_Expression {
		variant = call,
		type    = &invalid_type,
	}

	if !type_is_function(callee.type) {
		append(
			&checker.errors,
			Type_Error {
				type = .Bad_Conversion,
				message = fmt.tprintf(
					"Expected a function type for call expression, got %s",
					type_to_string(callee.type, context.temp_allocator),
				),
			},
		)

		return expr
	}

	func_type := callee.type.(Function_Type)
	if len(func_type.parameters) != xar.len(node.arguments) {
		append(
			&checker.errors,
			Type_Error {
				type = .Wrong_Argument_Count,
				message = fmt.tprintf(
					"Wrong number of arguments for call! Expected %d but received %d",
					len(func_type.parameters),
					xar.len(node.arguments),
				),
			},
		)

		return expr
	}

	for i in 0 ..< xar.len(node.arguments) {
		param := func_type.parameters[i]
		arg := check_expression(checker, xar.get(&node.arguments, i), param.type)
		xar.append(&call.arguments, arg)

		if !types_are_equivalent(arg.type, param.type) {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Conversion,
					message = fmt.tprintf(
						"Unable to assign type %s to parameter %s with type %s",
						type_to_string(arg.type, context.temp_allocator),
						param.name,
						type_to_string(param.type, context.temp_allocator),
					),
				},
			)
		}
	}

	expr.type = func_type.ret

	return expr
}

// Strict equivalence, no implicit conversions
types_are_equivalent :: proc(a_ptr, b_ptr: ^Type, loc := #caller_location) -> bool {
	if a_ptr == b_ptr {
		if a_ptr == &invalid_type {
			return false
		}
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
	case Array_Type:
		aarr := a.(Array_Type)
		barr := b.(Array_Type)

		if aarr.length != barr.length {
			return false
		}

		return types_are_equivalent(aarr.elem_type, barr.elem_type)
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

check_binary_expression :: proc(checker: ^Checker, node: ^Binary_Op_Node) -> Checked_Expression {
	checked_node := checker_new(Checked_Binary_Op, checker)

	left := check_expression(checker, node.left, nil)
	right := check_expression(checker, node.right, left.type)

	checked_node.left = left
	checked_node.right = right
	expr := Checked_Expression {
		variant = checked_node,
		type    = &invalid_type,
	}

	switch node.op {
	case .Invalid:
		panic("Invalid operation")
	case .Addition:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Add_I64
		} else {
			append(
				&checker.errors,
				Type_Error{type = .Bad_Operator, message = "Expected integer types for addition"},
			)
		}
	case .Subtraction:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Sub_I64
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected integer types for subtraction",
				},
			)
		}
	case .Multiplication:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Mul_I64
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected integer types for multiplication",
				},
			)
		}
	case .Division:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Div_I64
		} else {
			append(
				&checker.errors,
				Type_Error{type = .Bad_Operator, message = "Expected integer types for division"},
			)
		}
	case .Less_Than:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Less_Than_I64
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected integer types for comparison",
				},
			)
		}
	case .Less_Than_Or_Equal_To:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Less_Than_Or_Equal_To_I64
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected integer types for comparison",
				},
			)
		}
	case .Greater_Than:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Greater_Than_I64
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected integer types for comparison",
				},
			)
		}
	case .Greater_Than_Or_Equal_To:
		if type_is_integer(left.type) && type_is_integer(right.type) {
			checked_node.op = .Greater_Than_Or_Equal_To_I64
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected integer types for comparison",
				},
			)
		}
	case .Equal_To:
		if !types_are_equivalent(left.type, right.type) {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected equivalent types for comparison",
				},
			)
		} else {
			checked_node.op = .Byte_Compare
		}
	case .Not_Equal_To:
		if !types_are_equivalent(left.type, right.type) {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected equivalent types for comparison",
				},
			)
		} else {
			checked_node.op = .Negate_Byte_Compare
		}
	case .Logical_And:
		if type_is_boolean(left.type) && type_is_boolean(right.type) {
			checked_node.op = .Boolean_And
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected boolean types for logical and",
				},
			)
		}
	case .Logical_Or:
		if type_is_boolean(left.type) && type_is_boolean(right.type) {
			checked_node.op = .Boolean_Or
		} else {
			append(
				&checker.errors,
				Type_Error {
					type = .Bad_Operator,
					message = "Expected boolean types for logical or",
				},
			)
		}
	}

	switch checked_node.op {
	case .Invalid:
		expr.type = &invalid_type
	case .Add_I64, .Sub_I64, .Div_I64, .Mul_I64:
		expr.type = checked_node.left.type
	case .Byte_Compare,
	     .Negate_Byte_Compare,
	     .Less_Than_I64,
	     .Greater_Than_I64,
	     .Less_Than_Or_Equal_To_I64,
	     .Greater_Than_Or_Equal_To_I64,
	     .Boolean_Or,
	     .Boolean_And:
		expr.type = get_type(checker, Builtin_Type.Bool_Literal)
	}

	// append(
	// 	&checker.errors,
	// 	Type_Error {
	// 		type = .Bad_Operator,
	// 		message = fmt.tprintf(
	// 			"Unable to use operator %s on types %s and %s",
	// 			op,
	// 			type_to_string(left.type, context.temp_allocator),
	// 			type_to_string(right.type, context.temp_allocator),
	// 		),
	// 	},
	// )
	return expr
}

make_type :: proc(
	checker: ^Checker,
	$T: typeid,
) -> ^T where intrinsics.type_is_variant_of(Type, ^T) {
	type := new(T, checker.allocator)
	return type
}

checker_new :: proc($T: typeid, checker: ^Checker) -> ^T {
	return new(T, checker.allocator)
}

type_size_of :: proc(t: ^Type) -> Size {
	switch variant in t {
	case Builtin_Type:
		switch variant {
		case .Integer_Literal:
			return size_of(i64)
		case .String_Literal:
			return size_of(string)
		case .Bool_Literal:
			return size_of(bool)
		}
	case Function_Type:
		return size_of(rawptr)
	case Array_Type:
		return Size(variant.length) * type_size_of(variant.elem_type)
	case nil:
		return 0
	}
	panic("Impossible type")
}

type_align_of :: proc(t: ^Type) -> Size {
	switch variant in t {
	case Builtin_Type:
		switch variant {
		case .Integer_Literal:
			return align_of(i64)
		case .String_Literal:
			return align_of(string)
		case .Bool_Literal:
			return align_of(bool)
		}
	case Function_Type:
		return align_of(rawptr)
	case Array_Type:
		return type_align_of(variant.elem_type)
	case nil:
		return 1
	}
	panic("Impossible type")
}

