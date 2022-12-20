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
const Color = mu.Color;
const Icon = mu.Icon;
const Font = mu.Font;

pub const CommandType = enum(u16) {
    None,
    Jump,
    Clip,
    Rect,
    Text,
    Icon,
    _,
};

// TODO (Matteo): Rethink command implementation.
// The current solution works pretty well in C but seems a bit foreign in Zig;
// furthermore, I'd like to provide easy extension with user-defined commands.

pub const BaseCommand = extern struct { type: CommandType, size: CommandHandle };
pub const JumpCommand = extern struct { base: BaseCommand, dst: CommandHandle };
pub const ClipCommand = extern struct { base: BaseCommand, rect: Rect };
pub const RectCommand = extern struct { base: BaseCommand, rect: Rect, color: Color };
pub const IconCommand = extern struct { base: BaseCommand, rect: Rect, id: Icon, color: Color };

pub const TextCommand = extern struct {
    base: BaseCommand,
    font: *const Font,
    pos: Vec2,
    color: Color,
    len: CommandHandle,

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

pub const CommandHandle = u32;

pub fn CommandList(comptime N: u32) type {
    return struct {
        buffer: [N]u8 align(alignment) = undefined,
        tail: CommandHandle = 0,

        const alignment = @alignOf(Command);
        const Self = @This();

        const Iterator = struct {
            list: *Self,
            pos: CommandHandle = 0,

            pub fn next(self: *Iterator) ?*const Command {
                while (self.pos != self.list.tail) {
                    const cmd = self.list.get(self.pos);

                    if (cmd.base.type == .Jump) {
                        self.pos = cmd.jump.dst;
                    } else {
                        self.pos += cmd.base.size;
                        return cmd;
                    }
                }

                return null;
            }
        };

        pub inline fn clear(self: *Self) void {
            self.tail = 0;
        }

        pub inline fn get(self: *Self, pos: CommandHandle) *Command {
            return @ptrCast(*Command, @alignCast(alignment, &self.buffer[pos]));
        }

        pub inline fn iter(self: *Self) Iterator {
            return Iterator{ .list = self };
        }

        pub fn pushJump(self: *Self) !CommandHandle {
            const pos = try self.pushCmd(.Jump);
            self.get(pos).jump.dst = 0;
            return pos;
        }

        pub fn pushClip(self: *Self, rect: Rect) !void {
            const pos = try self.pushCmd(.Clip);
            var cmd = self.get(pos);
            cmd.clip.rect = rect;
        }

        pub fn pushRect(self: *Self, rect: Rect, color: Color) !void {
            const pos = try self.pushCmd(.Rect);
            var cmd = self.get(pos);
            cmd.rect.rect = rect;
            cmd.rect.color = color;
        }

        pub fn pushIcon(self: *Self, id: Icon, rect: Rect, color: Color) !void {
            const pos = try self.pushCmd(.Icon);
            var cmd = self.get(pos);
            cmd.icon.id = id;
            cmd.icon.rect = rect;
            cmd.icon.color = color;
        }

        pub fn pushText(
            self: *Self,
            str: []const u8,
            pos: Vec2,
            color: Color,
            font: *Font,
        ) !void {
            assert(str.len <= std.math.maxInt(CommandHandle));

            const header_size = @sizeOf(TextCommand);
            const full_size = header_size + str.len;
            const offset = try self.pushSize(.Text, full_size);

            var cmd = self.get(offset);
            cmd.text.pos = pos;
            cmd.text.font = font;
            cmd.text.color = color;
            cmd.text.len = @intCast(CommandHandle, str.len);

            var buf = self.buffer[offset + header_size .. offset + full_size];

            assert(buf.len == str.len);

            std.mem.copy(u8, buf, str);
        }

        pub fn pushCmd(self: *Self, comptime cmd_type: CommandType) !CommandHandle {
            const cmd_name = @tagName(cmd_type);

            const cmd_struct = switch (cmd_type) {
                .Jump => JumpCommand,
                .Clip => ClipCommand,
                .Rect => RectCommand,
                .Icon => IconCommand,
                .Text => @compileError(cmd_name ++ " requires explicit size to push"),
                else => @compileError(cmd_name ++ " command is not supported"),
            };

            return self.pushSize(cmd_type, @sizeOf(cmd_struct));
        }

        pub fn pushSize(self: *Self, cmd_type: CommandType, size: usize) !CommandHandle {
            if (size > self.buffer.len) return error.OutOfMemory;
            if (self.tail > self.buffer.len - size) return error.OutOfMemory;

            const curr_pos = self.tail;
            assert(std.mem.isAligned(curr_pos, alignment));

            const next_tail = std.mem.alignForward(curr_pos + size, alignment);
            if (next_tail > self.buffer.len) return error.OutOfMemory;

            self.tail = @intCast(CommandHandle, next_tail);

            var cmd = self.get(curr_pos);
            cmd.base.type = cmd_type;
            cmd.base.size = self.tail - curr_pos;

            return curr_pos;
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
