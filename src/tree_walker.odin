package palladium

import "core:container/xar"
import "core:log"
import "core:fmt"
import "core:reflect"

CHECKED_RUNTIME :: #config(CHECKED_RUNTIME, false)


Runtime :: struct {
	scopes: [dynamic]map[string]Value,
}

// FUTURE: when we get to bytecode,
//         make this all inline
Array :: struct {
	length: i64,
	data:   [^]Value,
}

Value :: union {
	i64,
	string,
	bool,
	Function,
	Array,
}

Runtime_Error_Type :: enum {
	Undeclared_Variable,
	Redeclared_Variable,
	Type_Error,
	Bad_Control_Flow,
	Bad_Call,
	Out_Of_Bounds_Index,
}

Runtime_Error :: struct {
	type:    Runtime_Error_Type,
	message: string,
}

Function :: struct {
	parameters: xar.Array(^Checked_Declaration, 2),
	body:       Checked_Statement,
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

execute_file :: proc(rt: ^Runtime, file: Checked_Program) -> Maybe(Runtime_Error) {
	file := file
	// no pop so we can read variables in tests
	push_scope(rt)

	for iter := xar.iterator(&file.statements); statement in xar.iterate_by_val(&iter) {
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
execute_statement :: proc(rt: ^Runtime, statement: Checked_Statement) -> Runtime_Propagation {
	#partial switch type in statement {
	case ^Checked_Declaration:
		declare_variable(rt, type) or_return
	case ^Checked_Block:
		execute_block(rt, type) or_return
	case ^Checked_Variable_Write:
		write_variable(rt, type) or_return
	case ^Checked_Index_Write:
	    write_index(rt, type) or_return
	case ^Checked_If:
		execute_if(rt, type) or_return
	case ^Checked_Loop:
		execute_while(rt, type) or_return
	case ^Checked_Break:
		return Break{}
	case ^Checked_Continue:
		return Continue{}
	case ^Checked_Return:
		ret: Return
		if node, ok := type.val.?; ok {
			ret.val = evaluate_expression(rt, node) or_return
		}

		return ret
	case:
		fmt.panicf("Impossible statement type '%s'", reflect.union_variant_typeid(statement))
	}

	return nil
}

execute_block :: proc(rt: ^Runtime, block: ^Checked_Block) -> Runtime_Propagation {
	push_scope(rt)
	defer pop_scope(rt)
	for iter := xar.iterator(&block.statements); stmt in xar.iterate_by_val(&iter) {
		execute_statement(rt, stmt) or_return
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

declare_variable :: proc(rt: ^Runtime, stmt: ^Checked_Declaration) -> Runtime_Propagation {
	// TODO: zero initialize
	val := evaluate_expression(rt, stmt.value.?) or_return

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

execute_while :: proc(rt: ^Runtime, stmt: ^Checked_Loop) -> Runtime_Propagation {

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

execute_if :: proc(rt: ^Runtime, stmt: ^Checked_If) -> Runtime_Propagation {
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
write_index :: proc(rt: ^Runtime, node: ^Checked_Index_Write) -> Runtime_Propagation {
    target := evaluate_expression(rt, node.target.variant.(^Checked_Array_Index).array) or_return
	arr := unwrap_value(target, Array) or_return
	assert(arr.data != nil, "nil array data")
   
	index_expr := evaluate_expression(rt, node.target.variant.(^Checked_Array_Index).index) or_return
	index := unwrap_value(index_expr, i64) or_return
   
	if index < 0 || index >= arr.length {
		return Runtime_Error{type = .Out_Of_Bounds_Index, message = fmt.tprintf("Index %d is out of bounds for array of length %d", index, arr.length)}
	}
   
	arr.data[index] = evaluate_expression(rt, node.new_value) or_return

	return nil
}

@(require_results)
write_variable :: proc(rt: ^Runtime, node: ^Checked_Variable_Write) -> Runtime_Propagation {
	var := resolve_variable(rt, node.target.name)

	if var == nil {
		return Runtime_Error {
			type = .Undeclared_Variable,
			message = fmt.tprintf("Undeclared variable '%s'", node.target.name),
		}
	}

	var^ = evaluate_expression(rt, node.new_value) or_return

	return nil
}

evaluate_expression :: proc(rt: ^Runtime, expr: Checked_Expression) -> (Value, Runtime_Propagation) {
	#partial switch type in expr.variant {
	case ^Checked_Binary_Op:
		return evaluate_binary_expression(rt, type)
	case ^Integer_Node:
		return type.value, nil
	case ^Boolean_Node:
		return type.value, nil
	case ^Checked_Variable_Read:
		return read_variable(rt, type.decl.name)
	case ^String_Node:
		return type.value, nil
	case Function:
		return type, nil
	case ^Checked_Call:
		return call_function(rt, type)
	case ^Checked_Array_Index:
		return evaluate_index(rt, type)
	case ^Array_Literal:
	    return evaluate_array_literal(rt, type)
	}

	fmt.panicf("Impossible expression type '%s'", reflect.union_variant_typeid(expr.variant))
}

// FUTURE: try avoiding using types at runtime
//         maybe swap out the AST nodes in type checking?
//         array lengths could also be reduced to integers that way
evaluate_array_literal :: proc(rt: ^Runtime, expr: ^Array_Literal) -> (_v: Value, _e: Runtime_Propagation) {
    length := xar.len(expr.body)
    // FUTURE: this always leaks. probably 
    //         okay for now, but needs 
    //         fixing for bytecode
    values := make([^]Value, length)

    for iter := xar.iterator(&expr.body); elem, i in xar.iterate_by_val(&iter) {
        values[i] = evaluate_expression(rt, elem) or_return
    }
    
    return Array {
        data = values,
        length = i64(length)
    }, nil
}

evaluate_index :: proc(rt: ^Runtime, expr: ^Checked_Array_Index) -> (_val: Value, _ret: Runtime_Propagation) {
	target := evaluate_expression(rt, expr.array) or_return
	arr := unwrap_value(target, Array) or_return
	assert(arr.data != nil, "nil array data")

	index_expr := evaluate_expression(rt, expr.index) or_return
	index := unwrap_value(index_expr, i64) or_return

	if index < 0 || index >= arr.length {
		return {}, Runtime_Error{type = .Out_Of_Bounds_Index, message = fmt.tprintf("Index %d is out of bounds for array of length %d", index, arr.length)}
	}

	return arr.data[index], nil
}

call_function :: proc(rt: ^Runtime, call: ^Checked_Call) -> (_val: Value, _ret: Runtime_Propagation) {
	callee := evaluate_expression(rt, call.callee) or_return
	function := unwrap_value(callee, Function) or_return

	if xar.len(function.parameters) != xar.len(call.arguments) {
		return {}, Runtime_Error{type = .Bad_Call, message = fmt.tprintf("Bad argument count for function. Expected %d but recieved %d", xar.len(function.parameters), xar.len(call.arguments))}
	}

	push_scope(rt)
	defer pop_scope(rt)

	for iter := xar.iterator(&call.arguments); arg, i in xar.iterate_by_val(&iter) {
		name := xar.get(&function.parameters, i)
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
	expr: ^Checked_Binary_Op,
) -> (
	_val: Value,
	_err: Runtime_Propagation,
) {
	left := evaluate_expression(rt, expr.left) or_return
	#partial switch expr.op {
	case .Logical_Or:
		left := unwrap_value(left, bool) or_return

		if left do return true, nil

		right := evaluate_expression(rt, expr.right) or_return
		right_raw := unwrap_value(right, bool) or_return

		if right_raw do return true, nil

		return false, nil
	case .Logical_And:
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
	expr: ^Checked_Binary_Op,
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
	expr: ^Checked_Binary_Op,
) -> (
	_val: Value,
	_err: Runtime_Propagation,
) {
	left := evaluate_expression(rt, expr.left) or_return
	right := evaluate_expression(rt, expr.right) or_return
	#partial switch expr.op {
	case .Addition:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left + right, nil
	case .Subtraction:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left - right, nil
	case .Multiplication:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left * right, nil
	case .Division:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left / right, nil
	case .Equal_To:
		return values_equal(left, right)
	case .Not_Equal_To:
		return !(values_equal(left, right) or_return), nil
	case .Less_Than:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left < right, nil
	case .Greater_Than:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left > right, nil
	case .Less_Than_Or_Equal_To:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left <= right, nil
	case .Greater_Than_Or_Equal_To:
		left := unwrap_value(left, i64) or_return
		right := unwrap_value(right, i64) or_return
		return left >= right, nil
	}

	fmt.panicf("Impossible binary expression operator %s", expr.op)
}

values_equal :: proc(a, b: Value) -> (_eq: bool, _err: Runtime_Propagation) {
	a_type := reflect.union_variant_typeid(a)
	b_type := reflect.union_variant_typeid(b)

	if a_type != b_type {
		when CHECKED_RUNTIME {
			return false, Runtime_Error {
				type = .Type_Error,
				message = fmt.tprintf(
					"Expected both sides of equality to be the same type, but but recieved %s and %s",
					a_type,
					b_type,
				),
			}
		} else {
			panic("Sides of equality are not equal.")
		}
	}

	switch type in a {
	case i64:
		return a.(i64) == b.(i64), nil
	case bool:
		return a.(bool) == b.(bool), nil
	case string:
		return a.(string) == b.(string), nil
	case Array:
		aarr := a.(Array)
		barr := b.(Array)
		when CHECKED_RUNTIME {
			if aarr.length != barr.length {
				return false, Runtime_Error {
					type = .Type_Error,
					message = fmt.tprintf(
						"Both arrays should have the same length, recieved %d and %d",
						aarr.length,
						barr.length,
					),
				}
			}
		} else {
			for i in 0 ..< aarr.length {
				if !(values_equal(aarr.data[i], barr.data[i]) or_return) {
				    return false, nil
				}
			}
			return true, nil
		}
	case Function:
		return a.(Function).body == b.(Function).body, nil
	}

	fmt.panicf("Impossible value type %s", a_type)
}

short_circuits :: proc(op: Binary_Operation) -> bool {
	#partial switch op {
	case .Logical_Or, .Logical_And:
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
	unwrap_value :: proc(
		val: Value,
		$T: typeid,
		loc := #caller_location,
	) -> (
		T,
		Runtime_Propagation,
	) {
		unwrapped, ok := val.(T)
		assert(ok, loc = loc)
		return unwrapped, nil
	}
}

