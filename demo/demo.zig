const std = @import("std");

const mu = @import("microui");
const Ui = mu.Ui(.{});
const Font = mu.Font;

var _logbuf = [_]u8{0} ** 64000;
var logbuf = std.io.fixedBufferStream(_logbuf[0..]);
var logbuf_updated = false;

var checks = [3]bool{ true, false, true };

pub fn frame(ui: anytype, bg: *mu.Color) !void {
    try testWindow(ui, bg);
    _ = logWindow(ui);
    styleWindow(ui);
}

fn writeLog(text: []const u8) void {
    const l = logbuf.getPos() catch unreachable;

    // Append new line
    if (l > 0) _ = logbuf.write("\n") catch unreachable;

    // Append text
    _ = logbuf.write(text) catch unreachable;

    logbuf_updated = true;
}

fn testWindow(ui: anytype, bg: *mu.Color) !void {
    // do window
    if (ui.beginWindow("Demo Window", mu.rect(40, 40, 300, 450), .{})) {
        defer ui.endWindow();

        var win = ui.getCurrentContainer();
        win.*.rect.sz.x = @max(win.*.rect.sz.x, 240);
        win.*.rect.sz.y = @max(win.*.rect.sz.y, 300);

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
            ui.drawRect(r, bg.*) catch unreachable;
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
    if (ui.beginWindow("Log Window", mu.rect(350, 40, 300, 200), .{})) {
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

fn styleWindow(ui: anytype) void {
    if (ui.beginWindow("Style Editor", mu.rect(350, 250, 300, 240), .{})) {
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
            const sw = @as(i32, @intFromFloat(@as(f64, @floatFromInt(width)) * 0.14));
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

fn sliderU8(ui: anytype, value: *u8) bool {
    return sliderInt(u8, ui, value, std.math.minInt(u8), std.math.maxInt(u8));
}

// TODO (Matteo): Use type deduction? Move to microui proper?
fn sliderInt(comptime T: type, ui: anytype, value: *T, min: T, max: T) bool {
    var tmp = @as(f32, @floatFromInt(value.*));

    // NOTE (Matteo): This is required to have an unique id based on the value
    // pointer, otherwise it would be generated using the temporary local pointer
    ui.pushId(value);
    defer ui.popId();

    const res = ui.sliderEx(
        &tmp,
        @as(f32, @floatFromInt(min)),
        @as(f32, @floatFromInt(max)),
        0,
        "{d:.0}",
        .{ .align_center = true },
    );
    value.* = @as(T, @intFromFloat(tmp));

    return res;
}

fn rgba(r: f32, g: f32, b: f32, a: f32) mu.Color {
    return .{
        .r = @as(u8, @intFromFloat(std.math.clamp(r * 255, 0, 255))),
        .g = @as(u8, @intFromFloat(std.math.clamp(g * 255, 0, 255))),
        .b = @as(u8, @intFromFloat(std.math.clamp(b * 255, 0, 255))),
        .a = @as(u8, @intFromFloat(std.math.clamp(a * 255, 0, 255))),
    };
}
