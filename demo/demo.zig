const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const mu = @import("microui");
const Ui = mu.Ui(.{});
const Font = mu.Font;

const Renderer = @import("renderer.zig");

const custom_theme = true;

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

var _logbuf = [_]u8{0} ** 64000;
var logbuf = std.io.fixedBufferStream(_logbuf[0..]);
var logbuf_updated = false;

var bg = mu.Color{ .r = 90, .g = 95, .b = 100, .a = 255 };
var checks = [3]bool{ true, false, true };

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
    var ui_font = Font{
        .ptr = r,
        .text_height = r.getTextHeight(),
        .text_width = textWidth,
    };
    var ui = try ui_alloc.create(Ui);
    ui.init(&ui_font, null);

    // NOTE (Matteo): Theming attempt
    var style = ui._style;
    if (custom_theme) {
        style.setColor(.Text, rgba(0.90, 0.90, 0.90, 1.00));
        style.setColor(.Border, rgba(0.54, 0.57, 0.51, 0.50));
        style.setColor(.BorderShadow, rgba(0.14, 0.16, 0.11, 0.52));
        style.setColor(.TitleBg, rgba(0.24, 0.27, 0.20, 1.00));
        style.setColor(.TitleText, style.getColor(.Text));
        style.setColor(.WindowBg, rgba(0.29, 0.34, 0.26, 1.00));
        style.setColor(.Header, rgba(0.35, 0.42, 0.31, 1.00));
        style.setColor(.HeaderHover, rgba(0.35, 0.42, 0.31, 0.60));
        style.setColor(.HeaderFocus, rgba(0.54, 0.57, 0.51, 0.50));
        style.setColor(.Button, rgba(0.29, 0.34, 0.26, 0.40));
        style.setColor(.ButtonHover, rgba(0.35, 0.42, 0.31, 1.00));
        style.setColor(.ButtonFocus, rgba(0.54, 0.57, 0.51, 0.50));
        style.setColor(.Base, rgba(0.29, 0.34, 0.26, 1.00));
        style.setColor(.Base, rgba(0.24, 0.27, 0.20, 1.00));
        style.setColor(.BaseHover, rgba(0.27, 0.30, 0.23, 1.00));
        style.setColor(.BaseFocus, rgba(0.30, 0.34, 0.26, 1.00));
        style.setColor(.ScrollBase, rgba(0.35, 0.42, 0.31, 1.00));
        style.setColor(.ScrollThumb, rgba(0.23, 0.27, 0.21, 1.00));
        // style.setColor(.ScrollThumb, rgba(0.25, 0.30, 0.22, 1.00));
        // style.setColor(.ScrollThumb, rgba(0.28, 0.32, 0.24, 1.00));
    }
    ui.style = &style;

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
            try ui.beginFrame(&input);
            defer ui.endFrame();

            try testWindow(ui);
            _ = logWindow(ui);
            styleWindow(ui);
        }

        // TODO (Matteo): TEST RENDERING!!!
        // render
        r.clear(bg);

        var iter = ui.command_list.iter();
        while (iter.next()) |cmd| {
            switch (cmd.type) {
                .Text => {
                    var buf: [1024]u8 = undefined;
                    const str = cmd.text.read();
                    std.debug.assert(str.len < buf.len);
                    std.mem.copy(u8, buf[0..], str);
                    buf[str.len] = 0;
                    r.drawText(&buf, cmd.text.pos, cmd.text.color);
                },
                .Rect => {
                    if (cmd.rect.fill) {
                        r.drawRect(cmd.rect.rect, cmd.rect.color);
                    } else {
                        renderBox(r, cmd.rect.rect, cmd.rect.color);
                    }
                },
                .Icon => r.drawIcon(cmd.icon.id, cmd.icon.rect, cmd.icon.color),
                .Clip => r.setClipRect(cmd.clip.rect),
                else => unreachable,
            }
        }
        r.flush();
        _ = c.SDL_GL_SwapWindow(window);
    }
}

fn renderBox(r: *Renderer, rect: mu.Rect, color: mu.Color) void {
    // NOTE (Matteo): This was part of the original microui implementation
    // I reviewed the drawing API in order to support both stroked and filled rects
    // (and ellipses), so this implementation detail moved to the rendering layer

    r.drawRect(mu.Rect.init(
        rect.pt.x + 1,
        rect.pt.y,
        rect.sz.x - 2,
        1,
    ), color);

    r.drawRect(mu.Rect.init(
        rect.pt.x + 1,
        rect.pt.y + rect.sz.y - 1,
        rect.sz.x - 2,
        1,
    ), color);

    r.drawRect(mu.Rect.init(
        rect.pt.x,
        rect.pt.y,
        1,
        rect.sz.y,
    ), color);

    r.drawRect(mu.Rect.init(
        rect.pt.x + rect.sz.x - 1,
        rect.pt.y,
        1,
        rect.sz.y,
    ), color);
}

