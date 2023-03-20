//
// MicroUI - Zig version
//
// Based on  https://github.com/rxi/microui - see end of file for license information
//
// This files contains utility code
//

const std = @import("std");
const assert = std.debug.assert;

const mu = @import("microui.zig");
const Vec2 = mu.Vec2;
const Rect = mu.Rect;
const Ellipse = mu.Ellipse;
const Color = mu.Color;
const Icon = mu.Icon;
const Font = mu.Font;

// TODO (Matteo): Review - 'None' is used purely to stop the iteration of commands;
// I opted for this instead of an optional return value because there's room in the
// tag to store the information (don't know if the Zig compiler can do the trick on its own)
pub const CommandType = enum(u32) {
    None,
    Jump,
    Clip,
    Text,
    Icon,
    Line,
    Rect,
    Circ,
    User,
};

pub const Command = union(CommandType) {
    None,
    Jump: u32,
    Clip: Rect,
    Text: TextCommand,
    Icon: IconCommand,
    Line: LineCommand,
    Rect: RectCommand,
    Circ: CircCommand,
    User: []const u8,
};

pub const TextCommand = struct { str: []const u8, font: *const Font, pos: Vec2, color: Color };
pub const IconCommand = struct { rect: Rect, color: Color, id: Icon };
pub const LineCommand = struct { p0: Vec2, p1: Vec2, color: Color };
pub const RectCommand = struct { rect: Rect, color: Color, opts: CommandOptions };
pub const CircCommand = struct { ellipse: Ellipse, color: Color, opts: CommandOptions };

pub const CommandOptions = packed struct(u32) {
    fill: bool = true,
    _dummy: u31 = 0,
};

