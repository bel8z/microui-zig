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
const Id = mu.Id;

//============//

pub fn Stack(comptime T: type, comptime N: usize) type {
    return struct {
        items: [N]T = undefined,
        idx: usize = 0,

        const Self = @This();

        pub fn clear(self: *Self) void {
            self.idx = 0;
        }

        pub fn push(self: *Self, item: T) void {
            assert(self.idx < self.items.len);
            self.items[self.idx] = item;
            self.idx += 1;
        }

        pub fn pop(self: *Self) T {
            assert(self.idx > 0);
            self.idx -= 1;
            return self.items[self.idx];
        }

        pub fn peek(self: *Self) ?*T {
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

const PoolItem = struct { id: Id = undefined, last_update: u32 = 0 };

// TODO (Matteo): API review. At the moment multiple elements with the same ID
// can be stored - this does not happen if the expected usage, which is to always
// call 'get' before 'init', is followed, but this policy is not enforced in anyway.

pub fn Pool(comptime N: usize) type {
    return struct {
        items: [N]PoolItem = [_]PoolItem{.{}} ** N,

        const Self = @This();

        pub fn init(self: *Self, id: Id, curr_frame: u32) usize {
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

        pub fn update(self: *Self, index: usize, curr_frame: u32) void {
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

pub fn CommandList(comptime N: usize) type {
    return struct {
        buffer: [N]u8 align(alignment) = undefined,
        pos: usize = 0,

        const Self = @This();
        const alignment = @alignOf(mu.Command);

        pub fn clear(self: *Self) void {
            self.pos = 0;
        }

        pub fn push(self: *Self, id: mu.CommandId, size: usize) *mu.Command {
            assert(size < self.buffer.len);
            assert(self.pos < self.buffer.len - size);

            const next_pos = std.mem.alignForward(self.pos + size, alignment);

            var cmd = @ptrCast(*mu.Command, @alignCast(alignment, &self.buffer[self.pos]));
            cmd.base.type = id;
            cmd.base.size = next_pos - self.pos;

            self.pos = next_pos;

            return cmd;
        }

        pub fn head(self: *Self) *mu.Command {
            return @ptrCast(*mu.Command, @alignCast(alignment, &self.buffer[0]));
        }

        pub fn tail(self: *Self) *mu.Command {
            return @ptrCast(*mu.Command, @alignCast(alignment, &self.buffer[self.pos]));
        }
    };
}

test "CommandList" {
    var cmds = CommandList(4096){};
    _ = cmds.push(.Rect, @sizeOf(mu.RectCommand));
}

//============//

pub fn memberCount(comptime Enum: type) usize {
    return @typeInfo(Enum).Enum.fields.len;
}

test "memberCount" {
    const expect = std.testing.expect;
    try expect(memberCount(mu.ColorId) == 14);
}

//============//

/// Mixin for bitsets implemented as packed structs
pub fn BitSet(comptime Struct: type, comptime Int: type) type {
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
