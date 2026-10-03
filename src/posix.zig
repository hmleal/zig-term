const std = @import("std");
const types = @import("types.zig");

/// The terminal attributes saved before switching terminal modes.
pub const State = std.posix.termios;

/// The terminal dimensions measured in character cells.
pub const Size = types.Size;

/// Switches `file` to raw mode and returns its original terminal attributes.
///
/// The returned state can be passed to `restore` to return the terminal to its
/// previous configuration.
pub fn makeRaw(file: std.Io.File) !State {
    const original = try std.posix.tcgetattr(file.handle);

    var raw = original;

    // Input flags
    raw.iflag.IGNBRK = false;
    raw.iflag.BRKINT = false;
    raw.iflag.PARMRK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.INLCR = false;
    raw.iflag.IGNCR = false;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;

    // Output flags
    raw.oflag.OPOST = false;

    // Local flags
    raw.lflag.ECHO = false;
    raw.lflag.ECHONL = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    // Control flags
    raw.cflag.CSIZE = .CS8;
    raw.cflag.PARENB = false;

    // Read one byte at a time.
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(file.handle, .FLUSH, raw);

    return original;
}

/// Restores terminal attributes previously returned by `makeRaw`.
pub fn restore(file: std.Io.File, state: State) !void {
    try std.posix.tcsetattr(file.handle, .DRAIN, state);
}

/// Returns the current terminal attributes for `file`.
pub fn getState(file: std.Io.File) !State {
    return try std.posix.tcgetattr(file.handle);
}

/// Returns the terminal dimensions in character cells.
///
/// `file` must refer to a terminal device. Returns an error when the
/// terminal size cannot be determined.
pub fn getSize(file: std.Io.File) !Size {
    var size: std.posix.winsize = undefined;

    const result = std.os.linux.ioctl(
        file.handle,
        std.os.linux.T.IOCGWINSZ,
        @intFromPtr(&size),
    );

    const errno = std.os.linux.errno(result);
    if (errno != .SUCCESS) {
        if (errno == .NOTTY) return error.NotATerminal;
        return std.posix.unexpectedErrno(errno);
    }

    return .{ .width = size.col, .height = size.row };
}

// pub fn readPassword(allocator: std.mem.Allocator, file: std.Io.File) ![]u8;

test "getSize returns an error for a regular file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(std.testing.io, "test", .{});
    defer file.close(std.testing.io);

    try std.testing.expectError(error.NotATerminal, getSize(file));
}
