//
// MicroUI - Zig version
//
// Based on  https://github.com/rxi/microui - see end of file for license information
//
// This files contains the main library API
//

const std = @import("std");
const util = @import("util.zig");

const assert = std.debug.assert;

test "MicroUi" {
    std.testing.refAllDecls(@This());

    const MicroUi = Context(.{});

    var font: Font = undefined;
    var ui: MicroUi = undefined;
    var input = ui.init(&font, null);

    try ui.beginFrame(&input);
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

pub const CommandType = enum(u32) {
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

pub const Font = struct {
    text_height: i32,
    text_width: *const fn (ptr: ?*anyopaque, str: []const u8) i32,
    ptr: ?*anyopaque = null,

    pub fn measure(self: *const Font, text: []const u8) i32 {
        return self.text_width(self.ptr, text);
    }
};

pub const Result = packed struct {
    active: bool = false,
    submit: bool = false,
    change: bool = false,

    pub usingnamespace util.BitSet(Result, u3);
};

pub const OptionFlags = packed struct {
    align_center: bool = false,
    align_right: bool = false,
    interact: bool = true,
    frame: bool = true,
    resize: bool = true,
    scroll: bool = true,
    close_button: bool = true,
    title: bool = true,
    hold_focus: bool = false,
    auto_size: bool = false,
    popup: bool = false,
    closed: bool = false,
    expanded: bool = false,

    pub usingnamespace util.BitSet(OptionFlags, u12);
};

pub const MouseButtons = packed struct {
    left: bool = false,
    right: bool = false,
    middle: bool = false,

    pub usingnamespace util.BitSet(MouseButtons, u3);
};

pub const Keys = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    backspace: bool = false,
    enter: bool = false,

    pub usingnamespace util.BitSet(Keys, u5);
};

pub const ControlState = packed struct {
    hovered: bool = false,
    focused: bool = false,

    pub usingnamespace util.BitSet(ControlState, u2);
};

// TODO (Matteo): Rethink command implementation.
// The current solution works pretty well in C but seems a bit foreign in Zig;
// furthermore, I'd like to provide easy extension with user-defined commands.

pub const BaseCommand = extern struct { type: CommandType, size: usize };
pub const JumpCommand = extern struct { base: BaseCommand, dst: usize };
pub const ClipCommand = extern struct { base: BaseCommand, rect: Rect };
pub const RectCommand = extern struct { base: BaseCommand, rect: Rect, color: Color };
pub const IconCommand = extern struct { base: BaseCommand, rect: Rect, id: Icon, color: Color };

pub const TextCommand = extern struct {
    base: BaseCommand,
    font: *const Font,
    pos: Vec2,
    color: Color,
    len: usize,

    pub fn read(cmd: *const TextCommand) []const u8 {
        const pos = @ptrToInt(cmd) + @sizeOf(TextCommand);
        const ptr = @intToPtr([*]const u8, pos);
        return ptr[0..cmd.len];
    }
};

pub const Command = extern union {
    type: CommandType,
    base: BaseCommand,
    jump: JumpCommand,
    clip: ClipCommand,
    rect: RectCommand,
    text: TextCommand,
    icon: IconCommand,
};

pub const Container = struct {
    head: usize = 0,
    tail: usize = 0,
    rect: Rect = .{},
    body: Rect = .{},
    content_size: Vec2 = .{},
    scroll: Vec2 = .{},
    zindex: i32 = 0,
    open: bool = false,
};

pub const Style = struct {
    font: *Font,
    size: Vec2 = .{ .x = 68, .y = 10 },
    padding: i32 = 5,
    spacing: i32 = 4,
    indent: i32 = 24,
    title_height: i32 = 24,
    scrollbar_size: i32 = 12,
    thumb_size: i32 = 8,
    // TODO (Matteo): populate
    colors: [util.memberCount(ColorId)]Color = [_]Color{
        .{ .r = 230, .g = 230, .b = 230, .a = 255 }, // Text
        .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // Border
        .{ .r = 50, .g = 50, .b = 50, .a = 255 }, // WindowBg
        .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // TitleBg
        .{ .r = 240, .g = 240, .b = 240, .a = 255 }, // TitleText
        .{ .r = 0, .g = 0, .b = 0, .a = 0 }, // PanelBg
        .{ .r = 75, .g = 75, .b = 75, .a = 255 }, // Button
        .{ .r = 95, .g = 95, .b = 95, .a = 255 }, // ButtonHover
        .{ .r = 115, .g = 115, .b = 115, .a = 255 }, // ButtonFocus
        .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // Base
        .{ .r = 35, .g = 35, .b = 35, .a = 255 }, // BaseHover
        .{ .r = 40, .g = 40, .b = 40, .a = 255 }, // BaseFocus
        .{ .r = 43, .g = 43, .b = 43, .a = 255 }, // ScrollBase
        .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // ScrollThumb
    },
};

pub fn Context(comptime config: Config) type {
    return struct {
        //=== Inner types ===//

        // NOTE (Matteo): Declare here because are configurable

        pub const Real = config.real;

        pub const DrawFrameFn = *const fn (self: *Self, rect: Rect, color: ColorId) void;

        pub const Input = struct {
            mouse_pos: Vec2 = .{},
            scroll_delta: Vec2 = .{},
            mouse_down: MouseButtons = .{},
            mouse_pressed: MouseButtons = .{},
            key_down: Keys = .{},
            key_pressed: Keys = .{},
            text_buf: [config.input_buf_size]u8 = [_]u8{0} ** config.input_buf_size,
            text_len: usize = 0,

            pub fn clear(self: *Input) void {
                self.key_pressed = .{};
                self.mouse_pressed = .{};
                self.scroll_delta = .{};
                self.text_len = 0;
            }

            pub inline fn mouseMove(self: *Input, x: i32, y: i32) void {
                self.mouse_pos = .{ .x = x, .y = y };
            }

            pub fn mouseDown(self: *Input, x: i32, y: i32, btn: MouseButtons) void {
                if (btn.any()) {
                    self.mouseMove(x, y);
                    self.mouse_down = self.mouse_down.unionWith(btn);
                    self.mouse_pressed = self.mouse_pressed.unionWith(btn);
                }
            }

            pub fn mouseUp(self: *Input, x: i32, y: i32, btn: MouseButtons) void {
                if (btn.any()) {
                    self.mouseMove(x, y);
                    self.mouse_down = self.mouse_down.exceptWith(btn);
                }
            }

            pub inline fn scroll(self: *Input, x: i32, y: i32) void {
                self.scroll_delta.x += x;
                self.scroll_delta.y += y;
            }

            pub fn keyDown(self: *Input, key: Keys) void {
                self.key_down = self.key_down.unionWith(key);
                self.key_pressed = self.key_pressed.unionWith(key);
            }

            pub fn keyUp(self: *Input, key: Keys) void {
                self.key_down = self.key_down.exceptWith(key);
            }

            pub fn text(self: *Input, str: []const u8) void {
                std.mem.copy(u8, self.text_buf[self.text_len..], str);
            }

            pub fn textZ(self: *Input, str: [*:0]const u8) void {
                const len = std.mem.len(str);
                std.mem.copy(u8, self.text_buf[self.text_len..], str[0..len]);
            }
        };

        const LayoutType = enum(u2) { None = 0, Relative = 1, Absolute = 2 };

        const Layout = struct {
            body: Rect = .{},
            next: Rect = .{},
            position: Vec2 = .{},
            size: Vec2 = .{},
            max: Vec2 = .{},
            widths: [config.max_widths]i32 = [_]i32{0} ** config.max_widths,
            items: usize = 0,
            item_index: usize = 0,
            next_row: i32 = 0,
            next_type: LayoutType = .None,
            indent: i32 = 0,
        };

        const Self = @This();

        //=== Data ===//

        // callbacks
        // TODO (Matteo): Improve custom drawing of window frames
        draw_frame: DrawFrameFn = &drawDefaultFrame,

        // core state
        _style: Style,
        style: *Style = undefined,
        hover: Id = 0,
        focus: Id = 0,
        last_id: Id = 0,
        last_rect: Rect = .{},
        last_zindex: i32 = 0,
        updated_focus: bool = false,
        frame: u32 = 0,
        hover_root: ?*Container = null,
        next_hover_root: ?*Container = null,
        scroll_target: ?*Container = null,
        number_edit_buf: [config.max_fmt]u8 = undefined,
        number_edit: Id = 0,

        // stacks
        command_list: util.CommandList(config.command_list_size) = .{},
        root_list: util.Stack(*Container, config.rootlist_size) = .{},
        container_stack: util.Stack(*Container, config.container_stack_size) = .{},
        clip_stack: util.Stack(Rect, config.clip_stack_size) = .{},
        id_stack: util.Stack(Id, config.id_stack_size) = .{},
        layout_stack: util.Stack(Layout, config.layout_stack_size) = .{},

        // retained state pools
        containers: [config.container_pool_size]Container = undefined,
        container_pool: util.Pool(config.container_pool_size) = .{},
        treenode_pool: util.Pool(config.treenode_pool_size) = .{},

        // input state
        last_input: Input = .{},
        mouse_delta: Vec2 = .{},

        // TODO (Matteo): Review - used to intercept missing calls to 'init'
        init_code: u16,

        //=== Initialization ===//

        pub fn init(self: *Self, font: *Font, draw_frame: ?DrawFrameFn) Input {
            // TODO (Matteo): Review
            // This init function is basically only required for making sure
            // that the 'style' pointer points to the internal '_style' member
            self.* = Self{
                ._style = Style{ .font = font },
                .init_code = 0x1DEA,
            };

            self.style = &self._style;

            if (draw_frame) |ptr| self.draw_frame = ptr;

            return .{};
        }

        //=== Frame management ===//

        pub fn beginFrame(self: *Self, input: *Input) !void {
            if (self.init_code != 0x1DEA) return error.NotInitialized;

            // Check stacks
            assert(self.container_stack.idx == 0);
            assert(self.clip_stack.idx == 0);
            assert(self.id_stack.idx == 0);
            assert(self.layout_stack.idx == 0);

            self.command_list.clear();
            self.root_list.clear();

            self.scroll_target = null;
            self.hover_root = self.next_hover_root;
            self.next_hover_root = null;

            self.mouse_delta = input.mouse_pos.sub(self.last_input.mouse_pos);
            self.last_input = input.*;
            input.clear();

            self.frame +%= 1; // wrapping increment, overflow is somewhat expected
        }

        pub fn endFrame(self: *Self) void {
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
            self.last_input.clear();

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
            for (self.root_list.items[0..n]) |cnt, i| {
                // If this is the first container then make the first command jump to it.
                // Otherwise set the previous container's tail to jump to this one
                var cmd = if (i == 0)
                    self.command_list.get(0)
                else
                    self.command_list.get(self.root_list.items[i - 1].tail);

                cmd.jump.dst = cnt.head + @sizeOf(JumpCommand);

                // Make the last container's tail jump to the end of command list
                if (i == n - 1) {
                    self.command_list.get(cnt.tail).jump.dst = self.command_list.tail;
                }
            }
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

        pub fn getContainer(self: *Self, name: []const u8) *Container {
            const id = self.getId(name);
            return self.getContainerById(id, .{}) orelse unreachable;
        }

        pub fn bringToFront(self: *Self, cnt: *Container) void {
            self.last_zindex += 1;
            cnt.zindex = self.last_zindex;
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
            cnt.* = Container{ .open = true };
            self.bringToFront(cnt);
            return cnt;
        }

        fn popContainer(self: *Self) void {
            const layout = self.peekLayout();
            var cnt = self.getCurrentContainer();

            cnt.content_size = layout.max.sub(layout.body.pt);

            _ = self.container_stack.pop();
            _ = self.layout_stack.pop();
            self.popId();
        }

        fn pushContainerBody(self: *Self, cnt: *Container, body: Rect, opt: OptionFlags) void {
            cnt.body = body;
            if (opt.scroll) self.scrollbars(cnt, &cnt.body);
            self.pushLayout(body.expand(-self.style.padding), cnt.scroll);
        }

        fn beginRootContainer(self: *Self, cnt: *Container) void {
            self.container_stack.push(cnt);
            self.root_list.push(cnt);
            // Push head command
            cnt.head = self.command_list.pushJump();
            // Set as hover root if the mouse is overlapping this container and it has a
            // higher zindex than the current hover root
            if (cnt.rect.overlaps(self.last_input.mouse_pos) and
                (self.next_hover_root == null or cnt.zindex > self.next_hover_root.?.zindex))
            {
                self.next_hover_root = cnt;
            }
            // Clipping is reset here in case a root-container is made within
            // another root-containers's begin/end block; this prevents the inner
            // root-container being clipped to the outer
            self.clip_stack.push(unclipped_rect);
        }

        fn endRootContainer(self: *Self) void {
            var cnt = self.getCurrentContainer();
            // Push tail 'goto' jump command and set head 'skip' command. the final steps
            // on initing these are done in 'endFrame'
            cnt.tail = self.command_list.pushJump();
            self.command_list.get(cnt.head).jump.dst = self.command_list.tail;
            // Pop base clip rect and container
            self.popClipRect();
            self.popContainer();
        }

        fn scrollbars(self: *Self, cnt: *Container, body: *Rect) void {
            _ = self;
            _ = cnt;
            _ = body;
            // @compileError("Not implemented");
        }

        //=== Layout management ===//

        pub fn layoutBeginColumn(self: *Self) void {
            self.pushLayout(self.layoutNext(), .{});
        }

        pub fn layoutEndColumn(self: *Self) void {
            const src = self.layout_stack.pop();
            var dst = self.peekLayout();

            // Inherit position/next_row/max from child layout if they are greater
            const dpos = src.body.pt.sub(dst.body.pt);

            dst.position.x = std.math.max(dst.position.x, src.position.x + dpos.x);
            dst.next_row = std.math.max(dst.next_row, src.next_row + dpos.y);
            dst.max.x = std.math.max(dst.max.x, src.max.x);
            dst.max.y = std.math.max(dst.max.y, src.max.y);
        }

        pub fn layoutRow(self: *Self, widths: anytype, height: i32) void {
            var layout = self.peekLayout();

            assert(widths.len <= layout.widths.len);

            comptime var items: usize = 0;
            inline while (items < widths.len) : (items += 1) {
                layout.widths[items] = widths[items];
            }

            layout.position = Vec2{ .x = layout.indent, .y = layout.next_row };
            layout.size.y = height;
            layout.items = items;
            layout.item_index = 0;
        }

        pub fn layoutWidth(self: *Self, width: i32) void {
            self.peekLayout().size.x = width;
        }

        pub fn layoutHeight(self: *Self, height: i32) void {
            self.peekLayout().size.y = height;
        }

        pub fn layoutSetNext(self: *Self, r: Rect, relative: bool) void {
            var layout = self.peekLayout();
            layout.next = r;
            layout.next_type = if (relative) .Relative else .Absolute;
        }

        pub fn layoutNext(self: *Self) Rect {
            var res: Rect = undefined;
            var layout = self.peekLayout();
            const style = self.style;
            const next_type = layout.next_type;

            if (next_type != .None) {
                // Handle rect set by `layoutSetNext'
                layout.next_type = .None;
                res = layout.next;
            } else {
                // Handle next row
                if (layout.item_index == layout.items) {
                    // NOTE (Matteo): Repositioning on the next row - original
                    // call was mu_layout_row(ctx, layout->items, NULL, layout->size.y)
                    layout.position = Vec2{ .x = layout.indent, .y = layout.next_row };
                    layout.item_index = 0;
                }

                // Position
                res.pt = layout.position;

                // Size
                res.sz = layout.size;

                if (layout.items > 0) res.sz.x = layout.widths[layout.item_index];

                if (res.sz.x == 0) res.sz.x = style.size.x + 2 * style.padding;
                if (res.sz.y == 0) res.sz.y = style.size.y + 2 * style.padding;

                if (res.sz.x < 0) res.sz.x += layout.body.sz.x - res.pt.x + 1;
                if (res.sz.y < 0) res.sz.y += layout.body.sz.y - res.pt.y + 1;

                // Advance
                layout.item_index += 1;
            }

            if (next_type != .Absolute) {
                // Update position
                layout.position.x += res.sz.x + style.spacing;
                layout.next_row = std.math.max(layout.next_row, res.pt.y + res.sz.y + style.spacing);

                // Apply body offset
                res.pt = res.pt.add(layout.body.pt);

                // Update max position
                layout.max.x = std.math.max(layout.max.x, res.pt.x + res.sz.x);
                layout.max.y = std.math.max(layout.max.y, res.pt.y + res.sz.y);
            }

            self.last_rect = res;
            return res;
        }

        fn pushLayout(self: *Self, body: Rect, scroll: Vec2) void {
            const min = std.math.minInt(i32);
            comptime assert(min < 0);

            self.layout_stack.push(Layout{
                .body = Rect{ .pt = body.pt.sub(scroll), .sz = body.sz },
                .max = Vec2{ .x = min, .y = min },
            });

            self.layoutRow(.{0}, 0);
        }

        fn peekLayout(self: *Self) *Layout {
            return self.layout_stack.peek() orelse unreachable;
        }

        //=== Clipping ===//

        pub fn pushClipRect(self: *Self, rect: Rect) void {
            const last = self.peekClipRect();
            self.clip_stack.push(last.intersect(rect));
        }

        pub fn popClipRect(self: *Self) void {
            _ = self.clip_stack.pop();
        }

        pub fn peekClipRect(self: *Self) *const Rect {
            return self.clip_stack.peek() orelse unreachable;
        }

        pub fn checkClip(self: *Self, r: Rect) Clip {
            const c = self.peekClipRect();

            const rx1 = r.pt.x + r.sz.x;
            const ry1 = r.pt.y + r.sz.y;

            const cx1 = c.pt.x + c.sz.x;
            const cy1 = c.pt.y + c.sz.y;

            if (r.pt.x > cx1 or rx1 < c.pt.x or
                r.pt.y > cy1 or ry1 < c.pt.y)
            {
                return .All;
            }

            if (r.pt.x >= c.pt.x and rx1 <= cx1 and
                r.pt.y >= c.pt.y and ry1 <= cy1)
            {
                return .None;
            }

            return .Part;
        }

        //=== Controls ===//

        // TODO (Matteo): Maybe rename
        pub fn updateControl(
            self: *Self,
            id: Id,
            rect: Rect,
            opts: OptionFlags,
        ) ControlState {
            const mouse_over = self.mouseOver(rect);
            const mouse_down = self.last_input.mouse_down.any();
            const mouse_pressed = self.last_input.mouse_pressed.any();

            // TODO (Matteo): Tidy up the logic here

            var state = ControlState{
                .focused = (self.focus == id),
                .hovered = (self.hover == id),
            };

            if (state.focused) self.updated_focus = true;

            if (opts.interact) {
                if (mouse_over and !mouse_down) {
                    self.hover = id;
                    state.hovered = true;
                }

                if (state.focused) {
                    if ((mouse_pressed and !mouse_over) or
                        (!mouse_down and !opts.hold_focus))
                    {
                        self.setFocus(0);
                        state.focused = false;
                    }
                }

                if (state.hovered) {
                    if (mouse_pressed) {
                        self.setFocus(id);
                        state.focused = true;
                    } else if (!mouse_over) {
                        self.hover = 0;
                        state.hovered = false;
                    }
                }
            }

            return state;
        }

        pub fn mouseOver(self: *Self, rect: Rect) bool {
            const mouse = self.last_input.mouse_pos;
            return rect.overlaps(mouse) and
                self.peekClipRect().overlaps(mouse) and
                self.inHoverRoot();
        }

        fn inHoverRoot(self: *Self) bool {
            var i = self.container_stack.idx;

            while (i > 0) {
                i -= 1;
                if (self.container_stack.items[i] == self.hover_root) return true;
                // Only root containers have their `head` field set; stop searching
                // if we've reached the current root container
                if (self.container_stack.items[i].head != 0) break;
            }

            return false;
        }

        pub fn text(self: *Self, str: []const u8) void {
            // TODO (Matteo): Proper shaping
            const rect = self.layoutNext();
            const color = self.getColor(.Text);
            self.drawText(self.style.font, str, rect.pt, color);
        }

        pub fn label(self: *Self, str: []const u8) void {
            self.drawControlText(str, self.layoutNext(), .Text, .{});
        }

        pub inline fn button(self: *Self, id: []const u8) Result {
            return self.buttonEx(id, .None, .{ .align_center = true });
        }

        pub fn buttonEx(
            self: *Self,
            id_str: []const u8,
            icon: Icon,
            opts: OptionFlags,
        ) Result {
            const id = if (id_str.len > 0)
                self.getId(id_str)
            else
                self.getId(std.mem.asBytes(&icon));

            const rect = self.layoutNext();
            const state = self.updateControl(id, rect, opts);

            // Draw
            self.drawButton(state, rect, opts);

            // Handle click
            return Result{
                .submit = (state.focused and self.last_input.mouse_pressed.left),
            };
        }

        pub fn checkbox(self: *Self, id: []const u8, state: *bool) Result {
            _ = self;
            _ = id;
            _ = state;
            return Result{};
        }

        pub fn textbox(self: *Self, buf: []u8, opts: OptionFlags) Result {
            return self.textboxRaw(buf, self.getId(buf), self.layoutNext(), opts);
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
            return Result{};
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
            return Result{};
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
            comptime fmt: []const u8,
            opts: OptionFlags,
        ) Result {
            const id = self.getId(std.mem.asBytes(&value));
            const base = self.layoutNext();
            const last = value.*;

            // Handle text input mode
            if (self.numberTextbox(value, base, id)) return Result{};

            // Handle normal mode
            const state = self.updateControl(id, base, opts);

            // Handle input
            if (state.focused and self.mouse_down.left) {
                value.* += self.mouse_delta.x * step;
            }

            // Draw base
            self.drawBase(state, base, opts);

            // Draw text
            var buf: [config.max_fmt + 1]u8 = undefined;
            self.drawControlText(
                std.fmt.bufPrint(buf, fmt, .{value.*}) catch unreachable,
                base,
                .Text,
                opts,
            );

            // Set flag if value changed
            return Result{ .change = (value.* != last) };
        }

        fn numberTextbox(
            self: *Self,
            value: *Real,
            r: Rect,
            id: Id,
        ) bool {
            _ = self;
            _ = value;
            _ = r;
            _ = id;
            return false;
        }

        pub fn header(self: *Self, id: []const u8, opts: OptionFlags) Result {
            return self.headerInternal(id, false, opts);
        }

        pub fn beginTreeNode(self: *Self, id: []const u8, opts: OptionFlags) Result {
            const res = self.headerInternal(id, true, opts);
            if (res.active) {
                self.peekLayout().indent += self.style.indent;
                self.id_stack.push(self.last_id);
            }
            return res;
        }

        pub fn endTreeNode(self: *Self) void {
            self.peekLayout().indent -= self.style.indent;
            self.popId();
        }

        fn headerInternal(
            self: *Self,
            id_str: []const u8,
            is_treenode: bool,
            opts: OptionFlags,
        ) Result {
            const id = self.getId(id_str);
            const pool_index = self.treenode_pool.get(id);
            const was_active = (pool_index != null);
            const expanded = opts.expanded != was_active; // opts.expanded XOR was_active
            var r = self.layoutNext();

            // Handle click
            const state = self.updateControl(id, r, .{});
            const clicked = (self.last_input.mouse_pressed.left and state.focused);
            const is_active = (was_active != clicked);

            // Update pool ref
            if (pool_index) |index| {
                if (is_active) {
                    self.treenode_pool.update(index, self.frame);
                } else { // TODO (Matteo): Better clearing
                    self.treenode_pool.items[index] = .{};
                }
            } else if (is_active) {
                _ = self.treenode_pool.init(id, self.frame);
            }

            // Draw
            if (is_treenode) {
                if (state.hovered) self.drawFrame(r, .ButtonHover);
            } else {
                self.drawButton(state, r, .{});
            }

            self.drawIcon(
                if (expanded) .Expanded else .Collapsed,
                Rect.init(r.pt.x, r.pt.y, r.sz.y, r.sz.y),
                self.getColor(.Text),
            );

            r.pt.x += r.sz.y - self.style.padding;
            r.pt.y -= r.sz.y - self.style.padding;

            self.drawControlText(id_str, r, .Text, .{});

            return Result{ .active = expanded };
        }

        pub fn beginWindow(
            self: *Self,
            title: []const u8,
            init_rect: Rect,
            opts: OptionFlags,
        ) Result {
            const id = self.getId(title);
            var cnt = self.getContainerById(id, opts) orelse return Result{};
            if (!cnt.open) return Result{};

            // Pushing explicitly because the function can return early
            self.id_stack.push(id);

            if (cnt.rect.sz.x == 0) cnt.rect = init_rect;
            self.beginRootContainer(cnt);

            // Draw frame
            if (opts.frame) self.drawFrame(cnt.rect, .WindowBg);

            const title_h = self.style.title_height;
            var body = cnt.rect;

            // Do title bar
            if (opts.title) {
                const title_rect = Rect{
                    .pt = cnt.rect.pt,
                    .sz = Vec2{ .x = cnt.rect.sz.x, .y = title_h },
                };

                self.drawFrame(title_rect, .TitleBg);

                // Title text
                const title_state = self.updateControl(self.getId("!title"), title_rect, opts);
                self.drawControlText(title, title_rect, .TitleText, opts);
                if (title_state.focused and self.last_input.mouse_down.left) {
                    cnt.rect.pt = cnt.rect.pt.add(self.mouse_delta);
                }

                // Close button
                if (opts.close_button) {
                    const rect = Rect.init(
                        title_rect.pt.x + title_rect.sz.x - title_h,
                        title_rect.pt.y,
                        title_h,
                        title_h,
                    );
                    const state = self.updateControl(self.getId("!close"), rect, opts);
                    if (state.focused and self.last_input.mouse_pressed.left) {
                        cnt.open = false;
                    }
                    self.drawIcon(.Close, rect, self.getColor(.TitleText));
                }

                // Remove title from body
                body.pt.y += title_h;
                body.sz.y -= title_h;
            }

            self.pushContainerBody(cnt, body, opts);

            // Do resize handle
            if (opts.resize) {
                const rect = Rect.init(
                    cnt.rect.pt.x + cnt.rect.sz.x - title_h,
                    cnt.rect.pt.y + cnt.rect.sz.y - title_h,
                    title_h,
                    title_h,
                );
                const state = self.updateControl(self.getId("!resize"), rect, opts);
                if (state.focused and self.last_input.mouse_down.left) {
                    const next_size = cnt.rect.sz.sub(self.mouse_delta);
                    cnt.rect.sz.x = std.math.max(96, next_size.x);
                    cnt.rect.sz.y = std.math.max(64, next_size.y);
                }
            }

            // Resize to content size
            if (opts.auto_size) {
                const layout = self.peekLayout().body;
                cnt.rect.sz = cnt.content_size.add(cnt.rect.sz.sub(layout.sz));
            }

            // Close if this is a popup window and elsewhere was clicked
            if (opts.popup and self.last_input.mouse_pressed.any() and self.hover_root != cnt) {
                cnt.open = false;
            }

            self.pushClipRect(cnt.body);
            return Result{ .active = true };
        }

        pub fn endWindow(self: *Self) void {
            self.popClipRect();
            self.endRootContainer();
        }

        pub fn openPopup(self: *Self, name: []const u8) void {
            var cnt = self.getContainer(name);
            // Set as hover root so popup isn't closed in 'beginWindow'
            self.next_hover_root = cnt;
            self.hover_root = self.next_hover_root;
            // position at mouse cursor, open and bring-to-front
            cnt.rect = Rect{ .pt = self.last_input.mouse_pos, .sz = Vec2{ .x = 1, .y = 1 } };
            cnt.open = true;
            self.bringToFront(cnt);
        }

        pub fn beginPopup(self: *Self, name: []const u8) Result {
            return self.beginWindow(name, .{}, .{
                .popup = true,
                .auto_size = true,
                .resize = false,
                .scroll = false,
                .title = false,
                .closed = true,
            });
        }

        pub fn endPopup(self: *Self) void {
            self.endWindow();
        }

        pub fn beginPanel(self: *Self, name: []const u8, opts: OptionFlags) void {
            self.pushId(name);
            var cnt = self.getContainerById(self.last_id, opts) orelse unreachable;
            cnt.rect = self.layoutNext();

            if (opts.frame) self.drawFrame(cnt.rect, .PanelBg);

            self.container_stack.push(cnt);
            self.pushContainerBody(cnt, cnt.rect, opts);
            self.pushClipRect(cnt.body);
        }

        pub fn endPanel(self: *Self) void {
            self.popClipRect();
            self.popContainer();
        }

        //=== Drawing ===//

        pub fn drawButton(
            self: *Self,
            state: ControlState,
            rect: Rect,
            opts: OptionFlags,
        ) void {
            if (opts.frame) {
                self.drawFrame(
                    rect,
                    if (state.focused)
                        .ButtonFocus
                    else if (state.hovered)
                        .ButtonHover
                    else
                        .Button,
                );
            }
        }

        pub fn drawBase(
            self: *Self,
            state: ControlState,
            rect: Rect,
            opts: OptionFlags,
        ) void {
            if (opts.frame) {
                self.drawFrame(
                    rect,
                    if (state.focused)
                        .BaseFocus
                    else if (state.hovered)
                        .BaseHover
                    else
                        .Base,
                );
            }
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
            // @compileError("Not implemented");
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

        // TODO (Matteo): move the drawing functions on the command list directly?
        // Can help a bit with code organization, since it is the only state touched.

        pub fn drawRect(self: *Self, rect: Rect, color: Color) void {
            const clipped = self.peekClipRect().intersect(rect);

            if (clipped.sz.x > 0 and clipped.sz.y > 0) {
                self.command_list.pushRect(rect, color);
            }
        }

        pub fn drawBox(self: *Self, rect: Rect, color: Color) void {
            self.drawRect(Rect.init(
                rect.pt.x + 1,
                rect.pt.y,
                rect.sz.x - 2,
                1,
            ), color);
            self.drawRect(Rect.init(
                rect.pt.x + 1,
                rect.pt.y + rect.sz.y - 1,
                rect.sz.x - 2,
                1,
            ), color);
            self.drawRect(Rect.init(
                rect.pt.x,
                rect.pt.y,
                1,
                rect.sz.y,
            ), color);
            self.drawRect(Rect.init(
                rect.pt.x + rect.sz.x - 1,
                rect.pt.y,
                1,
                rect.sz.y,
            ), color);
        }

        pub fn drawText(
            self: *Self,
            font: *Font,
            str: []const u8,
            pos: Vec2,
            color: Color,
        ) void {
            // Measure and clip
            const size = Vec2{ .x = font.measure(str), .y = font.text_height };
            const rect = Rect{ .pt = pos, .sz = size };
            const clip = self.checkClip(rect);
            switch (clip) {
                .All => return,
                .Part => self.command_list.pushClip(self.peekClipRect().*),
                else => {},
            }
            // Add command
            self.command_list.pushText(str, pos, color, font);
            // Reset clipping if set
            if (clip != .None) self.command_list.pushClip(unclipped_rect);
        }

        pub fn drawIcon(self: *Self, id: Icon, rect: Rect, color: Color) void {
            // Measure and clip
            const clip = self.checkClip(rect);
            switch (clip) {
                .All => return,
                .Part => self.command_list.pushClip(self.peekClipRect().*),
                else => {},
            }
            // Add command
            self.command_list.pushIcon(id, rect, color);
            // Reset clipping if set
            if (clip != .None) self.command_list.pushClip(unclipped_rect);
        }

        //=== Internals ===//

        inline fn getColor(self: *const Self, id: ColorId) Color {
            // NOTE (Matteo): Helper to avoid casting the id everywhere - ugly?
            return self.style.colors[@enumToInt(id)];
        }
    };
}

//========================//
//  Geometric primitives  //
//========================//

pub const Vec2 = extern struct {
    x: i32 = 0,
    y: i32 = 0,

    pub inline fn add(l: Vec2, r: Vec2) Vec2 {
        return Vec2{ .x = l.x + r.x, .y = l.y + r.y };
    }

    pub inline fn sub(l: Vec2, r: Vec2) Vec2 {
        return Vec2{ .x = l.x - r.x, .y = l.y - r.y };
    }

    pub inline fn negate(v: Vec2) Vec2 {
        return Vec2{ .x = -v.x, .y = -v.y };
    }

    pub inline fn eq(l: Vec2, r: Vec2) bool {
        return (l.x == r.x and l.y == r.y);
    }
};

pub const Rect = extern struct {
    pt: Vec2 = .{},
    sz: Vec2 = .{},

    pub fn init(x: i32, y: i32, w: i32, h: i32) Rect {
        return Rect{
            .pt = Vec2{ .x = x, .y = y },
            .sz = Vec2{ .x = w, .y = h },
        };
    }

    pub fn expand(rect: Rect, n: i32) Rect {
        return Rect{
            .pt = Vec2{ .x = rect.pt.x - n, .y = rect.pt.y - n },
            .sz = Vec2{ .x = rect.sz.x + 2 * n, .y = rect.sz.y + 2 * n },
        };
    }

    pub fn intersect(ls: Rect, rs: Rect) Rect {
        const min = Vec2{
            .x = std.math.max(ls.pt.x, rs.pt.x),
            .y = std.math.max(ls.pt.y, rs.pt.y),
        };

        const max = Vec2{
            .x = std.math.max(min.x, std.math.min(ls.pt.x + ls.sz.x, rs.pt.x + rs.sz.x)),
            .y = std.math.max(min.y, std.math.min(ls.pt.y + ls.sz.y, rs.pt.y + rs.sz.y)),
        };

        return Rect{ .pt = min, .sz = max.sub(min) };
    }

    pub fn overlaps(rect: Rect, p: Vec2) bool {
        const max = rect.pt.add(rect.sz);
        return p.x >= rect.pt.x and p.x <= max.x and
            p.y >= rect.pt.y and p.y <= max.y;
    }
};

const unclipped_rect = Rect.init(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));

test "Primitives" {
    const expect = std.testing.expect;

    var c: Rect = undefined;

    const a = Rect.init(0, 0, 2, 3);
    c = a.intersect(unclipped_rect);
    try expect(a.pt.eq(c.pt));
    try expect(a.sz.eq(c.sz));

    const b = Rect.init(1, 1, 3, 3);
    c = a.intersect(b);
    try expect(c.pt.eq(c.pt));
    try expect(c.sz.eq(.{ .x = 1, .y = 2 }));
}

//=====================//
//  32bit fnv-1a hash  //
//=====================//

const HASH_INITIAL: Id = 2166136261;

fn hash(data: []const u8, hash_in: Id) Id {
    var hash_out = hash_in;

    for (data) |byte| {
        hash_out = (hash_out ^ byte) *% 16777619;
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

//
// The MIT License (MIT)
//
// Original work Copyright (c) 2020 rxi
// Modified work Copyright (c) 2022 bassfault
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
