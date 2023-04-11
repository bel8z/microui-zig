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

pub const CommandOptions = packed struct(u32) {
    fill: bool = true,
    _dummy: u31 = 0,
};

pub const TextCommand = struct { str: []const u8, font: *const Font, pos: Vec2, color: Color };
pub const IconCommand = struct { rect: Rect, color: Color, id: Icon };
pub const LineCommand = struct { p0: Vec2, p1: Vec2, color: Color };
pub const RectCommand = struct { rect: Rect, color: Color, opts: CommandOptions };
pub const CircCommand = struct { ellipse: Ellipse, color: Color, opts: CommandOptions };

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

    const alignment = @alignOf(u32);
    const tag_size: u32 = @sizeOf(CommandType);

    comptime {
        assert(alignment == @alignOf(CommandType));
        assert(alignment == @alignOf(TextEncoding));
        assert(@sizeOf(FontEncoding) == @sizeOf(*const Font));
    }

    fn encodingSize(cmd: Command) u32 {
        const size = tag_size + cmd.payloadSize();
        assert(std.mem.isAligned(size, alignment));
        return size;
    }

    fn encode(cmd: Command, buf: []u8, pos: u32) u32 {
        const size = cmd.payloadSize();

        assert(buf.len - pos >= tag_size + size);

        encodeTag(cmd, buf[pos..][0..tag_size]);

        const dst = buf[pos + tag_size ..][0..size];

        switch (cmd) {
            .None => unreachable,
            .Text => |text| {
                const meta_size = @sizeOf(TextEncoding);
                assert(text.str.len <= std.math.maxInt(u32));
                assert(size >= @sizeOf(TextEncoding) + text.str.len);

                // Store encoded data
                var enc = std.mem.bytesAsValue(TextEncoding, dst[0..meta_size]);
                enc.pos = text.pos;
                enc.font = FontEncoding.encode(text.font);
                enc.color = text.color;
                enc.len = @intCast(u32, text.str.len);
                assert(enc.font.decode() == text.font);

                // Store text
                assert(dst.len - meta_size >= text.str.len);
                std.mem.copy(u8, dst[meta_size..], text.str);
            },
            .User => |data| {
                const meta_size = @sizeOf(u32);
                assert(data.len <= std.math.maxInt(u32));
                assert(size >= meta_size + data.len);
                assert(buf.len - meta_size >= data.len);
                std.mem.writeIntLittle(u32, dst[0..meta_size], @intCast(u32, data.len));
                std.mem.copy(u8, dst[meta_size..], data);
            },
            inline else => |*payload| {
                const src = std.mem.asBytes(payload);
                std.mem.copy(u8, dst, src);
            },
        }

        return pos + tag_size + size;
    }

    fn decode(buf: []u8, pos: u32) Command {
        assert(buf.len - pos > tag_size);

        const cmd_type = decodeTag(buf[pos..][0..tag_size]);
        const src = buf[pos + tag_size ..];

        switch (cmd_type) {
            .None => unreachable,
            .Text => {
                const meta_size = @sizeOf(TextEncoding);

                // Read encoded data
                const enc = std.mem.bytesAsValue(TextEncoding, src[0..meta_size]);

                return .{ .Text = .{
                    .str = src[meta_size..][0..enc.len],
                    .pos = enc.pos,
                    .color = enc.color,
                    .font = enc.font.decode(),
                } };
            },
            .User => {
                const meta_size = @sizeOf(u32);
                const len = std.mem.readIntLittle(u32, src[0..meta_size]);
                return .{ .User = src[meta_size..][0..len] };
            },
            inline else => |header| {
                const T = std.meta.TagPayload(Command, header);
                const payload = std.mem.bytesToValue(T, src[0..@sizeOf(T)]);

                // TODO (Matteo): Is there a better way to achieve this?
                return switch (header) {
                    inline .Jump => .{ .Jump = payload },
                    inline .Clip => .{ .Clip = payload },
                    inline .Icon => .{ .Icon = payload },
                    inline .Line => .{ .Line = payload },
                    inline .Rect => .{ .Rect = payload },
                    inline .Circ => .{ .Circ = payload },
                    inline else => unreachable,
                };
            },
        }
    }

    fn payloadSize(cmd: Command) u32 {
        const size = switch (cmd) {
            .None => unreachable,
            .Text => |text| std.mem.alignForward(@sizeOf(TextEncoding) + text.str.len, alignment),
            .User => |data| std.mem.alignForward(@sizeOf(u32) + data.len, alignment),
            inline else => |payload| @sizeOf(@TypeOf(payload)),
        };

        assert(std.mem.isAligned(size, alignment));

        return @intCast(u32, size);
    }

    inline fn encodeTag(tag: Command, buf: []u8) void {
        assert(buf.len == tag_size);
        const int = @enumToInt(@as(CommandType, tag));
        std.mem.writeIntLittle(u32, buf[0..tag_size], int);
    }

    inline fn decodeTag(buf: []const u8) CommandType {
        assert(buf.len == tag_size);
        return @intToEnum(
            CommandType,
            std.mem.readIntLittle(u32, buf[0..tag_size]),
        );
    }

    const TextEncoding = extern struct {
        pos: Vec2,
        color: Color,
        len: u32,
        font: FontEncoding,
    };

    // NOTE (Matteo): Use a fixed-width integer for stable memory layout (This is
    // required mainly for portable serialization, but is this an atual need?)
    const FontEncoding = switch (@sizeOf(*const Font)) {
        @sizeOf(u32) => extern struct {
            ptr: u32,

            pub fn encode(ptr: *const Font) FontEncoding {
                return .{ .ptr = @intCast(@ptrToInt(ptr), u32) };
            }

            fn decode(enc: FontEncoding) *const Font {
                return @intToPtr(*const Font, enc);
            }
        },
        @sizeOf(u64) => extern struct {
            ab: u32,
            cd: u32,

            pub fn encode(ptr: *const Font) FontEncoding {
                const int = @ptrToInt(ptr);
                return .{
                    .ab = @intCast(u32, (int >> 32) & 0xFFFFFFFF),
                    .cd = @intCast(u32, int & 0xFFFFFFFF),
                };
            }

            pub fn decode(enc: FontEncoding) *const Font {
                const int = @intCast(usize, enc.ab) << 32 | @intCast(usize, enc.cd);
                return @intToPtr(*const Font, int);
            }
        },
        else => {},
    };
};

