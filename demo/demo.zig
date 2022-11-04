const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const mu = @import("microui");
const Context = mu.Context(.{});
const Font = mu.Font;

// Render API
extern fn r_init(width: c_int, height: c_int) void;
extern fn r_draw_rect(rect: mu.Rect, color: mu.Color) void;
extern fn r_draw_text(text: [*]const u8, pos: mu.Vec2, color: mu.Color) void;
extern fn r_draw_icon(id: mu.Icon, rect: mu.Rect, color: mu.Color) void;
extern fn r_get_text_width(text: [*]const u8, len: c_int) c_int;
extern fn r_get_text_height() c_int;
extern fn r_set_clip_rect(rect: mu.Rect) void;
extern fn r_clear(color: mu.Color) void;
extern fn r_flush() void;

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
    value[c.SDLK_BACKSPACE & 0xff].backspace = true;
    break :init value;
};

const color_map = init: {
    const len = std.meta.fields(mu.ColorId).len;
    var value: [len][]const u8 = undefined;
    value[@enumToInt(mu.ColorId.Text)] = "text:";
    value[@enumToInt(mu.ColorId.Border)] = "border:";
    value[@enumToInt(mu.ColorId.WindowBg)] = "windowbg:";
    value[@enumToInt(mu.ColorId.TitleBg)] = "titlebg:";
    value[@enumToInt(mu.ColorId.TitleText)] = "titletext:";
    value[@enumToInt(mu.ColorId.PanelBg)] = "panelbg:";
    value[@enumToInt(mu.ColorId.Button)] = "button:";
    value[@enumToInt(mu.ColorId.ButtonHover)] = "buttonhover:";
    value[@enumToInt(mu.ColorId.ButtonFocus)] = "buttonfocus:";
    value[@enumToInt(mu.ColorId.Base)] = "base:";
    value[@enumToInt(mu.ColorId.BaseHover)] = "basehover:";
    value[@enumToInt(mu.ColorId.BaseFocus)] = "basefocus:";
    value[@enumToInt(mu.ColorId.ScrollBase)] = "scrollbase:";
    value[@enumToInt(mu.ColorId.ScrollThumb)] = "scrollthumb:";
    break :init value;
};

var _logbuf = [_]u8{0} ** 64000;
var logbuf = std.io.fixedBufferStream(_logbuf[0..]);
var logbuf_updated = false;

var bg = [_]f32{ 90, 95, 100 };
var checks = [3]bool{ true, false, true };

pub fn main() !void {
    // init microui
    const ui_alloc = std.heap.page_allocator;
    var ui_font = Font{
        .ptr = null,
        .text_height = r_get_text_height(),
        .text_width = textWidth,
    };
    var ui = try ui_alloc.create(Context);
    var input = ui.init(&ui_font, null);

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

    r_init(width, height);

    // main loop
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
            try ui.beginFrame(input);
            defer ui.endFrame();

            try testWindow(ui);
            logWindow(ui);
            styleWindow(ui);
        }

        // TODO (Matteo): TEST RENDERING!!!
        // render
        r_clear(mu.Color{
            .r = @floatToInt(u8, bg[0]),
            .g = @floatToInt(u8, bg[1]),
            .b = @floatToInt(u8, bg[2]),
            .a = 255,
        });

        var iter = ui.command_list.iter();
        while (iter.next()) |cmd| {
            switch (cmd.type) {
                .Text => {}, // r_draw_text(&cmd.text.str, cmd.text.pos, cmd.text.color),
                .Rect => r_draw_rect(cmd.rect.rect, cmd.rect.color),
                .Icon => r_draw_icon(cmd.icon.id, cmd.icon.rect, cmd.icon.color),
                .Clip => r_set_clip_rect(cmd.clip.rect),
                else => unreachable,
            }
        }
        r_flush();
        _ = c.SDL_GL_SwapWindow(window);
    }
}

