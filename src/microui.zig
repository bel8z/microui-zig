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

test {
    std.testing.refAllDecls(@This());
}

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

pub const Id = u32;

pub const Font = *opaque {};

pub const Vec2 = extern struct { x: i32 = 0, y: i32 = 0 };
pub const Rect = extern struct { x: i32 = 0, y: i32 = 0, w: i32 = 0, h: i32 = 0 };
pub const Color = extern struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 0 };

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

pub const PoolItem = struct { id: Id, last_update: i32 };

pub const BaseCommand = extern struct { type: CommandId, size: usize };
pub const JumpCommand = extern struct { base: BaseCommand, dst: *BaseCommand };
pub const ClipCommand = extern struct { base: BaseCommand, rect: Rect };
pub const RectCommand = extern struct { base: BaseCommand, rect: Rect, color: Color };
pub const TextCommand = extern struct { base: BaseCommand, font: Font, pos: Vec2, color: Color, str: []u8 };
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
    font: Font,
    size: Vec2,
    padding: i32,
    spacing: i32,
    indent: i32,
    title_height: i32,
    scrollbar_size: i32,
    thumb_size: i32,
    colors: [memberCount(ColorId)]Color,
};

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

    return extern struct {
        pub const Real = config.real;

        // callbacks
        //            int (*text_width)(mu_Font font, const char *str, int len);
        //            int (*text_height)(mu_Font font);
        //            void (*draw_frame)(mu_Context *ctx, mu_Rect rect, int colorid);

        // core state
        _style: Style = undefined,
        style: *Style = undefined,
        hover: Id = undefined,
        focus: Id = undefined,
        last_id: Id = undefined,
        last_rect: Rect = undefined,
        last_zindex: i32 = undefined,
        updated_focus: i32 = undefined,
        frame: i32 = undefined,
        hover_root: Container = undefined,
        next_hover_root: Container = undefined,
        scroll_target: Container = undefined,
        number_edit_buf: [config.max_fmt]u8 = undefined,
        number_edit: Id = undefined,

        // stacks
        command_list: Stack(u8, config.command_list_size) = .{},
        root_list: Stack(*Container, config.rootlist_size) = .{},
        container_stack: Stack(*Container, config.container_stack_size) = .{},
        clip_stack: Stack(Rect, config.clip_stack_size) = .{},
        id_stack: Stack(Id, config.id_stack_size) = .{},
        layout_stack: Stack(Layout, config.layout_stack_size) = .{},

        // retained state pools
        containers: [config.container_pool_size]Container = undefined,
        container_pool: [config.container_pool_size]PoolItem = undefined,
        treenode_pool: [config.treenode_pool_size]PoolItem = undefined,

        // input state
        mouse_pos: Vec2 = .{},
        last_mouse_pos: Vec2 = .{},
        mouse_delta: Vec2 = .{},
        scroll_delta: Vec2 = .{},
        mouse_down: i32 = 0,
        mouse_pressed: i32 = 0,
        key_down: i32 = 0,
        key_pressed: i32 = 0,
        input_text: [32]u8 = undefined,

        const Self = @This();

        //=== ID management ===//

        pub fn getId(self: *Self, data: []const u8) Id {
            self.last_id = hash(data, self.id_stack.peek() orelse HASH_INITIAL);
            return self.last_id;
        }

        pub fn pushId(self: *Self, data: []const u8) void {
            self.id_stack.push(self.getId(data));
        }

        pub fn popId(self: *Self) void {
            self.id_stack.pop();
        }

        //=== Internals ===//

    };
}

//============//

fn Stack(comptime T: type, comptime N: usize) type {
    return extern struct {
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

        fn peek(self: *const Self) ?T {
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
