const std = @import("std");
const builtin = @import("builtin");
const debugging = false;
const show_error_stack = debugging;
const show_trace = debugging;
pub const tailCall: std.builtin.CallModifier = if (show_error_stack) .never_inline else .always_tail;
pub inline fn trace(format: anytype, values: anytype) void {
    if (show_trace) std.debug.print(format, values);
}
pub const dispatchCache = false;
pub const indirectDispatch = true;
pub const stdCall: std.builtin.CallingConvention = if (builtin.cpu.arch == .x86) .Stdcall else .C; //.AAPCS;