pub const Error = std.mem.Allocator.Error;

// TODO (Matteo): Review - The storage implementation here is a bit ugly.
// The idea is to encode commands in a (not very much) packed format, so all
// data is aligned on 32 bit boundaries. During iteration commands are decoded
// in a more user-friendly tagged union type.
pub fn CommandList(comptime N: u32) type {
    return struct {
        buffer: [N]u8 align(Command.alignment) = undefined,
        tail: u32 = tail_init,

        // NOTE (Matteo): Append starts after 'alignment' bytes in order to
        // have 0 represent an invalid handle. I found wasting 4 bytes is worth
        // avoiding the hassle with nullable offsets...
        const tail_init = Command.alignment;

        const Self = @This();

        //=== Basic API ===//

        pub inline fn clear(self: *Self) void {
            self.tail = tail_init;
        }

        pub fn push(self: *Self, cmd: Command) Error!u32 {
            const size = cmd.encodingSize();
            const pos = self.tail;
            if (N - pos < size) return Error.OutOfMemory;

            self.tail = cmd.encode(&self.buffer, pos);

            assert(pos != 0);
            return pos;
        }

        //=== Jump ===//

        // TODO (Matteo): Review - I'm not very happy with the jump implementation
        // since it entangles CommandList with the main ui context.
        // Maybe this separation of data structures was not a good idea...

        pub fn pushJump(self: *Self) Error!u32 {
            // NOTE (Matteo): Enforce a loop by default
            const tail_pos = self.tail;
            const jump_pos = try self.push(.{ .Jump = tail_pos });

            assert(tail_pos == jump_pos);

            return jump_pos;
        }

        pub fn setJump(self: *Self, jump: u32, dest: u32) void {
            // TODO (Matteo): Review - Optimize
            var cmd = Command.decode(&self.buffer, jump);
            assert(cmd == .Jump);
            cmd.Jump = dest;
            _ = cmd.encode(&self.buffer, jump);
        }

        pub fn nextCommand(self: *Self, pos: u32) u32 {
            if (pos == self.tail) return pos;

            // TODO (Matteo): Review - Optimize
            const cmd = Command.decode(&self.buffer, pos);
            const next_pos = pos + cmd.encodingSize();

            assert(std.mem.isAligned(next_pos, Command.alignment));
            return next_pos;
        }

        //=== Iteration ===//

        pub inline fn iter(self: *Self) Iterator {
            return Iterator{ .list = self };
        }

        const Iterator = struct {
            list: *Self,
            pos: u32 = tail_init,

            pub fn next(self: *Iterator) Command {
                while (self.pos != self.list.tail) {
                    const cmd = Command.decode(&self.list.buffer, self.pos);

                    switch (cmd) {
                        .None => unreachable,
                        .Jump => |dest| self.pos = dest,
                        else => {
                            self.pos += cmd.encodingSize();
                            return cmd;
                        },
                    }
                }

                return .None;
            }
        };

        //=== High-level push API ===//

        pub fn pushClip(self: *Self, rect: Rect) Error!void {
            _ = try self.push(.{ .Clip = rect });
        }

        pub fn pushText(
            self: *Self,
            str: []const u8,
            pos: Vec2,
            color: Color,
            font: *const Font,
        ) Error!void {
            _ = try self.push(.{ .Text = .{
                .str = str,
                .pos = pos,
                .color = color,
                .font = font,
            } });
        }

        pub fn pushIcon(self: *Self, id: Icon, rect: Rect, color: Color) Error!void {
            _ = try self.push(.{ .Icon = .{ .id = id, .rect = rect, .color = color } });
        }

        pub fn pushLine(self: *Self, p0: Vec2, p1: Vec2, color: Color) Error!void {
            _ = try self.push(.{ .Line = .{ .p0 = p0, .p1 = p1, .color = color } });
        }

        pub fn pushRect(
            self: *Self,
            rect: Rect,
            color: Color,
            opts: CommandOptions,
        ) Error!void {
            _ = try self.push(.{ .Rect = .{
                .rect = rect,
                .color = color,
                .opts = opts,
            } });
        }

        pub fn pushEllipse(
            self: *Self,
            ellipse: Ellipse,
            color: Color,
            opts: CommandOptions,
        ) Error!void {
            _ = try self.push(.{ .Circ = .{
                .ellipse = ellipse,
                .color = color,
                .opts = opts,
            } });
        }

        pub inline fn pushCircle(
            self: *Self,
            center: Vec2,
            radius: Vec2,
            color: Color,
            opts: CommandOptions,
        ) Error!void {
            try self.pushEllipse(center, Ellipse.circle(center, radius), color, opts);
        }
    };
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
