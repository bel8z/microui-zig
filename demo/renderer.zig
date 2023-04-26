const std = @import("std");
const assert = std.debug.assert;

const mu = @import("microui");
const atlas = mu.atlas;

const root = @import("root");

const c = @cImport({
    @cInclude(root.gl_h);
});

const Renderer = @This();

const buffer_size = 16384;

width: c_int,
height: c_int,
buf_idx: c_uint = 0,
tex_buf: [buffer_size * 8]f32,
vert_buf: [buffer_size * 8]i32,
color_buf: [buffer_size * 16]u8,
index_buf: [buffer_size * 6]c_uint,
font: mu.Font,

pub fn init(width: c_int, height: c_int, allocator: std.mem.Allocator) !*Renderer {
    var r = try allocator.create(Renderer);

    r.width = width;
    r.height = height;
    r.buf_idx = 0;

    // init gl
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glDisable(c.GL_CULL_FACE);
    c.glDisable(c.GL_DEPTH_TEST);
    c.glEnable(c.GL_SCISSOR_TEST);
    c.glEnable(c.GL_TEXTURE_2D);
    c.glEnableClientState(c.GL_VERTEX_ARRAY);
    c.glEnableClientState(c.GL_TEXTURE_COORD_ARRAY);
    c.glEnableClientState(c.GL_COLOR_ARRAY);

    // init texture
    var id: c_uint = undefined;
    c.glGenTextures(1, &id);
    c.glBindTexture(c.GL_TEXTURE_2D, id);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_ALPHA,
        atlas.width,
        atlas.height,
        0,
        c.GL_ALPHA,
        c.GL_UNSIGNED_BYTE,
        &atlas.texture[0],
    );
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    assert(c.glGetError() == 0);

    // Init font
    r.font = mu.Font{
        .ptr = null,
        .text_height = atlas.text_height,
        .text_width = getTextWidth,
    };

    return r;
}

fn getTextWidth(_: ?*anyopaque, text: []const u8) i32 {
    return atlas.getTextWidth(text);
}

pub fn flush(self: *Renderer) void {
    if (self.buf_idx == 0) return;

    c.glViewport(0, 0, self.width, self.height);
    c.glMatrixMode(c.GL_PROJECTION);
    c.glPushMatrix();
    c.glLoadIdentity();
    c.glOrtho(
        0.0,
        @intToFloat(f64, self.width),
        @intToFloat(f64, self.height),
        0.0,
        -1.0,
        1.0,
    );
    c.glMatrixMode(c.GL_MODELVIEW);
    c.glPushMatrix();
    c.glLoadIdentity();

    c.glTexCoordPointer(2, c.GL_FLOAT, 0, &self.tex_buf);
    c.glVertexPointer(2, c.GL_INT, 0, &self.vert_buf);
    c.glColorPointer(4, c.GL_UNSIGNED_BYTE, 0, &self.color_buf);
    c.glDrawElements(
        c.GL_TRIANGLES,
        @intCast(c_int, self.buf_idx * 6),
        c.GL_UNSIGNED_INT,
        &self.index_buf,
    );

    c.glMatrixMode(c.GL_MODELVIEW);
    c.glPopMatrix();
    c.glMatrixMode(c.GL_PROJECTION);
    c.glPopMatrix();

    self.buf_idx = 0;
}

pub fn drawRect(self: *Renderer, cmd: mu.command.RectCommand) void {
    const rect = cmd.rect;
    const color = cmd.color;

    if (cmd.opts.fill) {
        self.pushQuad(rect, atlas.white, color);
    } else {
        // NOTE (Matteo): This was part of the original microui implementation
        // I reviewed the drawing API in order to support both stroked and filled rects
        // (and ellipses), so this implementation detail moved to the rendering layer

        self.pushQuad(mu.Rect.init(
            rect.pt.x + 1,
            rect.pt.y,
            rect.sz.x - 2,
            1,
        ), atlas.white, color);

        self.pushQuad(mu.Rect.init(
            rect.pt.x + 1,
            rect.pt.y + rect.sz.y - 1,
            rect.sz.x - 2,
            1,
        ), atlas.white, color);

        self.pushQuad(mu.Rect.init(
            rect.pt.x,
            rect.pt.y,
            1,
            rect.sz.y,
        ), atlas.white, color);

        self.pushQuad(mu.Rect.init(
            rect.pt.x + rect.sz.x - 1,
            rect.pt.y,
            1,
            rect.sz.y,
        ), atlas.white, color);
    }
}

