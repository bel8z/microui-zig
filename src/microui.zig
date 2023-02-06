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

    var font: Font = undefined;
    var ui: Ui(.{}) = undefined;
    ui.init(&font, null);

    var input = ui.getInput();

    try ui.beginFrame(&input);
    defer ui.endFrame();
}

pub const Id = u32;
pub const command = @import("command.zig");

pub const Clip = enum(u2) {
    None,
    Part,
    All,
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

// TODO (Matteo): Shrink to 16 bits? Demo rendering code depends on 32 at the moment
pub const Icon = enum(u32) {
    None,
    Close,
    Check,
    Collapsed,
    Expanded,
    _,
};

pub const Color = extern struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 0 };

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

pub const Container = struct {
    head: command.CommandHandle = 0,
    tail: command.CommandHandle = 0,
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

/// Compile-time configuration parameters
pub const Config = struct {
    command_list_size: u32 = (256 * 1024),
    rootlist_size: u16 = 32,
    container_stack_size: u16 = 32,
    clip_stack_size: u16 = 32,
    id_stack_size: u16 = 32,
    layout_stack_size: u16 = 16,
    container_pool_size: u16 = 48,
    treenode_pool_size: u16 = 48,
    max_widths: u16 = 16,
    real: type = f32,
    real_fmt: []const u8 = "{d:.3}",
    slider_fmt: []const u8 = "{d:.2}",
    fmt_buf_size: u16 = 127,
    input_buf_size: u32 = 32,
};

pub fn Ui(comptime config: Config) type {
    return struct {
        comptime {
            assert(config.max_widths <= std.math.maxInt(u32));
        }

        //=== Inner types ===//

        // NOTE (Matteo): Declare here because are configurable

        pub const Real = config.real;

        pub const DrawFrameFn = *const fn (self: *Self, rect: Rect, color: ColorId) void;

        const LayoutType = enum(u2) { None = 0, Relative = 1, Absolute = 2 };

        const Layout = struct {
            body: Rect = .{},
            next: Rect = .{},
            position: Vec2 = .{},
            size: Vec2 = .{},
            max: Vec2 = .{},
            widths: [config.max_widths]i32 = [_]i32{0} ** config.max_widths,
            items: u32 = 0,
            item_index: u32 = 0,
            next_row: i32 = 0,
            next_type: LayoutType = .None,
            indent: i32 = 0,
        };

        const Self = @This();

        const scratch_size = config.input_buf_size + config.fmt_buf_size;

        //=== Data ===//

        // callbacks
        // TODO (Matteo): Improve custom drawing of window frames
        draw_frame: DrawFrameFn = &drawDefaultFrame,

        // core state
        _style: Style,
        style: *Style = undefined,
        hover: Id = 0,
        last_focus: Id = 0,
        curr_focus: Id = 0,
        last_id: Id = 0,
        last_rect: Rect = .{},
        last_zindex: i32 = 0,
        frame: u32 = 0,
        hover_root: ?*Container = null,
        next_hover_root: ?*Container = null,
        scroll_target: ?*Container = null,
        num_edit_id: Id = 0,
        num_edit_buf: TextBuffer,

        // stacks
        command_list: command.CommandList(config.command_list_size) = .{},
        root_list: util.Stack(*Container, config.rootlist_size) = .{},
        container_stack: util.Stack(util.PoolSlot, config.container_stack_size) = .{},
        clip_stack: util.Stack(Rect, config.clip_stack_size) = .{},
        id_stack: util.Stack(Id, config.id_stack_size) = .{},
        layout_stack: util.Stack(Layout, config.layout_stack_size) = .{},

        // retained state pools
        containers: [config.container_pool_size]Container = undefined,
        container_pool: util.Pool(config.container_pool_size) = .{},
        treenode_pool: util.Pool(config.treenode_pool_size) = .{},

        // input state
        input: Input = .{ .text_buf = .{} },
        mouse_delta: Vec2 = .{},

        scratch_buf: [scratch_size]u8 = undefined,

        // TODO (Matteo): Review - used to intercept missing calls to 'init'
        init_code: u16,

        //=== Initialization ===//

        pub fn init(self: *Self, font: *Font, draw_frame: ?DrawFrameFn) void {
            // TODO (Matteo): Review
            // This init function is basically only required for making sure
            // that the 'style' pointer points to the internal '_style' member
            self.* = Self{
                ._style = Style{ .font = font },
                .init_code = 0x1DEA,
                .num_edit_buf = TextBuffer.fromSlice(
                    self.scratch_buf[config.input_buf_size..],
                ),
            };

            assert(self.num_edit_buf.cap == config.fmt_buf_size);

            self.style = &self._style;

            if (draw_frame) |ptr| self.draw_frame = ptr;
        }

        //=== Frame management ===//

        pub fn getInput(self: *Self) Input {
            var buf = self.scratch_buf[0..config.input_buf_size];
            std.mem.set(u8, buf, 0);
            return Input.init(buf);
        }

        pub fn beginFrame(self: *Self, input: *Input) !void {
            if (self.init_code != 0x1DEA) return error.NotInitialized;

            // Check stacks
            assert(self.container_stack.isEmpty());
            assert(self.clip_stack.isEmpty());
            assert(self.id_stack.isEmpty());
            assert(self.layout_stack.isEmpty());

            self.command_list.clear();
            self.root_list.clear();

            self.scroll_target = null;
            self.hover_root = self.next_hover_root;
            self.next_hover_root = null;

            self.mouse_delta = input.mouse_pos.sub(self.input.mouse_pos);
            self.input = input.*;
            input.clear();

            self.last_focus = self.curr_focus;
            self.curr_focus = 0;

            self.frame +%= 1; // wrapping increment, overflow is somewhat expected
        }

        pub fn endFrame(self: *Self) void {
            // Check stacks - assertion are fine here since we are checking
            // for internal consistency and not an user error
            assert(self.container_stack.isEmpty());
            assert(self.clip_stack.isEmpty());
            assert(self.id_stack.isEmpty());
            assert(self.layout_stack.isEmpty());

            // Handle scroll target
            if (self.scroll_target) |tgt| {
                tgt.scroll = tgt.scroll.add(self.input.scroll_delta);
            }

            // Bring hover root to front if mouse was pressed
            if (self.next_hover_root) |hover_root| {
                if (self.input.mouse_pressed.any() and
                    hover_root.zindex < self.last_zindex and
                    hover_root.zindex >= 0)
                {
                    self.bringToFront(hover_root);
                }
            }

            // Reset input state
            self.input.clear();

            // Sort root containers by zindex
            const compare = struct {
                fn lessThan(_: void, a: *Container, b: *Container) bool {
                    return a.zindex < b.zindex;
                }
            };

            const n = self.root_list.idx;
            std.sort.sort(*Container, self.root_list.items[0..n], {}, compare.lessThan);

            // TODO (Matteo): Review
            // Set root container jump commands
            for (self.root_list.items[0..n]) |cnt, i| {
                // If this is the first container then make the first command jump to it.
                // Otherwise set the previous container's tail to jump to this one
                var cmd = if (i == 0)
                    self.command_list.get(0)
                else
                    self.command_list.get(self.root_list.items[i - 1].tail);

                cmd.jump.dst = cnt.head + self.command_list.get(cnt.head).base.size;

                // Make the last container's tail jump to the end of command list
                if (i == n - 1) {
                    self.command_list.get(cnt.tail).jump.dst = self.command_list.tail;
                }
            }
        }

        //=== ID management ===//

        pub fn getId(self: *Self, data: anytype) Id {
            const init_id = if (self.id_stack.peek()) |id| id.* else HASH_INITIAL;
            self.last_id = hash(data, init_id);
            return self.last_id;
        }

        pub fn pushId(self: *Self, data: anytype) void {
            self.id_stack.push(self.getId(data)) catch unreachable;
        }

        pub fn popId(self: *Self) void {
            _ = self.id_stack.pop() catch unreachable;
        }

        //=== Container management ===//

        pub fn getCurrentContainer(self: *Self) *Container {
            const slot = self.container_stack.peek() orelse unreachable;
            return &self.containers[slot.*];
        }

        pub fn getContainer(self: *Self, name: []const u8) *Container {
            const id = self.getId(name);
            const slot = self.getContainerById(id, .{}) orelse unreachable;
            return &self.containers[slot];
        }

        pub fn bringToFront(self: *Self, cnt: *Container) void {
            self.last_zindex += 1;
            cnt.zindex = self.last_zindex;
        }

        fn getContainerById(self: *Self, id: Id, opt: OptionFlags) ?util.PoolSlot {
            // Try to get existing container from pool
            if (self.container_pool.getSlot(id)) |index| {
                if (self.containers[index].open or !opt.closed) {
                    // TODO (Matteo): Why update only in this case?
                    self.container_pool.updateSlot(index, self.frame);
                }
                return index;
            }

            if (opt.closed) return null;

            // Container not found in pool, init a new one
            const index = self.container_pool.initSlot(id, self.frame);
            self.containers[index] = Container{ .open = true };
            self.bringToFront(&self.containers[index]);
            return index;
        }

        fn pushContainerBody(self: *Self, cnt: *Container, body: Rect, opt: OptionFlags) !void {
            cnt.body = body;

            if (opt.scroll) {
                var cs = cnt.content_size;
                cs.x += 2 * self.style.padding;
                cs.y += 2 * self.style.padding;

                self.pushClipRect(cnt.body);
                self.scrollbars(cnt, cs);
                self.popClipRect();
            }

            try self.pushLayout(cnt.body.expand(-self.style.padding), cnt.scroll);
        }

        fn scrollbars(self: *Self, cnt: *Container, cs: Vec2) void {
            // TODO (Matteo): Compress code a bit?

            const sz = self.style.scrollbar_size;

            if (cs.y > cnt.body.sz.y) cnt.body.sz.x -= sz;
            if (cs.x > cnt.body.sz.x) cnt.body.sz.y -= sz;

            const max_scroll = cs.sub(cnt.body.sz);
            const body_hover = self.mouseOver(cnt.body);

            // Only add scrollbar if content size is larger than body
            if (max_scroll.y > 0 and cnt.body.sz.y > 0) {
                const id = self.getId("!vscrollbar");

                // Get size and position
                var base = cnt.body;
                base.pt.x = cnt.body.pt.x + cnt.body.sz.x;
                base.sz.x = sz;

                // Handle input
                const state = self.updateControl(id, base, .{});
                if (state.focused and self.input.mouse_down.left) {
                    cnt.scroll.y += @divTrunc(self.mouse_delta.y * cs.y, base.sz.y);
                }

                // Clamp scroll to limits
                cnt.scroll.y = std.math.clamp(cnt.scroll.y, 0, max_scroll.y);

                // Set this as scroll target (respond to mousewheel input) if
                // the body is hovered
                if (body_hover) self.scroll_target = cnt;

                // Draw
                self.drawFrame(base, .ScrollBase);
                var thumb = base;
                thumb.sz.y = std.math.max(self.style.thumb_size, @divTrunc(base.sz.y * cnt.body.sz.y, cs.y));
                thumb.pt.y += @divTrunc(cnt.scroll.y * (base.sz.y - thumb.sz.y), max_scroll.y);
                self.drawFrame(thumb, .ScrollThumb);
            } else {
                cnt.scroll.y = 0;
            }

            // Only add scrollbar if content size is larger than body
            if (max_scroll.x > 0 and cnt.body.sz.x > 0) {
                const id = self.getId("!hscrollbar");

                // Get size and position
                var base = cnt.body;
                base.pt.y = cnt.body.pt.y + cnt.body.sz.y;
                base.sz.y = sz;

                // Handle input
                const state = self.updateControl(id, base, .{});
                if (state.focused and self.input.mouse_down.left) {
                    cnt.scroll.x += @divTrunc(self.mouse_delta.x * cs.x, base.sz.x);
                }

                // Clamp scroll to limits
                cnt.scroll.x = std.math.clamp(cnt.scroll.x, 0, max_scroll.x);

                // Set this as scroll target (respond to mousewheel input) if
                // the body is hovered
                if (body_hover) self.scroll_target = cnt;

                // Draw
                self.drawFrame(base, .ScrollBase);
                var thumb = base;
                thumb.sz.x = std.math.max(self.style.thumb_size, @divTrunc(base.sz.x * cnt.body.sz.x, cs.x));
                thumb.pt.x += @divTrunc(cnt.scroll.x * (base.sz.x - thumb.sz.x), max_scroll.x);
                self.drawFrame(thumb, .ScrollThumb);
            } else {
                cnt.scroll.x = 0;
            }
        }

        //=== Layout management ===//

        pub fn layoutBeginColumn(self: *Self) void {
            self.pushLayout(self.layoutNext(), .{}) catch unreachable;
        }

        pub fn layoutEndColumn(self: *Self) void {
            const src = self.layout_stack.pop() catch unreachable;
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

            comptime var items: u32 = 0;
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

                // Retrieve layout position and size and
                res.pt = layout.position;
                res.sz = layout.size;

                // Handle row layout
                if (layout.items > 0) {
                    res.sz.x = layout.widths[layout.item_index];
                    layout.item_index += 1;
                }

                // Ensure minimum size
                if (res.sz.x == 0) res.sz.x = style.size.x + 2 * style.padding;
                if (res.sz.y == 0) res.sz.y = style.size.y + 2 * style.padding;

                // TODO (Matteo): Review usage of negative dimensions
                if (res.sz.x < 0) res.sz.x += 1 + layout.body.sz.x - res.pt.x;
                if (res.sz.y < 0) res.sz.y += 1 + layout.body.sz.y - res.pt.y;
            }

            if (next_type != .Absolute) {
                // Update position
                layout.position.x += res.sz.x + style.spacing;
                layout.next_row = std.math.max(
                    layout.next_row,
                    res.pt.y + res.sz.y + style.spacing,
                );

                // Apply body offset
                res.pt = res.pt.add(layout.body.pt);

                // Update max position
                layout.max.x = std.math.max(layout.max.x, res.pt.x + res.sz.x);
                layout.max.y = std.math.max(layout.max.y, res.pt.y + res.sz.y);
            }

            self.last_rect = res;
            return res;
        }

        fn pushLayout(self: *Self, body: Rect, scroll: Vec2) !void {
            const min = std.math.minInt(i32);
            comptime assert(min < 0);

            try self.layout_stack.push(Layout{
                .body = Rect{ .pt = body.pt.sub(scroll), .sz = body.sz },
                .max = Vec2{ .x = min, .y = min },
            });

            // NOTE (Matteo): Originally there was a call to 'layoutRow' here, in order
            // to force a row with 0 size. 'layoutNext' does the job already if a 0-sized
            // layout is found.
        }

        fn peekLayout(self: *Self) *Layout {
            return self.layout_stack.peek() orelse unreachable;
        }

        //=== Clipping ===//

        pub fn pushClipRect(self: *Self, rect: Rect) void {
            const last = self.peekClipRect();
            const clip = last.intersect(rect);
            self.clip_stack.push(clip) catch unreachable;
        }

        pub fn popClipRect(self: *Self) void {
            _ = self.clip_stack.pop() catch unreachable;
        }

        pub fn peekClipRect(self: *Self) Rect {
            const ptr = self.clip_stack.peek() orelse unreachable;
            return ptr.*;
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

        pub fn updateControl(
            self: *Self,
            id: Id,
            rect: Rect,
            opts: OptionFlags,
        ) ControlState {
            const mouse_over = self.mouseOver(rect);
            const mouse_down = self.input.mouse_down.any();
            const mouse_pressed = self.input.mouse_pressed.any();

            // TODO (Matteo): Tidy up the logic here

            var state = ControlState{
                .focused = (self.last_focus == id),
                .hovered = (self.hover == id),
            };

            if (state.focused) self.curr_focus = id;

            if (opts.interact) {
                if (mouse_over and !mouse_down) {
                    self.hover = id;
                    state.hovered = true;
                }

                if (state.focused) {
                    if ((mouse_pressed and !mouse_over) or
                        (!mouse_down and !opts.hold_focus))
                    {
                        self.curr_focus = 0;
                        state.focused = false;
                    }
                }

                if (state.hovered) {
                    if (mouse_pressed) {
                        self.curr_focus = id;
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
            const mouse = self.input.mouse_pos;
            return rect.overlaps(mouse) and
                self.peekClipRect().overlaps(mouse) and
                self.inHoverRoot();
        }

        fn inHoverRoot(self: *Self) bool {
            var i = self.container_stack.idx;

            while (i > 0) {
                i -= 1;

                const slot = self.container_stack.items[i];
                if (&self.containers[slot] == self.hover_root) return true;

                // Only root containers have their `head` field set; stop searching
                // if we've reached the current root container
                if (self.containers[slot].head != 0) break;
            }

            return false;
        }

        pub fn text(self: *Self, str: []const u8) void {
            // TODO (Matteo): Handle proper text shaping (via user callbacks?)
            const color = self.getColor(.Text);
            const font = self.style.font;

            self.layoutBeginColumn();
            defer self.layoutEndColumn();
            self.layoutRow(.{-1}, font.text_height);

            var cursor: usize = 0;
            var line_end = cursor;

            while (line_end != str.len) {
                const r = self.layoutNext();
                var line_width: i32 = 0;

                var line_start = cursor;
                line_end = line_start;

                while (true) {
                    const word_start = cursor;

                    if (std.mem.indexOfAnyPos(u8, str, cursor, " \n")) |word_end| {
                        cursor = word_end;

                        line_width += font.measure(str[word_start..word_end]).x;

                        // If the word would exceed the available width, wrap previous line
                        if (line_width > r.sz.x and line_end != line_start) break;

                        // Add space to the width and advance
                        line_width += font.measure(str[line_end..cursor]).x;
                        line_end = cursor;
                        cursor += 1;
                    } else {
                        // No spaces or newlines left, render all remaining text
                        // TODO (Matteo): Improve this - last word could be truncated
                        cursor = str.len;
                        line_end = cursor;
                    }

                    if (line_end == str.len or str[line_end] == '\n') break;
                }

                self.drawText(font, str[line_start..line_end], r.pt, color) catch unreachable;
                cursor = line_end + 1;
            }
        }

        pub fn label(self: *Self, str: []const u8) void {
            self.drawControlText(str, self.layoutNext(), .Text, .{});
        }

        pub inline fn button(self: *Self, str: []const u8) Result {
            return self.buttonEx(str, .None, .{ .align_center = true });
        }

        pub fn buttonEx(
            self: *Self,
            str: []const u8,
            icon: Icon,
            opts: OptionFlags,
        ) Result {
            const id = if (str.len > 0)
                self.getId(str)
            else
                self.getId(icon);

            const rect = self.layoutNext();
            const state = self.updateControl(id, rect, opts);

            // Draw
            self.drawButton(state, rect, opts);
            if (icon != .None) self.drawIcon(icon, rect, self.getColor(.Text)) catch unreachable;
            if (str.len > 0) self.drawControlText(str, rect, .Text, opts);

            // Handle click
            return Result{
                .submit = (state.focused and self.input.mouse_pressed.left),
            };
        }

        pub fn checkbox(self: *Self, str: []const u8, checked: *bool) Result {
            const id = self.getId(str);
            const rect = self.layoutNext();
            const state = self.updateControl(id, rect, .{});

            // Handle click
            var res = Result{};
            if (state.focused and self.input.mouse_pressed.left) {
                res.change = true;
                checked.* = !checked.*;
            }

            // Draw
            const box_size = rect.sz.y;
            const box = Rect.init(rect.pt.x, rect.pt.y, box_size, box_size);
            self.drawBase(state, box, .{});

            if (checked.*) self.drawIcon(.Check, box, self.getColor(.Text)) catch unreachable;

            self.drawControlText(
                str,
                Rect.init(rect.pt.x + box_size, rect.pt.y, rect.sz.x - box_size, rect.sz.y),
                .Text,
                .{},
            );

            return res;
        }

        pub fn textbox(self: *Self, buf: *TextBuffer, opts: OptionFlags) Result {
            return self.textboxRaw(
                buf,
                self.getId(buf),
                self.layoutNext(),
                opts,
            );
        }

        pub fn textboxRaw(
            self: *Self,
            buf: *TextBuffer,
            id: Id,
            rect: Rect,
            opts: OptionFlags,
        ) Result {
            var res = Result{};

            var text_opts = opts;
            text_opts.hold_focus = true;
            const state = self.updateControl(id, rect, text_opts);

            if (state.focused) {
                // Handle text input
                if (buf.append(self.input.text_buf.text)) {
                    res.change = true;
                }

                // Handle backspace
                if (self.input.key_pressed.backspace and buf.deleteLast()) {
                    res.change = true;
                }

                // Handle return
                if (self.input.key_pressed.enter) {
                    self.curr_focus = 0;
                    res.submit = true;
                }
            }

            // Draw
            self.drawBase(state, rect, opts);

            if (state.focused) {
                const font = self.style.font;
                const size = font.measure(buf.text);

                const pad = self.style.padding;
                const ofx = std.math.min(pad, rect.sz.x - size.x - pad - 1);
                const pos = Vec2{
                    .x = rect.pt.x + std.math.min(ofx, self.style.padding),
                    .y = rect.pt.y + @divTrunc(rect.sz.y - size.y, 2),
                };

                // Active text and cursor
                const clip = rect.intersect(self.peekClipRect());
                const color = self.getColor(.Text);
                const cursor = Rect.init(pos.x + size.x, pos.y, 1, size.y).intersect(clip);
                if (cursor.sz.x > 0 and cursor.sz.y > 0) {
                    self.command_list.pushRect(cursor, color) catch {};
                }
                self.drawTextClipped(font, buf.text, pos, color, clip) catch {};
            } else {
                // Inactive text
                self.drawControlText(buf.text, rect, .Text, opts);
            }

            return res;
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
            comptime fmt: []const u8,
            opts: OptionFlags,
        ) Result {
            const id = self.getId(value);
            const base = self.layoutNext();
            const last = value.*;
            var v = last;

            // Handle text input mode
            if (self.numberTextbox(fmt, &v, base, id)) return Result{};

            // Handle normal mode
            const state = self.updateControl(id, base, opts);
            const range = high - low;

            // Handle input
            const clicked = (self.input.mouse_down.left or
                self.input.mouse_pressed.left);

            if (state.focused and clicked) {
                const delta = @intToFloat(Real, self.input.mouse_pos.x - base.pt.x);
                v = low + delta * range / @intToFloat(Real, base.sz.x);
                // TODO (Matteo): Why was division-then-multiplication by step needed
                // in the first place?
                if (step != 0) v = step * ((v + 0.5 * step) / step);
            }

            // Clamp and store value
            v = std.math.clamp(v, low, high);
            value.* = v;

            // Draw
            self.drawBase(state, base, opts);
            // Thumb
            const perc = (v - low) / range;
            const width = self.style.thumb_size;
            const thumb = Rect.init(
                base.pt.x + @floatToInt(i32, perc * @intToFloat(Real, base.sz.x - width)),
                base.pt.y,
                width,
                base.sz.y,
            );
            self.drawButton(state, thumb, opts);
            // Text
            var buf: [config.fmt_buf_size]u8 = undefined;
            self.drawControlText(
                std.fmt.bufPrint(&buf, fmt, .{v}) catch unreachable,
                base,
                .Text,
                opts,
            );

            return Result{ .change = (last != v) };
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
            const id = self.getId(value);
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
            var buf: [config.fmt_buf_size]u8 = undefined;
            self.drawControlText(
                std.fmt.bufPrint(&buf, fmt, .{value.*}) catch unreachable,
                base,
                .Text,
                opts,
            );

            // Set flag if value changed
            return Result{ .change = (value.* != last) };
        }

        fn numberTextbox(
            self: *Self,
            comptime fmt: []const u8,
            value: *Real,
            rect: Rect,
            id: Id,
            // state: ControlState,
        ) bool {
            // TODO (Matteo): Improve NumberEdit API?

            if (self.input.mouse_pressed.left and
                self.input.key_down.shift and
                self.hover == id)
            {
                self.num_edit_id = id;
                _ = self.num_edit_buf.print(fmt, .{value.*});
            }

            if (self.num_edit_id == id) {
                const res = self.textboxRaw(&self.num_edit_buf, id, rect, .{});

                if (res.submit or self.curr_focus != id) {
                    self.num_edit_id = 0;

                    if (std.fmt.parseFloat(Real, self.num_edit_buf.text)) |x| {
                        value.* = x;
                    } else |_| {}
                } else {
                    // Signal that input is still in progress
                    return true;
                }
            }

            return false;
        }

        pub fn header(self: *Self, str: []const u8, opts: OptionFlags) Result {
            return self.headerInternal(str, false, opts);
        }

        pub fn beginTreeNode(self: *Self, str: []const u8, opts: OptionFlags) Result {
            var res = self.headerInternal(str, true, opts);

            if (res.active) {
                if (self.id_stack.push(self.last_id)) {
                    self.peekLayout().indent += self.style.indent;
                } else |_| {
                    // Behave as if the node is closed so the user won't keep
                    // pushing stuff (hopefully)
                    res = Result{};
                }
            }

            return res;
        }

        pub fn endTreeNode(self: *Self) void {
            if (self.id_stack.pop()) |_| {
                self.peekLayout().indent -= self.style.indent;
            } else |_| {
                assert(false);
            }
        }

        fn headerInternal(
            self: *Self,
            str: []const u8,
            is_treenode: bool,
            opts: OptionFlags,
        ) Result {
            const id = self.getId(str);
            const pool_index = self.treenode_pool.getSlot(id);
            const was_active = (pool_index != null);
            const expanded = opts.expanded != was_active; // opts.expanded XOR was_active

            // NOTE (Matteo): -1 causes the header to adapt to container width
            self.layoutRow(.{-1}, 0);
            var r = self.layoutNext();

            // Handle click
            const state = self.updateControl(id, r, .{});
            const clicked = (self.input.mouse_pressed.left and state.focused);
            const is_active = (was_active != clicked);

            // Update pool ref
            if (pool_index) |index| {
                if (is_active) {
                    self.treenode_pool.updateSlot(index, self.frame);
                } else {
                    self.treenode_pool.freeSlot(index);
                }
            } else if (is_active) {
                _ = self.treenode_pool.initSlot(id, self.frame);
            }

            // Draw
            if (is_treenode) {
                if (state.hovered) self.drawFrame(r, .ButtonHover);
            } else {
                self.drawButton(state, r, .{});
            }

            if (self.drawIcon(
                if (expanded) .Expanded else .Collapsed,
                Rect.init(r.pt.x, r.pt.y, r.sz.y, r.sz.y),
                self.getColor(.Text),
            )) {
                const delta_x = r.sz.y - self.style.padding;
                r.pt.x += delta_x;
                r.sz.x -= delta_x;

                self.drawControlText(str, r, .Text, .{});
            } else |_| {
                // Skip drawing in case of errors
            }

            return Result{ .active = expanded };
        }

        pub fn beginWindow(
            self: *Self,
            title: []const u8,
            init_rect: Rect,
            opts: OptionFlags,
        ) Result {
            const id = self.getId(title);
            const slot = self.getContainerById(id, opts) orelse return Result{};
            var cnt = &self.containers[slot];
            if (!cnt.open) return Result{};

            if (cnt.rect.sz.x == 0) cnt.rect = init_rect;

            // Push root container
            // TODO (Matteo): Handle gracefully by returning Result{} and
            // pop from affected stacks
            self.id_stack.push(id) catch unreachable;
            self.container_stack.push(slot) catch unreachable;
            self.root_list.push(cnt) catch unreachable;

            // Push head command
            cnt.head = self.command_list.pushJump() catch unreachable;
            // Set as hover root if the mouse is overlapping this container and it has a
            // higher zindex than the current hover root
            if (cnt.rect.overlaps(self.input.mouse_pos) and
                (self.next_hover_root == null or cnt.zindex > self.next_hover_root.?.zindex))
            {
                self.next_hover_root = cnt;
            }

            // Clipping is reset here in case a root-container is made within
            // another root-containers's begin/end block; this prevents the inner
            // root-container being clipped to the outer
            self.clip_stack.push(Rect.unclipped) catch unreachable;

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
                if (title_state.focused and self.input.mouse_down.left) {
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
                    if (state.focused and self.input.mouse_pressed.left) {
                        cnt.open = false;
                    }
                    self.drawIcon(.Close, rect, self.getColor(.TitleText)) catch unreachable;
                }

                // Remove title from body
                body.pt.y += title_h;
                body.sz.y -= title_h;
            }

            self.pushContainerBody(cnt, body, opts) catch unreachable;

            // Do resize handle
            if (opts.resize) {
                const rect = Rect.init(
                    cnt.rect.pt.x + cnt.rect.sz.x - title_h,
                    cnt.rect.pt.y + cnt.rect.sz.y - title_h,
                    title_h,
                    title_h,
                );
                const state = self.updateControl(self.getId("!resize"), rect, opts);
                if (state.focused and self.input.mouse_down.left) {
                    const next_size = cnt.rect.sz.add(self.mouse_delta);
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
            if (opts.popup and self.input.mouse_pressed.any() and self.hover_root != cnt) {
                cnt.open = false;
            }

            self.pushClipRect(cnt.body);
            return Result{ .active = true };
        }

        pub fn endWindow(self: *Self) void {
            self.popClipRect();

            const slot = self.container_stack.pop() catch unreachable;
            var cnt = &self.containers[slot];

            // Push tail 'goto' jump command and set head 'skip' command. the final steps
            // on initing these are done in 'endFrame'
            cnt.tail = self.command_list.pushJump() catch unreachable;
            self.command_list.get(cnt.head).jump.dst = self.command_list.tail;

            // Pop container
            const layout = self.layout_stack.pop() catch unreachable;
            cnt.content_size = layout.max.sub(layout.body.pt);
            self.popId();

            // Pop "unclipped" rect
            self.popClipRect();
        }

        pub fn openPopup(self: *Self, name: []const u8) void {
            var cnt = self.getContainer(name);
            // Set as hover root so popup isn't closed in 'beginWindow'
            self.next_hover_root = cnt;
            self.hover_root = self.next_hover_root;
            // position at mouse cursor, open and bring-to-front
            cnt.rect = Rect{ .pt = self.input.mouse_pos, .sz = Vec2{ .x = 1, .y = 1 } };
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

        pub fn beginPanel(self: *Self, name: []const u8, opts: OptionFlags) bool {
            const id = self.getId(name);
            self.id_stack.push(id) catch return false;

            const slot = self.getContainerById(id, opts) orelse unreachable;

            if (self.container_stack.push(slot)) {
                var cnt = &self.containers[slot];
                cnt.rect = self.layoutNext();

                if (self.pushContainerBody(cnt, cnt.rect, opts)) {
                    if (opts.frame) self.drawFrame(cnt.rect, .PanelBg);
                    self.pushClipRect(cnt.body);
                } else |_| {
                    _ = self.container_stack.pop() catch unreachable;
                    return false;
                }
            } else |_| {
                return false;
            }

            return true;
        }

        pub fn endPanel(self: *Self) void {
            // NOTE (Matteo): This function is considered infallible because
            // it should be called only if beginPanel returned true
            self.popClipRect();
            const layout = self.layout_stack.pop() catch unreachable;
            const slot = self.container_stack.pop() catch unreachable;
            self.containers[slot].content_size = layout.max.sub(layout.body.pt);
            self.popId();
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
            const font = self.style.font;
            const size = font.measure(str);
            var pos = Vec2{
                .y = rect.pt.y + @divTrunc(rect.sz.y - size.y, 2),
            };

            if (opts.align_center) {
                pos.x = rect.pt.x + @divTrunc(rect.sz.x - size.x, 2);
            } else if (opts.align_right) {
                pos.x = rect.pt.x + rect.sz.x - size.x - self.style.padding;
            } else {
                pos.x = rect.pt.x + self.style.padding;
            }

            self.drawTextClipped(
                font,
                str,
                pos,
                self.getColor(color),
                rect.intersect(self.peekClipRect()),
            ) catch unreachable;
        }

        inline fn drawFrame(self: *Self, rect: Rect, color_id: ColorId) void {
            // NOTE (Matteo): Helper to abbreviate the calls involving the function
            // pointer - ugly?
            self.draw_frame(self, rect, color_id);
        }

        fn drawDefaultFrame(self: *Self, frame: Rect, color_id: ColorId) void {
            const rect = self.peekClipRect().intersect(frame);
            if (rect.isEmpty()) return;

            // TODO (Matteo): Review / improve.
            // Ignoring OOM here means something will not be drawn
            self.command_list.pushRect(rect, self.getColor(color_id)) catch return;

            switch (color_id) {
                .ScrollBase, .ScrollThumb, .TitleBg => {},
                else => {
                    const border = self.getColor(.Border);
                    if (border.a != 0) {
                        self.drawBox(rect.expand(1), border) catch return;
                    }
                },
            }
        }

        // TODO (Matteo): move the drawing functions on the command list directly?
        // Can help a bit with code organization, since it is the only state touched.

        // NOTE (Matteo): Primitive drawing functions may fail in cause the command
        // list memory is exhausted. We could simply ignore and not draw but propagating
        // the error is useful to inform higher level decisions

        pub fn drawRect(self: *Self, rect: Rect, color: Color) !void {
            const clipped = self.peekClipRect().intersect(rect);
            if (!clipped.isEmpty()) try self.command_list.pushRect(clipped, color);
        }

        pub fn drawBox(self: *Self, box: Rect, color: Color) !void {
            const rect = self.peekClipRect().intersect(box);
            if (rect.isEmpty()) return;

            try self.command_list.pushRect(Rect.init(
                rect.pt.x + 1,
                rect.pt.y,
                rect.sz.x - 2,
                1,
            ), color);

            try self.command_list.pushRect(Rect.init(
                rect.pt.x + 1,
                rect.pt.y + rect.sz.y - 1,
                rect.sz.x - 2,
                1,
            ), color);

            try self.command_list.pushRect(Rect.init(
                rect.pt.x,
                rect.pt.y,
                1,
                rect.sz.y,
            ), color);

            try self.command_list.pushRect(Rect.init(
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
        ) !void {
            return drawTextClipped(self, font, str, pos, color, self.peekClipRect());
        }

        pub fn drawIcon(self: *Self, id: Icon, rect: Rect, color: Color) !void {
            const clip = self.peekClipRect();

            switch (rect.checkClip(clip)) {
                .All => return,
                .Part => {
                    try self.command_list.pushClip(clip);
                    defer self.command_list.pushClip(Rect.unclipped) catch {};

                    try self.command_list.pushIcon(id, rect, color);
                },
                else => {
                    try self.command_list.pushIcon(id, rect, color);
                },
            }
        }

        fn drawTextClipped(
            self: *Self,
            font: *Font,
            str: []const u8,
            pos: Vec2,
            color: Color,
            clip: Rect,
        ) !void {
            const rect = Rect{ .pt = pos, .sz = font.measure(str) };

            switch (rect.checkClip(clip)) {
                .All => return,
                .Part => {
                    try self.command_list.pushClip(clip);
                    defer self.command_list.pushClip(Rect.unclipped) catch {};

                    try self.command_list.pushText(str, pos, color, font);
                },
                else => {
                    try self.command_list.pushText(str, pos, color, font);
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

    const unclipped = init(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));

    pub fn init(x: i32, y: i32, w: i32, h: i32) Rect {
        return Rect{
            .pt = Vec2{ .x = x, .y = y },
            .sz = Vec2{ .x = w, .y = h },
        };
    }

    pub inline fn isEmpty(rect: Rect) bool {
        return (rect.sz.x <= 0 or rect.sz.y <= 0);
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

    pub fn checkClip(r: Rect, c: Rect) Clip {
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
};

test "Primitives" {
    const expect = std.testing.expect;

    var c: Rect = undefined;

    const a = Rect.init(0, 0, 2, 3);
    c = a.intersect(Rect.unclipped);
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

fn hash(data: anytype, hash_in: Id) Id {
    var hash_out = hash_in;

    // const bytes = std.mem.asBytes(&data);
    const bytes = std.mem.toBytes(data);

    for (bytes) |byte| {
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

//=======================//
//  Input / interaction  //
//=======================//

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

pub const Input = struct {
    mouse_pos: Vec2 = .{},
    scroll_delta: Vec2 = .{},
    mouse_down: MouseButtons = .{},
    mouse_pressed: MouseButtons = .{},
    key_down: Keys = .{},
    key_pressed: Keys = .{},
    text_buf: TextBuffer,

    pub fn init(text_buffer: []u8) Input {
        return Input{ .text_buf = TextBuffer.fromSlice(text_buffer) };
    }

    pub fn clear(self: *Input) void {
        self.key_pressed = .{};
        self.mouse_pressed = .{};
        self.scroll_delta = .{};
        self.text_buf.clear();
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
        _ = self.text_buf.append(str);
    }

    pub fn textZ(self: *Input, str: [*:0]const u8) void {
        const len = std.mem.len(str);
        _ = self.text_buf.append(str[0..len]);
    }
};

pub const ControlState = packed struct {
    hovered: bool = false,
    focused: bool = false,

    pub usingnamespace util.BitSet(ControlState, u2);
};

// TODO (Matteo): Is as bitset really useful? Would a simple boolean be enough?
pub const Result = packed struct {
    active: bool = false,
    submit: bool = false,
    change: bool = false,

    pub usingnamespace util.BitSet(Result, u3);
};

//=================//
//  Text handling  //
//=================//

pub const Font = struct {
    text_height: i32,
    text_width: *const fn (ptr: ?*anyopaque, str: []const u8) i32,
    ptr: ?*anyopaque = null,

    pub fn measure(self: *const Font, str: []const u8) Vec2 {
        return .{ .x = self.text_width(self.ptr, str), .y = self.text_height };
    }
};

pub const TextBuffer = struct {
    text: []u8 = &[_]u8{},
    cap: usize = 0,

    pub fn fromSlice(slice: []u8) TextBuffer {
        return TextBuffer{ .cap = slice.len, .text = slice[0..0] };
    }

    pub fn clear(self: *TextBuffer) void {
        self.text.len = 0;
    }

    pub fn print(self: *TextBuffer, comptime fmt: []const u8, args: anytype) bool {
        var stream = std.io.fixedBufferStream(self.text.ptr[0..self.cap]);
        std.fmt.format(stream.writer(), fmt, args) catch return false;

        assert(self.text.ptr == stream.buffer.ptr);

        self.text = stream.getWritten();
        return true;
    }

    pub fn append(self: *TextBuffer, str: []const u8) bool {
        var dst = self.text.ptr[self.text.len..self.cap];

        const count = std.math.min(dst.len, str.len);

        assert(count == str.len);

        if (count > 0) {
            std.mem.copy(u8, dst[0..count], str[0..count]);
            self.text.len += count;
            return true;
        }

        return false;
    }

    pub fn deleteLast(self: *TextBuffer) bool {
        // TODO (Matteo): Use stdlib unicode facilities?
        if (self.text.len > 0) {
            // skip utf-8 continuation bytes
            var cursor = self.text.len - 1;
            while (cursor > 0 and (self.text[cursor] & 0xc0) == 0x80) {
                cursor -= 1;
            }
            self.text.len = cursor;
            return true;
        }

        return false;
    }
};

//=====================//

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
