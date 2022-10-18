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

test "MicroUi" {
    std.testing.refAllDecls(@This());

    const MicroUi = Context(.{});

    const font: Font = undefined;
    var ui: MicroUi = undefined;
    ui.init(&font, null);

    try ui.beginFrame(.{});
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
pub const PoolItem = struct { id: Id, last_update: i32 };

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
};

pub const Font = struct {
    text_height: i32,
    text_width: fn (ptr: *anyopaque, str: []const u8) i32,
    ptr: *anyopaque,

    pub fn measure(self: *const Font, text: []const u8) i32 {
        return self.text_width(self.ptr, text);
    }
};

pub const Result = packed struct {
    active: bool = false,
    submit: bool = false,
    change: bool = false,
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
};

pub const MouseButtons = packed struct {
    left: bool = false,
    right: bool = false,
    middle: bool = false,
};

pub const Keys = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    backspace: bool = false,
    enter: bool = false,
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

pub const Input = struct {
    mouse_pos: Vec2 = .{},
    scroll_delta: Vec2 = .{},
    mouse_down: MouseButtons = .{},
    mouse_pressed: MouseButtons = .{},
    key_down: Keys = .{},
    key_pressed: Keys = .{},
    input_text: [32]u8 = [_]u8{0} ** 32,

    pub fn clear(self: *Input) void {
        self.key_pressed = .{};
        self.mouse_pressed = .{};
        self.scroll_delta = .{};
        self.input_text[0] = 0;
    }
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
        updated_focus: i32,
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
        container_pool: [config.container_pool_size]PoolItem,
        treenode_pool: [config.treenode_pool_size]PoolItem,

        // input state
        last_input: Input,
        mouse_delta: Vec2 = .{},

        // TODO (Matteo): Review - used to intercept missing calls to the init functions
        init_code: u16,

        //=== Initialization ===//

        pub fn init(self: *Self, font: *const Font, draw_frame: ?DrawFrameFn) void {
            self.init_code = 0x1DEA;
            self._style.font = font;
            self.style = &self._style;
            self.draw_frame = if (draw_frame) |ptr|
                ptr
            else
                @ptrCast(DrawFrameFn, drawDefaultFrame);
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

        pub fn beginFrame(self: *Self, input: *Input) !void {
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
        }

        //=== ID management ===//

        pub fn getId(self: *Self, data: []const u8) Id {
            const init_id = if (self.id_stack.peek()) |id| id.* orelse HASH_INITIAL;
            self.last_id = hash(data, init_id);
            return self.last_id;
        }

        pub fn pushId(self: *Self, data: []const u8) void {
            self.id_stack.push(self.getId(data));
        }

        pub fn popId(self: *Self) void {
            _ = self.id_stack.pop();
        }

        //=== Window management ===//

        //=== Widgets ===//

        //=== Text ===//

        //=== Drawing ===//

        // TODO (Matteo): move the drawing functions on the command list directly?
        // Can help a bit with code organization, since it is the only state touched.

        fn drawRect(self: *Self, rect: Rect, color: Color) void {
            _ = self;
            _ = rect;
            _ = color;
        }

        fn drawBox(self: *Self, rect: Rect, color: Color) void {
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

        inline fn pushCommand(self: *Self, id: CommandId, size: usize) *Command {
            return self.command_list.push(id, size);
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
            std.debug.assert(self.idx < self.items.len);
            self.items[self.idx] = item;
            self.idx += 1;
        }

        fn pop(self: *Self) T {
            std.debug.assert(self.idx > 0);
            self.idx -= 1;
            return self.items[self.idx];
        }

        fn peek(self: *const Self) ?*T {
            return if (self.idx == 0) null else self.items[self.idx - 1];
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
            std.debug.assert(size < self.buffer.len);
            std.debug.assert(self.pos < self.buffer.len - size);

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

