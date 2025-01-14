//
// MicroUI - Zig version
//
// Based on  https://github.com/rxi/microui - see end of file for license information
//
// This files contains the main library API
//

const std = @import("std");
const assert = std.debug.assert;

test "MicroUi" {
    std.testing.refAllDecls(@This());

    var font: Font = undefined;
    var ui: Ui(.{}) = undefined;
    ui.init(&font, null);

    var input = ui.getInput();

    try ui.beginFrame(&input, .{});
    defer ui.endFrame();
}

pub const Id = u32;
pub const command = @import("command.zig");
pub const atlas = @import("atlas.zig");

pub const DrawError = command.Error;

pub const Clip = enum(u2) {
    None,
    Part,
    All,
};

pub const ColorId = enum(u5) {
    Text,
    Border,
    BorderShadow,
    WindowBg,
    TitleBg,
    TitleText,
    PanelBg,
    Header,
    HeaderHover,
    HeaderFocus,
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
};

pub const Container = struct {
    head: u32 = 0,
    tail: u32 = 0,
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
    colors: [color_count]Color = [_]Color{
        .{ .r = 230, .g = 230, .b = 230, .a = 255 }, // Text
        .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // Border
        .{ .r = 0, .g = 0, .b = 0, .a = 0 }, // BorderShadow
        .{ .r = 50, .g = 50, .b = 50, .a = 255 }, // WindowBg
        .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // TitleBg
        .{ .r = 240, .g = 240, .b = 240, .a = 255 }, // TitleText
        .{ .r = 0, .g = 0, .b = 0, .a = 0 }, // PanelBg
        .{ .r = 75, .g = 75, .b = 75, .a = 255 }, // Header
        .{ .r = 95, .g = 95, .b = 95, .a = 255 }, // HeaderHover
        .{ .r = 115, .g = 115, .b = 115, .a = 255 }, // HeaderFocus
        .{ .r = 75, .g = 75, .b = 75, .a = 255 }, // Button
        .{ .r = 95, .g = 95, .b = 95, .a = 255 }, // ButtonHover
        .{ .r = 115, .g = 115, .b = 115, .a = 255 }, // ButtonFocus
        .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // Base
        .{ .r = 35, .g = 35, .b = 35, .a = 255 }, // BaseHover
        .{ .r = 40, .g = 40, .b = 40, .a = 255 }, // BaseFocus
        .{ .r = 43, .g = 43, .b = 43, .a = 255 }, // ScrollBase
        .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // ScrollThumb
    },

    const color_count = @typeInfo(ColorId).Enum.fields.len;

    /// Helper to access the color value by id without casting the enum explicitly
    pub inline fn getColor(self: *const Style, id: ColorId) Color {
        return self.colors[@intFromEnum(id)];
    }

    /// Helper to set the color value by id without casting the enum explicitly
    pub inline fn setColor(self: *Style, id: ColorId, color: Color) void {
        self.colors[@intFromEnum(id)] = color;
    }
};

/// Compile-time configuration parameters
pub const Config = struct {
    // Sizes
    command_list_size: u32 = (256 * 1024),
    rootlist_size: u16 = 32,
    container_stack_size: u16 = 32,
    clip_stack_size: u16 = 32,
    id_stack_size: u16 = 32,
    layout_stack_size: u16 = 16,
    container_pool_size: u16 = 48,
    treenode_pool_size: u16 = 48,
    // TODO (Matteo): Review
    fmt_buf_size: u16 = 127,
    input_buf_size: u32 = 32,

    /// Maximum number of columns in a layout row
    max_widths: u16 = 16,

    /// Type used to represent real numbers
    real_type: type = f32,
};

