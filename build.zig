const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Disable AVX since some CPUs don't support it (Pentium G4560).
    var target_patch = target;
    target_patch.result.cpu.model = std.Target.Cpu.Model.baseline(
        target.result.cpu.arch,
        target.result.os,
    );

    const strip = b.option(bool, "strip", "strip debug information");
    const unwind_tables: ?std.builtin.UnwindTables = if (optimize != .Debug) .none else null;
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "_dt_mod_autopatch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .unwind_tables = unwind_tables,
            .strip = strip,
            .link_libc = false,
            .link_libcpp = false,
        }),
    });

    lib.bundle_ubsan_rt = if (strip) |strip_| !strip_ else null;
    lib.is_linking_libc = false;

    b.installArtifact(lib);

    const lib_tests = b.addTest(.{
        .root_module = lib.root_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
}
