const std = @import("std");
const builtin = @import("builtin");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    var run_step = b.step("demo", "Run the demo app");
    var demo = b.addExecutable("microui-demo", "demo/demo.zig");
    demo.setTarget(target);
    demo.setBuildMode(mode);
    demo.install();

    demo.addIncludeDir("src");
    demo.addIncludeDir("demo");
    demo.addCSourceFiles(
        &.{
            "src/microui.c",
            // "demo/main.c",
            "demo/renderer.c",
        },
        &.{
            "-std=c11",
            "-pedantic",
            "-Werror",
            "-Wall",
            "-Wpedantic",
            // TODO (Matteo): fix compiles with this flag enabled
            // "-Wextra",
        },
    );

    demo.linkLibC();

    if (target.isWindows()) {
        demo.linkSystemLibrary("kernel32");
        demo.linkSystemLibrary("user32");
        demo.linkSystemLibrary("gdi32");
        demo.linkSystemLibrary("opengl32");
        demo.linkSystemLibrary("setupapi");
        demo.linkSystemLibrary("winmm");
        demo.linkSystemLibrary("imm32");
        demo.linkSystemLibrary("version");
        demo.linkSystemLibrary("oleaut32");
        demo.linkSystemLibrary("ole32");

        demo.subsystem = .Windows;

        const path =
            switch (target.getCpuArch()) {
            .i386 => "demo/sdl2/i686-w64-mingw32",
            .x86_64 => "demo/sdl2/x86_64-w64-mingw32",
            else => unreachable,
        };

        demo.addIncludeDir(std.mem.concat(b.allocator, u8, &.{ path, "/include" }) catch unreachable);
        demo.addObjectFile(std.mem.concat(b.allocator, u8, &.{ path, "/lib/libSDL2.a" }) catch unreachable);
        demo.addObjectFile(std.mem.concat(b.allocator, u8, &.{ path, "/lib/libSDL2main.a" }) catch unreachable);
    } else {
        demo.linkSystemLibrary("libsdl2");
        demo.linkSystemLibrary("GL");
    }

    // Configure run step
    const run_cmd = demo.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    run_step.dependOn(&run_cmd.step);

    // Configure test step
    const tests = b.addTest("src/microui.zig");
    tests.setTarget(target);
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests.step);
}
