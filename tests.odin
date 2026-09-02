// TODO: Fix quaternions
#+private
package ini_config

import "core:testing"
import "core:fmt"

TEST_CONFIG_SRC :: `
[misc]
color = #696969AA

[signed_integers]
int_t  = 69
i8_t   = -69
i16_t  = 69
i32_t  = -69
i64_t  = 69
i128_t = -69

[unsigned_integers]
uintptr_t = 69420
uint_t = 420
u8_t   = 42
u16_t  = 420
u32_t  = 420
u64_t  = 420
u128_t = 420

[booleans]
bool_t = true
b8_t = false
b32_t = true
b64_t = false

[floats]
f16_t = 420.69
f32_t = 69.420
f64_t = -69.420

[strings]
string_t = aboba
cstring_t = urmom

[complex]
c32 = 69+420i
c64 = -69+420i
c128 = 69-420i

; [quternions]
; q64 = 1+2i+3j+4k
; q128 = 1-2i+3j-4k
; q256 = 1+2i+3j+4k
`

Test_Config :: struct {
    misc: Misc,
    signed: Signed_Integers `ini_section:"signed_integers"`,
    unsigned: Unsigned_Integers `ini_section:"unsigned_integers"`,
    booleans: Booleans,
    floats: Floats,
    strings: Strings,
    complex: Complex,
    // quaternions: Quaternions,
}

Color :: [4]u8

Misc :: struct {
    color: Color,
}

Signed_Integers :: struct {
    int_value: int `ini_option:"int_t"`,
    i8_t: i8,
    i16_t: i16,
    i32_t: i32,
    i64_t: i64,
    i128_t: i128,
}

Unsigned_Integers :: struct {
    uintptr_t: uintptr,
    uint_value: uint `ini_option:"uint_t"`,
    u8_t: u8,
    u16_t: u16,
    u32_t: u32,
    u64_t: u64,
    u128_t: u128,
}

Booleans :: struct {
    bool_t: bool,
    b8_t: b8,
    b32_t: b32,
    b64_t: b64,
}

Floats :: struct {
    f16_t: f16,
    f32_t: f32,
    f64_t: f64,
}

Strings :: struct {
    string_t: string,
    cstring_t: cstring,
}

Complex :: struct {
    c32: complex32,
    c64: complex64,
    c128: complex128,
}

Quaternions :: struct {
    q64: quaternion64,
    q128: quaternion128,
    q256: quaternion256,
}

check :: proc(config: Test_Config) -> bool {
    not_ok: bool

    {
        using misc := config.misc
        not_ok |= color.r != 0x69
        not_ok |= color.g != 0x69
        not_ok |= color.b != 0x69
        not_ok |= color.a != 0xAA
    }

    {
        using signed := config.signed
        not_ok |= int_value != 69
        not_ok |= i8_t != -69
        not_ok |= i16_t != 69
        not_ok |= i32_t != -69
        not_ok |= i64_t != 69
        not_ok |= i128_t != -69
    }

    {
        using unsigned := config.unsigned
        not_ok |= uintptr_t != 69420
        not_ok |= uint_value != 420
        not_ok |= u8_t != 42
        not_ok |= u16_t != 420
        not_ok |= u32_t != 420
        not_ok |= u64_t != 420
        not_ok |= u128_t != 420
    }

    {
        using booleans := config.booleans
        not_ok |= bool_t != true
        not_ok |= b8_t != false
        not_ok |= b32_t != true
        not_ok |= b64_t != false
    }

    {
        using floats := config.floats
        not_ok |= f16_t != 420.69
        not_ok |= f32_t != 69.420
        not_ok |= f64_t != -69.420
    }

    {
        using strings := config.strings
        not_ok |= string_t != "aboba"
        not_ok |= cstring_t != "urmom"
    }

    {
        using complex := config.complex
        not_ok |= c32 != 69+420i
        not_ok |= c64 != -69+420i
        not_ok |= c128 != 69-420i
    }

    // {
    //     using quaternions := config.quaternions
    //     not_ok |= q64 != 1+2i+3j+4k
    //     not_ok |= q128 != 1-2i+3j-4k
    //     not_ok |= q256 != 1+2i+3j+4k
    // }

    return !not_ok
}

@(test)
test :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    defer free_all(context.allocator)

    config: Test_Config
    res := config_load_from_string(&config, TEST_CONFIG_SRC)
    testing.expect(t, res == .Ok, fmt.tprintf("Parse error: %v", res))

    testing.expect(t, check(config), fmt.tprintf("Incorrect values: %v", config))

    data := config_save_to_string(&config)
    config = {}

    res = config_load_from_string(&config, data)
    testing.expect(t, res == .Ok, fmt.tprintf("Parse error: %v", res))

    testing.expect(t, check(config), fmt.tprintf("Incorrect values: %v\n%s", config, data))
}
