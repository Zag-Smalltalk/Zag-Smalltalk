const std = @import("std");
const checkEqual = @import("utilities.zig").checkEqual;
const Thread = @import("thread.zig").Thread;
const object = @import("object.zig");
const Object = object.Object;
const Nil = object.Nil;
const NotAnObject = object.NotAnObject;
const True = object.True;
const False = object.False;
const u64_MINVAL = object.u64_MINVAL;
const Context = @import("context.zig").Context;
const TestExecution = @import("context.zig").TestExecution;
const arenas = @import("arenas.zig");
const heap = @import("heap.zig");
const HeapPtr = heap.HeapPtr;
pub const Hp = heap.HeaderArray;
const Format = heap.Format;
const Age = heap.Age;
const class = @import("class.zig");
const sym = @import("symbol.zig").symbols;
const uniqueSymbol = @import("symbol.zig").uniqueSymbol;
pub const tailCall: std.builtin.CallOptions = .{.modifier = .always_tail};
const noInlineCall: std.builtin.CallOptions = .{.modifier = .never_inline};
const print = std.debug.print;
pub const MethodReturns = void;

pub const CompiledByteCodeMethodPtr = *CompiledByteCodeMethod;
pub const CompiledByteCodeMethod = extern struct {
    header: heap.Header,
    name: Object,
    class: Object,
    stackStructure: Object, // number of local values beyond the parameters
    objects: ?[*]Object,
    methods: ?[*]CompiledByteCodeMethod,
    size: u64,
    code: [1] ByteCode,
    const Self = @This();
    const codeOffset = @offsetOf(CompiledByteCodeMethod,"code");
    const nIVars = codeOffset/@sizeOf(Object)-2;
    comptime {
        if (checkEqual(codeOffset,@offsetOf(CompileTimeByteCodeMethod(.{0}),"code"))) |s|
            @compileError("CompileByteCodeMethod prefix not the same as CompileTimeByteCodeMethod == " ++ s);
    }
    const pr = std.io.getStdOut().writer().print;
    pub fn init(name: Object, size: u64) Self {
        return Self {
            .header = undefined,
            .name = name,
            .class = Nil,
            .objects = null,
            .methods = null,
            .stackStructure = Object.from(0),
            .size = size,
            .code = [1]ByteCode{ByteCode.int(0)},
        };
    }
    fn codeSlice(self: * const CompiledByteCodeMethod) [] const ByteCode{
        @setRuntimeSafety(false);
        return self.code[0..self.codeSize()];
    }
    pub fn codePtr(self: * const CompiledByteCodeMethod) [*] const ByteCode {
        return @ptrCast([*]const ByteCode,&self.code[0]);
    }
    inline fn codeSize(self: * const CompiledByteCodeMethod) usize {
        return @alignCast(8,&self.header).inHeapSize()-@sizeOf(Self)/@sizeOf(Object)+1;
    }
    fn matchedSelector(pc: [*] const ByteCode) bool {
        _ = pc;
        return true;
    }
    fn methodFromCodeOffset(pc: [*] const ByteCode) CompiledByteCodeMethodPtr {
        const method = @intToPtr(CompiledByteCodeMethodPtr,@ptrToInt(pc)-codeOffset-(pc[0].uint)*@sizeOf(ByteCode));
        return method;
    }
    fn print(self: *Self) void {
        pr("CByteCodeMethod: {} {} {} {} (",.{self.header,self.name,self.class,self.stackStructure}) catch @panic("io");
//            for (self.code[0..]) |c| {
//                pr(" 0x{x:0>16}",.{@bitCast(u64,c)}) catch @panic("io");
//            }
        pr(")\n",.{}) catch @panic("io");
    }
};
pub const ByteCode = enum(i8) {
    noop,
    branch,
    ifTrue,
    ifFalse,
    primFailure,
    dup,
    over,
    drop,
    pushLiteral,
    pushLiteral0,
    pushLiteral1,
    pushNil,
    pushTrue,
    pushFalse,
    popIntoTemp,
    popIntoTemp1,
    pushTemp,
    pushTemp1,
    lookupByteCodeMethod,
    send,
    call,
    pushContext,
    returnTrampoline,
    returnWithContext,
    returnTop,
    returnNoContext,
    dnu,
    return_tos,
    failed_test,
    unexpected_return,
    dumpContext,
    exit,
    _,
    const Self = @This();
    fn interpret(method: *CompiledByteCodeMethod, _pc: [*]const ByteCode, _sp: [*]Object, _: Hp, _: *Thread, _: *Context(ByteCode,*CompiledByteCodeMethod)) void {
        var pc = _pc;
        var sp = _sp;
        while (true) {
            switch (pc[0]) {
                .noop => {},
                .pushLiteral => {sp-=1;sp[0]=method.objects[@intCast(usize,@enumToInt(pc[1]))];pc+=1;},
                .return_tos => return,
                .exit => @panic("fell off the end"),
                else => { var buf: [100]u8 = undefined;
                         @panic(std.fmt.bufPrint(buf[0..], "unexpected bytecode {}", .{pc[0]}) catch unreachable);
                         }
            }
            pc += 1;
        }
    }
    inline fn asInt(self: Self) i8 {
        return @enumToInt(self);
    }
    inline fn asObject(_: Self) Object {
        return Nil;
    }
    inline fn int(i: i8) ByteCode {
        return @intToEnum(ByteCode,i);
    }
};
fn countNonLabels(comptime tup: anytype) struct
    {
        codeSize : usize,
        nObjects : usize,
        nMethods : usize,
} {
    var n = 1;
    var o = 0;
    var m = 0;
    inline for (tup) |field| {
        switch (@TypeOf(field)) {
            Object => {o+=1;n+=1;},
            @TypeOf(null) => {n+=1;},
            comptime_int,comptime_float => {n+=1;},
            ByteCode => {n+=1;},
            else => 
                switch (@typeInfo(@TypeOf(field))) {
                    .Pointer => {if (field[field.len-1]!=':') n = n + 1;},
                    else => {n = n+1;},
            }
        }
    }
        return .{
            .codeSize = n,
            .nObjects = o,
            .nMethods = m};
}
fn CompileTimeByteCodeMethod(comptime tup: anytype) type {
    const counts = countNonLabels(tup);
    return extern struct { // structure must exactly match CompiledByteCodeMethod
        header: heap.Header,
        name: Object,
        class: Object,
        stackStructure: Object,
        objects: ?[*]Object,
        methods: ?[*]CompiledByteCodeMethod,
        size: u64,
        code: [counts.codeSize] ByteCode,
        objArray: [counts.nObjects] Object,
        methodArray: [counts.nMethods] CompiledByteCodeMethod,
        const pr = std.io.getStdOut().writer().print;
        const codeOffsetInUnits = CompiledByteCodeMethod.codeOffset/@sizeOf(ByteCode);
        const methodIVars = CompiledByteCodeMethod.nIVars;
        const Self = @This();
        fn init(name: Object, comptime locals: comptime_int) Self {
            return Self {
                .header = heap.header(methodIVars,Format.both,class.CompiledMethod_I,name.hash24(),Age.static),
                .name = name,
                .class = Nil,
                .stackStructure = Object.packedInt(locals,locals+name.numArgs(),0),
                .objects = null,
                .methods = null,
                .size = counts.codeSize+counts.nObjects+counts.nMethods,
                .code = undefined,
                .objArray = undefined,
                .methodArray = undefined,
            };
        }
        pub fn asCompiledByteCodeMethodPtr(self: *Self) * CompiledByteCodeMethod {
            return @ptrCast(* CompiledByteCodeMethod,self);
        }
        pub fn update(_: *Self, _: Object, _: CompiledByteCodeMethodPtr) void {
//            for (self.code) |*c| {
//                if (c.asObject().equals(tag)) c.* = ByteCode.method(method);
            //            }
            unreachable;
        }
        fn headerOffset(_: *Self, codeIndex: usize) ByteCode {
            return ByteCode.uint(codeIndex+codeOffsetInUnits);
        }
        fn getCodeSize(_: *Self) usize {
            return counts.codeSize;
        }
        fn print(self: *Self) void {
            pr("CTByteCodeMethod: {} {} {} {} (",.{self.header,self.name,self.class,self.stackStructure}) catch @panic("io");
            for (self.code[0..]) |c| {
                pr(" 0x{x:0>16}",.{@bitCast(u64,c)}) catch @panic("io");
            }
            pr(")\n",.{}) catch @panic("io");
        }
    };
}
pub fn compileByteCodeMethod(name: Object, comptime parameters: comptime_int, comptime locals: comptime_int, comptime tup: anytype) CompileTimeByteCodeMethod(tup) {
    @setEvalBranchQuota(2000);
    const methodType = CompileTimeByteCodeMethod(tup);
    var method = methodType.init(name,locals);
    comptime var n = 0;
    comptime var o: i8 = 0;
//    comptime var m: i8 = 0;
    _ = parameters;
    method.objects = &method.objArray;
    method.methods = &method.methodArray;
    inline for (tup) |field| {
        switch (@TypeOf(field)) {
            Object => {method.code[n]=ByteCode.int(o);method.objArray[o]=field;o+=1;n+=1;},
            @TypeOf(null) => {method.code[n]=ByteCode.object(Nil);n+=1;},
            comptime_int => {method.code[n]=ByteCode.int(field);n+=1;},
            ByteCode => {method.code[n]=field;n+=1;},
            else => {
                comptime var found = false;
                switch (@typeInfo(@TypeOf(field))) {
                    .Pointer => {
                        if (field[field.len-1]==':') {
                            found = true;
                        } else if (field.len==1 and field[0]=='^') {
                            method.code[n]=ByteCode.int(n);
                            n=n+1;
                            found = true;
                        } else if (field.len==1 and field[0]=='*') {
                            method.code[n]=ByteCode.int(-1);
                            n=n+1;
                            found = true;
                        } else {
                            comptime var lp = 0;
                            inline for (tup) |t| {
                                if (@TypeOf(t) == ByteCode) lp+=1
                                    else
                                    switch (@typeInfo(@TypeOf(t))) {
                                        .Pointer => {
                                            if (t[t.len-1]==':') {
                                                if (comptime std.mem.startsWith(u8,t,field)) {
                                                    method.code[n]=ByteCode.int(lp-n-1);
                                                    n+=1;
                                                    found = true;
                                                }
                                            } else lp+=1;
                                        },
                                        else => {lp+=1;},
                                }
                            }
                            if (!found) @compileError("missing label: \""++field++"\"");
                        }
                    },
                    else => {},
                }
                if (!found) @compileError("don't know how to handle \""++@typeName(@TypeOf(field))++"\"");
            },
        }
    }
    method.code[n]=ByteCode.exit;
//    method.print();
    return method;
}
const b = ByteCode;
test "compiling method" {
    const expectEqual = std.testing.expectEqual;
    const mref = comptime uniqueSymbol(42);
    var m = compileByteCodeMethod(Nil,0,0,.{"abc:", b.return_tos, "def", True, comptime Object.from(42), "def:", "abc", "*", "^", 3, mref, Nil});
//    const mcmp = m.asCompiledByteCodeMethodPtr();
//    m.update(mref,mcmp);
    var t = m.code[0..];
    for (t) | v,idx | {
        std.debug.print("t[{}] = {}\n",.{idx,v});
    }
    try expectEqual(t.len,11);
    try expectEqual(t[0],b.return_tos);
    try expectEqual(t[1].asInt(),2);
    try expectEqual(t[2].asObject(),True);
    try expectEqual(t[3].asObject(),Object.from(42));
    try expectEqual(t[4].asInt(),-5);
    try expectEqual(t[5].asInt(),-1);
    try expectEqual(t[6].asInt(),7);
//    try expectEqual(t[?].asMethodPtr(),mcmp);
    try expectEqual(t[7].asInt(),3);
//    try expectEqual(t[8].method,mcmp);
    try expectEqual(t[9].asObject(),Nil);
}
test "simple return via execute" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(Nil,0,0,.{
        b.noop,
        b.return_tos,
    });
    var te = TestExecution(ByteCode,CompiledByteCodeMethod,&b.interpret).new();
    te.init();
    var objs = [_]Object{Nil};
    var result = te.run(objs[0..],method.asCompiledByteCodeMethodPtr());
    try expectEqual(result[0],Nil);
}
test "simple return via TestExecution" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(Nil,0,0,.{
        b.noop,
        b.pushLiteral,comptime Object.from(42),
        b.returnNoContext,
    });
    var te = TestExecution(ByteCode,CompiledByteCodeMethod,&b.interpret).new();
    te.init();
    var objs = [_]Object{Nil,True};
    var result = te.run(objs[0..],method.asCompiledByteCodeMethodPtr());
    try expectEqual(result.len,3);
    try expectEqual(result[0],Object.from(42));
    try expectEqual(result[1],Nil);
    try expectEqual(result[2],True);
}
test "context return via TestExecution" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(Nil,0,0,.{
        b.noop,
        b.pushContext,"^",
        b.pushLiteral,comptime Object.from(42),
        b.returnWithContext,1,
    });
    var te = TestExecution(ByteCode,CompiledByteCodeMethod,&b.interpret).new();
    te.init();
    var objs = [_]Object{Nil,True};
    var result = te.run(objs[0..],method.asCompiledByteCodeMethodPtr());
    try expectEqual(result.len,1);
    try expectEqual(result[0],True);
}
test "context returnTop via TestExecution" {
    const expectEqual = std.testing.expectEqual;
    var method = compileByteCodeMethod(Nil,0,0,.{
        b.noop,
        b.pushContext,"^",
        b.pushLiteral,comptime Object.from(42),
        b.returnTop,1,
    });
    var te = TestExecution(ByteCode,CompiledByteCodeMethod,&b.interpret).new();
    te.init();
    var objs = [_]Object{Nil,True};
    var result = te.run(objs[0..],method.asCompiledByteCodeMethodPtr());
    try expectEqual(result.len,1);
    try expectEqual(result[0],Object.from(42));
}
test "simple executable" {
    var method = compileByteCodeMethod(Nil,0,1,.{
        b.pushContext,"^",
        "label1:",
        b.pushLiteral,comptime Object.from(42),
        b.popIntoTemp,1,
        b.pushTemp1,
        b.pushLiteral0,
        b.pushTrue,
        b.ifFalse,"label3",
        b.branch,"label2",
        "label3:",
        b.pushTemp,1,
        "label4:",
        b.returnWithContext,1,
        "label2:",
        b.pushLiteral0,
        b.branch,"label4",
    });
    var objs = [_]Object{Nil};
    var te = TestExecution(ByteCode,CompiledByteCodeMethod,&b.interpret).new();
    te.init();
    _ = te.run(objs[0..],method.asCompiledByteCodeMethodPtr());
}
