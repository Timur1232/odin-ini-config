//
// Generic parser for custom configuration model.
//
// Model type must be struct. Each field is representing ini sections and must
// be struct as well.
//
// Section structs must contain only primitive types, like
// integers, floats and strings, or color types. Color type is 4 element array
// of any integer (e.g. [4]u8).
//
// Strings are cloned to passed allocator.
//
// Section names taken either from field name or tag with key `ini_section`.
//
// Option names taken either from field name of tag with key `ini_option`.
//
// Example:
// ```odin
// Config_Model :: struct {
//     style: Style_Section `ini_section:"urmom"`,
//     window: Window_Section,
// }
//
// Color :: [4]u8
//
// Style_Section :: struct {
//     roundness: f64,
//     bg_color: Color,
// }
//
// Window_Section :: struct {
//     x: int `ini_option:"aboba"`,
//     y: int,
//     width, height: int,
// }
//
// main :: proc() {
//     defer free_all(context.temp_allocator)
//     defer free_all(context.allocator)
//
//     config: Config_Model
//     res := iniconf.config_load_from_path(&config, "config.ini")
//     assert(res != .Fatal_Error)
//
//     config.window.width = 420
//     iniconf.config_save_to_path(&config, "config.ini")
// }
// ```
//
// Parser will ignore options, that not set in ini file. So, to have defaults, you need to initialize them before parsing:
// ```odin
// config: Config
// some_defaults(&config)
// iniconf.config_load_from_path(&config, "config.ini")
// ```
//
// To turn logging not presented sections and options, set `-define:LOG_NOT_PRESENTED=true`.
// To turn logging unrecognized sections and options, set `-define:LOG_UNRECOGNIZED=true`.
//
package ini_config

INI_SECTION_TAG_KEY :: "ini_section"
INI_OPTION_TAG_KEY  :: "ini_option"

COLOR_FORMAT_STRING_LENGTH :: 9 // "#rrggbbaa"

// Will log if section or option from model is not presented inside ini file
LOG_NOT_PRESENTED :: #config(LOG_NOT_PRESENTED, false)

// Will log unrecognized sections or options
LOG_UNRECOGNIZED :: #config(LOG_UNRECOGNIZED, false)

// Default block size for arena, that storing strings of proccessed sections and options. Used only when LOG_UNRECOGNIZED is true.
PROCCESSED_ARENA_BLOCK_SIZE :: #config(PROCCESSED_ARENA_BLOCK_SIZE, 1024*4)

Parse_Result :: enum {
    Ok,
    Has_Parse_Errors,
    Fatal_Error,
}

