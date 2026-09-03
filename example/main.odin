package main

import iniconf "../"
import "core:log"
import "core:fmt"

Config :: struct {
    style: Style_Section `ini:"urmom"`,
    window: Window_Section,
}

Color :: [4]u8

Style_Section :: struct {
    roundness: f64,
    bg_color: Color,
}

Window_Section :: struct {
    x: int `ini:"aboba"`,
    y: int,
    width, height: int,
}

main :: proc() {
    defer free_all(context.temp_allocator)
    defer free_all(context.allocator)

    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

    config: Config
    res := iniconf.config_load_from_path(&config, "config.ini")
    assert(res != .Fatal_Error)

    fmt.println(config)

    config.window.y = 69
    config.window.width = 800
    config.window.height = 600

    err := iniconf.config_save_to_path(&config, "config.ini")
    assert(err == nil)
}
