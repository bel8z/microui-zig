const std = @import("std");
const win32 = std.os.windows;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const WINAPI = win32.WINAPI;

pub const gl_h = "GL/gl.h";

const mu = @import("microui");
const Ui = mu.Ui(.{});
const Font = mu.Font;

const demo = @import("demo.zig");

const Renderer = @import("renderer.zig");

const custom_theme = false;

var ui: *Ui = undefined;
var input: mu.Input = undefined;
var renderer: *Renderer = undefined;
var bg = mu.Color{ .r = 90, .g = 95, .b = 100, .a = 255 };

pub fn main() !void {
    const ui_alloc = std.heap.page_allocator;

    // Initialize Windows OpenGL support
    _ = try wgl.init();

    // Create main window
    const win_name = L("Microui demo");

    const win_class = win32.user32.WNDCLASSEXW{
        .style = 0,
        .lpfnWndProc = wndProc,
        .hInstance = wgl.getCurrentInstance(),
        .lpszClassName = win_name,
        // Default arrow
        .hCursor = getDefaultCursor(),
        // Don't erase background
        .hbrBackground = null,
        // No icons available
        .hIcon = null,
        .hIconSm = null,
        // No menu
        .lpszMenuName = null,
    };

    _ = try win32.user32.registerClassExW(&win_class);

    var win_flags = win32.user32.WS_OVERLAPPEDWINDOW & ~@as(u32, win32.user32.WS_SIZEBOX);
    const window = try win32.user32.createWindowExW(
        0,
        win_name,
        win_name,
        win_flags,
        win32.user32.CW_USEDEFAULT,
        win32.user32.CW_USEDEFAULT,
        800,
        600,
        null,
        null,
        win_class.hInstance,
        null,
    );

    // Create OpenGL context
    const dc = try win32.user32.getDC(window);
    defer _ = win32.user32.releaseDC(window, dc);

    const ctx = try wgl.createContext(dc, 1, 0);
    _ = try wgl.makeCurrent(dc, ctx);

    // NOTE (Matteo): VSync is disabled because the frames are painted only
    // in response to events, not in a continous render loop
    try wgl.setSwapInterval(0);

    // init renderer
    const size = getClientSize(window);
    renderer = try Renderer.init(size.x, size.y, ui_alloc);
    defer ui_alloc.destroy(renderer);

    // init microui
    ui = try ui_alloc.create(Ui);
    ui.init(&renderer.font, null);
    input = ui.getInput();

    // NOTE (Matteo): Theming attempt
    var style = ui._style;
    if (custom_theme) {
        style.setColor(.Text, rgba(0.90, 0.90, 0.90, 1.00));
        style.setColor(.Border, rgba(0.54, 0.57, 0.51, 0.50));
        style.setColor(.BorderShadow, rgba(0.14, 0.16, 0.11, 0.52));
        style.setColor(.TitleBg, rgba(0.24, 0.27, 0.20, 1.00));
        style.setColor(.TitleText, style.getColor(.Text));
        style.setColor(.WindowBg, rgba(0.29, 0.34, 0.26, 1.00));
        style.setColor(.Header, rgba(0.35, 0.42, 0.31, 1.00));
        style.setColor(.HeaderHover, rgba(0.35, 0.42, 0.31, 0.60));
        style.setColor(.HeaderFocus, rgba(0.54, 0.57, 0.51, 0.50));
        style.setColor(.Button, rgba(0.29, 0.34, 0.26, 0.40));
        style.setColor(.ButtonHover, rgba(0.35, 0.42, 0.31, 1.00));
        style.setColor(.ButtonFocus, rgba(0.54, 0.57, 0.51, 0.50));
        style.setColor(.Base, rgba(0.29, 0.34, 0.26, 1.00));
        style.setColor(.Base, rgba(0.24, 0.27, 0.20, 1.00));
        style.setColor(.BaseHover, rgba(0.27, 0.30, 0.23, 1.00));
        style.setColor(.BaseFocus, rgba(0.30, 0.34, 0.26, 1.00));
        style.setColor(.ScrollBase, rgba(0.35, 0.42, 0.31, 1.00));
        style.setColor(.ScrollThumb, rgba(0.23, 0.27, 0.21, 1.00));
        // style.setColor(.ScrollThumb, rgba(0.25, 0.30, 0.22, 1.00));
        // style.setColor(.ScrollThumb, rgba(0.28, 0.32, 0.24, 1.00));
    }
    ui.style = &style;

    // Show window
    _ = win32.user32.showWindow(window, win32.user32.SW_SHOWDEFAULT);
    try win32.user32.updateWindow(window);

    // main loop
    var msg: win32.user32.MSG = undefined;

    while (true) {
        win32.user32.getMessageW(&msg, null, 0, 0) catch |err| switch (err) {
            error.Quit => break,
            else => return err,
        };

        _ = win32.user32.translateMessage(&msg);
        _ = win32.user32.dispatchMessageW(&msg);
    }
}