// Paramenters:
// - model: ^<generic struct> - pointer to user's configuration model.
// - ini_map: ini.Map - map, loaded from ini file with `core:encoding/ini` package.
// - allocator: runtime.Allocator - for storing strings. Also used for finding unrecognized options when `LOG_UNRECOGNIZED` is true.
//
// Returns:
// - res: Parse_Result - whether parsing is successful or not. Ok - ok, Has_Parse_Errors - configuration has syntax errors (parser will skip them), Fatal_Error - fatal error (parsing is stopped)
//
// See config_load_from_path
config_parse :: proc(model: ^$T, ini_map: ini.Map, allocator := context.allocator, loc := #caller_location) -> (res: Parse_Result) where intrinsics.type_is_struct(T) {
    model_ti := reflect.type_info_base(type_info_of(T)).variant.(runtime.Type_Info_Struct)

    when LOG_UNRECOGNIZED {
        proccessed_arena: mem.Dynamic_Arena
        mem.dynamic_arena_init(&proccessed_arena, allocator, allocator, PROCCESSED_ARENA_BLOCK_SIZE)
        defer {
            mem.dynamic_arena_destroy(&proccessed_arena)
        }
        proccessed := make(map[string]map[string]struct{}, mem.dynamic_arena_allocator(&proccessed_arena))
    }

    for i in 0..<model_ti.field_count {
        section_name := get_ini_name(&model_ti, i, INI_SECTION_TAG_KEY)

        if section_map, ok := ini_map[section_name]; ok {
            section_ti := reflect.type_info_base(model_ti.types[i])
            section_offset := cast(uintptr)model + model_ti.offsets[i]

            when LOG_UNRECOGNIZED {
                proccessed[section_name] = {}
                proccessed_section := &proccessed[section_name]
            }

            #partial switch &section_v in section_ti.variant {
            case runtime.Type_Info_Struct:
                for j in 0..<section_v.field_count {
                    option_name := get_ini_name(&section_v, j, INI_OPTION_TAG_KEY)

                    if option_str, ok := section_map[option_name]; ok {
                        option_ti := reflect.type_info_base(section_v.types[j])
                        option_ptr := cast(rawptr)(section_offset + section_v.offsets[j])

                        when LOG_UNRECOGNIZED {
                            proccessed_section[option_name] = {}
                        }

                        #partial switch option_v in option_ti.variant {
                        case runtime.Type_Info_String:
                            err: runtime.Allocator_Error
                            if option_v.is_cstring {
                                (cast(^cstring)option_ptr)^, err = strings.clone_to_cstring(option_str, allocator)
                            } else {
                                (cast(^string)option_ptr)^, err = strings.clone(option_str, allocator)
                            }
                            if err != nil {
                                log.errorf("Allocator error while cloning strings: %v", err, location = loc)
                                res = .Fatal_Error
                                return
                            }
                        case runtime.Type_Info_Array: // Color
                            #partial switch elem_v in option_v.elem.variant {
                            case runtime.Type_Info_Integer:
                                if len(option_str) == COLOR_FORMAT_STRING_LENGTH && strings.starts_with(option_str, "#") {
                                    color_str := option_str[1:]
                                    for c in 0..<option_v.count {
                                        component_str := color_str[c*2:][:2]
                                        component_ptr := cast(rawptr)(cast(uintptr)option_ptr + cast(uintptr)(option_v.elem.size*c))
                                        parse_and_set_ok := parse_and_set_pointer_by_base_type(component_ptr, component_str, option_v.elem, int_hex = true)
                                        if !parse_and_set_ok {
                                            res = .Has_Parse_Errors
                                            log.errorf("Parse error: Unable to parse or set %d color component of option `%s.%s` with value `%s`", c, section_name, option_name, option_str, location = loc)
                                            break
                                        }
                                    }
                                } else {
                                    res = .Has_Parse_Errors
                                    log.errorf("Parse error: invalid format for `%s.%s`: color type must be in format `#rrggbbaa` in hex", section_name, option_name, location = loc)
                                }
                            case:
                                res = .Fatal_Error
                                log.errorf("Type error: For vector types only array of any 4 integers is supported: for field `%s` expected type `[4]any_int`, but got `%s`", section_v.names[j], elem_v, location = loc)
                                return
                            }
                        case:
                            parse_and_set_ok := parse_and_set_pointer_by_base_type(option_ptr, option_str, option_ti)
                            if !parse_and_set_ok {
                                res = .Has_Parse_Errors
                                log.errorf("Parse error: Unable to parse or set option `%s.%s` with value `%s`", section_name, option_name, option_str, location = loc)
                            }
                        }
                    } else if LOG_NOT_PRESENTED {
                        log.warnf("Option `%s.%s` is not presented. Skipping.", section_name, option_name, location = loc)
                    }
                }
            case:
                res = .Fatal_Error
                log.errorf("Sections must be structs: type of section field `%s` is `%v`.", model_ti.names[i], section_ti, location = loc)
                return
            }
        } else if LOG_NOT_PRESENTED {
            log.warnf("Section `%s` is not presented. Skipping.", section_name, location = loc)
        }
    }

    when LOG_UNRECOGNIZED {
        for section_name, section in ini_map {
            if proccessed_section, ok := proccessed[section_name]; ok {
                for option_name in section {
                    if _, ok := proccessed_section[option_name]; !ok {
                        log.warnf("Option `%s.%s` unrecognized.", section_name, option_name, location = loc)
                    }
                }
            } else {
                log.warnf("Section `%s` unrecognized.", section_name, location = loc)
            }
        }
    }

    return
}

// See config_parse
config_load_from_path :: proc(model: ^$T, path: string, ini_allocator := context.temp_allocator, string_allocator := context.allocator, loc := #caller_location) -> Parse_Result {
    ini_map, err, ok := ini.load_map_from_path(path, ini_allocator)
    if err != nil || !ok do return .Fatal_Error
    return config_parse(model, ini_map, string_allocator, loc)
}

