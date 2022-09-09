const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}

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

pub const Id = u32;

pub const Font = *opaque {};

pub const Vec2 = struct { x: i32 = 0, y: i32 = 0 };
pub const Rect = struct { x: i32 = 0, y: i32 = 0, w: i32 = 0, h: i32 = 0 };
pub const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 0 };

pub const PoolItem = struct { id: Id, last_update: i32 };

pub const Layout = struct {};
pub const Container = struct {};
pub const Style = struct {};

pub fn Context(comptime config: Config) type {
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