pub fn Ui(comptime config: Config) type {
    return struct {
        comptime {
            assert(config.max_widths <= std.math.maxInt(u32));
        }

        //=== Inner types ===//

        // NOTE (Matteo): Those types are declared here since they depend on
        // comptime configuration parameters

        pub const Real = config.real_type;

        pub const DrawFrameFn = *const fn (self: *Self, rect: Rect, color: ColorId) DrawError!void;

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
        root_list: std.BoundedArray(*Container, config.rootlist_size) = .{},
        container_stack: std.BoundedArray(PoolSlot, config.container_stack_size) = .{},
        clip_stack: std.BoundedArray(Rect, config.clip_stack_size) = .{},
        id_stack: std.BoundedArray(Id, config.id_stack_size) = .{},
        layout_stack: std.BoundedArray(Layout, config.layout_stack_size) = .{},

        // retained state pools
        containers: [config.container_pool_size]Container = undefined,
        container_pool: Pool(config.container_pool_size) = .{},
        treenode_pool: Pool(config.treenode_pool_size) = .{},

        // input state
        input: Input = .{ .text_buf = .{} },
        mouse_delta: Vec2 = .{},

        scratch_buf: [scratch_size]u8 = undefined,

        // TODO (Matteo): Review - used to intercept missing calls to 'init'
        init_code: u16,

        // TODO (Matteo): Experimental
        bounds: Rect = Rect.unclipped,

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
            @memset(buf, 0);
            return Input.init(buf);
        }

        pub fn beginFrame(self: *Self, input: *Input, screen_size: Vec2) !void {
            if (self.init_code != 0x1DEA) return error.NotInitialized;

            // Check stacks
            assert(self.container_stack.len == 0);
            assert(self.clip_stack.len == 0);
            assert(self.id_stack.len == 0);
            assert(self.layout_stack.len == 0);

            self.command_list.clear();
            try self.root_list.resize(0);

            self.scroll_target = null;
            self.hover_root = self.next_hover_root;
            self.next_hover_root = null;

            self.mouse_delta = input.mouse_pos.sub(self.input.mouse_pos);
            self.input = input.*;
            input.clear();

            self.last_focus = self.curr_focus;
            self.curr_focus = 0;

            self.frame +%= 1; // wrapping increment, overflow is somewhat expected

            // TODO (Matteo): Experimental
            self.bounds.sz = screen_size;
        }

        pub fn endFrame(self: *Self) void {
            // Check stacks - assertion are fine here since we are checking
            // for internal consistency and not an user error
            assert(self.container_stack.len == 0);
            assert(self.clip_stack.len == 0);
            assert(self.id_stack.len == 0);
            assert(self.layout_stack.len == 0);

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

            const roots = self.root_list.slice();
            std.sort.block(*Container, roots, {}, compare.lessThan);

            // TODO (Matteo): Review
            // Set root container jump commands
            for (roots, 0..) |cnt, i| {
                // If this is the first container then make the first command jump to it.
                // Otherwise set the previous container's tail to jump to this one
                var jump = if (i == 0) cnt.head else roots[i - 1].tail;
                self.command_list.setJump(jump, self.command_list.nextCommand(cnt.head));

                // Make the last container's tail jump to the end of command list
                if (i == roots.len - 1) {
                    self.command_list.setJump(cnt.tail, self.command_list.tail);
                }
            }
        }

        //=== ID management ===//

        pub fn getId(self: *Self, data: anytype) Id {
            const id_count = self.id_stack.len;
            const init_id = if (id_count > 0) self.id_stack.get(id_count - 1) else HASH_INITIAL;
            self.last_id = hash(data, init_id);
            return self.last_id;
        }

        pub fn pushId(self: *Self, data: anytype) void {
            self.id_stack.append(self.getId(data)) catch unreachable;
        }

        pub fn popId(self: *Self) void {
            _ = self.id_stack.pop();
        }

        //=== Container management ===//

        pub fn getCurrentContainer(self: *Self) *Container {
            const n = self.container_stack.len;
            assert(n > 0);
            const slot = self.container_stack.get(n - 1);
            return &self.containers[slot];
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

        fn getContainerById(self: *Self, id: Id, opt: OptionFlags) ?PoolSlot {
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
                thumb.sz.y = @max(self.style.thumb_size, @divTrunc(base.sz.y * cnt.body.sz.y, cs.y));
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
                thumb.sz.x = @max(self.style.thumb_size, @divTrunc(base.sz.x * cnt.body.sz.x, cs.x));
                thumb.pt.x += @divTrunc(cnt.scroll.x * (base.sz.x - thumb.sz.x), max_scroll.x);
                self.drawFrame(thumb, .ScrollThumb);
            } else {
                cnt.scroll.x = 0;
            }
        }

        fn beginRootContainer(self: *Self, id: Id, slot: PoolSlot, cnt: *Container) void {
            // Push root container
            // TODO (Matteo): Handle gracefully by returning 'false' and
            // pop from affected stacks
            self.id_stack.append(id) catch unreachable;
            self.container_stack.append(slot) catch unreachable;
            self.root_list.append(cnt) catch unreachable;

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
            self.clip_stack.append(self.bounds) catch unreachable;
        }

        fn endRootContainer(self: *Self) void {
            const slot = self.container_stack.pop();
            var cnt = &self.containers[slot];

            // Push tail 'goto' jump command and set head 'skip' command. the final steps
            // on initing these are done in 'endFrame'
            cnt.tail = self.command_list.pushJump() catch unreachable;
            self.command_list.setJump(cnt.head, self.command_list.tail);

            // Pop container
            const layout = self.layout_stack.pop();
            cnt.content_size = layout.max.sub(layout.body.pt);
            self.popId();

            // Pop "unclipped" rect
            self.popClipRect();
        }

        //=== Layout management ===//

        pub fn layoutBeginColumn(self: *Self) void {
            self.pushLayout(self.layoutNext(), .{}) catch unreachable;
        }

        pub fn layoutEndColumn(self: *Self) void {
            const src = self.layout_stack.pop();
            var dst = self.peekLayout();

            // Inherit position/next_row/max from child layout if they are greater
            const dpos = src.body.pt.sub(dst.body.pt);

            dst.position.x = @max(dst.position.x, src.position.x + dpos.x);
            dst.next_row = @max(dst.next_row, src.next_row + dpos.y);
            dst.max.x = @max(dst.max.x, src.max.x);
            dst.max.y = @max(dst.max.y, src.max.y);
        }

        pub fn layoutRow(self: *Self, widths: anytype, height: i32) void {
            var layout = self.peekLayout();

            assert(widths.len <= layout.widths.len);

            comptime var items: u32 = 0;
            inline while (items < widths.len) : (items += 1) {
                layout.widths[items] = widths[items];
            }

            layout.position = .{ .x = layout.indent, .y = layout.next_row };
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
                    layout.position = .{ .x = layout.indent, .y = layout.next_row };
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
                layout.next_row = @max(
                    layout.next_row,
                    res.pt.y + res.sz.y + style.spacing,
                );

                // Apply body offset
                res.pt = res.pt.add(layout.body.pt);

                // Update max position
                layout.max.x = @max(layout.max.x, res.pt.x + res.sz.x);
                layout.max.y = @max(layout.max.y, res.pt.y + res.sz.y);
            }

            self.last_rect = res;
            return res;
        }

        fn pushLayout(self: *Self, body: Rect, scroll: Vec2) !void {
            const min = std.math.minInt(i32);
            comptime assert(min < 0);

            try self.layout_stack.append(Layout{
                .body = .{ .pt = body.pt.sub(scroll), .sz = body.sz },
                .max = .{ .x = min, .y = min },
            });

            // NOTE (Matteo): Originally there was a call to 'layoutRow' here, in order
            // to force a row with 0 size. 'layoutNext' does the job already if a 0-sized
            // layout is found.
            self.layoutRow(.{0}, 0);
        }

        fn peekLayout(self: *Self) *Layout {
            const n = self.layout_stack.len;
            assert(n > 0);
            return &self.layout_stack.buffer[n - 1];
        }

        //=== Clipping ===//

        pub fn pushClipRect(self: *Self, clip: Rect) void {
            const last = self.peekClipRect();
            self.clip_stack.append(last.intersect(clip)) catch unreachable;
        }

        pub fn popClipRect(self: *Self) void {
            _ = self.clip_stack.pop();
        }

        pub fn peekClipRect(self: *Self) Rect {
            return self.clip_stack.get(self.clip_stack.len - 1);
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
            bounds: Rect,
            opts: OptionFlags,
        ) ControlState {
            const mouse_over = self.mouseOver(bounds);
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

        pub fn mouseOver(self: *Self, box: Rect) bool {
            const mouse = self.input.mouse_pos;
            return box.overlaps(mouse) and
                self.peekClipRect().overlaps(mouse) and
                self.inHoverRoot();
        }

        fn inHoverRoot(self: *Self) bool {
            var i = self.container_stack.len;

            while (i > 0) {
                i -= 1;

                const slot = self.container_stack.get(i);
                const cnt = &self.containers[slot];
                if (cnt == self.hover_root) return true;

                // Only root containers have their `head` field set; stop searching
                // if we've reached the current root container
                if (cnt.head != 0) break;
            }

            return false;
        }

        pub fn text(self: *Self, str: []const u8) void {
            // TODO (Matteo): Handle proper text shaping (via user callbacks?)
            const color = self.style.getColor(.Text);
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

                // TODO (Matteo): Improve - If drawing fails, we can bail out since
                // future calls will fail too
                self.drawText(font, str[line_start..line_end], r.pt, color) catch return;
                cursor = line_end + 1;
            }
        }

        pub fn label(self: *Self, str: []const u8) void {
            self.drawControlText(str, self.layoutNext(), .Text, .{});
        }

        /// Returns 'true' if clicked
        pub inline fn button(self: *Self, str: []const u8) bool {
            return self.buttonEx(str, .None, .{ .align_center = true });
        }

        /// Returns 'true' if clicked
        pub fn buttonEx(
            self: *Self,
            str: []const u8,
            icon: Icon,
            opts: OptionFlags,
        ) bool {
            const id = if (str.len > 0)
                self.getId(str)
            else
                self.getId(icon);

            const bounds = self.layoutNext();
            const state = self.updateControl(id, bounds, opts);

            // Draw
            self.drawControlFrame(.Button, bounds, state, .{});
            if (icon != .None) {
                // TODO (Matteo): Is not drawing on error the right choice?
                self.drawIcon(icon, bounds, self.style.getColor(.Text)) catch {};
            }
            if (str.len > 0) self.drawControlText(str, bounds, .Text, opts);

            // Handle click
            return (state.focused and self.input.mouse_pressed.left);
        }

        /// Returns 'true' if checked state changed, 'false' otherwise
        pub fn checkbox(self: *Self, str: []const u8, checked: *bool) bool {
            const id = self.getId(str);
            const bounds = self.layoutNext();
            const state = self.updateControl(id, bounds, .{});

            // Handle click
            var changed = false;
            if (state.focused and self.input.mouse_pressed.left) {
                changed = true;
                checked.* = !checked.*;
            }

            // Draw
            const box_size = bounds.sz.y;
            const box = rect(bounds.pt.x, bounds.pt.y, box_size, box_size);
            self.drawControlFrame(.Base, box, state, .{});

            if (checked.*) {
                // TODO (Matteo): Is not drawing on error the right choice?
                self.drawIcon(.Check, box, self.style.getColor(.Text)) catch {};
            }

            self.drawControlText(
                str,
                rect(bounds.pt.x + box_size, bounds.pt.y, bounds.sz.x - box_size, bounds.sz.y),
                .Text,
                .{},
            );

            return changed;
        }

        pub fn textbox(self: *Self, buf: *TextBuffer, opts: OptionFlags) TextBoxState {
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
            bounds: Rect,
            opts: OptionFlags,
        ) TextBoxState {
            var res = TextBoxState{};

            var text_opts = opts;
            text_opts.hold_focus = true;
            const state = self.updateControl(id, bounds, text_opts);

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
            self.drawControlFrame(.Base, bounds, state, opts);

            if (state.focused) {
                const font = self.style.font;
                const size = font.measure(buf.text);

                const pad = self.style.padding;
                const ofx = @min(pad, bounds.sz.x - size.x - pad - 1);
                const pos = vec2(
                    bounds.pt.x + @min(ofx, self.style.padding),
                    bounds.pt.y + @divTrunc(bounds.sz.y - size.y, 2),
                );

                // Active text and cursor
                const clip = bounds.intersect(self.peekClipRect());
                const color = self.style.getColor(.Text);
                const cursor = rect(pos.x + size.x, pos.y, 1, size.y).intersect(clip);
                if (cursor.sz.x > 0 and cursor.sz.y > 0) {
                    self.command_list.pushRect(cursor, color, .{}) catch {};
                }
                self.drawTextClipped(font, buf.text, pos, color, clip) catch {};
            } else {
                // Inactive text
                self.drawControlText(buf.text, bounds, .Text, opts);
            }

            return res;
        }

        /// Returns 'true' if value is changed, 'false' otherwise
        pub inline fn slider(
            self: *Self,
            value: *Real,
            low: Real,
            high: Real,
        ) bool {
            return self.sliderEx(
                value,
                low,
                high,
                0,
                "{d:.2}",
                .{ .align_center = true },
            );
        }

        /// Returns 'true' if value is changed, 'false' otherwise
        pub fn sliderEx(
            self: *Self,
            value: *Real,
            low: Real,
            high: Real,
            step: Real,
            comptime fmt: []const u8,
            opts: OptionFlags,
        ) bool {
            const id = self.getId(value);
            const base = self.layoutNext();
            const last = value.*;
            var v = last;

            // Handle text input mode
            if (self.numberTextbox(fmt, &v, base, id)) return false;

            // Handle normal mode
            const state = self.updateControl(id, base, opts);
            const range = high - low;

            // Handle input
            const clicked = (self.input.mouse_down.left or
                self.input.mouse_pressed.left);

            if (state.focused and clicked) {
                const delta = @as(Real, @floatFromInt(self.input.mouse_pos.x - base.pt.x));
                v = low + delta * range / @as(Real, @floatFromInt(base.sz.x));
                // TODO (Matteo): Why was division-then-multiplication by step needed
                // in the first place?
                if (step != 0) v = step * ((v + 0.5 * step) / step);
            }

            // Clamp and store value
            v = std.math.clamp(v, low, high);
            value.* = v;

            // Draw
            self.drawControlFrame(.Base, base, state, opts);
            // Thumb
            const perc = (v - low) / range;
            const width = self.style.thumb_size;
            const thumb = rect(
                base.pt.x + @as(i32, @intFromFloat(perc * @as(Real, @floatFromInt(base.sz.x - width)))),
                base.pt.y,
                width,
                base.sz.y,
            );
            self.drawControlFrame(.Button, thumb, state, .{});

            // Text
            var buf: [config.fmt_buf_size]u8 = undefined;
            self.drawControlText(
                std.fmt.bufPrint(&buf, fmt, .{v}) catch unreachable,
                base,
                .Text,
                opts,
            );

            return (last != v);
        }

        /// Returns 'true' if value is changed, 'false' otherwise
        pub fn number(
            self: *Self,
            value: *Real,
            step: Real,
        ) bool {
            return self.numberEx(
                value,
                step,
                "{d:.2}",
                .{ .align_center = true },
            );
        }

        /// Returns 'true' if value is changed, 'false' otherwise
        pub fn numberEx(
            self: *Self,
            value: *Real,
            step: Real,
            comptime fmt: []const u8,
            opts: OptionFlags,
        ) bool {
            const id = self.getId(value);
            const base = self.layoutNext();
            const last = value.*;

            // Handle text input mode
            if (self.numberTextbox(value, base, id)) return false;

            // Handle normal mode
            const state = self.updateControl(id, base, opts);

            // Handle input
            if (state.focused and self.mouse_down.left) {
                value.* += self.mouse_delta.x * step;
            }

            // Draw base
            self.drawControlFrame(.Base, base, state, opts);

            // Draw text
            var buf: [config.fmt_buf_size]u8 = undefined;
            self.drawControlText(
                std.fmt.bufPrint(&buf, fmt, .{value.*}) catch unreachable,
                base,
                .Text,
                opts,
            );

            // Set flag if value changed
            return (value.* != last);
        }

        fn numberTextbox(
            self: *Self,
            comptime fmt: []const u8,
            value: *Real,
            bounds: Rect,
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
                const res = self.textboxRaw(&self.num_edit_buf, id, bounds, .{});

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

        /// Returns 'true' if expanded
        pub fn header(self: *Self, str: []const u8, opts: OptionFlags) bool {
            return self.headerInternal(str, false, opts);
        }

        /// Returns 'true' if expanded
        pub fn beginTreeNode(self: *Self, str: []const u8, opts: OptionFlags) bool {
            if (!self.headerInternal(str, true, opts)) return false;

            if (self.id_stack.append(self.last_id)) {
                self.peekLayout().indent += self.style.indent;
            } else |_| {
                // Behave as if the node is closed so the user won't keep
                // pushing stuff (hopefully)
                return false;
            }

            return true;
        }

        pub fn endTreeNode(self: *Self) void {
            if (self.id_stack.popOrNull()) |_| {
                self.peekLayout().indent -= self.style.indent;
            } else {
                assert(false);
            }
        }

        fn headerInternal(
            self: *Self,
            str: []const u8,
            is_treenode: bool,
            opts: OptionFlags,
        ) bool {
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
                if (state.hovered) self.drawFrame(r, .HeaderHover);
            } else {
                self.drawControlFrame(.Header, r, state, .{});
            }

            if (self.drawIcon(
                if (expanded) .Expanded else .Collapsed,
                rect(r.pt.x, r.pt.y, r.sz.y, r.sz.y),
                self.style.getColor(.Text),
            )) {
                const delta_x = r.sz.y - self.style.padding;
                r.pt.x += delta_x;
                r.sz.x -= delta_x;

                self.drawControlText(str, r, .Text, .{});
            } else |_| {
                // Skip drawing in case of errors
            }

            return expanded;
        }

        pub fn beginWindow(
            self: *Self,
            title: []const u8,
            init_rect: Rect,
            opts: OptionFlags,
        ) bool {
            const id = self.getId(title);
            const slot = self.getContainerById(id, opts) orelse return false;
            var cnt = &self.containers[slot];
            if (!cnt.open) return false;

            if (cnt.rect.sz.x == 0) cnt.rect = init_rect;

            self.beginRootContainer(id, slot, cnt);

            // Draw frame
            if (opts.frame) self.drawFrame(cnt.rect, .WindowBg);

            const title_h = self.style.title_height;
            var body = cnt.rect;

            // Do title bar
            if (opts.title) {
                const title_rect = Rect{
                    .pt = cnt.rect.pt,
                    .sz = .{ .x = cnt.rect.sz.x, .y = title_h },
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
                    const bounds = rect(
                        title_rect.pt.x + title_rect.sz.x - title_h,
                        title_rect.pt.y,
                        title_h,
                        title_h,
                    );
                    const state = self.updateControl(self.getId("!close"), bounds, opts);
                    if (state.focused and self.input.mouse_pressed.left) {
                        cnt.open = false;
                    }
                    // TODO (Matteo): Is not drawing on error the right choice?
                    self.drawIcon(.Close, bounds, self.style.getColor(.TitleText)) catch {};
                }

                // Remove title from body
                body.pt.y += title_h;
                body.sz.y -= title_h;
            }

            self.pushContainerBody(cnt, body, opts) catch unreachable;

            // Do resize handle
            if (opts.resize) {
                const bounds = rect(
                    cnt.rect.pt.x + cnt.rect.sz.x - title_h,
                    cnt.rect.pt.y + cnt.rect.sz.y - title_h,
                    title_h,
                    title_h,
                );
                const state = self.updateControl(self.getId("!resize"), bounds, opts);
                if (state.focused and self.input.mouse_down.left) {
                    const next_size = cnt.rect.sz.add(self.mouse_delta);
                    cnt.rect.sz.x = @max(96, next_size.x);
                    cnt.rect.sz.y = @max(64, next_size.y);
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
            return true;
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
            cnt.rect = Rect{ .pt = self.input.mouse_pos, .sz = vec2(1, 1) };
            cnt.open = true;
            self.bringToFront(cnt);
        }

        pub fn beginPopup(self: *Self, name: []const u8) bool {
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
            const slot = self.getContainerById(id, opts) orelse return false;
            var cnt = &self.containers[slot];

            self.beginRootContainer(id, slot, cnt);

            if (self.container_stack.len == 1) {
                // Root panel takes all the available space
                cnt.rect = self.bounds;

                self.pushContainerBody(cnt, cnt.rect, opts) catch {
                    self.endRootContainer();
                    return false;
                };

                // FIXME (Matteo): This hack is required otherwise empty panels
                // will cause a crash in endPanel due to integer overflow
                _ = self.layoutNext();
            } else {
                cnt.rect = self.layoutNext();

                self.pushContainerBody(cnt, cnt.rect, opts) catch {
                    self.endRootContainer();
                    return false;
                };
            }

            if (opts.frame) {
                self.drawFrame(cnt.rect, .PanelBg);
            } else {
                self.drawRect(cnt.rect, self.style.getColor(.PanelBg)) catch {};
            }

            self.pushClipRect(cnt.body);

            return true;
        }

        pub fn endPanel(self: *Self) void {
            // NOTE (Matteo): This function is considered infallible because
            // it should be called only if beginPanel returned true
            self.popClipRect();
            self.endRootContainer();
        }

        //=== Drawing ===//

        // TODO (Matteo): Make color a comptime parameter? Usually that's the case,
        // and would allow for better code generation but it removes flexibility
        // from the user side
        pub fn drawControlFrame(
            self: *Self,
            color: ColorId,
            frame: Rect,
            state: ControlState,
            opts: OptionFlags,
        ) void {
            if (opts.frame) {
                const offset: u3 = switch (color) {
                    .Base,
                    .Button,
                    .Header,
                    => if (state.hovered) 1 else if (state.focused) 2 else 0,
                    inline else => 0,
                };

                self.drawFrame(frame, @as(ColorId, @enumFromInt(@intFromEnum(color) + offset)));
            }
        }

        pub fn drawControlText(
            self: *Self,
            str: []const u8,
            bounds: Rect,
            color: ColorId,
            opts: OptionFlags,
        ) void {
            const font = self.style.font;
            const size = font.measure(str);
            var pos = Vec2{
                .y = bounds.pt.y + @divTrunc(bounds.sz.y - size.y, 2),
            };

            if (opts.align_center) {
                pos.x = bounds.pt.x + @divTrunc(bounds.sz.x - size.x, 2);
            } else if (opts.align_right) {
                pos.x = bounds.pt.x + bounds.sz.x - size.x - self.style.padding;
            } else {
                pos.x = bounds.pt.x + self.style.padding;
            }

            // TODO (Matteo): Is not drawing on error the right choice?
            self.drawTextClipped(
                font,
                str,
                pos,
                self.style.getColor(color),
                bounds.intersect(self.peekClipRect()),
            ) catch {};
        }

        inline fn drawFrame(self: *Self, frame: Rect, color_id: ColorId) void {
            // NOTE (Matteo): Helper to abbreviate the calls involving the function
            // pointer - ugly?
            // TODO (Matteo): Is not drawing on error the right choice?
            self.draw_frame(self, frame, color_id) catch {};
        }

        fn drawDefaultFrame(self: *Self, frame: Rect, color_id: ColorId) DrawError!void {
            const clipped = self.peekClipRect().intersect(frame);
            if (clipped.isEmpty()) return;

            try self.command_list.pushRect(clipped, self.style.getColor(color_id), .{});

            switch (color_id) {
                .ScrollBase, .ScrollThumb, .TitleBg => {},
                else => {
                    const bound = clipped.expand(1);

                    const shadow = self.style.getColor(.BorderShadow);
                    if (shadow.a != 0) {
                        try self.drawBox(bound.move(vec2(1, 1)), shadow);
                    }

                    const border = self.style.getColor(.Border);
                    if (border.a != 0) try self.drawBox(bound, border);
                },
            }
        }

        // TODO (Matteo): move the drawing functions on the command list directly?
        // Can help a bit with code organization, since it is the only state touched.

        // NOTE (Matteo): Primitive drawing functions may fail in cause the command
        // list memory is exhausted. We could simply ignore and not draw but propagating
        // the error is useful to inform higher level decisions

        pub fn drawRect(self: *Self, r: Rect, color: Color) DrawError!void {
            const clipped = self.peekClipRect().intersect(r);
            if (!clipped.isEmpty()) try self.command_list.pushRect(clipped, color, .{});
        }

        pub fn drawBox(self: *Self, box: Rect, color: Color) DrawError!void {
            const clipped = self.peekClipRect().intersect(box);
            if (!clipped.isEmpty()) try self.command_list.pushRect(
                clipped,
                color,
                .{ .fill = false },
            );
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

        pub fn drawIcon(self: *Self, id: Icon, box: Rect, color: Color) DrawError!void {
            const clip = self.peekClipRect();

            switch (box.checkClip(clip)) {
                .All => return,
                .Part => {
                    try self.command_list.pushClip(clip);
                    defer self.command_list.pushClip(self.bounds) catch {};

                    try self.command_list.pushIcon(id, box, color);
                },
                else => {
                    try self.command_list.pushIcon(id, box, color);
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
        ) DrawError!void {
            const bounds = Rect{ .pt = pos, .sz = font.measure(str) };

            switch (bounds.checkClip(clip)) {
                .All => return,
                .Part => {
                    try self.command_list.pushClip(clip);
                    defer self.command_list.pushClip(self.bounds) catch {};

                    try self.command_list.pushText(str, pos, color, font);
                },
                else => {
                    try self.command_list.pushText(str, pos, color, font);
                },
            }
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
        return .{
            .x = l.x + r.x,
            .y = l.y + r.y,
        };
    }

    pub inline fn sub(l: Vec2, r: Vec2) Vec2 {
        return .{
            .x = l.x - r.x,
            .y = l.y - r.y,
        };
    }

    pub inline fn negate(v: Vec2) Vec2 {
        return .{ .x = -v.x, .y = -v.y };
    }

    pub inline fn eq(l: Vec2, r: Vec2) bool {
        return (l.x == r.x and l.y == r.y);
    }
};

pub const Rect = extern struct {
    pt: Vec2 = .{},
    sz: Vec2 = .{},

    const unclipped = rect(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));

    pub inline fn isEmpty(self: Rect) bool {
        return (self.sz.x <= 0 or self.sz.y <= 0);
    }

    pub fn expand(self: Rect, n: i32) Rect {
        return .{
            .pt = vec2(self.pt.x - n, self.pt.y - n),
            .sz = vec2(self.sz.x + 2 * n, self.sz.y + 2 * n),
        };
    }

    pub fn move(self: Rect, v: Vec2) Rect {
        return .{ .pt = self.pt.add(v), .sz = self.sz };
    }

    pub fn intersect(ls: Rect, rs: Rect) Rect {
        const min = vec2(
            @max(ls.pt.x, rs.pt.x),
            @max(ls.pt.y, rs.pt.y),
        );

        const max = vec2(
            @max(min.x, @min(ls.pt.x + ls.sz.x, rs.pt.x + rs.sz.x)),
            @max(min.y, @min(ls.pt.y + ls.sz.y, rs.pt.y + rs.sz.y)),
        );

        return .{ .pt = min, .sz = max.sub(min) };
    }

    pub fn overlaps(self: Rect, p: Vec2) bool {
        const max = self.pt.add(self.sz);
        return p.x >= self.pt.x and p.x <= max.x and
            p.y >= self.pt.y and p.y <= max.y;
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

/// Represents an ellipse (or a circle as a degenerate case with equal radii)
pub const Ellipse = extern struct {
    center: Vec2,
    radii: Vec2,

    pub inline fn isCircle(ell: Ellipse) bool {
        return (ell.radii.x == ell.radii.y);
    }
};

pub inline fn vec2(x: i32, y: i32) Vec2 {
    return .{ .x = x, .y = y };
}

pub inline fn rect(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{ .pt = vec2(x, y), .sz = vec2(w, h) };
}

pub inline fn circle(center: Vec2, radius: i32) Ellipse {
    return .{ .center = center, .radii = vec2(radius, radius) };
}

test "Primitives" {
    const expect = std.testing.expect;

    var c: Rect = undefined;

    const a = rect(0, 0, 2, 3);
    c = a.intersect(Rect.unclipped);
    try expect(a.pt.eq(c.pt));
    try expect(a.sz.eq(c.sz));

    const b = rect(1, 1, 3, 3);
    c = a.intersect(b);
    try expect(c.pt.eq(c.pt));
    try expect(c.sz.eq(vec2(1, 2)));
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

pub const MouseButtons = packed struct(u3) {
    left: bool = false,
    right: bool = false,
    middle: bool = false,

    pub usingnamespace BitSet(MouseButtons);
};

pub const Keys = packed struct(u5) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    backspace: bool = false,
    enter: bool = false,

    pub usingnamespace BitSet(Keys);
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

    pub inline fn mouseMove(self: *Input, pos: Vec2) void {
        self.mouse_pos = pos;
    }

    pub fn mouseDown(self: *Input, pos: Vec2, btn: MouseButtons) void {
        if (btn.any()) {
            self.mouseMove(pos);
            self.mouse_down = self.mouse_down.unionWith(btn);
            self.mouse_pressed = self.mouse_pressed.unionWith(btn);
        }
    }

    pub fn mouseUp(self: *Input, pos: Vec2, btn: MouseButtons) void {
        if (btn.any()) {
            self.mouseMove(pos);
            self.mouse_down = self.mouse_down.exceptWith(btn);
        }
    }

    pub inline fn scroll(self: *Input, delta: Vec2) void {
        self.scroll_delta.x += delta.x;
        self.scroll_delta.y += delta.y;
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

        const count = @min(dst.len, str.len);

        assert(count == str.len);

        if (count > 0) {
            std.mem.copy(u8, dst[0..count], str[0..count]);
            self.text.len += count;
            return true;
        }

        return false;
    }

    pub fn deleteLast(self: *TextBuffer) bool {
        if (self.text.len > 0) {
            // skip utf-8 continuation bytes
            var cursor = self.text.len - 1;
            while (cursor > 0 and isUnicodeContinuation(self.text[cursor])) {
                cursor -= 1;
            }
            self.text.len = cursor;
            return true;
        }

        return false;
    }
};

pub const TextBoxState = packed struct {
    submit: bool = false,
    change: bool = false,
};

//=============//
//  Utilities  //
//=============//

// TODO (Matteo): Use stdlib unicode facilities?
pub inline fn isUnicodeContinuation(char: u8) bool {
    return (char & 0xC0 == 0x80);
}

// TODO (Matteo): API review. At the moment multiple elements with the same ID
// can be stored - this does not happen if the expected usage, which is to always
// call 'get' before 'init', is followed, but this policy is not enforced in anyway.

const PoolSlot = u32;

fn Pool(comptime N: u32) type {
    return struct {
        items: [N]Item = [_]Item{.{}} ** N,

        const Item = struct { id: Id = 0, last_update: u32 = 0 };

        const Self = @This();

        pub fn initSlot(self: *Self, id: Id, curr_frame: u32) PoolSlot {
            assert(id != 0);

            var slot = N;

            if (curr_frame == 0) {
                // First frame, find first free slot
                for (self.items, 0..) |item, index| {
                    if (item.id == 0) {
                        slot = @as(PoolSlot, @intCast(index));
                        break;
                    }
                }
            } else {
                var frame = curr_frame;

                // Find the least recently updated item
                for (self.items, 0..) |item, index| {
                    if (item.last_update < frame) {
                        frame = item.last_update;
                        slot = @as(PoolSlot, @intCast(index));
                    }
                }
            }

            assert(slot < N);

            self.items[slot].id = id;
            self.items[slot].last_update = curr_frame;

            return slot;
        }

        pub fn getSlot(self: *Self, id: Id) ?PoolSlot {
            for (self.items, 0..) |item, index| {
                if (item.id == id) return @as(PoolSlot, @intCast(index));
            }

            return null;
        }

        pub fn updateSlot(self: *Self, index: PoolSlot, curr_frame: u32) void {
            assert(index < self.items.len);
            self.items[index].last_update = curr_frame;
        }

        pub fn freeSlot(self: *Self, index: PoolSlot) void {
            assert(index < self.items.len);
            self.items[index] = .{};
        }
    };
}

test "Pool" {
    const expect = std.testing.expect;

    var p = Pool(5){};

    try expect(p.getSlot(1) == null);

    try expect(p.initSlot(1, 0) == 0);
    try expect(p.initSlot(2, 0) == 1);

    try expect(p.getSlot(1).? == 0);
    try expect(p.getSlot(2).? == 1);

    try expect(p.initSlot(3, 5) == 0);
    try expect(p.getSlot(3).? == 0);

    p.updateSlot(0, 5);

    try expect(p.initSlot(4, 5) == 1);
    try expect(p.getSlot(4).? == 1);
}

/// Provide common operations for bitsets implemented as packed structs
fn BitSet(comptime Struct: type) type {
    const info = @typeInfo(Struct).Struct;
    const Int = info.backing_integer orelse unreachable;

    comptime {
        assert(info.layout == .Packed);
        assert(@sizeOf(Int) == @sizeOf(Struct));
    }

    return struct {
        pub inline fn none(a: Struct) bool {
            return toInt(a) == 0;
        }

        pub inline fn any(a: Struct) bool {
            return toInt(a) != 0;
        }

        pub inline fn toInt(self: Struct) Int {
            return @as(Int, @bitCast(self));
        }

        pub inline fn fromInt(value: Int) Struct {
            return @as(Struct, @bitCast(value));
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
