This package provides tools to load, new firmware and monitor serial usb based logging for quick
development.  The main goal is to provide a single click/key stroke solution for iterating
on a design.  

# Overview
Enables two build steps to help facilitate the goals stated above.  First is a simple serial interface that can send a reboot to bootloader command through the serial interface and log back results from the device.  

Second is a dependency on the rp picotool to do the actual loading of the uf2 file once the device is in the bootloader mode. 

# Usage
An example configuration that enables a load step and a load+logging option (runtest)
The serial control and monitor binary requires a vidpid to look for as well as a magic reboot character.  The device must handle the magic boot character 

The magic boot character is recommended to be 0xFE which is not a valid UTC-8 value (and is not 0xFF which is more likely to conflict).  

```zig
// ADD SerialCtrl & Monitor
const sctrl_dep = b.dependency("rpxxxx_dbg", .{
    .magic_boot_char = MAGICREBOOTCODE,
    .vid = tusb.DEFAULT_VID,
    .pid = tusb.DEFAULT_PID,
});
const uf2_path = firmware.get_emitted_bin(firmware.target.preferred_binary_format);
const load_step = try sctrl.getLoadStep(b, sctrl_dep, uf2_path);
const monitor_step = sctrl.getLoggingStep(b, sctrl_dep);
monitor_step.dependOn(load_step);
const runtest_step = b.step("runtest", "Loads uf2 into rpxxxx and logs output");
runtest_step.dependOn(monitor_step);
```