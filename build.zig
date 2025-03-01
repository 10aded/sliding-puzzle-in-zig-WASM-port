const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const zjb = b.dependency("zjb", .{});

    const rainbow_triangle = b.addExecutable(.{
        .name = "rainbow_triangle",
        .root_source_file = b.path("rainbow_triangle/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    rainbow_triangle.root_module.addImport("zjb", zjb.module("zjb"));
    rainbow_triangle.entry = .disabled;
    rainbow_triangle.rdynamic = true;

    const extract_rainbow_triangle = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_rainbow_triangle_out = extract_rainbow_triangle.addOutputFileArg("zjb_extract.js");
    extract_rainbow_triangle.addArg("Zjb"); // Name of js class.
    extract_rainbow_triangle.addArtifactArg(rainbow_triangle);

    const rainbow_triangle_step = b.step("rainbow_triangle", "Build the hello Zig example");
    rainbow_triangle_step.dependOn(&b.addInstallArtifact(rainbow_triangle, .{
        .dest_dir = .{ .override = dir },
    }).step);
    rainbow_triangle_step.dependOn(&b.addInstallFileWithDir(extract_rainbow_triangle_out, dir, "zjb_extract.js").step);
    rainbow_triangle_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("rainbow_triangle/static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
}
