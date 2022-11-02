//
// Copyright (c) 2020 rxi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
//

const std = @import("std");

const assert = std.debug.assert;

test "MicroUi" {
    std.testing.refAllDecls(@This());

    const MicroUi = Context(.{});

    const font: Font = undefined;
    var ui: MicroUi = undefined;
    const input = ui.init(&font, null);

    try ui.beginFrame(input);
    defer ui.endFrame();
}

pub const Id = u32;

/// Compile-time configuration parameters
pub const Config = struct {
    command_list_size: usize = (256 * 1024),
    rootlist_size: usize = 32,
    container_stack_size: usize = 32,
    clip_stack_size: usize = 32,
    id_stack_size: usize = 32,
    layout_stack_size: usize = 16,
    container_pool_size: usize = 48,
    treenode_pool_size: usize = 48,
    max_widths: usize = 16,
    real: type = f32,
    real_fmt: []const u8 = "%.3g",
    slider_fmt: []const u8 = "%.2f",
    max_fmt: usize = 127,
    input_buf_size: usize = 32,
};

pub const Clip = enum(u2) {
    None,
    Part,
    All,
};

pub const CommandId = enum(u32) {
    None,
    Jump,
    Clip,
    Rect,
    Text,
    Icon,
    _,
};

pub const ColorId = enum(u4) {
    Text,
    Border,
    WindowBg,
    TitleBg,
    TitleText,
    PanelBg,
    Button,
    ButtonHover,
    ButtonFocus,
    Base,
    BaseHover,
    BaseFocus,
    ScrollBase,
    ScrollThumb,
};

pub const Icon = enum(u32) {
    None,
    Close,
    Check,
    Collapsed,
    Expanded,
    _,
};

pub const Color = extern struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 0 };

pub const Vec2 = extern struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn add(l: Vec2, r: Vec2) Vec2 {
        return Vec2{ .x = l.x + r.x, .y = l.y + r.y };
    }

    pub fn sub(l: Vec2, r: Vec2) Vec2 {
        return Vec2{ .x = l.x - r.x, .y = l.y - r.y };
    }
};

pub const Rect = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    fn expand(rect: Rect, n: i32) Rect {
        return Rect{
            .x = rect.x - n,
            .y = rect.y - n,
            .w = rect.w + 2 * n,
            .h = rect.h + 2 * n,
        };
    }

    pub fn intersect(r1: Rect, r2: Rect) Rect {
        const x1 = std.math.max(r1.x, r2.x);
        const y1 = std.math.max(r1.y, r2.y);

        var x2 = std.math.min(r1.x + r1.w, r2.x + r2.w);
        var y2 = std.math.min(r1.y + r1.h, r2.y + r2.h);

        if (x2 < x1) x2 = x1;
        if (y2 < y1) y2 = y1;

        return Rect{
            .x = x1,
            .y = y1,
            .w = x2 - x1,
            .h = y2 - y1,
        };
    }

    pub fn overlaps(rect: Rect, p: Vec2) bool {
        return p.x >= rect.x and p.x <= rect.x + rect.w and
            p.y >= rect.y and p.y <= rect.y + rect.h;
    }
};

pub const Font = struct {
    text_height: i32,
    text_width: fn (ptr: ?*anyopaque, str: []const u8) i32,
    ptr: ?*anyopaque = null,

    pub fn measure(self: *const Font, text: []const u8) i32 {
        return self.text_width(self.ptr, text);
    }
};

pub const Result = packed struct {
    active: bool = false,
    submit: bool = false,
    change: bool = false,

    pub usingnamespace BitSet(Result, u3);
};

pub const OptionFlags = packed struct {
    align_center: bool = false,
    align_right: bool = false,
    no_interact: bool = false,
    no_frame: bool = false,
    no_resize: bool = false,
    no_scroll: bool = false,
    no_title: bool = false,
    hold_focus: bool = false,
    auto_size: bool = false,
    popup: bool = false,
    closed: bool = false,
    expanded: bool = false,

    pub usingnamespace BitSet(OptionFlags, u12);
};

pub const MouseButtons = packed struct {
    left: bool = false,
    right: bool = false,
    middle: bool = false,

    pub usingnamespace BitSet(MouseButtons, u3);
};