// See config_parse
config_load_from_string :: proc(model: ^$T, src: string, ini_allocator := context.temp_allocator, string_allocator := context.allocator, loc := #caller_location) -> Parse_Result {
    ini_map, err := ini.load_map_from_string(src, ini_allocator)
    if err != nil do return .Fatal_Error
    return config_parse(model, ini_map, string_allocator, loc)
}

// See config_parse
config_save_to_map :: proc(model: ^$T, ini_map: ^ini.Map, string_allocator := context.temp_allocator, loc := #caller_location) -> (ok: bool) {
    model_ti := reflect.type_info_base(type_info_of(T)).variant.(runtime.Type_Info_Struct)

    for i in 0..<model_ti.field_count {
        section_name := get_ini_name(&model_ti, i, INI_SECTION_TAG_KEY)

        ini_map[section_name] = {}
        section_map := &ini_map[section_name]

        section_ti := reflect.type_info_base(model_ti.types[i])
        section_offset := cast(uintptr)model + model_ti.offsets[i]

        #partial switch &section_v in section_ti.variant {
        case runtime.Type_Info_Struct:
            for j in 0..<section_v.field_count {
                option_name := get_ini_name(&section_v, j, INI_OPTION_TAG_KEY)
                option_ptr := cast(rawptr)(section_offset + section_v.offsets[j])

                option_str: string

                // Color
                if color_field, color_ok := section_v.types[j].variant.(runtime.Type_Info_Array); color_ok {
                    #partial switch elem_v in color_field.elem.variant {
                    case runtime.Type_Info_Integer:
                        sb: strings.Builder
                        strings.builder_init_len_cap(&sb, 0, COLOR_FORMAT_STRING_LENGTH, string_allocator)
                        strings.write_rune(&sb, '#')
                        buf: [2]u8

                        for c in 0..<color_field.count {
                            component_ptr := cast(rawptr)(cast(uintptr)option_ptr + cast(uintptr)(color_field.elem.size*c))
                            component_any: any
                            component_any.id = color_field.elem.id
                            component_any.data = component_ptr
                            comp_str := fmt.bprintf(buf[:], "%02X", component_any)
                            strings.write_string(&sb, comp_str)
                        }

                        option_str = strings.to_string(sb)
                    case:
                        log.errorf("Type error: For vector types only array of any 4 integers is supported: for field `%s` expected type `[4]any_int`, but got `%s`", section_v.names[j], elem_v, location = loc)
                        return false
                    }
                } else {
                    option: any
                    option.id = section_v.types[j].id
                    option.data = option_ptr
                    option_str = fmt.aprint(option, allocator = string_allocator)
                }

                section_map[option_name] = option_str
            }
        case:
            log.warnf("Sections must be structs: type of section field `%s` is `%v`.", model_ti.names[i], section_ti, location = loc)
            return false
        }
    }
    return true
}

@(require_results)
config_save_to_string :: proc(model: ^$T, ini_allocator := context.temp_allocator, string_allocator := context.allocator) -> (data: string) {
    ini_map := make(ini.Map, ini_allocator)
    config_save_to_map(model, &ini_map, ini_allocator)
    return ini.save_map_to_string(ini_map, string_allocator)
}

config_save_to_path :: proc(model: ^$T, path: string, allocator := context.temp_allocator) -> (err: os.Error) {
    data := config_save_to_string(model, allocator)
    err = os.write_entire_file(path, data)
    return
}

@(require_results)
get_ini_name :: proc(type_info_struct: ^reflect.Type_Info_Struct, i: i32, tag_name: string) -> string {
    tag := reflect.struct_tag_get(cast(reflect.Struct_Tag)type_info_struct.tags[i], tag_name)
    if tag == "" {
        return type_info_struct.names[i]
    } else {
        return tag
    }
}