fn textWidth(ptr: ?*anyopaque, str: []const u8) i32 {
    _ = ptr;
    return r_get_text_width(str.ptr, @intCast(c_int, str.len));
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

fn testWindow(ctx: *Context) !void {
    // do window
    if (ctx.beginWindow("Demo Window", mu.Rect.init(40, 40, 300, 450), .{}).any()) {
        defer ctx.endWindow();

        var win = ctx.getCurrentContainer();
        win.*.rect.sz.x = std.math.max(win.*.rect.sz.x, 240);
        win.*.rect.sz.y = std.math.max(win.*.rect.sz.y, 300);

        // window info */
        if (ctx.header("Window Info", .{}).any()) {
            win = ctx.getCurrentContainer();
            var buf: [64]u8 = undefined;
            ctx.layoutRow(.{ 54, -1 }, 0);

            ctx.label("Position:");
            ctx.label(try std.fmt.bufPrint(
                buf[0..],
                "{}, {}",
                .{ win.*.rect.pt.x, win.*.rect.pt.y },
            ));

            ctx.label("Size:");
            ctx.label(try std.fmt.bufPrint(
                buf[0..],
                "{}, {}",
                .{ win.*.rect.sz.x, win.*.rect.sz.y },
            ));
        }

        // labels + buttons */
        if (ctx.header("Test Buttons", .{ .expanded = true }).any()) {
            ctx.layoutRow(.{ 86, -110, -1 }, 0);

            ctx.label("Test buttons 1:");

            if (ctx.button("Button 1").any()) writeLog("Pressed button 1");
            if (ctx.button("Button 2").any()) writeLog("Pressed button 2");

            ctx.label("Test buttons 2:");

            if (ctx.button("Button 3").any()) writeLog("Pressed button 3");
            if (ctx.button("Popup").any()) ctx.openPopup("Test Popup");

            if (ctx.beginPopup("Test Popup").any()) {
                _ = ctx.button("Hello");
                _ = ctx.button("World");
                ctx.endPopup();
            }
        }

        // tree */
        if (ctx.header("Tree and Text", .{ .expanded = true }).any()) {
            ctx.layoutRow(.{ 140, -1 }, 0);
            ctx.layoutBeginColumn();

            if (ctx.beginTreeNode("Test 1", .{}).any()) {
                if (ctx.beginTreeNode("Test 1a", .{}).any()) {
                    ctx.label("Hello");
                    ctx.label("world");
                    ctx.endTreeNode();
                }

                if (ctx.beginTreeNode("Test 1b", .{}).any()) {
                    if (ctx.button("Button 1").any()) writeLog("Pressed button 1");
                    if (ctx.button("Button 2").any()) writeLog("Pressed button 2");
                    ctx.endTreeNode();
                }

                ctx.endTreeNode();
            }

            if (ctx.beginTreeNode("Test 2", .{}).any()) {
                ctx.layoutRow(.{ 54, 54 }, 0);

                if (ctx.button("Button 3").any()) writeLog("Pressed button 3");
                if (ctx.button("Button 4").any()) writeLog("Pressed button 4");
                if (ctx.button("Button 5").any()) writeLog("Pressed button 5");
                if (ctx.button("Button 6").any()) writeLog("Pressed button 6");

                ctx.endTreeNode();
            }

            if (ctx.beginTreeNode("Test 3", .{}).any()) {
                _ = ctx.checkbox("Checkbox 1", &checks[0]);
                _ = ctx.checkbox("Checkbox 2", &checks[1]);
                _ = ctx.checkbox("Checkbox 3", &checks[2]);
                ctx.endTreeNode();
            }
            ctx.layoutEndColumn();

            ctx.layoutBeginColumn();
            ctx.layoutRow(.{-1}, 0);
            ctx.text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus ipsum, eu varius magna felis a nulla.");
            ctx.layoutEndColumn();
        }

        // background color sliders */
        if (ctx.header("Background Color", .{ .expanded = true }).any()) {
            ctx.layoutRow(.{ -78, -1 }, 74);
            // sliders */
            ctx.layoutBeginColumn();
            ctx.layoutRow(.{ 46, -1 }, 0);
            ctx.label("Red:");
            _ = ctx.slider(&bg[0], 0, 255);
            ctx.label("Green:");
            _ = ctx.slider(&bg[1], 0, 255);
            ctx.label("Blue:");
            _ = ctx.slider(&bg[2], 0, 255);
            ctx.layoutEndColumn();
            // color preview */
            const r = ctx.layoutNext();
            ctx.drawRect(r, mu.Color{
                .r = @floatToInt(u8, bg[1]),
                .g = @floatToInt(u8, bg[0]),
                .b = @floatToInt(u8, bg[2]),
                .a = 255,
            });
            var buf: [32]u8 = undefined;
            ctx.drawControlText(
                try std.fmt.bufPrint(buf[0..], "#{X}{X}{X}", .{
                    @floatToInt(i32, bg[0]),
                    @floatToInt(i32, bg[1]),
                    @floatToInt(i32, bg[2]),
                }),
                r,
                .Text,
                .{ .align_center = true },
            );
        }
    }
}

fn logWindow(ctx: *Context) void {
    if (ctx.beginWindow("Log Window", mu.Rect.init(350, 40, 300, 200), .{}).any()) {
        defer ctx.endWindow();

        //  output text panel
        ctx.layoutRow(.{-1}, -25);
        ctx.beginPanel("Log Output", .{});
        var panel = ctx.getCurrentContainer();
        ctx.layoutRow(.{-1}, -1);

        const text = logbuf.getWritten()[0.. :0];

        ctx.text(text);
        ctx.endPanel();
        if (logbuf_updated) {
            panel.*.scroll.y = panel.*.content_size.y;
            logbuf_updated = false;
        }

        // input textbox + submit button
        const input = struct {
            var buf = [_]u8{0} ** 128;
        };
        var submitted = false;

        ctx.layoutRow(.{ -70, -1 }, 0);

        if (ctx.textbox(&input.buf, .{}).submit) {
            ctx.setFocus(ctx.*.last_id);
            submitted = true;
        }

        if (ctx.button("Submit").any()) submitted = true;

        if (submitted) {
            const len = std.mem.indexOfScalar(u8, input.buf[0..], 0) orelse unreachable;
            writeLog(input.buf[0..len :0]);
            std.mem.set(u8, input.buf[0..], 0);
        }
    }
}

fn styleWindow(ctx: *Context) void {
    if (ctx.beginWindow("Style Editor", mu.Rect.init(350, 250, 300, 240), .{}).any()) {
        defer ctx.endWindow();

        const width = ctx.getCurrentContainer().*.body.sz.x;
        const sw = @floatToInt(i32, @intToFloat(f64, width) * 0.14);
        ctx.layoutRow(.{ 80, sw, sw, sw, sw, -1 }, 0);

        for (color_map) |label, i| {
            var color = &ctx.style.*.colors[i];
            ctx.label(label);
            _ = sliderU8(ctx, &color.r, 0, 255);
            _ = sliderU8(ctx, &color.g, 0, 255);
            _ = sliderU8(ctx, &color.b, 0, 255);
            _ = sliderU8(ctx, &color.a, 0, 255);
            ctx.drawRect(ctx.layoutNext(), color.*);
        }
    }
}

fn sliderU8(ctx: *Context, value: *u8, low: u8, high: u8) mu.Result {
    var tmp = @intToFloat(f32, value.*);

    ctx.pushId(std.mem.asBytes(&value));

    const res = ctx.sliderEx(
        &tmp,
        @intToFloat(f32, low),
        @intToFloat(f32, high),
        0,
        "%.0f",
        .{ .align_center = true },
    );
    value.* = @floatToInt(u8, tmp);

    ctx.popId();

    return res;
}