pub const Keys = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    backspace: bool = false,
    enter: bool = false,

    pub usingnamespace BitSet(Keys, u5);
};

// TODO (Matteo): Rethink command implementation.
// The current solution works pretty well in C but seems a bit foreign in Zig;
// furthermore, I'd like to provide easy extension with user-defined commands.

pub const BaseCommand = extern struct { type: CommandId, size: usize };
pub const JumpCommand = extern struct { base: BaseCommand, dst: usize };
pub const ClipCommand = extern struct { base: BaseCommand, rect: Rect };
pub const RectCommand = extern struct { base: BaseCommand, rect: Rect, color: Color };
pub const TextCommand = extern struct { base: BaseCommand, font: *const Font, pos: Vec2, color: Color, str: [*:0]u8 };
pub const IconCommand = extern struct { base: BaseCommand, rect: Rect, id: Icon, color: Color };

pub const Command = extern union {
    type: CommandId,
    base: BaseCommand,
    jump: JumpCommand,
    clip: ClipCommand,
    rect: RectCommand,
    text: TextCommand,
    icon: IconCommand,
};

pub const Container = struct {
    head: *Command,
    tail: *Command,
    rect: Rect,
    body: Rect,
    content_size: Vec2,
    scroll: Vec2,
    zindex: i32,
    open: bool,
};

pub const Style = struct {
    font: *const Font,
    size: Vec2,
    padding: i32,
    spacing: i32,
    indent: i32,
    title_height: i32,
    scrollbar_size: i32,
    thumb_size: i32,
    colors: [memberCount(ColorId)]Color,
};

// NOTE (Matteo): Using 'anyopaque' because the Context type is dependent on
// the comptime configuration - ugly?
pub const DrawFrameFn = fn (self: *anyopaque, rect: Rect, color: ColorId) void;

