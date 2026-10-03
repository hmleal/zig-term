const std = @import("std");
const types = @import("types.zig");

const windows = std.os.windows;

/// The terminal attributes saved before switching terminal modes.
///
/// Windows console modes are a single `DWORD` bitmask, so this is a thin
/// wrapper over the raw value rather than a struct like `termios` on POSIX.
pub const State = struct {
    mode: windows.DWORD,

    /// Reserved so that `State` is not interchangeable with a raw `DWORD`.
    _opaque: void = {},
};

/// The terminal dimensions measured in character cells.
pub const Size = types.Size;

const BOOL = windows.BOOL;
const SHORT = windows.SHORT;
const WORD = windows.WORD;

// `std.os.windows` does not export these in Zig 0.17, they only exist as
// nested `ACCESS_MASK` members.
const GENERIC_READ: windows.DWORD = 0x8000_0000;
const GENERIC_WRITE: windows.DWORD = 0x4000_0000;
const FILE_SHARE_READ: windows.DWORD = 0x0000_0001;
const FILE_SHARE_WRITE: windows.DWORD = 0x0000_0002;
const OPEN_EXISTING: windows.DWORD = 3;

const COORD = extern struct {
    X: SHORT,
    Y: SHORT,
};

const SMALL_RECT = extern struct {
    Left: SHORT,
    Top: SHORT,
    Right: SHORT,
    Bottom: SHORT,
};

const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: WORD,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

extern "kernel32" fn GetConsoleScreenBufferInfo(
    hConsoleOutput: windows.HANDLE,
    lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO,
) callconv(.winapi) BOOL;

extern "kernel32" fn GetConsoleMode(
    hConsoleHandle: windows.HANDLE,
    lpMode: *windows.DWORD,
) callconv(.winapi) BOOL;

extern "kernel32" fn SetConsoleMode(
    hConsoleHandle: windows.HANDLE,
    dwMode: windows.DWORD,
) callconv(.winapi) BOOL;

// Console input mode flags, see the `ENABLE_*` values in the Win32 API docs.
const ENABLE_PROCESSED_INPUT: windows.DWORD = 0x0001;
const ENABLE_LINE_INPUT: windows.DWORD = 0x0002;
const ENABLE_ECHO_INPUT: windows.DWORD = 0x0004;
const ENABLE_MOUSE_INPUT: windows.DWORD = 0x0010;
const ENABLE_INSERT_MODE: windows.DWORD = 0x0020;
const ENABLE_QUICK_EDIT_MODE: windows.DWORD = 0x0040;
const ENABLE_EXTENDED_FLAGS: windows.DWORD = 0x0080;
const ENABLE_VIRTUAL_TERMINAL_INPUT: windows.DWORD = 0x0200;

/// Maps a failed Win32 console call onto a library error.
fn consoleError() anyerror {
    return switch (windows.GetLastError()) {
        .INVALID_HANDLE, .INVALID_PARAMETER, .ACCESS_DENIED => error.NotATerminal,
        else => error.Unexpected,
    };
}

/// Switches `file` to raw mode and returns its original terminal attributes.
///
/// Raw mode is the Windows analogue of POSIX `cfmakeraw`: input is delivered
/// without line editing or echo, one key press at a time.
pub fn makeRaw(file: std.Io.File) !State {
    const original = try getState(file);

    // Disable cooked-mode input handling and the console's own mouse reporting,
    // which would otherwise inject sequences into the input stream.
    const raw = original.mode & ~@as(windows.DWORD, ENABLE_PROCESSED_INPUT |
        ENABLE_LINE_INPUT |
        ENABLE_ECHO_INPUT |
        ENABLE_MOUSE_INPUT |
        ENABLE_INSERT_MODE |
        ENABLE_QUICK_EDIT_MODE |
        ENABLE_EXTENDED_FLAGS);

    // Ask the console to report keys as VT sequences so escape codes for arrows,
    // function keys and friends arrive as input instead of scanning `0x00`.
    const new_mode = raw | ENABLE_VIRTUAL_TERMINAL_INPUT;

    if (!SetConsoleMode(file.handle, new_mode).toBool()) return consoleError();

    return original;
}

/// Restores terminal attributes previously returned by `makeRaw`.
pub fn restore(file: std.Io.File, state: State) !void {
    if (!SetConsoleMode(file.handle, state.mode).toBool()) return consoleError();
}

/// Returns the current terminal attributes for `file`.
pub fn getState(file: std.Io.File) !State {
    var mode: windows.DWORD = undefined;
    if (!GetConsoleMode(file.handle, &mode).toBool()) return consoleError();
    return .{ .mode = mode };
}

extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const u16,
    dwDesiredAccess: windows.DWORD,
    dwShareMode: windows.DWORD,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: windows.DWORD,
    dwFlagsAndAttributes: windows.DWORD,
    hTemplateFile: windows.HANDLE,
) callconv(.winapi) windows.HANDLE;

/// Returns the terminal dimensions in character cells.
///
/// `file` may refer to any handle attached to a console. Console input
/// handles (`CONIN$`, and therefore stdin) carry no size information, so
/// those fall back to opening `CONOUT$`. Returns `error.NotATerminal` when
/// the process has no console at all.
pub fn getSize(file: std.Io.File) !Size {
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;

    if (!GetConsoleScreenBufferInfo(file.handle, &info).toBool()) {
        if (windows.GetLastError() != .INVALID_HANDLE) return error.Unexpected;

        // `GetConsoleScreenBufferInfo` only accepts console screen buffers, so
        // it fails with `INVALID_HANDLE` for console *input* handles too. Probe
        // with `GetConsoleMode` (which accepts both) to tell an input handle
        // apart from a handle that is not a console at all.
        var mode: windows.DWORD = undefined;
        if (!GetConsoleMode(file.handle, &mode).toBool()) return consoleError();

        // A console input handle (or stdin) has no screen buffer attached,
        // so read the geometry from the console's output buffer instead.
        const out = CreateFileW(
            std.unicode.utf8ToUtf16LeStringLiteral("CONOUT$"),
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            null,
            OPEN_EXISTING,
            0,
            windows.INVALID_HANDLE_VALUE,
        );
        if (out == windows.INVALID_HANDLE_VALUE) return error.NotATerminal;
        defer windows.CloseHandle(out);

        if (!GetConsoleScreenBufferInfo(out, &info).toBool()) {
            return switch (windows.GetLastError()) {
                .INVALID_HANDLE => error.NotATerminal,
                else => error.Unexpected,
            };
        }
    }

    // `dwSize` is the whole buffer, which is larger than the visible window
    // whenever the buffer has been scrolled, so use `srWindow` instead.
    const window = info.srWindow;
    return .{
        .width = @intCast(@as(i32, window.Right) - @as(i32, window.Left) + 1),
        .height = @intCast(@as(i32, window.Bottom) - @as(i32, window.Top) + 1),
    };
}
