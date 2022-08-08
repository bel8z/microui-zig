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
    var exe = b.addExecutable("microui-demo", null);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    exe.addIncludeDir("src");
    exe.addCSourceFiles(
        &.{
            "src/microui.c",
            "demo/main.c",
            "demo/renderer.c",
        },
        &.{
            // "-std=c11",
            // "-pedantic",
            // "-Werror",
            // "-Wall",
            // "-Wextra",
            // "-Wpedantic",
        },
    );

    exe.linkLibC();

    if (target.isWindows()) {
        exe.linkSystemLibrary("kernel32");
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("setupapi");
        exe.linkSystemLibrary("winmm");
        exe.linkSystemLibrary("imm32");
        exe.linkSystemLibrary("version");
        exe.linkSystemLibrary("oleaut32");
        exe.linkSystemLibrary("ole32");

        exe.subsystem = .Windows;

        const path =
            switch (target.getCpuArch()) {
            .i386 => "demo/sdl2/i686-w64-mingw32",
            .x86_64 => "demo/sdl2/x86_64-w64-mingw32",
            else => unreachable,
        };

        exe.addIncludeDir(std.mem.concat(b.allocator, u8, &.{ path, "/include" }) catch unreachable);
        exe.addObjectFile(std.mem.concat(b.allocator, u8, &.{ path, "/lib/libSDL2.a" }) catch unreachable);
        exe.addObjectFile(std.mem.concat(b.allocator, u8, &.{ path, "/lib/libSDL2main.a" }) catch unreachable);
    } else {
        exe.linkSystemLibrary("libsdl2");
        exe.linkSystemLibrary("GL");
    }

    // Configure run step
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    run_step.dependOn(&run_cmd.step);

    // const exe_tests = b.addTest("src/tests.zig");
    // exe_tests.setTarget(target);
    // exe_tests.setBuildMode(mode);
    // exe_tests.addPackage(bolts);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}
