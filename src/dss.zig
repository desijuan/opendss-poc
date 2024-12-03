const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("dss_capi.h");
});

pub fn run(mode: c_char, input_fp: []const u8, output_fp: []const u8) !void {
    return switch (mode) {
        0 => try BaseRunner.run(input_fp, output_fp),
        1 => try FaultRunner.run(input_fp, output_fp),
        else => error.InvalidMode,
    };
}

const MAX_STR_LEN = 256;
const MAX_LINE_LEN = 2 * 1024;

const FileBufferedReader = std.io.BufferedReader(4096, std.fs.File.Reader);
const FileBufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

const GRPointers = struct {
    data_PPAnsiChar: [*c][*c][*c]u8,
    data_PDouble: [*c][*c]f64,
    data_PInteger: [*c][*c]i32,
    data_PByte: [*c][*c]i8,
    count_PPAnsiChar: [*c]i32,
    count_PDouble: [*c]i32,
    count_PInteger: [*c]i32,
    count_PByte: [*c]i32,
};

const BaseRunner = struct {
    fn run(input_fp: []const u8, output_fp: []const u8) !void {
        var str_buffer: [MAX_STR_LEN]u8 = undefined;

        const stdout = std.io.getStdOut().writer();
        const stderr = std.io.getStdErr().writer();

        std.posix.access(input_fp, 0) catch |err| {
            stderr.print("Error accessing file: {s}\n", .{input_fp}) catch {};
            return err;
        };

        const output_file: std.fs.File = std.fs.cwd().createFile(output_fp, .{}) catch |err| {
            stderr.print("Error creating file: {s}\n", .{output_fp}) catch {};
            return err;
        };
        defer output_file.close();

        var file_bw: FileBufferedWriter = std.io.bufferedWriter(output_file.writer());
        const writer = file_bw.writer();

        var grp = GRPointers{
            .data_PPAnsiChar = undefined,
            .data_PDouble = undefined,
            .data_PInteger = undefined,
            .data_PByte = undefined,
            .count_PPAnsiChar = undefined,
            .count_PDouble = undefined,
            .count_PInteger = undefined,
            .count_PByte = undefined,
        };

        try stdout.writeAll("Starting Base Load Flow Calculation...\n");

        if (c.DSS_Start(0) == 0) {
            stderr.print("{s}\n", .{"Error initializing DSS"}) catch {};
            return error.DSSInitializationFailed;
        }

        c.DSS_GetGRPointers(
            &grp.data_PPAnsiChar,
            &grp.data_PDouble,
            &grp.data_PInteger,
            &grp.data_PByte,
            &grp.count_PPAnsiChar,
            &grp.count_PDouble,
            &grp.count_PInteger,
            &grp.count_PByte,
        );

        const compile_cmd = try std.fmt.bufPrintZ(
            &str_buffer,
            "compile {s}",
            .{input_fp},
        );

        c.Text_Set_Command(compile_cmd);

        c.Solution_Solve();

        try writeResults(&grp, writer, &str_buffer);

        try file_bw.flush();

        // c.DSS_DisposeGRData();

        try stdout.writeAll("SUCCESS\n");
    }

    fn writeResults(grp: *const GRPointers, writer: FileBufferedWriter.Writer, str_buffer: []u8) !void {
        const stderr = std.io.getStdErr().writer();

        const num_ckt_elements = c.Circuit_Get_NumCktElements();
        if (num_ckt_elements <= 0) {
            const error_str = try std.fmt.bufPrint(
                str_buffer,
                "ERROR: CktElements = {}",
                .{num_ckt_elements},
            );
            stderr.print("{s}\n", .{error_str}) catch {};
            writer.print("{s}\n", .{error_str}) catch {};
            return error.DSSError;
        }

        const num_buses = c.Circuit_Get_NumBuses();
        if (num_buses <= 0) {
            const error_str = try std.fmt.bufPrint(
                str_buffer,
                "ERROR: NumBuses = {}",
                .{num_buses},
            );
            stderr.print("{s}\n", .{error_str}) catch {};
            writer.print("{s}\n", .{error_str}) catch {};
            return error.DSSError;
        }

        c.Circuit_Get_TotalPower_GR();
        assert(grp.count_PDouble.* == 2);
        const total_power = grp.data_PDouble.*;
        try writer.print("CktTotalPower, kW, kVAr, {}, {}\n", .{
            total_power[0], total_power[1],
        });

        c.Circuit_Get_Losses_GR();
        assert(grp.count_PDouble.* == 2);
        const losses = grp.data_PDouble.*;
        try writer.print("CktLosses, W, VAr, {}, {}\n", .{
            losses[0], losses[1],
        });

        c.Circuit_Get_LineLosses_GR();
        assert(grp.count_PDouble.* == 2);
        const line_losses = grp.data_PDouble.*;
        try writer.print("LineLosses, kW, VAr, {}, {}\n", .{
            line_losses[0], line_losses[1],
        });

        c.LineCodes_Get_AllNames_GR();
        assert(grp.count_PPAnsiChar.* >= 0);
        const n_linecodes: usize = @intCast(grp.count_PPAnsiChar.*);
        const linecodes = grp.data_PPAnsiChar.*;
        try writer.print("LineCodes, {}", .{n_linecodes});
        for (0..n_linecodes) |i| {
            try writer.print(", {s}", .{linecodes[i]});
        }
        try writer.writeAll("\n");

        const num_elements: usize = @intCast(num_ckt_elements);
        for (0..num_elements) |i| {
            c.Circuit_SetCktElementIndex(@as(i32, @intCast(i)));

            try writer.print("{s}\n", .{c.CktElement_Get_Name()});
            try writer.writeAll("sR\n");

            try writer.print("Phases, {}", .{c.CktElement_Get_NumPhases()});

            c.CktElement_Get_TotalPowers_GR();
            assert(grp.count_PDouble.* >= 0);
            const n_powers: usize = @intCast(grp.count_PDouble.*);
            try writer.print(", nPwr, {}\n", .{n_powers});
            assert(n_powers % 2 == 0);
            const np: usize = n_powers / 2;
            const powers = grp.data_PDouble.*;
            for (0..np) |j| {
                try writer.print("Power, {}, {}\n", .{
                    powers[2 * j], powers[2 * j + 1],
                });
            }

            c.CktElement_Get_NodeOrder_GR();
            assert(grp.count_PInteger.* >= 0);
            const n_nodes: usize = @intCast(grp.count_PInteger.*);
            const nodes = grp.data_PInteger.*;
            c.CktElement_Get_Currents_GR();
            const n_currents = grp.count_PDouble.*;
            const currents = grp.data_PDouble.*;
            assert(n_currents == 2 * n_nodes);
            for (0..n_nodes) |j| {
                try writer.print("Node, {}, {}, {}\n", .{
                    nodes[j], currents[2 * j], currents[2 * j + 1],
                });
            }

            c.CktElement_Get_Residuals_GR();
            assert(grp.count_PDouble.* >= 0);
            const n_residuals: usize = @intCast(grp.count_PDouble.*);
            assert(n_residuals % 2 == 0);
            const nr: usize = n_residuals / 2;
            const residuals = grp.data_PDouble.*;
            for (0..nr) |j| {
                try writer.print("Residual, {}, {}\n", .{
                    residuals[2 * j], residuals[2 * j + 1],
                });
            }

            try writer.writeAll("eR\n");
        }

        var next_bus: i32 = 0;
        while (next_bus != -1) : (next_bus = c.Bus_Get_Next()) {
            try writer.print("Bus, {s}\n", .{c.Bus_Get_Name()});
            try writer.writeAll("sR\n");

            c.Bus_Get_Nodes_GR();
            assert(grp.count_PInteger.* >= 0);
            const n_nodes: usize = @intCast(grp.count_PInteger.*);
            const nodes = grp.data_PInteger.*;
            c.Bus_Get_Voltages_GR();
            const n_voltages = grp.count_PDouble.*;
            const voltages = grp.data_PDouble.*;
            assert(n_voltages == 2 * n_nodes);
            for (0..n_nodes) |i| {
                try writer.print("Node, {}, {}, {}\n", .{ nodes[i], voltages[2 * i], voltages[2 * i + 1] });
            }

            try writer.writeAll("eR\n");
        }
    }
};

