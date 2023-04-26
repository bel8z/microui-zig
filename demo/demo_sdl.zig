const std = @import("std");

pub const gl_h = "SDL2/SDL_opengl.h";

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const mu = @import("microui");
const Ui = mu.Ui(.{});
const Font = mu.Font;

const demo = @import("demo.zig");

const Renderer = @import("renderer.zig");

const button_map = init: {
    var value = [_]mu.MouseButtons{.{}} ** 256;
    value[c.SDL_BUTTON_LEFT & 0xff].left = true;
    value[c.SDL_BUTTON_RIGHT & 0xff].right = true;
    value[c.SDL_BUTTON_MIDDLE & 0xff].middle = true;
    break :init value;
};

const key_map = init: {
    var value = [_]mu.Keys{.{}} ** 256;
    value[c.SDLK_LSHIFT & 0xff].shift = true;
    value[c.SDLK_RSHIFT & 0xff].shift = true;
    value[c.SDLK_LCTRL & 0xff].ctrl = true;
    value[c.SDLK_RCTRL & 0xff].ctrl = true;
    value[c.SDLK_LALT & 0xff].alt = true;
    value[c.SDLK_RALT & 0xff].alt = true;
    value[c.SDLK_RETURN & 0xff].enter = true;
    value[c.SDLK_KP_ENTER & 0xff].enter = true;
    value[c.SDLK_BACKSPACE & 0xff].backspace = true;
    break :init value;
};

var bg = mu.Color{ .r = 90, .g = 95, .b = 100, .a = 255 };

pub fn main() !void {
    const ui_alloc = std.heap.page_allocator;

    // init SDL and renderer
    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);

    const width = 800;
    const height = 600;

    var window = c.SDL_CreateWindow(
        null,
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        width,
        height,
        c.SDL_WINDOW_OPENGL,
    );
    _ = c.SDL_GL_CreateContext(window);

    var r = try Renderer.init(width, height, ui_alloc);
    defer ui_alloc.destroy(r);

    // init microui
    var ui = try ui_alloc.create(Ui);
    ui.init(&r.font, null);

    // main loop
    var input = ui.getInput();

    while (true) {
        // handle SDL events
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            switch (e.type) {
                c.SDL_QUIT => return,

                c.SDL_MOUSEMOTION => input.mouseMove(e.motion.x, e.motion.y),
                c.SDL_MOUSEWHEEL => input.scroll(0, e.wheel.y * -30),
                c.SDL_TEXTINPUT => input.textZ(@ptrCast([*:0]const u8, &e.text.text)),

                c.SDL_MOUSEBUTTONDOWN => {
                    const b = button_map[e.button.button & 0xff];
                    input.mouseDown(e.button.x, e.button.y, b);
                },

                c.SDL_MOUSEBUTTONUP => {
                    const b = button_map[e.button.button & 0xff];
                    input.mouseUp(e.button.x, e.button.y, b);
                },

                c.SDL_KEYDOWN => {
                    const k = @intCast(usize, e.key.keysym.sym & 0xff);
                    input.keyDown(key_map[k]);
                },

                c.SDL_KEYUP => {
                    const k = @intCast(usize, e.key.keysym.sym & 0xff);
                    input.keyUp(key_map[k]);
                },

                else => {},
            }
        }

        // process frame
        {
            ui.beginFrame(&input, .{ .x = width, .y = height }) catch unreachable;
            defer ui.endFrame();
            demo.frame(ui, &bg) catch unreachable;
        }

        // render
        r.clear(bg);
        var iter = ui.command_list.iter();
        while (true) {
            switch (iter.next()) {
                .None => break,
                .Clip => |cmd| r.setClipRect(cmd),
                .Icon => |cmd| r.drawIcon(cmd.id, cmd.rect, cmd.color),
                .Rect => |cmd| r.drawRect(cmd),
                .Text => |cmd| {
                    std.debug.assert(cmd.font == &r.font);
                    r.drawText(cmd.str, cmd.pos, cmd.color);
                },
                else => unreachable,
            }
        }
        r.flush();
        _ = c.SDL_GL_SwapWindow(window);
    }
}
