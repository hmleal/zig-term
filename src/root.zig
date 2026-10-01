const std = @import("std");

pub const TerminalSize = struct {
    width: u16,
    heigth: u16,
};

pub fn isTerminal(file: std.Io.File) bool {
    std.debug.print("{any}", .{file});

    return true;
}

// pub fn makeRaw(file: std.fs.File) !State;

// pub fn restore(file: std.fs.File, state: State) !void;

// pub fn getState(file: std.fs.File) !State;

// pub fn getSize(file: std.fs.File) !Size;

// pub fn readPassword(allocator: std.mem.Allocator, file: std.fs.File) ![]u8;
