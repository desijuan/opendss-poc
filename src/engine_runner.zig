const std = @import("std");
const dss = @import("dss.zig");

export fn runEngine(
    mode: c_char,
    input_len: usize,
    input: [*c]const c_char,
    output_len: usize,
    output: [*c]const c_char,
) callconv(.C) c_int {
    const input_fp: []const u8 = @as([*]const u8, @ptrCast(input))[0..input_len];
    const output_fp: []const u8 = @as([*]const u8, @ptrCast(output))[0..output_len];

    dss.run(mode, input_fp, output_fp) catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        return 1;
    };

    return 0;
}
