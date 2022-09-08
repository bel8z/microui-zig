const std = @import("std");

const c = @cImport({
    @cInclude("demo.h");
});

const button_map = init: {
    var value = [_]u8{0} ** 256;
    value[c.SDL_BUTTON_LEFT & 0xff] = c.MU_MOUSE_LEFT;
    value[c.SDL_BUTTON_RIGHT & 0xff] = c.MU_MOUSE_RIGHT;
    value[c.SDL_BUTTON_MIDDLE & 0xff] = c.MU_MOUSE_MIDDLE;
    break :init value;
};

const key_map = init: {
    var value = [_]u8{0} ** 256;
    value[c.SDLK_LSHIFT & 0xff] = c.MU_KEY_SHIFT;
    value[c.SDLK_RSHIFT & 0xff] = c.MU_KEY_SHIFT;
    value[c.SDLK_LCTRL & 0xff] = c.MU_KEY_CTRL;
    value[c.SDLK_RCTRL & 0xff] = c.MU_KEY_CTRL;
    value[c.SDLK_LALT & 0xff] = c.MU_KEY_ALT;
    value[c.SDLK_RALT & 0xff] = c.MU_KEY_ALT;
    value[c.SDLK_RETURN & 0xff] = c.MU_KEY_RETURN;
    value[c.SDLK_BACKSPACE & 0xff] = c.MU_KEY_BACKSPACE;
    break :init value;
};

var logbuf = [_]u8{0} * 64000;
var logbuf_updated = false;
var bg = [_]f32{ 90, 95, 100 };

pub fn main() !void {
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

    c.r_init(width, height);

    // init microui
    const a = std.heap.page_allocator;
    var ctx = try a.create(c.mu_Context);
    c.mu_init(ctx);
    ctx.text_width = textWidth;
    ctx.text_height = textHeight;

    // main loop
    while (true) {
        // handle SDL events
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            switch (e.type) {
                c.SDL_QUIT => return,

                c.SDL_MOUSEMOTION => c.mu_input_mousemove(ctx, e.motion.x, e.motion.y),
                c.SDL_MOUSEWHEEL => c.mu_input_scroll(ctx, 0, e.wheel.y * -30),
                c.SDL_TEXTINPUT => c.mu_input_text(ctx, &e.text.text),

                c.SDL_MOUSEBUTTONDOWN => {
                    const b = button_map[e.button.button & 0xff];
                    if (b != 0) c.mu_input_mousedown(ctx, e.button.x, e.button.y, b);
                },

                c.SDL_MOUSEBUTTONUP => {
                    const b = button_map[e.button.button & 0xff];
                    if (b != 0) c.mu_input_mouseup(ctx, e.button.x, e.button.y, b);
                },

                c.SDL_KEYDOWN => {
                    const b = key_map[e.button.button & 0xff];
                    if (b != 0) c.mu_input_keydown(ctx, b);
                },

                c.SDL_KEYUP => {
                    const b = key_map[e.button.button & 0xff];
                    if (b != 0) c.mu_input_keyup(ctx, b);
                },

                else => {},
            }
        }

        // process frame
        processFrame(ctx);

        // render
        c.r_clear(c.mu_color(
            @floatToInt(u8, bg[0]),
            @floatToInt(u8, bg[1]),
            @floatToInt(u8, bg[2]),
            255,
        ));
        var maybe_cmd: ?*c.mu_Command = null;
        while (c.mu_next_command(ctx, &maybe_cmd) != 0) {
            const cmd = maybe_cmd orelse unreachable;
            switch (cmd.type) {
                c.MU_COMMAND_TEXT => c.r_draw_text(&cmd.text.str, cmd.text.pos, cmd.text.color),
                c.MU_COMMAND_RECT => c.r_draw_rect(cmd.rect.rect, cmd.rect.color),
                c.MU_COMMAND_ICON => c.r_draw_icon(cmd.icon.id, cmd.icon.rect, cmd.icon.color),
                c.MU_COMMAND_CLIP => c.r_set_clip_rect(cmd.clip.rect),
                else => unreachable,
            }
        }
        c.r_flush();
        _ = c.SDL_GL_SwapWindow(window);
    }
}

export fn textWidth(font: c.mu_Font, text: [*c]const u8, len: c_int) c_int {
    _ = font;
    return c.r_get_text_width(text, if (len < 0) @intCast(c_int, c.strlen(text)) else len);
}
export fn textHeight(font: c.mu_Font) c_int {
    _ = font;
    return c.r_get_text_height();
}

fn processFrame(ctx: *c.mu_Context) void {
    c.mu_begin(ctx);
    testWindow(ctx);
    c.mu_end(ctx);
}

fn testWindow(ctx: *c.mu_Context) void {
    if (c.mu_begin_window(ctx, "Demo Window", c.mu_rect(40, 40, 300, 450)) == 0) {
        // var win = c.mu_get_current_container(ctx);
        // win.*.rect.w = std.math.max(win.*.rect.w, 240);
        // win.*.rect.h = std.math.max(win.*.rect.h, 300);
        c.mu_end_window(ctx);
    }
}
