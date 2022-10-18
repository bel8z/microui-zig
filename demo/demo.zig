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

var _logbuf = [_]u8{0} ** 64000;
var logbuf = std.io.fixedBufferStream(_logbuf[0..]);
var logbuf_updated = false;

var bg = [_]f32{ 90, 95, 100 };
var checks = [3]c_int{ 1, 0, 1 };

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
        try processFrame(ctx);

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

fn processFrame(ctx: *c.mu_Context) !void {
    c.mu_begin(ctx);
    defer c.mu_end(ctx);

    try testWindow(ctx);
    logWindow(ctx);
}

fn testWindow(ctx: *c.mu_Context) !void {
    // do window
    if (c.mu_begin_window(ctx, "Demo Window", c.mu_rect(40, 40, 300, 450)) != 0) {
        defer c.mu_end_window(ctx);

        var win = c.mu_get_current_container(ctx);
        win.*.rect.w = std.math.max(win.*.rect.w, 240);
        win.*.rect.h = std.math.max(win.*.rect.h, 300);

        // window info */
        if (c.mu_header(ctx, "Window Info") != 0) {
            win = c.mu_get_current_container(ctx);
            var buf: [64]u8 = undefined;
            c.mu_layout_row(ctx, 2, &[_]c_int{ 54, -1 }, 0);

            c.mu_label(ctx, "Position:");
            _ = try std.fmt.bufPrintZ(buf[0..], "{}, {}", .{ win.*.rect.x, win.*.rect.y });
            c.mu_label(ctx, &buf);

            c.mu_label(ctx, "Size:");
            _ = try std.fmt.bufPrintZ(buf[0..], "{}, {}", .{ win.*.rect.w, win.*.rect.h });
            c.mu_label(ctx, &buf);
        }

        // labels + buttons */
        if (c.mu_header_ex(ctx, "Test Buttons", c.MU_OPT_EXPANDED) != 0) {
            c.mu_layout_row(ctx, 3, &[_]c_int{ 86, -110, -1 }, 0);

            c.mu_label(ctx, "Test buttons 1:");

            if (c.mu_button(ctx, "Button 1") != 0) writeLog("Pressed button 1");
            if (c.mu_button(ctx, "Button 2") != 0) writeLog("Pressed button 2");

            c.mu_label(ctx, "Test buttons 2:");

            if (c.mu_button(ctx, "Button 3") != 0) writeLog("Pressed button 3");
            if (c.mu_button(ctx, "Popup") != 0) c.mu_open_popup(ctx, "Test Popup");

            if (c.mu_begin_popup(ctx, "Test Popup") != 0) {
                _ = c.mu_button(ctx, "Hello");
                _ = c.mu_button(ctx, "World");
                c.mu_end_popup(ctx);
            }
        }

        // tree */
        if (c.mu_header_ex(ctx, "Tree and Text", c.MU_OPT_EXPANDED) != 0) {
            c.mu_layout_row(ctx, 2, &[_]c_int{ 140, -1 }, 0);
            c.mu_layout_begin_column(ctx);

            if (c.mu_begin_treenode(ctx, "Test 1") != 0) {
                if (c.mu_begin_treenode(ctx, "Test 1a") != 0) {
                    c.mu_label(ctx, "Hello");
                    c.mu_label(ctx, "world");
                    c.mu_end_treenode(ctx);
                }

                if (c.mu_begin_treenode(ctx, "Test 1b") != 0) {
                    if (c.mu_button(ctx, "Button 1") != 0) writeLog("Pressed button 1");
                    if (c.mu_button(ctx, "Button 2") != 0) writeLog("Pressed button 2");
                    c.mu_end_treenode(ctx);
                }

                c.mu_end_treenode(ctx);
            }

            if (c.mu_begin_treenode(ctx, "Test 2") != 0) {
                c.mu_layout_row(ctx, 2, &[_]c_int{ 54, 54 }, 0);

                if (c.mu_button(ctx, "Button 3") != 0) writeLog("Pressed button 3");
                if (c.mu_button(ctx, "Button 4") != 0) writeLog("Pressed button 4");
                if (c.mu_button(ctx, "Button 5") != 0) writeLog("Pressed button 5");
                if (c.mu_button(ctx, "Button 6") != 0) writeLog("Pressed button 6");

                c.mu_end_treenode(ctx);
            }

            if (c.mu_begin_treenode(ctx, "Test 3") != 0) {
                _ = c.mu_checkbox(ctx, "Checkbox 1", &checks[0]);
                _ = c.mu_checkbox(ctx, "Checkbox 2", &checks[1]);
                _ = c.mu_checkbox(ctx, "Checkbox 3", &checks[2]);
                c.mu_end_treenode(ctx);
            }
            c.mu_layout_end_column(ctx);

            c.mu_layout_begin_column(ctx);
            c.mu_layout_row(ctx, 1, &[_]c_int{-1}, 0);
            c.mu_text(ctx, "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus ipsum, eu varius magna felis a nulla.");
            c.mu_layout_end_column(ctx);
        }

        // background color sliders */
        if (c.mu_header_ex(ctx, "Background Color", c.MU_OPT_EXPANDED) != 0) {
            c.mu_layout_row(ctx, 2, &[_]c_int{ -78, -1 }, 74);
            // sliders */
            c.mu_layout_begin_column(ctx);
            c.mu_layout_row(ctx, 2, &[_]c_int{ 46, -1 }, 0);
            c.mu_label(ctx, "Red:");
            _ = c.mu_slider(ctx, &bg[0], 0, 255);
            c.mu_label(ctx, "Green:");
            _ = c.mu_slider(ctx, &bg[1], 0, 255);
            c.mu_label(ctx, "Blue:");
            _ = c.mu_slider(ctx, &bg[2], 0, 255);
            c.mu_layout_end_column(ctx);
            // color preview */
            const r = c.mu_layout_next(ctx);
            c.mu_draw_rect(ctx, r, c.mu_color(
                @floatToInt(c_int, bg[0]),
                @floatToInt(c_int, bg[1]),
                @floatToInt(c_int, bg[2]),
                255,
            ));
            var buf: [32]u8 = undefined;
            _ = try std.fmt.bufPrint(buf[0..], "#{X}{X}{X}", .{
                @floatToInt(c_int, bg[0]),
                @floatToInt(c_int, bg[1]),
                @floatToInt(c_int, bg[2]),
            });
            c.mu_draw_control_text(ctx, &buf, r, c.MU_COLOR_TEXT, c.MU_OPT_ALIGNCENTER);
        }
    }
}