// TODO (Matteo): Review - The storage implementation here is a bit ugly.
// The idea is to encode commands in a (not very much) packed format, so all
// data is aligned on 32 bit boundaries. During iteration commands are decoded
// in a more user-friendly tagged union type.
pub fn CommandList(comptime N: u32) type {
    return struct {
        buffer: [N]u8 align(alignment) = undefined,
        tail: u32 = 0,

        const header_size = @sizeOf(CommandType);
        const alignment = @alignOf(u32);
        const Self = @This();

        //=== Basic API ===//

        pub inline fn clear(self: *Self) void {
            self.tail = 0;
        }

        pub fn pushCmd(self: *Self, comptime cmd_type: CommandType) !*CommandPayload(cmd_type) {
            const T = CommandPayload(cmd_type);
            comptime assert(@alignOf(T) == alignment);

            const size = @sizeOf(T);
            const pos = try self.pushSize(cmd_type, size);
            return self.getPtr(T, pos);
        }

        fn CommandPayload(comptime cmd_type: CommandType) type {
            const cmd_name = @tagName(cmd_type);
            const cmd_fields = @typeInfo(Command).Union.fields;

            switch (cmd_type) {
                .Jump => @compileError(cmd_name ++ " requires explicit call to pushJump"),
                .Text => @compileError(cmd_name ++ " requires explicit call to pushText"),
                .User => @compileError(cmd_name ++ " requires explicit call to pushUser"),
                .None => @compileError(cmd_name ++ " command is not supported"),
                inline else => return cmd_fields[@enumToInt(cmd_type)].field_type,
            }
        }

        fn pushSize(self: *Self, cmd_type: CommandType, size: usize) !u32 {
            if (size > self.buffer.len) return error.OutOfMemory;

            // Compute payload offset and check available storage
            const payload_pos = self.tail + header_size;
            assert(std.mem.isAligned(payload_pos, alignment));
            if (self.buffer.len - self.tail < payload_pos + size) return error.OutOfMemory;

            // Write header at current offset
            assert(std.mem.isAligned(self.tail, alignment));
            const header = std.mem.bytesAsValue(CommandType, self.buffer[self.tail..][0..header_size]);
            header.* = cmd_type;

            // Move tail forward
            self.tail = alignPos(payload_pos + size);
            assert(self.tail <= self.buffer.len);

            return payload_pos;
        }

        fn getPtr(self: *Self, comptime T: type, offset: u32) *T {
            assert(offset < self.tail);
            assert(std.mem.isAligned(offset, alignment));
            const bytes = @alignCast(alignment, self.buffer[offset..][0..@sizeOf(T)]);
            return std.mem.bytesAsValue(T, bytes);
        }

        fn getValue(self: *Self, comptime T: type, offset: u32) T {
            assert(offset < self.tail);
            assert(std.mem.isAligned(offset, alignment));
            const bytes = @alignCast(alignment, self.buffer[offset..][0..@sizeOf(T)]);
            return std.mem.bytesToValue(T, bytes);
        }

        fn alignPos(pos: anytype) u32 {
            return @intCast(u32, std.mem.alignForward(pos, alignment));
        }

        //=== Jump ===//

        // TODO (Matteo): Review - I'm not very happy with the jump implementation
        // since it entangles CommandList with the main ui context.
        // Maybe this separation of data structures was not a good idea...

        pub fn pushJump(self: *Self) !u32 {
            const handle = self.tail;

            const size = @sizeOf(u32);
            const jump = try self.pushSize(.Jump, size);
            const ptr = self.getPtr(u32, jump);
            ptr.* = 0;

            return handle;
        }

        pub fn setJumpLocation(self: *Self, handle: u32, dest: u32) void {
            assert(self.getValue(CommandType, handle) == .Jump);

            const offset = handle + header_size;
            const ptr = self.getPtr(u32, offset);
            ptr.* = dest;
        }

        pub fn getNextLocation(self: *Self, pos: u32) u32 {
            if (pos == self.tail) return pos;

            const next_pos = switch (self.getValue(CommandType, pos)) {
                .None => unreachable,
                .Jump => block: {
                    break :block pos + header_size + @sizeOf(u32);
                },
                .Text => block: {
                    const payload_pos = pos + header_size;
                    const payload = self.getPtr(TextPayload, payload_pos);
                    // NOTE (Matteo): Location is aligned after text insertion (see pushText)
                    break :block alignPos(payload_pos + @sizeOf(TextPayload) + payload.len);
                },
                .User => block: {
                    const data_pos = pos + header_size;
                    const data_len = self.getValue(u32, data_pos);
                    // NOTE (Matteo): Location is aligned after data insertion (see pushUser)
                    break :block alignPos(data_pos + @sizeOf(u32) + data_len);
                },
                inline else => |header| block: {
                    const T = CommandPayload(header);
                    break :block pos + header_size + @sizeOf(T);
                },
            };

            assert(std.mem.isAligned(next_pos, alignment));

            return next_pos;
        }

        //=== Text ===//

        pub fn pushText(
            self: *Self,
            str: []const u8,
            pos: Vec2,
            color: Color,
            font: *const Font,
        ) !void {
            assert(str.len <= std.math.maxInt(u32));

            // Push enough storage for the full payload
            const payload_size = @sizeOf(TextPayload);
            const full_size = payload_size + str.len;
            const offset = try self.pushSize(.Text, full_size);
            var bytes = self.buffer[offset..][0..full_size];

            // Store payload data
            var cmd = std.mem.bytesAsValue(TextPayload, bytes[0..payload_size]);
            cmd.pos = pos;
            cmd.font = FontHandle.encode(font);
            cmd.color = color;
            cmd.len = @intCast(u32, str.len);

            assert(cmd.font.decode() == font);

            // Store text
            var buf = bytes[payload_size..];
            assert(buf.len == str.len);
            std.mem.copy(u8, buf, str);
        }

        const TextPayload = struct {
            font: FontHandle,
            pos: Vec2,
            color: Color,
            len: u32,
        };

        // NOTE (Matteo): Use a fixed-width integer for stable memory layout (This is
        // required mainly for portable serialization, but is this an atual need?)
        const FontHandle = switch (@sizeOf(*const Font)) {
            4 => struct {
                ptr: u32,

                pub inline fn encode(ptr: *const Font) FontHandle {
                    return .{ .ptr = @intCast(@ptrToInt(ptr), u32) };
                }

                pub inline fn decode(handle: FontHandle) *const Font {
                    return @intToPtr(*const Font, handle.ptr);
                }
            },
            8 => struct {
                ptr: [2]u32,

                pub inline fn encode(ptr: *const Font) FontHandle {
                    const int = @ptrToInt(ptr);
                    return .{ .ptr = .{
                        @intCast(u32, (int >> 32) & 0xFFFFFFFF),
                        @intCast(u32, int & 0xFFFFFFFF),
                    } };
                }

                pub inline fn decode(handle: FontHandle) *const Font {
                    const int = @intCast(usize, handle.ptr[0]) << 32 | @intCast(usize, handle.ptr[1]);
                    return @intToPtr(*const Font, int);
                }
            },
            else => unreachable,
        };

        //=== Iteration ===//

        pub inline fn iter(self: *Self) Iterator {
            return Iterator{ .list = self };
        }

        const Iterator = struct {
            list: *Self,
            pos: u32 = 0,

            pub fn next(self: *Iterator) Command {
                while (self.pos != self.list.tail) {
                    const curr_pos = self.pos;
                    const data_pos = curr_pos + header_size;

                    assert(std.mem.isAligned(data_pos, alignment));

                    self.pos = self.list.getNextLocation(curr_pos);

                    switch (self.list.getValue(CommandType, curr_pos)) {
                        .None => unreachable,
                        .Jump => {
                            self.pos = self.list.getValue(u32, data_pos);
                        },
                        .Text => {
                            const payload = self.list.getPtr(TextPayload, data_pos);

                            return .{ .Text = .{
                                .str = self.list.buffer[data_pos + @sizeOf(TextPayload) ..][0..payload.len],
                                .font = payload.font.decode(),
                                .color = payload.color,
                                .pos = payload.pos,
                            } };
                        },
                        .User => {
                            const data_len = self.list.getValue(u32, data_pos);
                            return .{ .User = self.list.buffer[data_pos + @sizeOf(u32) ..][0..data_len] };
                        },
                        inline else => |header| {
                            const T = CommandPayload(header);
                            const payload = self.list.getValue(T, data_pos);

                            return switch (header) {
                                .Clip => .{ .Clip = payload },
                                .Icon => .{ .Icon = payload },
                                .Line => .{ .Line = payload },
                                .Rect => .{ .Rect = payload },
                                .Circ => .{ .Circ = payload },
                                .User => .{ .User = payload },
                                else => unreachable,
                            };
                        },
                    }
                }

                return .None;
            }
        };

        //=== Custom command ===//

        pub fn pushUser(
            self: *Self,
            data: []const u8,
        ) !void {
            assert(data.len <= std.math.maxInt(u32));

            // Push enough storage for the full payload
            const payload_size = @sizeOf(u32);
            const full_size = payload_size + data.len;
            const offset = try self.pushSize(.User, full_size);
            var bytes = self.buffer[offset..][0..full_size];

            // Store data length
            const len = std.mem.bytesAsValue(u32, bytes[0..payload_size]);
            len.* = @intCast(u32, data.len);

            // Store data
            var buf = bytes[payload_size..];
            assert(buf.len == data.len);
            std.mem.copy(u8, buf, data);
        }

        //=== High-level push API ===//

        pub fn pushClip(self: *Self, rect: Rect) !void {
            var cmd = try self.pushCmd(.Clip);
            cmd.* = rect;
        }

        pub fn pushIcon(self: *Self, id: Icon, rect: Rect, color: Color) !void {
            var cmd = try self.pushCmd(.Icon);
            cmd.id = id;
            cmd.rect = rect;
            cmd.color = color;
        }

        pub fn pushLine(self: *Self, p0: Vec2, p1: Vec2, color: Color) !void {
            var cmd = try self.pushCmd(.Line);
            cmd.p0 = p0;
            cmd.p1 = p1;
            cmd.color = color;
        }

        pub fn pushRect(self: *Self, rect: Rect, color: Color, opts: CommandOptions) !void {
            var cmd = try self.pushCmd(.Rect);
            cmd.rect = rect;
            cmd.color = color;
            cmd.opts = opts;
        }

        pub fn pushEllipse(
            self: *Self,
            ellipse: Ellipse,
            color: Color,
            opts: CommandOptions,
        ) !void {
            var cmd = try self.pushCmd(.Circ);
            cmd.ellipse = ellipse;
            cmd.color = color;
            cmd.fill = opts;
        }

        pub inline fn pushCircle(
            self: *Self,
            center: Vec2,
            radius: Vec2,
            color: Color,
            opts: CommandOptions,
        ) !void {
            try self.pushEllipse(center, Ellipse.circle(center, radius), color, opts);
        }
    };
}

test "CommandList" {
    var cmds = CommandList(4096){};
    _ = cmds.pushSize(.Rect, @sizeOf(RectCommand));
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
