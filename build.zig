const std = @import("std");
const builtin = @import("builtin");

const Builder = std.build.Builder;

fn setupDemo(
    b: *Builder,
    target: std.zig.CrossTarget,
    demo: *std.build.LibExeObjStep,
    run_step: *std.build.Step,
) void {
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

    const run_cmd = demo.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const flags = [_][]const u8{
        "-std=c11",
        "-pedantic",
        "-Werror",
        "-Wall",
        "-Wpedantic",
        // TODO (Matteo): fix compiles with this flag enabled
        // "-Wextra",
    };

    var lib = b.addStaticLibrary("microui", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.install();
    lib.linkLibC();
    lib.addIncludeDir("src");
    lib.addCSourceFile("src/microui.c", &flags);

    var demo_c = b.addExecutable("microui-demo-c", null);
    demo_c.setTarget(target);
    demo_c.setBuildMode(mode);
    demo_c.install();
    demo_c.addIncludeDir("src");
    demo_c.addIncludeDir("demo");
    demo_c.addCSourceFiles(
        &.{
            "demo/main.c",
            "demo/renderer.c",
        },
        &flags,
    );
    demo_c.linkLibrary(lib);
    setupDemo(b, target, demo_c, b.step("c", "Run the C demo app"));

    var demo_z = b.addExecutable("microui-demo-z", "demo/demo.zig");
    demo_z.setTarget(target);
    demo_z.setBuildMode(mode);
    demo_z.install();
    demo_z.addIncludeDir("src");
    demo_z.addIncludeDir("demo");
    demo_z.addCSourceFiles(
        &.{"demo/renderer.c"},
        &flags,
    );
    demo_z.linkLibrary(lib);
    setupDemo(b, target, demo_z, b.step("z", "Run the Zig demo app"));

    // Configure test step
    const tests = b.addTest("src/microui.zig");
    tests.setTarget(target);
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests.step);
}