fn wndProc(
    win: win32.HWND,
    msg: u32,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(WINAPI) win32.LRESULT {
    switch (msg) {
        win32.user32.WM_CLOSE => {
            if (wgl.getCurrentContext()) |context| {
                wgl.deleteContext(context) catch unreachable;
            }
            win32.user32.destroyWindow(win) catch unreachable;
        },
        win32.user32.WM_DESTROY => {
            win32.user32.PostQuitMessage(0);
        },
        win32.user32.WM_PAINT => {
            // NOTE (Matteo): We need to call this not only for obtaining the DC
            // required for swapping buffers, but also to notify the system that
            // we performed the painting so another WM_PAINT message would not
            // be sent until the window is invalidated again
            var ps: PAINTSTRUCT = undefined;
            const dc = BeginPaint(win, &ps) orelse unreachable;
            defer _ = EndPaint(win, &ps);

            // process frame
            {
                const size = getClientSize(win);
                ui.beginFrame(&input, size) catch unreachable;
                defer ui.endFrame();
                demo.frame(ui, &bg) catch unreachable;
            }

            // render
            renderer.clear(bg);
            var iter = ui.command_list.iter();
            while (true) {
                switch (iter.next()) {
                    .None => break,
                    .Clip => |cmd| renderer.setClipRect(cmd),
                    .Icon => |cmd| renderer.drawIcon(cmd.id, cmd.rect, cmd.color),
                    .Rect => |cmd| renderer.drawRect(cmd),
                    .Text => |cmd| {
                        std.debug.assert(cmd.font == &renderer.font);
                        renderer.drawText(cmd.str, cmd.pos, cmd.color);
                    },
                    else => unreachable,
                }
            }
            renderer.flush();

            wgl.swapBuffers(dc) catch {};
        },
        win32.user32.WM_MOUSEMOVE => {
            input.mouseMove(getMousePos(lparam));
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        win32.user32.WM_LBUTTONDOWN => {
            input.mouseDown(getMousePos(lparam), .{ .left = true });
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        win32.user32.WM_MBUTTONDOWN => {
            input.mouseDown(getMousePos(lparam), .{ .middle = true });
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        win32.user32.WM_RBUTTONDOWN => {
            input.mouseDown(getMousePos(lparam), .{ .right = true });
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        win32.user32.WM_LBUTTONUP => {
            input.mouseUp(getMousePos(lparam), .{ .left = true });
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        win32.user32.WM_MBUTTONUP => {
            input.mouseUp(getMousePos(lparam), .{ .middle = true });
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        win32.user32.WM_RBUTTONUP => {
            input.mouseUp(getMousePos(lparam), .{ .right = true });
            _ = InvalidateRect(win, null, win32.TRUE);
        },
        else => return win32.user32.defWindowProcW(win, msg, wparam, lparam),
    }

    return 0;
}

fn rgba(r: f32, g: f32, b: f32, a: f32) mu.Color {
    return .{
        .r = @as(u8, @intFromFloat(std.math.clamp(r * 255, 0, 255))),
        .g = @as(u8, @intFromFloat(std.math.clamp(g * 255, 0, 255))),
        .b = @as(u8, @intFromFloat(std.math.clamp(b * 255, 0, 255))),
        .a = @as(u8, @intFromFloat(std.math.clamp(a * 255, 0, 255))),
    };
}

// Windows specific stuff

fn getMousePos(lparam: win32.LPARAM) mu.Vec2 {
    return .{
        .x = @as(i32, @intCast(0xFFFF & lparam)),
        .y = @as(i32, @intCast(0xFFFF & (lparam >> 16))),
    };
}

fn getClientSize(win: win32.HWND) mu.Vec2 {
    var r: win32.RECT = undefined;
    _ = GetClientRect(win, &r);
    return .{ .x = r.right - r.left, .y = r.bottom - r.top };
}

fn getDefaultCursor() ?win32.HCURSOR {
    const name = @as(win32.LPCWSTR, @ptrFromInt(32512));
    return LoadCursorW(null, name);
}

const PAINTSTRUCT = extern struct {
    hdc: win32.HDC,
    fErase: win32.BOOL,
    rcPaint: win32.RECT,
    fRestore: win32.BOOL,
    fIncUpdate: win32.BOOL,
    rgbReserved: [32]u8,
};

extern "user32" fn BeginPaint(
    hwnd: win32.HWND,
    paint: *PAINTSTRUCT,
) callconv(win32.WINAPI) ?win32.HDC;

extern "user32" fn EndPaint(
    hwnd: win32.HWND,
    paint: *const PAINTSTRUCT,
) callconv(win32.WINAPI) win32.BOOL;

extern "user32" fn LoadCursorW(
    hinst: ?win32.HINSTANCE,
    cursor_name: win32.LPCWSTR,
) callconv(WINAPI) ?win32.HCURSOR;

extern "user32" fn InvalidateRect(
    hWnd: win32.HWND,
    lpRect: ?*const win32.RECT,
    bErase: win32.BOOL,
) callconv(WINAPI) win32.BOOL;

extern fn GetClientRect(
    win: win32.HWND,
    out_rect: *win32.RECT,
) callconv(WINAPI) win32.BOOL;

// Keep WGL specific stuff in its own namespace

const wgl = struct {
    // See https://www.khronos.org/registry/OpenGL/extensions/ARB/WGL_ARB_create_context.txt for all
    // values
    const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
    const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
    const WGL_CONTEXT_FLAGS_ARB = 0x2094;
    const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
    const WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;
    const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;
    const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
    const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;
    // See https://www.khronos.org/registry/OpenGL/extensions/ARB/WGL_ARB_pixel_format.txt for all
    // values
    const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
    const WGL_ACCELERATION_ARB = 0x2003;
    const WGL_SUPPORT_OPENGL_ARB = 0x2010;
    const WGL_DOUBLE_BUFFER_ARB = 0x2011;
    const WGL_PIXEL_TYPE_ARB = 0x2013;
    const WGL_COLOR_BITS_ARB = 0x2014;
    const WGL_DEPTH_BITS_ARB = 0x2022;
    const WGL_STENCIL_BITS_ARB = 0x2023;
    // See https://registry.khronos.org/OpenGL/extensions/ARB/WGL_ARB_pixel_format.txt
    const WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB = 0x20A9;

    const WGL_FULL_ACCELERATION_ARB = 0x2027;
    const WGL_TYPE_RGBA_ARB = 0x202B;

    const PFD_TYPE_RGBA = 0;

    const PFD_MAIN_PLANE = 0;

    const PFD_DRAW_TO_WINDOW = 0x00000004;
    const PFD_DRAW_TO_BITMAP = 0x00000008;
    const PFD_SUPPORT_GDI = 0x00000010;
    const PFD_SUPPORT_OPENGL = 0x00000020;
    const PFD_GENERIC_ACCELERATED = 0x00001000;
    const PFD_GENERIC_FORMAT = 0x00000040;
    const PFD_NEED_PALETTE = 0x00000080;
    const PFD_NEED_SYSTEM_PALETTE = 0x00000100;
    const PFD_DOUBLEBUFFER = 0x00000001;
    const PFD_STEREO = 0x00000002;
    const PFD_SWAP_LAYER_BUFFERS = 0x00000800;

    const PFD_DEPTH_DONTCARE = 0x20000000;
    const PFD_DOUBLEBUFFER_DONTCARE = 0x40000000;
    const PFD_STEREO_DONTCARE = 0x80000000;

    extern "gdi32" fn DescribePixelFormat(
        hdc: win32.HDC,
        iPixelFormat: c_int,
        nBytes: c_uint,
        ppfd: [*c]win32.gdi32.PIXELFORMATDESCRIPTOR,
    ) callconv(WINAPI) win32.BOOL;

    extern "gdi32" fn SetPixelFormat(
        hdc: win32.HDC,
        iPixelFormat: c_int,
        ppfd: [*c]const win32.gdi32.PIXELFORMATDESCRIPTOR,
    ) callconv(WINAPI) win32.BOOL;

    extern "gdi32" fn wglDeleteContext(hglrc: win32.HGLRC) callconv(WINAPI) win32.BOOL;
    extern "gdi32" fn wglGetProcAddress(name: win32.LPCSTR) callconv(WINAPI) ?win32.FARPROC;
    extern "gdi32" fn wglGetCurrentContext() callconv(WINAPI) ?win32.HGLRC;
    extern "gdi32" fn wglGetCurrentDC() callconv(WINAPI) win32.HDC;

    const WglCreateContextAttribsARBFn = *const fn (
        hdc: win32.HDC,
        hShareContext: ?win32.HGLRC,
        attribList: [*c]const c_int,
    ) callconv(WINAPI) ?win32.HGLRC;

    const WglChoosePixelFormatARBFn = *const fn (
        hdc: win32.HDC,
        piAttribIList: [*c]const c_int,
        pfAttribFList: [*c]const f32,
        nMaxFormats: c_uint,
        piFormats: [*c]c_int,
        nNumFormats: [*c]c_uint,
    ) callconv(WINAPI) win32.BOOL;

    const WglSwapIntervalEXTFn = *const fn (interval: c_int) callconv(WINAPI) win32.BOOL;

    var wglCreateContextAttribsARB: WglCreateContextAttribsARBFn = undefined;
    var wglChoosePixelFormatARB: WglChoosePixelFormatARBFn = undefined;
    var wglSwapIntervalEXT: WglSwapIntervalEXTFn = undefined;

    fn init() !void {
        // Before we can load extensions, we need a dummy OpenGL context, created using a dummy window.
        // We use a dummy window because you can only set the pixel format for a window once. For the
        // real window, we want to use wglChoosePixelFormatARB (so we can potentially specify options
        // that aren't available in PIXELFORMATDESCRIPTOR), but we can't load and use that before we
        // have a context.

        const window_class = win32.user32.WNDCLASSEXW{
            .style = win32.user32.CS_HREDRAW | win32.user32.CS_VREDRAW | win32.user32.CS_OWNDC,
            .lpfnWndProc = win32.user32.DefWindowProcW,
            .hInstance = getCurrentInstance(),
            .lpszClassName = L("WGL_Boostrap_Window"),
            .lpszMenuName = null,
            .hIcon = null,
            .hIconSm = null,
            .hCursor = null,
            .hbrBackground = null,
        };

        _ = try win32.user32.registerClassExW(&window_class);
        defer win32.user32.unregisterClassW(window_class.lpszClassName, window_class.hInstance) catch unreachable;

        const dummy_window = try win32.user32.createWindowExW(
            0,
            window_class.lpszClassName,
            window_class.lpszClassName,
            win32.user32.WS_OVERLAPPEDWINDOW,
            win32.user32.CW_USEDEFAULT,
            win32.user32.CW_USEDEFAULT,
            win32.user32.CW_USEDEFAULT,
            win32.user32.CW_USEDEFAULT,
            null,
            null,
            window_class.hInstance,
            null,
        );
        defer win32.user32.destroyWindow(dummy_window) catch unreachable;

        const dummy_dc = try win32.user32.getDC(dummy_window);
        defer _ = win32.user32.releaseDC(dummy_window, dummy_dc);

        var pfd = win32.gdi32.PIXELFORMATDESCRIPTOR{
            .nVersion = 1,
            .iPixelType = PFD_TYPE_RGBA,
            .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
            .iLayerType = PFD_MAIN_PLANE,
            .cDepthBits = 24,
            .cStencilBits = 8,
            .cColorBits = 32,
            .cAlphaBits = 8,
            .cAlphaShift = 0,
            .cRedBits = 0,
            .cRedShift = 0,
            .cGreenBits = 0,
            .cGreenShift = 0,
            .cBlueBits = 0,
            .cBlueShift = 0,
            .cAccumBits = 0,
            .cAccumRedBits = 0,
            .cAccumGreenBits = 0,
            .cAccumBlueBits = 0,
            .cAccumAlphaBits = 0,
            .cAuxBuffers = 0,
            .bReserved = 0,
            .dwLayerMask = 0,
            .dwVisibleMask = 0,
            .dwDamageMask = 0,
        };

        const pixel_format = win32.gdi32.ChoosePixelFormat(dummy_dc, &pfd);
        if (pixel_format == 0) return error.Unexpected;

        if (SetPixelFormat(dummy_dc, pixel_format, &pfd) == 0) return error.Unexpected;

        const dummy_context = win32.gdi32.wglCreateContext(dummy_dc) orelse return error.Unexpected;
        defer _ = wglDeleteContext(dummy_context);

        try makeCurrent(dummy_dc, dummy_context);
        defer makeCurrent(dummy_dc, null) catch unreachable;

        wglCreateContextAttribsARB = loadProc(
            WglCreateContextAttribsARBFn,
            "wglCreateContextAttribsARB",
        ) orelse return error.Unexpected;

        wglChoosePixelFormatARB = loadProc(
            WglChoosePixelFormatARBFn,
            "wglChoosePixelFormatARB",
        ) orelse return error.Unexpected;

        wglSwapIntervalEXT = loadProc(
            WglSwapIntervalEXTFn,
            "wglSwapIntervalEXT",
        ) orelse return error.Unexpected;
    }

    fn getCurrentInstance() win32.HINSTANCE {
        return @as(
            win32.HINSTANCE,
            @ptrCast(win32.kernel32.GetModuleHandleW(null) orelse unreachable),
        );
    }

    fn loadProc(comptime T: type, comptime name: [*:0]const u8) ?T {
        if (wglGetProcAddress(name)) |proc| return @as(T, @ptrCast(proc));

        if (win32.kernel32.GetModuleHandleW(L("opengl32"))) |gl32| {
            return @as(T, @ptrCast(win32.kernel32.GetProcAddress(gl32, name)));
        }

        return null;
    }

    fn createContext(dc: win32.HDC, v_major: c_int, v_minor: c_int) !win32.HGLRC {
        const pixel_format_attribs = [_]c_int{
            WGL_DRAW_TO_WINDOW_ARB, 1, // GL_TRUE
            WGL_SUPPORT_OPENGL_ARB, 1, // GL_TRUE
            WGL_DOUBLE_BUFFER_ARB, 1, // GL_TRUE
            WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB, 1, // GL_TRUE
            WGL_ACCELERATION_ARB,             WGL_FULL_ACCELERATION_ARB,
            WGL_PIXEL_TYPE_ARB,               WGL_TYPE_RGBA_ARB,
            WGL_COLOR_BITS_ARB,               32,
            WGL_DEPTH_BITS_ARB,               24,
            WGL_STENCIL_BITS_ARB,             8,
            0,
        };

        var pixel_format: i32 = undefined;
        var num_formats: u32 = undefined;
        if (wglChoosePixelFormatARB(
            dc,
            &pixel_format_attribs,
            0,
            1,
            &pixel_format,
            &num_formats,
        ) == 0) {
            return error.ChoosePixelFormatFailed;
        }

        std.debug.assert(num_formats > 0);

        var pfd: win32.gdi32.PIXELFORMATDESCRIPTOR = undefined;
        if (DescribePixelFormat(dc, pixel_format, @sizeOf(@TypeOf(pfd)), &pfd) == 0) return error.DescribePixelFormatFailed;
        if (SetPixelFormat(dc, pixel_format, &pfd) == 0) return error.SetPixelFormatFailed;

        // Specify that we want to create an OpenGL core profile context
        var context_attribs = [_]c_int{
            WGL_CONTEXT_MAJOR_VERSION_ARB, v_major,
            WGL_CONTEXT_MINOR_VERSION_ARB, v_minor,
            WGL_CONTEXT_FLAGS_ARB,         0,
            0,                             0,
            0,
        };

        if (v_major > 2) {
            context_attribs[5] = WGL_CONTEXT_DEBUG_BIT_ARB | WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB;
            context_attribs[6] = WGL_CONTEXT_PROFILE_MASK_ARB;
            context_attribs[7] = WGL_CONTEXT_CORE_PROFILE_BIT_ARB;
        }

        if (wglCreateContextAttribsARB(dc, null, &context_attribs)) |context| {
            return context;
        }

        return error.CannotCreateContext;
    }

    fn deleteContext(context: win32.HGLRC) !void {
        if (wglDeleteContext(context) == 0) return error.Unexpected;
    }

    fn makeCurrent(dc: win32.HDC, gl_context: ?win32.HGLRC) !void {
        if (!win32.gdi32.wglMakeCurrent(dc, gl_context)) return error.Unexpected;
    }

    fn getCurrentContext() ?win32.HGLRC {
        return wglGetCurrentContext();
    }

    fn getCurrentDC() ?win32.HDC {
        return wglGetCurrentDC();
    }

    fn swapBuffers(dc: win32.HDC) !void {
        if (!win32.gdi32.SwapBuffers(dc)) return error.Unexpected;
    }

    fn setSwapInterval(interval: c_int) !void {
        if (wglSwapIntervalEXT(interval) == 0) return error.Unexpected;
    }
};
