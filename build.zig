const std = @import("std");
const builtin = @import("builtin");

const Builder = std.build.Builder;
const Module = std.build.Module;

pub fn module(b: *Builder) *Module {
    return b.createModule(.{
        .source_file = .{ .path = "src/microui.zig" },
    });
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

    const sdl_path =
        switch (target.getCpuArch()) {
        .x86 => "demo/sdl2/i686-w64-mingw32",
        .x86_64 => "demo/sdl2/x86_64-w64-mingw32",
        else => unreachable,
    };

    // C Demo
    {
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

        demo_c.subsystem = .Windows;
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
        demo_c.linkLibC();
        demo_c.linkLibrary(lib);
        demo_c.linkSystemLibrary("gdi32");
        demo_c.linkSystemLibrary("opengl32");
        demo_c.linkSystemLibrary("setupapi");
        demo_c.linkSystemLibrary("winmm");
        demo_c.linkSystemLibrary("imm32");
        demo_c.linkSystemLibrary("version");
        demo_c.linkSystemLibrary("oleaut32");
        demo_c.linkSystemLibrary("ole32");
        demo_c.addIncludePath(std.mem.concat(b.allocator, u8, &.{ sdl_path, "/include" }) catch unreachable);
        demo_c.addObjectFile(std.mem.concat(b.allocator, u8, &.{ sdl_path, "/lib/libSDL2.a" }) catch unreachable);
        demo_c.addObjectFile(std.mem.concat(b.allocator, u8, &.{ sdl_path, "/lib/libSDL2main.a" }) catch unreachable);

        const run_cmd = demo_c.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        b.step("c", "Run the C demo app").dependOn(&run_cmd.step);
    }

    // Zig demo - SDL
    {
        const demo_sdl = b.addExecutable(.{
            .name = "microui_demo_sdl",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{ .path = "demo/demo_sdl.zig" },
            .target = target,
            .optimize = optimize,
        });

        demo_sdl.subsystem = .Windows;
        demo_sdl.install();
        demo_sdl.addIncludePath("src");
        demo_sdl.addIncludePath("demo");
        demo_sdl.addModule("microui", microui);
        demo_sdl.linkLibC();
        demo_sdl.linkSystemLibrary("gdi32");
        demo_sdl.linkSystemLibrary("opengl32");
        demo_sdl.linkSystemLibrary("setupapi");
        demo_sdl.linkSystemLibrary("winmm");
        demo_sdl.linkSystemLibrary("imm32");
        demo_sdl.linkSystemLibrary("version");
        demo_sdl.linkSystemLibrary("oleaut32");
        demo_sdl.linkSystemLibrary("ole32");
        demo_sdl.addIncludePath(std.mem.concat(b.allocator, u8, &.{ sdl_path, "/include" }) catch unreachable);
        demo_sdl.addObjectFile(std.mem.concat(b.allocator, u8, &.{ sdl_path, "/lib/libSDL2.a" }) catch unreachable);
        demo_sdl.addObjectFile(std.mem.concat(b.allocator, u8, &.{ sdl_path, "/lib/libSDL2main.a" }) catch unreachable);

        const run_cmd = demo_sdl.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        b.step("sdl", "Run the Zig demo app - SDL backend").dependOn(&run_cmd.step);
    }

    // Zig demo - WGL
    {
        const demo_wgl = b.addExecutable(.{
            .name = "microui_demo_wgl",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{ .path = "demo/demo_wgl.zig" },
            .target = target,
            .optimize = optimize,
        });

        demo_wgl.subsystem = .Windows;
        demo_wgl.install();
        demo_wgl.addIncludePath("src");
        demo_wgl.addIncludePath("demo");
        demo_wgl.addModule("microui", microui);
        demo_wgl.linkLibC();
        demo_wgl.linkSystemLibrary("opengl32");

        const run_cmd = demo_wgl.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        b.step("wgl", "Run the Zig demo app - WGL backend").dependOn(&run_cmd.step);
    }

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
