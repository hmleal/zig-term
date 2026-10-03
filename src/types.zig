const std = @import("std");

// There is deliberately no shared `State` here. The saved terminal attributes
// are platform-specific (a `termios` on POSIX, a console-mode bitmask on
// Windows), so each backend defines its own and `root.zig` re-exports
// `impl.State`.

/// The terminal dimensions measured in character cells.
pub const Size = struct {
    /// The number of columns.
    width: u16,
    /// The number of rows.
    height: u16,
};
