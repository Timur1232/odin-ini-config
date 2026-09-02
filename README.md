# Odin INI config

Simple ini parser for custom configuration model written in Odin.

## Usage

Config model must be a struct with fields correspond to ini sections. Sections must be structs as well. Section fields must be either primitive types, like any integer, any float or string (cstring), or an array of any intergers with length 4 for color type (e.g. \[4\]u8).

Section name are taken from field name or from tag with key `ini_section`. Option name are also taken from field name or from tag with key `ini_option` (see example).

Example:

```odin
package main

import "iniconf"

Config :: struct {
    style: Style_Section `ini_section:"urmom"`,
    window: Window_Section,
}

Color :: [4]u8

Style_Section :: struct {
    roundness: f64,
    bg_color: Color,
}

Window_Section :: struct {
    x: int `ini_option:"aboba"`,
    y: int,
    width, height: int,
}

main :: proc() {
    config: Config

    res := iniconf.config_load_from_path(&config, "config.ini")
    assert(res != .Fatal_Error)

    config.window.width = 420

    err := iniconf.config_save_to_path(&config, "config.ini")
    assert(err == nil)
}
```

Parser will ignore options, that not set in ini file. So, to have defaults, you need to initialize them before parsing:

```odin
config: Config
some_defaults(&config)
iniconf.config_load_from_path(&config, "config.ini")
```