// Stolen from `<odin-root>/core/flags/internal_rtti.odin:18` because it is private.
// Added int_hex parameter as a hack to parse colors.
@(optimization_mode="favor_size")
parse_and_set_pointer_by_base_type :: proc(ptr: rawptr, str: string, type_info: ^runtime.Type_Info, int_hex := false) -> bool {
    bounded_int :: proc(value, min, max: i128) -> (result: i128, ok: bool) {
        return value, min <= value && value <= max
    }

    bounded_uint :: proc(value, max: u128) -> (result: u128, ok: bool) {
        return value, value <= max
    }

    // NOTE(Feoramund): This procedure has been written with the goal in mind
    // of generating the least amount of assembly, given that this library is
    // likely to be called once and forgotten.
    //
    // I've rewritten the switch tables below in 3 different ways, and the
    // current one generates the least amount of code for me on Linux AMD64.
    //
    // The other two ways were:
    //
    // - the original implementation: use of parametric polymorphism which led
    //   to dozens of functions generated, one for each type.
    //
    // - a `value, ok` assignment statement with the `or_return` done at the
    //   end of the switch, instead of inline.
    //
    // This seems to be the smallest way for now.

    #partial switch specific_type_info in type_info.variant {
    case runtime.Type_Info_Integer:
        if specific_type_info.signed {
            value: i128
            if int_hex {
                value = i128(strconv.parse_int(str, 16) or_return)
            } else {
                value = strconv.parse_i128(str) or_return
            }
            switch type_info.id {
            case i8:     (^i8)    (ptr)^ = cast(i8)     bounded_int(value, cast(i128)min(i8),     cast(i128)max(i8)    ) or_return
            case i16:    (^i16)   (ptr)^ = cast(i16)    bounded_int(value, cast(i128)min(i16),    cast(i128)max(i16)   ) or_return
            case i32:    (^i32)   (ptr)^ = cast(i32)    bounded_int(value, cast(i128)min(i32),    cast(i128)max(i32)   ) or_return
            case i64:    (^i64)   (ptr)^ = cast(i64)    bounded_int(value, cast(i128)min(i64),    cast(i128)max(i64)   ) or_return
            case i128:   (^i128)  (ptr)^ = value

            case int:    (^int)   (ptr)^ = cast(int)    bounded_int(value, cast(i128)min(int),    cast(i128)max(int)   ) or_return

            case i16le:  (^i16le) (ptr)^ = cast(i16le)  bounded_int(value, cast(i128)min(i16le),  cast(i128)max(i16le) ) or_return
            case i32le:  (^i32le) (ptr)^ = cast(i32le)  bounded_int(value, cast(i128)min(i32le),  cast(i128)max(i32le) ) or_return
            case i64le:  (^i64le) (ptr)^ = cast(i64le)  bounded_int(value, cast(i128)min(i64le),  cast(i128)max(i64le) ) or_return
            case i128le: (^i128le)(ptr)^ = cast(i128le) bounded_int(value, cast(i128)min(i128le), cast(i128)max(i128le)) or_return

            case i16be:  (^i16be) (ptr)^ = cast(i16be)  bounded_int(value, cast(i128)min(i16be),  cast(i128)max(i16be) ) or_return
            case i32be:  (^i32be) (ptr)^ = cast(i32be)  bounded_int(value, cast(i128)min(i32be),  cast(i128)max(i32be) ) or_return
            case i64be:  (^i64be) (ptr)^ = cast(i64be)  bounded_int(value, cast(i128)min(i64be),  cast(i128)max(i64be) ) or_return
            case i128be: (^i128be)(ptr)^ = cast(i128be) bounded_int(value, cast(i128)min(i128be), cast(i128)max(i128be)) or_return
            }
        } else {
            value: u128
            if int_hex {
                value = u128(strconv.parse_uint(str, 16) or_return)
            } else {
                value = strconv.parse_u128(str) or_return
            }
            switch type_info.id {
            case u8:      (^u8)     (ptr)^ = cast(u8)      bounded_uint(value, cast(u128)max(u8)     ) or_return
            case u16:     (^u16)    (ptr)^ = cast(u16)     bounded_uint(value, cast(u128)max(u16)    ) or_return
            case u32:     (^u32)    (ptr)^ = cast(u32)     bounded_uint(value, cast(u128)max(u32)    ) or_return
            case u64:     (^u64)    (ptr)^ = cast(u64)     bounded_uint(value, cast(u128)max(u64)    ) or_return
            case u128:    (^u128)   (ptr)^ = value

            case uint:    (^uint)   (ptr)^ = cast(uint)    bounded_uint(value, cast(u128)max(uint)   ) or_return
            case uintptr: (^uintptr)(ptr)^ = cast(uintptr) bounded_uint(value, cast(u128)max(uintptr)) or_return

            case u16le:   (^u16le)  (ptr)^ = cast(u16le)   bounded_uint(value, cast(u128)max(u16le)  ) or_return
            case u32le:   (^u32le)  (ptr)^ = cast(u32le)   bounded_uint(value, cast(u128)max(u32le)  ) or_return
            case u64le:   (^u64le)  (ptr)^ = cast(u64le)   bounded_uint(value, cast(u128)max(u64le)  ) or_return
            case u128le:  (^u128le) (ptr)^ = cast(u128le)  bounded_uint(value, cast(u128)max(u128le) ) or_return

            case u16be:   (^u16be)  (ptr)^ = cast(u16be)   bounded_uint(value, cast(u128)max(u16be)  ) or_return
            case u32be:   (^u32be)  (ptr)^ = cast(u32be)   bounded_uint(value, cast(u128)max(u32be)  ) or_return
            case u64be:   (^u64be)  (ptr)^ = cast(u64be)   bounded_uint(value, cast(u128)max(u64be)  ) or_return
            case u128be:  (^u128be) (ptr)^ = cast(u128be)  bounded_uint(value, cast(u128)max(u128be) ) or_return
            }
        }

    case runtime.Type_Info_Rune:
        if utf8.rune_count_in_string(str) != 1 {
            return false
        }

        (^rune)(ptr)^ = utf8.rune_at_pos(str, 0)

    case runtime.Type_Info_Float:
        value := strconv.parse_f64(str) or_return
        switch type_info.id {
        case f16:   (^f16)  (ptr)^ = cast(f16)   value
        case f32:   (^f32)  (ptr)^ = cast(f32)   value
        case f64:   (^f64)  (ptr)^ =             value

        case f16le: (^f16le)(ptr)^ = cast(f16le) value
        case f32le: (^f32le)(ptr)^ = cast(f32le) value
        case f64le: (^f64le)(ptr)^ = cast(f64le) value

        case f16be: (^f16be)(ptr)^ = cast(f16be) value
        case f32be: (^f32be)(ptr)^ = cast(f32be) value
        case f64be: (^f64be)(ptr)^ = cast(f64be) value
        }

    case runtime.Type_Info_Complex:
        value := strconv.parse_complex128(str) or_return
        switch type_info.id {
        case complex32:  (^complex32) (ptr)^ = (complex32)(value)
        case complex64:  (^complex64) (ptr)^ = (complex64)(value)
        case complex128: (^complex128)(ptr)^ = value
        }

    case runtime.Type_Info_Quaternion:
        value := strconv.parse_quaternion256(str) or_return
        switch type_info.id {
        case quaternion64:  (^quaternion64) (ptr)^ = (quaternion64)(value)
        case quaternion128: (^quaternion128)(ptr)^ = (quaternion128)(value)
        case quaternion256: (^quaternion256)(ptr)^ = value
        }

    case runtime.Type_Info_String:
        assert(specific_type_info.encoding == .UTF_8)

        if specific_type_info.is_cstring {
            cstr_ptr := (^cstring)(ptr)
            if cstr_ptr != nil {
                // Prevent memory leaks from us setting this value multiple times.
                delete(cstr_ptr^)
            }
            cstr_ptr^ = strings.clone_to_cstring(str)
        } else {
            (^string)(ptr)^ = str
        }

    case runtime.Type_Info_Boolean:
        value := strconv.parse_bool(str) or_return
        switch type_info.id {
        case bool: (^bool)(ptr)^ =     value
        case b8:   (^b8)  (ptr)^ =  b8(value)
        case b16:  (^b16) (ptr)^ = b16(value)
        case b32:  (^b32) (ptr)^ = b32(value)
        case b64:  (^b64) (ptr)^ = b64(value)
        }

    case runtime.Type_Info_Bit_Set:
        // Parse a string of 1's and 0's, from left to right,
        // least significant bit to most significant bit.
        value: u128

        // NOTE: `upper` is inclusive, i.e: `0..=31`
        max_bit_index := u128(1 + specific_type_info.upper - specific_type_info.lower)
        bit_index := u128(0)
        #no_bounds_check for string_index in 0..<uint(len(str)) {
            if bit_index == max_bit_index {
                // The string's too long for this bit_set.
                return false
            }

            switch str[string_index] {
            case '1':
                value |= 1 << bit_index
                bit_index += 1
            case '0':
                bit_index += 1
                continue
            case '_':
                continue
            case:
                return false
            }
        }

        if specific_type_info.underlying != nil {
            set_unbounded_integer_by_type(ptr, value, specific_type_info.underlying.id)
        } else {
            switch 8*type_info.size {
            case 8:   (^u8)  (ptr)^ = cast(u8)   value
            case 16:  (^u16) (ptr)^ = cast(u16)  value
            case 32:  (^u32) (ptr)^ = cast(u32)  value
            case 64:  (^u64) (ptr)^ = cast(u64)  value
            case 128: (^u128)(ptr)^ =            value
            }
        }

    case:
        fmt.panicf("Unsupported base data type: %v", specific_type_info)
    }

    return true
}