const FaultRunner = struct {
    fn run(input_fp: []const u8, output_fp: []const u8) !void {
        var str_buffer: [MAX_STR_LEN]u8 = undefined;

        const stdout = std.io.getStdOut().writer();
        const stderr = std.io.getStdErr().writer();

        const input_file: std.fs.File = std.fs.cwd().openFile(input_fp, .{ .mode = .read_only }) catch |err| {
            stderr.print("Error opening file: {s}\n", .{input_fp}) catch {};
            return err;
        };
        defer input_file.close();

        const output_file: std.fs.File = std.fs.cwd().createFile(output_fp, .{}) catch |err| {
            stderr.print("Error creating file: {s}\n", .{output_fp}) catch {};
            return err;
        };
        defer output_file.close();

        var file_br: FileBufferedReader = std.io.bufferedReader(input_file.reader());
        const reader = file_br.reader();

        var file_bw: FileBufferedWriter = std.io.bufferedWriter(output_file.writer());
        const writer = file_bw.writer();

        var grp = GRPointers{
            .data_PPAnsiChar = undefined,
            .data_PDouble = undefined,
            .data_PInteger = undefined,
            .data_PByte = undefined,
            .count_PPAnsiChar = undefined,
            .count_PDouble = undefined,
            .count_PInteger = undefined,
            .count_PByte = undefined,
        };

        try stdout.writeAll("Starting Short Circuit Calculation...\n");

        if (c.DSS_Start(0) == 0) {
            stderr.writeAll("Error initializing DSS\n") catch {};
            return error.DSSInitializationFailed;
        }

        c.DSS_GetGRPointers(
            &grp.data_PPAnsiChar,
            &grp.data_PDouble,
            &grp.data_PInteger,
            &grp.data_PByte,
            &grp.count_PPAnsiChar,
            &grp.count_PDouble,
            &grp.count_PInteger,
            &grp.count_PByte,
        );

        var line_buffer: [MAX_LINE_LEN]u8 = undefined;
        var fbs: std.io.FixedBufferStream([]u8) = std.io.fixedBufferStream(&line_buffer);
        while (line_z: {
            reader.streamUntilDelimiter(fbs.writer(), '\n', fbs.buffer.len - 1) catch |err| switch (err) {
                error.EndOfStream => {
                    if (fbs.pos == 0) break :line_z null;
                },

                else => return err,
            };

            const line_len = fbs.pos;
            fbs.buffer[line_len] = 0;

            break :line_z @as([:0]const u8, fbs.buffer[0..line_len :0]);
        }) |line_z| : (fbs.pos = 0) {
            c.Text_Set_Command(line_z);

            if (std.mem.eql(u8, "solve", line_z)) {
                c.Solution_Solve();
                try writeResults(&grp, writer, &str_buffer);
            }
        }

        try file_bw.flush();

        // c.DSS_DisposeGRData();

        try stdout.writeAll("SUCCESS\n");
    }

    fn writeResults(grp: *const GRPointers, writer: FileBufferedWriter.Writer, str_buffer: []u8) !void {
        const stderr = std.io.getStdErr().writer();

        const num_ckt_elements = c.Circuit_Get_NumCktElements();
        if (num_ckt_elements <= 0) {
            const error_str = try std.fmt.bufPrint(
                str_buffer,
                "ERROR: CktElements = {}",
                .{num_ckt_elements},
            );
            stderr.print("{s}\n", .{error_str}) catch {};
            writer.print("{s}\n", .{error_str}) catch {};
            return error.DSSError;
        }

        // We expect the Fault to be the last Circuit Element
        c.Circuit_SetCktElementIndex(num_ckt_elements);

        const element_name = c.CktElement_Get_Name();

        // Skip if Circuit Element is not a Fault
        const fault_cname = "Fault";
        if (!std.mem.eql(u8, fault_cname, element_name[0..fault_cname.len]))
            return;

        try writer.print("{s}\n", .{element_name});
        try writer.writeAll("sR\n");

        try writer.print("Phases, {}", .{c.CktElement_Get_NumPhases()});

        c.CktElement_Get_BusNames_GR();
        assert(grp.count_PPAnsiChar.* == 2);
        const bus_names = grp.data_PPAnsiChar.*;
        try writer.print(", Bus1, {s}, Bus2, {s}\n", .{ bus_names[0], bus_names[1] });

        c.CktElement_Get_NodeOrder_GR();
        assert(grp.count_PInteger.* >= 0);
        const n_nodes: usize = @intCast(grp.count_PInteger.*);
        const nodes = grp.data_PInteger.*;
        c.CktElement_Get_CurrentsMagAng_GR();
        const n_mag_ang = grp.count_PDouble.*;
        const mag_ang = grp.data_PDouble.*;
        assert(n_mag_ang == 2 * n_nodes);
        for (0..n_nodes) |j| {
            try writer.print("Node, {}, {}, {}\n", .{
                nodes[j], mag_ang[2 * j], mag_ang[2 * j + 1],
            });
        }

        try writer.writeAll("eR\n");
    }
};
