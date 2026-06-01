package palladium

import "core:fmt"
import "core:hash"
import "core:slice"

Type_Registry :: map[Type_Hash]^Type

Type_Hash :: distinct u64

invalid_type: Type = nil

bytesof :: proc(t: ^$T) -> []byte {
	return slice.from_ptr((^byte)(t), size_of(t))
}

declare_named_type :: proc(checker: ^Checker, name: string, type: ^Type) {
	this_scope := &checker.scopes[len(checker.scopes) - 1].aliases

	if name in this_scope {
		append(
			&checker.errors,
			Type_Error {
				type = .Redeclaration,
				message = fmt.tprintf("Redeclaration of type %s in this scope", name),
			},
		)
		return
	}

	this_scope[name] = type
}

find_type_by_name :: proc(checker: ^Checker, name: string) -> (^Type, bool) {
	#reverse for &scope in checker.scopes {
		type, exists := scope.aliases[name]
		if exists {
			return type, true
		}
	}

	return {}, false
}

get_type :: proc(checker: ^Checker, t: Type) -> ^Type {
    assert(len(checker.scopes) > 0, "No open scopes?")
	t := t
	id := hash_type(t)

	#reverse for &scope in checker.scopes {
		val, ok := scope.type_registry[id]
		if ok {
			assert(
				types_are_equivalent(val, &t),
				"Hash collision in the type checker. I honestly don't know what to do here, sorry!",
			)

			return val
		}
	}

	this_scope := &checker.scopes[len(checker.scopes) - 1].type_registry

	this_scope[id] = new_clone(t, checker.allocator)

	return this_scope[id]
}

hash_type :: proc(t: Type, loc := #caller_location) -> Type_Hash {
	switch &type in t {
	case Builtin_Type:
		return auto_cast hash.fnv64a(bytesof(&type))
	case Function_Type:
		// magic number from core:hash, pretty good seed
		running_hash: u64 = 0xcbf29ce484222325

		if type.ret != nil {
			running_hash = hash.fnv64a(bytesof(&type.ret), running_hash)
		}

		for &param in type.parameters {
			running_hash = hash.fnv64a(bytesof(&param.type), running_hash)
		}

		return Type_Hash(running_hash)

	}
	panic("Impossible type", loc = loc)
}

