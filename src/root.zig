const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

const impl = switch (builtin.os.tag) {
    .windows => @import("windows.zig"),
    else => @import("posix.zig"),
};

/// The terminal attributes saved before switching terminal modes.
///
/// This is platform-specific: `std.posix.termios` on POSIX, and a `DWORD`
/// console-mode bitmask wrapper on Windows. Treat it as opaque.
pub const State = impl.State;

/// The terminal dimensions measured in character cells.
pub const Size = types.Size;

/// Returns whether `file` refers to an interactive terminal.
///
/// The supplied `io` instance is used for platform-specific terminal
/// detection. Returns `false` when the file is not a terminal.
pub fn isTerminal(io: std.Io, file: std.Io.File) !bool {
    return file.isTty(io);
}

/// Switches `file` to raw mode and returns its original terminal attributes.
///
/// The returned state can be passed to `restore` to return the terminal to its
/// previous configuration.
pub fn makeRaw(file: std.Io.File) !State {
    return impl.makeRaw(file);
}

/// Restores terminal attributes previously returned by `makeRaw`.
pub fn restore(file: std.Io.File, state: State) !void {
    return impl.restore(file, state);
}

/// Returns the current terminal attributes for `file`.
pub fn getState(file: std.Io.File) !State {
    return impl.getState(file);
}

/// Returns the terminal dimensions in character cells.
///
/// `file` must refer to a terminal device. Returns an error when the
/// terminal size cannot be determined.
pub fn getSize(file: std.Io.File) !Size {
    return try impl.getSize(file);
}

// pub fn readPassword(allocator: std.mem.Allocator, file: std.Io.File) ![]u8;

test "isTerminal returns false for a regular file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(std.testing.io, "test", .{});
    defer file.close(std.testing.io);

    try std.testing.expect(!(try isTerminal(std.testing.io, file)));
}