pub fn drawIcon(self: *Renderer, id: mu.Icon, rect: mu.Rect, color: mu.Color) void {
    const src = atlas.getIcon(id);
    var dst = mu.Rect{ .pt = rect.pt, .sz = src.sz };
    dst.pt.x += @divFloor(rect.sz.x - dst.sz.x, 2);
    dst.pt.y += @divFloor(rect.sz.y - dst.sz.y, 2);
    self.pushQuad(dst, src, color);
}

pub fn drawText(self: *Renderer, text: []const u8, pos: mu.Vec2, color: mu.Color) void {
    var dst = mu.Rect{ .pt = pos };
    for (text) |char| {
        const src = atlas.getGlyph(char);
        dst.sz = src.sz;
        self.pushQuad(dst, src, color);
        dst.pt.x += dst.sz.x;
    }
}

pub fn setClipRect(self: *Renderer, rect: mu.Rect) void {
    self.flush();
    c.glScissor(
        rect.pt.x,
        self.height - (rect.pt.y + rect.sz.y),
        rect.sz.x,
        rect.sz.y,
    );
}

pub fn clear(self: *Renderer, color: mu.Color) void {
    self.flush();

    const f = @as(f32, 1) / 255;
    c.glClearColor(
        @intToFloat(f32, color.r) * f,
        @intToFloat(f32, color.g) * f,
        @intToFloat(f32, color.b) * f,
        @intToFloat(f32, color.a) * f,
    );
    c.glClear(c.GL_COLOR_BUFFER_BIT);
}

fn pushQuad(self: *Renderer, dst: mu.Rect, src: mu.Rect, color: mu.Color) void {
    if (self.buf_idx == buffer_size) self.flush();

    const texvert_idx = self.buf_idx * 8;
    const color_idx = self.buf_idx * 16;
    const element_idx = self.buf_idx * 4;
    const index_idx = self.buf_idx * 6;

    self.buf_idx += 1;

    // update texture buffer
    const atlas_w = @intToFloat(f32, atlas.width);
    const atlas_h = @intToFloat(f32, atlas.height);
    const x = @intToFloat(f32, src.pt.x) / atlas_w;
    const y = @intToFloat(f32, src.pt.y) / atlas_h;
    const w = @intToFloat(f32, src.sz.x) / atlas_w;
    const h = @intToFloat(f32, src.sz.y) / atlas_h;
    self.tex_buf[texvert_idx + 0] = x;
    self.tex_buf[texvert_idx + 1] = y;
    self.tex_buf[texvert_idx + 2] = x + w;
    self.tex_buf[texvert_idx + 3] = y;
    self.tex_buf[texvert_idx + 4] = x;
    self.tex_buf[texvert_idx + 5] = y + h;
    self.tex_buf[texvert_idx + 6] = x + w;
    self.tex_buf[texvert_idx + 7] = y + h;

    // update vertex buffer
    self.vert_buf[texvert_idx + 0] = dst.pt.x;
    self.vert_buf[texvert_idx + 1] = dst.pt.y;
    self.vert_buf[texvert_idx + 2] = dst.pt.x + dst.sz.x;
    self.vert_buf[texvert_idx + 3] = dst.pt.y;
    self.vert_buf[texvert_idx + 4] = dst.pt.x;
    self.vert_buf[texvert_idx + 5] = dst.pt.y + dst.sz.y;
    self.vert_buf[texvert_idx + 6] = dst.pt.x + dst.sz.x;
    self.vert_buf[texvert_idx + 7] = dst.pt.y + dst.sz.y;

    // update color buffer
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        self.color_buf[color_idx + 4 * i + 0] = color.r;
        self.color_buf[color_idx + 4 * i + 1] = color.g;
        self.color_buf[color_idx + 4 * i + 2] = color.b;
        self.color_buf[color_idx + 4 * i + 3] = color.a;
    }

    // update index buffer
    self.index_buf[index_idx + 0] = element_idx + 0;
    self.index_buf[index_idx + 1] = element_idx + 1;
    self.index_buf[index_idx + 2] = element_idx + 2;
    self.index_buf[index_idx + 3] = element_idx + 2;
    self.index_buf[index_idx + 4] = element_idx + 3;
    self.index_buf[index_idx + 5] = element_idx + 1;
}
