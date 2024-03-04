const std = @import("std");

const dss = @import("dss.zig");

const StudyMode = enum(u8) {
    LoadFlow = 0,
    ShortCircuit = 1,

    fn fromInt(int: u8) !StudyMode {
        if (int >= @typeInfo(StudyMode).Enum.fields.len)
            return error.InvalidMode;

        return @enumFromInt(int);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const bin: []const u8 = args.next().?;
    const mode_str: []const u8, const input_fp: []const u8, const output_fp: []const u8 = read_args: {
        const mode_str = args.next() orelse break :read_args error.InvalidArguments;
        const source = args.next() orelse break :read_args error.InvalidArguments;
        const dest = args.next() orelse break :read_args error.InvalidArguments;
        if (args.skip()) break :read_args error.InvalidArguments;

        break :read_args .{ mode_str, source, dest };
    } catch |err| {
        std.debug.print("Usage: {s} <mode> <source> <dest>\n", .{bin});
        return err;
    };

    const mode_int = try std.fmt.parseInt(u8, mode_str, 10);
    const studyMode = try StudyMode.fromInt(mode_int);

    const output_file = try std.fs.cwd().createFile(output_fp, .{});
    defer output_file.close();

    var buffered_writer = std.io.bufferedWriter(output_file.writer());
    defer buffered_writer.flush() catch {};

    const engine = dss.initEngine(buffered_writer.writer());

    switch (studyMode) {
        .LoadFlow => try engine.runBaseCalc(input_fp),
        .ShortCircuit => try engine.runFaultCalc(input_fp),
    }
}