// Stolen from `<odin-root>/core/flags/internal_rtti.odin:335` because it is private.
@(optimization_mode="favor_size")
set_unbounded_integer_by_type :: proc(ptr: rawptr, value: $T, data_type: typeid) where intrinsics.type_is_integer(T) {
    switch data_type {
    case i8:      (^i8)     (ptr)^ = cast(i8)      value
    case i16:     (^i16)    (ptr)^ = cast(i16)     value
    case i32:     (^i32)    (ptr)^ = cast(i32)     value
    case i64:     (^i64)    (ptr)^ = cast(i64)     value
    case i128:    (^i128)   (ptr)^ = cast(i128)    value

    case int:     (^int)    (ptr)^ = cast(int)     value

    case i16le:   (^i16le)  (ptr)^ = cast(i16le)   value
    case i32le:   (^i32le)  (ptr)^ = cast(i32le)   value
    case i64le:   (^i64le)  (ptr)^ = cast(i64le)   value
    case i128le:  (^i128le) (ptr)^ = cast(i128le)  value

    case i16be:   (^i16be)  (ptr)^ = cast(i16be)   value
    case i32be:   (^i32be)  (ptr)^ = cast(i32be)   value
    case i64be:   (^i64be)  (ptr)^ = cast(i64be)   value
    case i128be:  (^i128be) (ptr)^ = cast(i128be)  value

    case u8:      (^u8)     (ptr)^ = cast(u8)      value
    case u16:     (^u16)    (ptr)^ = cast(u16)     value
    case u32:     (^u32)    (ptr)^ = cast(u32)     value
    case u64:     (^u64)    (ptr)^ = cast(u64)     value
    case u128:    (^u128)   (ptr)^ = cast(u128)    value

    case uint:    (^uint)   (ptr)^ = cast(uint)    value
    case uintptr: (^uintptr)(ptr)^ = cast(uintptr) value

    case u16le:   (^u16le)  (ptr)^ = cast(u16le)   value
    case u32le:   (^u32le)  (ptr)^ = cast(u32le)   value
    case u64le:   (^u64le)  (ptr)^ = cast(u64le)   value
    case u128le:  (^u128le) (ptr)^ = cast(u128le)  value

    case u16be:   (^u16be)  (ptr)^ = cast(u16be)   value
    case u32be:   (^u32be)  (ptr)^ = cast(u32be)   value
    case u64be:   (^u64be)  (ptr)^ = cast(u64be)   value
    case u128be:  (^u128be) (ptr)^ = cast(u128be)  value

    case rune:    (^rune)   (ptr)^ = cast(rune)    value

    case:
        fmt.panicf("Unsupported integer backing type: %v", data_type)
    }
}

import "base:intrinsics"
import "base:runtime"

import "core:encoding/ini"
import "core:reflect"
import "core:unicode/utf8"
import "core:strconv"
import "core:strings"
import "core:fmt"
import "core:log"
import "core:os"
import "core:mem"
