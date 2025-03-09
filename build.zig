const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const zjb = b.dependency("zjb", .{});

    const sliding_puzzle = b.addExecutable(.{
        .name = "port_sliding_puzzle",
        .root_source_file = b.path("sliding_puzzle_web_game.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    sliding_puzzle.root_module.addImport("zjb", zjb.module("zjb"));
    sliding_puzzle.entry = .disabled;
    sliding_puzzle.rdynamic = true;
    //    sliding_puzzle.initial_memory = std.wasm.page_size * 100;
    //    sliding_puzzle.max_memory = std.wasm.page_size * 1000;
    sliding_puzzle.stack_size = std.wasm.page_size * 1000;
    

    const extract_sliding_puzzle = b.addRunArtifact(zjb.artifact("generate_js"));
    const extract_sliding_puzzle_out = extract_sliding_puzzle.addOutputFileArg("zjb_extract.js");
    extract_sliding_puzzle.addArg("Zjb"); // Name of js class.
    extract_sliding_puzzle.addArtifactArg(sliding_puzzle);

    const sliding_puzzle_step = b.step("sliding_puzzle", "Build the sliding puzzle static website");
    sliding_puzzle_step.dependOn(&b.addInstallArtifact(sliding_puzzle, .{
        .dest_dir = .{ .override = dir },
    }).step);
    sliding_puzzle_step.dependOn(&b.addInstallFileWithDir(extract_sliding_puzzle_out, dir, "zjb_extract.js").step);
    sliding_puzzle_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
}
