const std = @import("std");
const dss = @import("dss.zig");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const bin: []const u8 = args.next().?;
    const mode_str, const input_fp, const output_fp = args: {
        const err = error.InvalidArguments;

        const mode_str = args.next() orelse break :args err;
        const source = args.next() orelse break :args err;
        const dest = args.next() orelse break :args err;
        if (args.skip()) break :args err;

        break :args [3][]const u8{ mode_str, source, dest };
    } catch {
        std.debug.print("Usage: {s} <mode> <source> <dest>\n", .{bin});
        return 1;
    };

    const mode = try std.fmt.parseInt(c_char, mode_str, 10);

    try dss.run(mode, input_fp, output_fp);

    return 0;
}