fn textWidth(ptr: ?*anyopaque, str: []const u8) i32 {
    const r = opaqueCast(Renderer, ptr orelse unreachable);
    return r.getTextWidth(str);
}

fn opaqueCast(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

fn writeLog(text: []const u8) void {
    const l = logbuf.getPos() catch unreachable;

    // Append new line
    if (l > 0) _ = logbuf.write("\n") catch unreachable;

    // Append text
    _ = logbuf.write(text) catch unreachable;

    logbuf_updated = true;
}

fn testWindow(ui: *Ui) !void {
    // do window
    if (ui.beginWindow("Demo Window", mu.Rect.init(40, 40, 300, 450), .{})) {
        defer ui.endWindow();

        var win = ui.getCurrentContainer();
        win.*.rect.sz.x = std.math.max(win.*.rect.sz.x, 240);
        win.*.rect.sz.y = std.math.max(win.*.rect.sz.y, 300);

        // window info */
        if (ui.header("Window Info", .{})) {
            win = ui.getCurrentContainer();
            var buf: [64]u8 = undefined;
            ui.layoutRow(.{ 54, -1 }, 0);

            ui.label("Position:");
            ui.label(try std.fmt.bufPrint(
                buf[0..],
                "{}, {}",
                .{ win.*.rect.pt.x, win.*.rect.pt.y },
            ));

            ui.label("Size:");
            ui.label(try std.fmt.bufPrint(
                buf[0..],
                "{}, {}",
                .{ win.*.rect.sz.x, win.*.rect.sz.y },
            ));
        }

        // labels + buttons */
        if (ui.header("Test Buttons", .{ .expanded = true })) {
            ui.layoutRow(.{ 86, -110, -1 }, 0);

            ui.label("Test buttons 1:");

            if (ui.button("Button 1")) writeLog("Pressed button 1");
            if (ui.button("Button 2")) writeLog("Pressed button 2");

            ui.label("Test buttons 2:");

            if (ui.button("Button 3")) writeLog("Pressed button 3");
            if (ui.button("Popup")) ui.openPopup("Test Popup");

            if (ui.beginPopup("Test Popup")) {
                _ = ui.button("Hello");
                _ = ui.button("World");
                ui.endPopup();
            }
        }

        // tree */
        if (ui.header("Tree and Text", .{ .expanded = true })) {
            ui.layoutRow(.{ 140, -1 }, 0);
            ui.layoutBeginColumn();

            if (ui.beginTreeNode("Test 1", .{})) {
                if (ui.beginTreeNode("Test 1a", .{})) {
                    ui.label("Hello");
                    ui.label("world");
                    ui.endTreeNode();
                }

                if (ui.beginTreeNode("Test 1b", .{})) {
                    if (ui.button("Button 1")) writeLog("Pressed button 1");
                    if (ui.button("Button 2")) writeLog("Pressed button 2");
                    ui.endTreeNode();
                }

                ui.endTreeNode();
            }

            if (ui.beginTreeNode("Test 2", .{})) {
                ui.layoutRow(.{ 54, 54 }, 0);

                if (ui.button("Button 3")) writeLog("Pressed button 3");
                if (ui.button("Button 4")) writeLog("Pressed button 4");
                if (ui.button("Button 5")) writeLog("Pressed button 5");
                if (ui.button("Button 6")) writeLog("Pressed button 6");

                ui.endTreeNode();
            }

            if (ui.beginTreeNode("Test 3", .{})) {
                _ = ui.checkbox("Checkbox 1", &checks[0]);
                _ = ui.checkbox("Checkbox 2", &checks[1]);
                _ = ui.checkbox("Checkbox 3", &checks[2]);
                ui.endTreeNode();
            }
            ui.layoutEndColumn();

            ui.layoutBeginColumn();
            ui.layoutRow(.{-1}, 0);
            ui.text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus ipsum, eu varius magna felis a nulla.");
            ui.layoutEndColumn();
        }

        // background color sliders */
        if (ui.header("Background Color", .{ .expanded = true })) {
            ui.layoutRow(.{ -78, -1 }, 74);
            // sliders */
            ui.layoutBeginColumn();
            ui.layoutRow(.{ 46, -1 }, 0);
            ui.label("Red:");
            _ = sliderU8(ui, &bg.r);
            ui.label("Green:");
            _ = sliderU8(ui, &bg.g);
            ui.label("Blue:");
            _ = sliderU8(ui, &bg.b);
            ui.layoutEndColumn();
            // color preview */
            const r = ui.layoutNext();
            ui.drawRect(r, bg) catch unreachable;
            var buf: [32]u8 = undefined;
            ui.drawControlText(
                try std.fmt.bufPrint(buf[0..], "#{X}{X}{X}", .{ bg.r, bg.g, bg.b }),
                r,
                .Text,
                .{ .align_center = true },
            );
        }
    }
}

fn logWindow(ui: *Ui) void {
    if (ui.beginWindow("Log Window", mu.Rect.init(350, 40, 300, 200), .{})) {
        defer ui.endWindow();

        //  output text panel
        ui.layoutRow(.{-1}, -25);

        if (ui.beginPanel("Log Output", .{})) {
            var panel = ui.getCurrentContainer();
            ui.layoutRow(.{-1}, -1);

            ui.text(logbuf.getWritten());
            ui.endPanel();

            if (logbuf_updated) {
                panel.*.scroll.y = panel.*.content_size.y;
                logbuf_updated = false;
            }
        }

        // input textbox + submit button
        const input = struct {
            var buf = [_]u8{0} ** 128;
            var text = mu.TextBuffer.fromSlice(buf[0..]);
        };

        ui.layoutRow(.{ -70, -1 }, 0);

        var result = ui.textbox(&input.text, .{});

        if (result.submit) ui.curr_focus = ui.*.last_id;

        if (ui.button("Submit")) result.submit = true;

        if (result.submit) {
            writeLog(input.text.text);
            input.text.clear();
        }
    }
}

fn styleWindow(ui: *Ui) void {
    if (ui.beginWindow("Style Editor", mu.Rect.init(350, 250, 300, 240), .{})) {
        defer ui.endWindow();

        const width = ui.getCurrentContainer().*.body.sz.x;

        ui.layoutRow(.{-1}, 0);
        if (ui.header("Dimensions", .{})) {
            ui.layoutRow(.{ 80, -1 }, 0);

            ui.label("Indent");
            _ = sliderInt(i32, ui, &ui.style.indent, 0, 32);

            ui.label("Padding");
            _ = sliderInt(i32, ui, &ui.style.padding, 1, 32);

            ui.label("Spacing");
            _ = sliderInt(i32, ui, &ui.style.spacing, 1, 32);

            ui.label("Row height");
            _ = sliderInt(i32, ui, &ui.style.size.y, 1, 32);

            ui.label("Title height");
            _ = sliderInt(i32, ui, &ui.style.title_height, 1, 32);

            ui.label("Scrollbar size");
            _ = sliderInt(i32, ui, &ui.style.scrollbar_size, 1, 32);

            ui.label("Thumb size");
            _ = sliderInt(i32, ui, &ui.style.thumb_size, 1, 32);
        }

        ui.layoutRow(.{-1}, 0);
        if (ui.header("Colors", .{ .expanded = true })) {
            const sw = @floatToInt(i32, @intToFloat(f64, width) * 0.14);
            ui.layoutRow(.{ 80, sw, sw, sw, sw, -1 }, 0);

            const fields = @typeInfo(mu.ColorId).Enum.fields;

            inline for (fields) |field| {
                var color = &ui.style.colors[field.value];
                ui.label(field.name);
                _ = sliderU8(ui, &color.r);
                _ = sliderU8(ui, &color.g);
                _ = sliderU8(ui, &color.b);
                _ = sliderU8(ui, &color.a);
                ui.drawRect(ui.layoutNext(), color.*) catch unreachable;
            }
        }
    }
}

fn sliderU8(ui: *Ui, value: *u8) bool {
    return sliderInt(u8, ui, value, std.math.minInt(u8), std.math.maxInt(u8));
}

// TODO (Matteo): Use type deduction? Move to microui proper?
fn sliderInt(comptime T: type, ui: *Ui, value: *T, min: T, max: T) bool {
    var tmp = @intToFloat(f32, value.*);

    // NOTE (Matteo): This is required to have an unique id based on the value
    // pointer, otherwise it would be generated using the temporary local pointer
    ui.pushId(value);
    defer ui.popId();

    const res = ui.sliderEx(
        &tmp,
        @intToFloat(f32, min),
        @intToFloat(f32, max),
        0,
        "{d:.0}",
        .{ .align_center = true },
    );
    value.* = @floatToInt(T, tmp);

    return res;
}

fn rgba(r: f32, g: f32, b: f32, a: f32) mu.Color {
    return .{
        .r = @floatToInt(u8, std.math.clamp(r * 255, 0, 255)),
        .g = @floatToInt(u8, std.math.clamp(g * 255, 0, 255)),
        .b = @floatToInt(u8, std.math.clamp(b * 255, 0, 255)),
        .a = @floatToInt(u8, std.math.clamp(a * 255, 0, 255)),
    };
}
