const std = @import("std");
const builtin = @import("builtin");

const Builder = std.build.Builder;
const Module = std.build.Module;

pub fn module(b: *Builder) *Module {
    return b.createModule(.{
        .source_file = .{ .path = "src/microui.zig" },
    });
}

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
            .x86 => "demo/sdl2/i686-w64-mingw32",
            .x86_64 => "demo/sdl2/x86_64-w64-mingw32",
            else => unreachable,
        };

        demo.addIncludePath(std.mem.concat(b.allocator, u8, &.{ path, "/include" }) catch unreachable);
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

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const microui = module(b);

    const flags = [_][]const u8{
        "-std=c11",
        "-pedantic",
        "-Werror",
        "-Wall",
        "-Wpedantic",
        // TODO (Matteo): fix compiles with this flag enabled
        // "-Wextra",
    };

    var lib = b.addStaticLibrary(.{
        .name = "microui",
        .target = target,
        .optimize = optimize,
    });

    lib.install();
    lib.linkLibC();
    lib.addIncludePath("src");
    lib.addCSourceFile("src/microui.c", &flags);

    const demo_c = b.addExecutable(.{
        .name = "microui_demo_c",
        .target = target,
        .optimize = optimize,
    });

    demo_c.install();
    demo_c.addIncludePath("src");
    demo_c.addIncludePath("demo");
    demo_c.addCSourceFiles(
        &.{
            "demo/main.c",
            "demo/renderer.c",
        },
        &flags,
    );
    demo_c.linkLibrary(lib);
    setupDemo(b, target, demo_c, b.step("c", "Run the C demo app"));

    const demo_z = b.addExecutable(.{
        .name = "microui_demo_z",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "demo/demo.zig" },
        .target = target,
        .optimize = optimize,
    });

    demo_z.install();
    demo_z.addIncludePath("src");
    demo_z.addIncludePath("demo");
    demo_z.addCSourceFiles(
        &.{"demo/renderer.c"},
        &flags,
    );
    demo_z.linkLibrary(lib);
    demo_z.addModule("microui", microui);
    setupDemo(b, target, demo_z, b.step("z", "Run the Zig demo app"));

    // Creates a step for unit testing.
    const tests = b.addTest(.{
        .root_source_file = .{ .path = microui.source_file.path },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests.step);
}
