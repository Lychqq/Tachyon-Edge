const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Build the static library
    const lib = b.addLibrary(.{
        .name = "p2p_sdk",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    
    // Zig's std.net handles ws2_32 on Windows natively in 0.17+ 
    // when using high-level std.net functions.
    b.installArtifact(lib);

    // 2. Build the shared library (DLL / SO / DYLIB) for Python
    const lib_shared = b.addLibrary(.{
        .name = "p2p_sdk_shared",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/capi.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    b.installArtifact(lib_shared);

}