pub fn Context(comptime config: Config) type {
    const Layout = struct {
        body: Rect,
        next: Rect,
        position: Vec2,
        size: Vec2,
        max: Vec2,
        widths: [config.max_widths]i32,
        item: i32,
        item_index: i32,
        next_row: i32,
        next_type: i32,
        indent: i32,
    };

    const Input = struct {
        mouse_pos: Vec2 = .{},
        scroll_delta: Vec2 = .{},
        mouse_down: MouseButtons = .{},
        mouse_pressed: MouseButtons = .{},
        key_down: Keys = .{},
        key_pressed: Keys = .{},
        text_buf: [config.input_buf_size]u8 = [_]u8{0} ** config.input_buf_size,
        text_len: usize = 0,

        const Self = @This();

        pub inline fn mouseMove(self: *Self, x: i32, y: i32) void {
            self.mouse_pos = .{ .x = x, .y = y };
        }

        pub fn mouseDown(self: *Self, x: i32, y: i32, btn: MouseButtons) void {
            if (btn.any()) {
                self.mouseMove(x, y);
                self.mouse_down = self.mouse_down.unionWith(btn);
                self.mouse_pressed = self.mouse_pressed.unionWith(btn);
            }
        }

        pub fn mouseUp(self: *Self, x: i32, y: i32, btn: MouseButtons) void {
            if (btn.any()) {
                self.mouseMove(x, y);
                self.mouse_down = self.mouse_down.exceptWith(btn);
            }
        }

        pub inline fn scroll(self: *Self, x: i32, y: i32) void {
            self.scroll_delta.x += x;
            self.scroll_delta.y += y;
        }

        pub fn keyDown(self: *Self, key: Keys) void {
            self.key_down = self.key_down.unionWith(key);
            self.key_pressed = self.key_pressed.unionWith(key);
        }

        pub fn keyUp(self: *Self, key: Keys) void {
            self.key_down = self.key_down.exceptWith(key);
        }

        pub fn text(self: *Self, str: []const u8) void {
            std.mem.copy(u8, self.text_buf[self.text_len..], str);
        }

        pub fn textZ(self: *Self, str: [*:0]const u8) void {
            const len = std.mem.len(str);
            std.mem.copy(u8, self.text_buf[self.text_len..], str[0..len]);
        }
    };

    return struct {
        pub const Real = config.real;

        const Self = @This();

        //=== Data ===//

        // callbacks
        // TODO (Matteo): Improve custom drawing of window frames
        draw_frame: DrawFrameFn,

        // core state
        _style: Style,
        style: *Style,
        hover: Id,
        focus: Id,
        last_id: Id,
        last_rect: Rect,
        last_zindex: i32,
        updated_focus: bool,
        frame: u32,
        hover_root: ?*Container,
        next_hover_root: ?*Container,
        scroll_target: ?*Container,
        number_edit_buf: [config.max_fmt]u8,
        number_edit: Id,

        // stacks
        command_list: CommandList(config.command_list_size) = .{},
        root_list: Stack(*Container, config.rootlist_size) = .{},
        container_stack: Stack(*Container, config.container_stack_size) = .{},
        clip_stack: Stack(Rect, config.clip_stack_size) = .{},
        id_stack: Stack(Id, config.id_stack_size) = .{},
        layout_stack: Stack(Layout, config.layout_stack_size) = .{},

        // retained state pools
        containers: [config.container_pool_size]Container,
        container_pool: Pool(config.container_pool_size) = .{},
        treenode_pool: Pool(config.treenode_pool_size) = .{},

        // input state
        last_input: Input,
        mouse_delta: Vec2 = .{},

        // TODO (Matteo): Review - used to intercept missing calls to the init functions
        init_code: u16,

        //=== Initialization ===//

        pub fn init(self: *Self, font: *const Font, draw_frame: ?DrawFrameFn) Input {
            self.init_code = 0x1DEA;
            self._style.font = font;
            self.style = &self._style;
            self.draw_frame = if (draw_frame) |ptr|
                ptr
            else
                @ptrCast(DrawFrameFn, drawDefaultFrame);

            return .{};
        }

        pub fn allocate(alloc: std.mem.Allocator, font: *const Font) !*Self {
            var self = try alloc.create(Self);
            self.init(font);
            return self;
        }

        pub fn release(self: *Self, alloc: std.mem.Allocator) void {
            alloc.destroy(self);
        }

        //=== Frame management ===//

        pub fn beginFrame(self: *Self, input: Input) !void {
            if (self.init_code != 0x1DEA) return error.NotInitialized;

            self.command_list.clear();
            self.root_list.clear();

            self.scroll_target = null;
            self.hover_root = self.next_hover_root;
            self.next_hover_root = null;

            self.mouse_delta = input.mouse_pos.sub(self.last_input.mouse_pos);
            self.last_input = input;

            self.frame +%= 1; // wrapping increment, overflow is somewhat expected
        }

        pub fn endFrame(self: *Self) void {
            _ = self;

            // Check stacks
            assert(self.container_stack.idx == 0);
            assert(self.clip_stack.idx == 0);
            assert(self.id_stack.idx == 0);
            assert(self.layout_stack.idx == 0);

            // Handle scroll target
            if (self.scroll_target) |tgt| {
                tgt.scroll = tgt.scroll.add(self.last_input.scroll_delta);
            }

            // unset focus if focus id was not touched this frame
            if (!self.updated_focus) self.focus = 0;
            self.updated_focus = false;

            // Bring hover root to front if mouse was pressed
            if (self.next_hover_root) |hover_root| {
                if (self.last_input.mouse_pressed.any() and
                    hover_root.zindex < self.last_zindex and
                    hover_root.zindex >= 0)
                {
                    self.bringToFront(hover_root);
                }
            }

            // Reset input state
            self.last_input.key_pressed = .{};
            self.last_input.mouse_pressed = .{};
            self.last_input.scroll_delta = .{};
            self.last_input.text_len = 0;

            // Sort root containers by zindex
            const compare = struct {
                fn lessThan(_: void, a: *Container, b: *Container) bool {
                    return a.zindex < b.zindex;
                }
            };

            const n = self.root_list.idx;
            std.sort.sort(*Container, self.root_list.items[0..n], {}, compare.lessThan);

            // TODO (Matteo)
            // Set root container jump commands
        }

        //=== ID management ===//

        pub fn getId(self: *Self, data: []const u8) Id {
            const init_id = if (self.id_stack.peek()) |id| id.* else HASH_INITIAL;
            self.last_id = hash(data, init_id);
            return self.last_id;
        }

        pub fn pushId(self: *Self, data: []const u8) void {
            self.id_stack.push(self.getId(data));
        }

        pub fn popId(self: *Self) void {
            _ = self.id_stack.pop();
        }

        pub fn setFocus(self: *Self, id: Id) void {
            self.focus = id;
            self.updated_focus = true;
        }

        //=== Container management ===//

        pub fn getCurrentContainer(self: *Self) *Container {
            var ptr = self.container_stack.peek() orelse unreachable;
            return ptr.*;
        }

        pub fn getContainer(self: *Self, name: []u8) *Container {
            const id = self.getId(name);
            return self.getContainerById(id, .{}) orelse unreachable;
        }

        pub fn bringToFront(self: *Self, cnt: *Container) void {
            self.last_zindex += 1;
            cnt.zindex = self.last_zindex;
        }

        fn popContainer(self: *Self) void {
            const layout = self.getLayout();
            var cnt = self.getCurrentContainer();

            cnt.content_size.x = layout.max.x - layout.body.x;
            cnt.content_size.y = layout.max.y - layout.body.y;

            _ = self.container_stack.pop();
            _ = self.layout_stack.pop();
            self.popId();
        }

        fn getContainerById(self: *Self, id: Id, opt: OptionFlags) ?*Container {
            // Try to get existing container from pool
            if (self.container_pool.get(id)) |index| {
                if (self.containers[index].open or !opt.closed) {
                    // TODO (Matteo): Why update only in this case?
                    self.container_pool.update(index, self.frame);
                }
                return &self.containers[index];
            }

            if (opt.closed) return null;

            // Container not found in pool, init a new one
            const index = self.container_pool.init(id, self.frame);
            const cnt = &self.containers[index];
            // TODO (Matteo): Can be improved?
            cnt.* = std.mem.zeroInit(Container, .{});
            cnt.open = true;
            self.bringToFront(cnt);
            return cnt;
        }

        //=== Layout management ===//

        pub fn layoutRow(self: *Self, widths: anytype, height: i32) void {
            _ = self;
            _ = widths;
            _ = height;
            @compileError("Not implemented");
        }

        pub fn layoutWidth(self: *Self, width: i32) void {
            _ = self;
            _ = width;
            @compileError("Not implemented");
        }

        pub fn layoutHeight(self: *Self, height: i32) void {
            _ = self;
            _ = height;
            @compileError("Not implemented");
        }

        pub fn layoutBeginColumn(self: *Self) void {
            _ = self;
            @compileError("Not implemented");
        }

        pub fn layoutEndColumn(self: *Self) void {
            _ = self;
            @compileError("Not implemented");
        }

        pub fn layoutSetNext(self: *Self, r: Rect, relative: bool) void {
            _ = self;
            _ = r;
            _ = relative;
            @compileError("Not implemented");
        }

        pub fn layoutNext(self: *Self) Rect {
            _ = self;
            @compileError("Not implemented");
        }

        fn getLayout(self: *Self) *Layout {
            return self.layout_stack.peek() orelse unreachable;
        }

        //=== Clipping ===//

        pub fn pushClipRect(self: *Self, rect: Rect) void {
            const last = self.getClipRect();
            self.clip_stack.push(rect.intersect(last));
        }

        pub fn popClipRect(self: *Self) void {
            _ = self.clip_stack.pop();
        }

        pub fn getClipRect(self: *Self) Rect {
            self.clip_stack.peek() orelse unreachable;
        }

        pub fn checkClip(self: *Self, r: Rect) Clip {
            const c = self.getClipRect();

            const rx1 = r.x + r.w;
            const ry1 = r.y + r.h;

            const cx1 = c.x + c.w;
            const cy1 = c.y + c.h;

            if (r.x > cx1 or rx1 < c.x or
                r.y > cy1 or ry1 < c.y)
            {
                return .All;
            }

            if (r.x >= c.x and rx1 <= cx1 and
                r.y >= c.y and ry1 <= cy1)
            {
                return .None;
            }

            return .Part;
        }

        //=== Controls ===//

        pub fn mouseOver(self: *Self, rect: Rect) bool {
            _ = self;
            _ = rect;
            @compileError("Not implemented");
        }

        pub fn updateControl(
            self: *Self,
            id: Id,
            rect: Rect,
            opts: OptionFlags,
        ) void {
            _ = self;
            _ = id;
            _ = rect;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn text(self: *Self, str: []const u8) void {
            _ = self;
            _ = str;
            @compileError("Not implemented");
        }

        pub fn label(self: *Self, str: []const u8) void {
            _ = self;
            _ = str;
            @compileError("Not implemented");
        }

        pub inline fn button(self: *Self, id: []const u8) Result {
            return self.buttonEx(id, .None, .{ .align_center = true });
        }

        pub fn buttonEx(
            self: *Self,
            id: []const u8,
            icon: Icon,
            opts: OptionFlags,
        ) Result {
            _ = self;
            _ = id;
            _ = icon;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn checkbox(self: *Self, id: []const u8, state: *bool) Result {
            _ = self;
            _ = id;
            _ = state;
            @compileError("Not implemented");
        }

        pub fn textbox(self: *Self, buf: []u8, opts: OptionFlags) Result {
            _ = self;
            _ = buf;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn textboxRaw(
            self: *Self,
            buf: []u8,
            id: Id,
            rect: Rect,
            opts: OptionFlags,
        ) Result {
            _ = self;
            _ = buf;
            _ = id;
            _ = rect;
            _ = opts;
            @compileError("Not implemented");
        }

        pub inline fn slider(
            self: *Self,
            value: *Real,
            low: Real,
            high: Real,
        ) Result {
            return self.sliderEx(
                value,
                low,
                high,
                0,
                config.slider_fmt,
                .{ .align_center = true },
            );
        }

        pub fn sliderEx(
            self: *Self,
            value: *Real,
            low: Real,
            high: Real,
            step: Real,
            fmt: []const u8,
            opts: OptionFlags,
        ) Result {
            _ = self;
            _ = value;
            _ = low;
            _ = high;
            _ = step;
            _ = fmt;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn number(
            self: *Self,
            value: *Real,
            step: Real,
        ) Result {
            return self.numberEx(
                value,
                step,
                config.slider_fmt,
                .{ .align_center = true },
            );
        }

        pub fn numberEx(
            self: *Self,
            value: *Real,
            step: Real,
            fmt: []const u8,
            opts: OptionFlags,
        ) Result {
            _ = self;
            _ = value;
            _ = step;
            _ = fmt;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn header(self: *Self, id: []const u8, opts: OptionFlags) Result {
            _ = self;
            _ = id;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn beginTreeNode(self: *Self, id: []const u8, opts: OptionFlags) Result {
            _ = self;
            _ = id;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn endTreeNode(self: *Self) void {
            _ = self;
            @compileError("Not implemented");
        }

        pub fn beginWindow(
            self: *Self,
            title: []const u8,
            rect: Rect,
            opts: OptionFlags,
        ) Result {
            _ = self;
            _ = title;
            _ = rect;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn endWindow(self: *Self) void {
            _ = self;
            @compileError("Not implemented");
        }

        pub fn openPopup(self: *Self, name: []const u8) void {
            _ = self;
            _ = name;
            @compileError("Not implemented");
        }

        pub fn beginPopup(self: *Self, name: []const u8) Result {
            return self.beginWindow(name, .{}, .{
                .popup = true,
                .auto_size = true,
                .no_resize = true,
                .no_scroll = true,
                .no_title = true,
                .closed = true,
            });
        }

        pub fn endPopup(self: *Self) void {
            self.endWindow();
        }

        pub fn beginPanel(self: *Self, name: []const u8, opts: OptionFlags) void {
            _ = self;
            _ = name;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn endPanel(self: *Self) void {
            self.popClipRect();
            self.popContainer();
        }

        //=== Drawing ===//

        // TODO (Matteo): move the drawing functions on the command list directly?
        // Can help a bit with code organization, since it is the only state touched.

        pub fn pushCommand(self: *Self, id: CommandId, size: usize) *Command {
            return self.command_list.push(id, size);
        }

        // TODO (Matteo): Command iteration

        pub fn setClip(self: *Self, rect: Rect) void {
            _ = self;
            _ = rect;
            @compileError("Not implemented");
        }

        pub fn drawControlFrame(
            self: *Self,
            id: Id,
            rect: Rect,
            color: ColorId,
            opts: OptionFlags,
        ) void {
            _ = self;
            _ = id;
            _ = rect;
            _ = color;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn drawControlText(
            self: *Self,
            str: []const u8,
            rect: Rect,
            color: ColorId,
            opts: OptionFlags,
        ) void {
            _ = self;
            _ = str;
            _ = rect;
            _ = color;
            _ = opts;
            @compileError("Not implemented");
        }

        pub fn drawRect(self: *Self, rect: Rect, color: Color) void {
            _ = self;
            _ = rect;
            _ = color;
            // Not implemented
            unreachable;
        }

        pub fn drawBox(self: *Self, rect: Rect, color: Color) void {
            self.drawRect(.{
                .x = rect.x + 1,
                .y = rect.y,
                .w = rect.w - 2,
                .h = 1,
            }, color);
            self.drawRect(.{
                .x = rect.x + 1,
                .y = rect.y + rect.h - 1,
                .w = rect.w - 2,
                .h = 1,
            }, color);
            self.drawRect(.{
                .x = rect.x,
                .y = rect.y,
                .w = 1,
                .h = rect.h,
            }, color);
            self.drawRect(.{
                .x = rect.x + rect.w - 1,
                .y = rect.y,
                .w = 1,
                .h = rect.h,
            }, color);
        }

        pub fn drawText(self: *Self, font: *Font, str: []const u8, pos: Vec2, color: Color) void {
            _ = self;
            _ = font;
            _ = str;
            _ = pos;
            _ = color;
            @compileError("Not implemented");
        }

        pub fn drawIcon(self: *Self, id: Icon, rect: Rect, color: Color) void {
            _ = self;
            _ = id;
            _ = rect;
            _ = color;
            @compileError("Not implemented");
        }

        inline fn drawFrame(self: *Self, rect: Rect, color_id: ColorId) void {
            // NOTE (Matteo): Helper to abbreviate the calls involving the function
            // pointer - ugly?
            self.draw_frame(self, rect, color_id);
        }

        fn drawDefaultFrame(self: *Self, rect: Rect, color_id: ColorId) void {
            const color = self.getColor(color_id);
            self.drawRect(rect, color);

            switch (color_id) {
                .ScrollBase, .ScrollThumb, .TitleBg => return,
                else => if (color.a != 0) {
                    self.drawBox(rect.expand(1), color);
                },
            }
        }

        //=== Internals ===//

        inline fn getColor(self: *const Self, id: ColorId) Color {
            // NOTE (Matteo): Helper to avoid casting the id everywhere - ugly?
            return self.style.colors[@enumToInt(id)];
        }
    };
}

//============//

fn Stack(comptime T: type, comptime N: usize) type {
    return struct {
        items: [N]T = undefined,
        idx: usize = 0,

        const Self = @This();

        fn clear(self: *Self) void {
            self.idx = 0;
        }

        fn push(self: *Self, item: T) void {
            assert(self.idx < self.items.len);
            self.items[self.idx] = item;
            self.idx += 1;
        }

        fn pop(self: *Self) T {
            assert(self.idx > 0);
            self.idx -= 1;
            return self.items[self.idx];
        }

        fn peek(self: *Self) ?*T {
            return if (self.idx == 0) null else &self.items[self.idx - 1];
        }
    };
}

test "Stack" {
    const expect = std.testing.expect;

    var s = Stack(i32, 5){};

    try expect(s.idx == 0);

    s.push(0);
    s.push(1);
    s.push(2);
    s.push(3);
    s.push(4);

    try expect(s.pop() == 4);
    try expect(s.pop() == 3);
    try expect(s.pop() == 2);
    try expect(s.pop() == 1);
    try expect(s.pop() == 0);
    try expect(s.idx == 0);
}

//============//

pub const PoolItem = struct { id: Id = undefined, last_update: i32 = 0 };

// TODO (Matteo): API review. At the moment multiple elements with the same ID
// can be stored - this does not happen if the expected usage, which is to always
// call 'get' before 'init', is followed, but this policy is not enforced in anyway.

fn Pool(comptime N: usize) type {
    return struct {
        items: [N]PoolItem = [_]PoolItem{.{}} ** N,

        const Self = @This();

        pub fn init(self: *Self, id: Id, curr_frame: i32) usize {
            var last_index = N;
            var frame = curr_frame;

            // Find the least recently updated item
            for (self.items) |item, index| {
                if (item.last_update < frame) {
                    frame = item.last_update;
                    last_index = index;
                }
            }

            assert(last_index < N);

            self.items[last_index].id = id;
            self.items[last_index].last_update = curr_frame;

            return last_index;
        }

        pub fn get(self: *Self, id: Id) ?usize {
            for (self.items) |item, index| {
                if (item.id == id) return index;
            }

            return null;
        }

        pub fn update(self: *Self, index: usize, curr_frame: i32) void {
            self.items[index].last_update = curr_frame;
        }
    };
}

test "Pool" {
    const expect = std.testing.expect;

    var p = Pool(5){};

    try expect(p.get(1) == null);

    try expect(p.init(1, 0) == 0);
    try expect(p.init(1, 0) == 1);

    try expect(p.get(1).? == 0);
    try expect(p.get(2).? == 1);

    try expect(p.init(3, 5) == 0);
    try expect(p.get(3).? == 0);

    p.update(0, 5);

    try expect(p.init(4, 5) == 1);
    try expect(p.get(4).? == 4);
}

//============//

fn CommandList(comptime N: usize) type {
    return struct {
        buffer: [N]u8 align(alignment) = undefined,
        pos: usize = 0,

        const Self = @This();
        const alignment = @alignOf(Command);

        fn clear(self: *Self) void {
            self.pos = 0;
        }

        pub fn push(self: *Self, id: CommandId, size: usize) *Command {
            assert(size < self.buffer.len);
            assert(self.pos < self.buffer.len - size);

            const next_pos = std.mem.alignForward(self.pos + size, alignment);

            var cmd = @ptrCast(*Command, @alignCast(alignment, &self.buffer[self.pos]));
            cmd.base.type = id;
            cmd.base.size = next_pos - self.pos;

            self.pos = next_pos;

            return cmd;
        }
    };
}

test "CommandList" {
    var cmds = CommandList(4096){};
    _ = cmds.push(.Rect, @sizeOf(RectCommand));
}

//============//

//  32bit fnv-1a hash

const HASH_INITIAL: Id = 2166136261;

fn hash(data: []const u8, hash_in: Id) Id {
    var hash_out = hash_in;

    for (data) |byte| {
        hash_out = (hash_out ^ byte) * 16777619;
    }

    return hash_out;
}

test "Hash" {
    const expect = std.testing.expect;

    const str1 = "Hello MicroUi!";
    const str2 = "Hallo microui!";

    const h1 = hash(str1, HASH_INITIAL);

    try expect(h1 == hash(str1, HASH_INITIAL));
    try expect(h1 != hash(str2, HASH_INITIAL));

    const h2 = hash(str2, h1);

    try expect(h1 != h2);
    try expect(h2 != hash(str2, HASH_INITIAL));
}

//============//

fn memberCount(comptime Enum: type) usize {
    return @typeInfo(Enum).Enum.fields.len;
}

test "memberCount" {
    const expect = std.testing.expect;
    try expect(memberCount(ColorId) == 14);
}

//============//

/// Mixin for bitsets implemented as packed structs
fn BitSet(comptime Struct: type, comptime Int: type) type {
    comptime {
        assert(@sizeOf(Struct) == @sizeOf(Int));
    }

    return struct {
        pub inline fn none(a: Struct) bool {
            return toInt(a) == 0;
        }

        pub inline fn any(a: Struct) bool {
            return toInt(a) != 0;
        }

        pub inline fn toInt(self: Struct) Int {
            return @bitCast(Int, self);
        }

        pub inline fn fromInt(value: Int) Struct {
            return @bitCast(Struct, value);
        }

        pub inline fn unionWith(a: Struct, b: Struct) Struct {
            return fromInt(toInt(a) | toInt(b));
        }

        pub inline fn intersectWith(a: Struct, b: Struct) Struct {
            return fromInt(toInt(a) & toInt(b));
        }

        pub fn exceptWith(a: Struct, b: Struct) Struct {
            return fromInt(toInt(a) & ~toInt(b));
        }
    };
}

//============//