fn logWindow(ctx: *c.mu_Context) void {
    if (c.mu_begin_window(ctx, "Log Window", c.mu_rect(350, 40, 300, 200)) != 0) {
        defer c.mu_end_window(ctx);
        //  output text panel */
        c.mu_layout_row(ctx, 1, &[_]c_int{-1}, -25);
        c.mu_begin_panel(ctx, "Log Output");
        var panel = c.mu_get_current_container(ctx);
        c.mu_layout_row(ctx, 1, &[_]c_int{-1}, -1);

        const text = logbuf.getWritten()[0.. :0];

        c.mu_text(ctx, text);
        c.mu_end_panel(ctx);
        if (logbuf_updated) {
            panel.*.scroll.y = panel.*.content_size.y;
            logbuf_updated = false;
        }
    }
}

fn writeLog(text: [:0]const u8) void {
    const l = logbuf.getPos() catch unreachable;

    if (l > 0) {
        // Replace null terminator with new line
        logbuf.seekBy(-1) catch unreachable;
        _ = logbuf.write(&[_]u8{'\n'}) catch unreachable;
    }

    // Append text & terminator
    _ = logbuf.write(text) catch unreachable;
    _ = logbuf.write(&[_]u8{0}) catch unreachable;

    logbuf_updated = true;
}
