const std = @import("std");
const builtin = @import("builtin");

/// Returns "Load" step which loads the uf2 file into the connected rpxxxx device
/// by first attempting to force it into the boot loader then loading with picotool
pub fn getLoadStep(
    root_build: *std.Build,
    this_dep: *std.Build.Dependency,
    uf2_file: std.Build.LazyPath,
) !*std.Build.Step {
    // Build an executable from the serialctrl.zig
    const exe = root_build.addExecutable(.{
        .name = "serialctrl",
        .root_module = this_dep.module("serialctrl"),
    });

    // Add a build step for installing the executable
    root_build.installArtifact(exe);

    // restart_step:   calls serialctrl with the reboot flag
    //                 depends on this_dep.builder.getInstallStep()
    // Create force reboot step - calling the executable with the argument "reboot"
    const to_bootloader_cmd = root_build.addRunArtifact(exe);
    to_bootloader_cmd.addArg("reboot");
    to_bootloader_cmd.has_side_effects = true;
    to_bootloader_cmd.step.name = "Force Reboot with Serial";

    // picotool_load:  loads using picotool depends on this_dep.builder.getInstallStep()
    // picotool_reset: resets device with picotool
    // Find program should find the newly copied picotool in bin (if needed)
    const picotool_prog = root_build.findProgram(&.{"picotool"}, &.{}) catch blk: {
        // If not in path we'll try to pull it in from the lazy dep defined in zig.zon.
        if (builtin.os.tag != .linux)
            @panic("Only supports auto getting Linux version of picotool currently");
        const picotool_dep = this_dep.builder.dependency("linux_picotool", .{});
        // TODO: only pulling linux currently should not be hard to add others
        const install_picotool = root_build.addInstallBinFile(
            picotool_dep.path("picotool/picotool"),
            "picotool",
        );
        root_build.getInstallStep().dependOn(&install_picotool.step);
        break :blk root_build.getInstallPath(
            install_picotool.dir,
            install_picotool.dest_rel_path,
        );
    };
    const load_uf2_argv = [_][]const u8{ picotool_prog, "load" };
    const load_uf2_cmd = root_build.addSystemCommand(&load_uf2_argv);
    load_uf2_cmd.addFileArg(uf2_file);
    load_uf2_cmd.setName("picotool: load into device");
    load_uf2_cmd.has_side_effects = true;

    const restart = [_][]const u8{ picotool_prog, "reboot" };
    const restart_cmd = root_build.addSystemCommand(&restart);
    restart_cmd.setName("picotool: reboot device");
    restart_cmd.has_side_effects = true;

    // return: Load_Step depends on the above chain
    const load_step = root_build.step("load", "Loads uf2 into rp2xxx");
    load_step.dependOn(&restart_cmd.step);
    restart_cmd.step.dependOn(&load_uf2_cmd.step);
    load_uf2_cmd.step.dependOn(&to_bootloader_cmd.step);
    to_bootloader_cmd.step.dependOn(root_build.getInstallStep());

    return load_step;
}

/// Return "Logging" step which will open the serial port using the generated serial control artifact.
/// Must be explicitly chained to after load if that is desired.
pub fn getLoggingStep(root_build: *std.Build) *std.Build.Step {
    // TODO: Must be a better way but I could not add the executable in build then get artifact for some reason...
    var exe: ?*std.Build.Step.Compile = null;
    for (root_build.install_tls.step.dependencies.items) |dep_step| {
        const inst = dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
        if (std.mem.eql(u8, inst.artifact.name, "serialctrl")) {
            exe = inst.artifact;
        }
    }
    const log_cmd = root_build.addRunArtifact(exe.?);
    log_cmd.has_side_effects = true;
    log_cmd.step.name = "Start Logging";

    return &log_cmd.step;
}

pub fn build(b: *std.Build) !void {
    // - Get options: vid, pic, magicbootchar
    // - Create Module to compile
    // - Add artifact
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("serialctrl", .{
        .root_source_file = b.path("serialctrl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const vid = b.option(
        u16,
        "vid",
        "target VID",
    ) orelse @panic("Need VID to be set");
    const pid = b.option(
        u16,
        "pid",
        "target PID",
    ) orelse @panic("Need PID to be set");
    const magic_boot_char = b.option(
        u8,
        "magic_boot_char",
        "magic boot character",
    ) orelse @panic("Need magic_boot_char to be set");

    // Add config options based on device & HW setup
    const options = b.addOptions();
    options.addOption(u16, "vid", vid);
    options.addOption(u16, "pid", pid);
    options.addOption(u8, "magic_boot_char", magic_boot_char);
    module.addOptions("config", options);

    const serial_dep = b.dependency("serial", .{});
    module.addImport("serial", serial_dep.module("serial"));
}
