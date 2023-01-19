const std = @import("std");
const checkEqual = @import("utilities.zig").checkEqual;
const Thread = @import("thread.zig").Thread;
const object = @import("object.zig");
const Object = object.Object;
const Nil = object.Nil;
const True = object.True;
const False = object.False;
const u64_MINVAL = object.u64_MINVAL;
const arenas = @import("arenas.zig");
const heap = @import("heap.zig");
const HeapPtr = heap.HeapPtr;
pub const Hp = heap.HeaderArray;
const Format = heap.Format;
const Age = heap.Age;
const class = @import("class.zig");
const execute = @import("execute.zig");
const tailCall = execute.tailCall;
const Code = execute.Code;
const CompiledMethod = execute.CompiledMethod;
const CompiledMethodPtr = execute.CompiledMethodPtr;
const MethodReturns = execute.MethodReturns;
pub const Context = struct {
    header: heap.Header,
    tpc: [*]const Code, // threaded PC
    npc: ThreadedFn, // native PC - in Continuation Passing Style
    prevCtxt: ContextPtr,
    method: CompiledMethodPtr,
    size: u64,
    addr: *Object,
    temps: [1]Object,
    const Self = @This();
    const ContextPtr = *Self;
    const ThreadedFn = * const fn(programCounter: [*]const Code, stackPointer: [*]Object, heapPointer: Hp, thread: *Thread, context: ContextPtr) MethodReturns;
    const baseSize = @sizeOf(Self)/@sizeOf(Object) - 1;
    fn init() Self {
        return Self {
            .header = heap.header(4,Format.bothPP,class.Context_I,0,Age.static),
            .tpc = undefined,
            .npc = undefined,
            .prevCtxt = undefined,
            .method = undefined,
            .size = 0,
            .addr = undefined,
            .temps = undefined,
        };
    }
    pub fn format(
        self: ContextPtr,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("context: {}",.{self.header});
        try writer.print(" prev: 0x{x}",.{@ptrToInt(self.prevCtxt)});
        { @setRuntimeSafety(false);
         try writer.print(" temps: {any}",.{self.temps[0..self.size]});
         }
    }
    pub inline fn pop(self: ContextPtr, thread: *Thread) struct { sp: [*]Object,ctxt: ContextPtr } {
        const wordsToDiscard = self.asHeapPtr().hash16();
        if (self.isInStack())
            return .{.sp=self.asObjectPtr() + wordsToDiscard,.ctxt=self.prevCtxt};
        const itemsToKeep = self.temps[wordsToDiscard-baseSize..self.size];
        const newSp = thread.endOfStack() - itemsToKeep.len;
        for (itemsToKeep) | obj,index | {
            newSp[index] = obj;
        }
        return .{.sp=newSp,.ctxt=self.previous()};
    }
    pub inline fn push(self: ContextPtr, sp: [*]Object, hp: Hp, thread: *Thread, method: CompiledMethodPtr, locals: u16, maxStackNeeded: u16, selfOffset: u16)  struct { hp: Hp,ctxt: ContextPtr } {
        const newSp = sp - baseSize - locals;
        if (arenas.arenaFree(newSp,hp)<5+maxStackNeeded) @panic("grow heap1");
        const ctxt = @ptrCast(ContextPtr,@alignCast(@alignOf(Self),newSp));
        ctxt.prevCtxt = self;
        ctxt.method = method;
        { @setRuntimeSafety(false);
         for (ctxt.temps[0..locals]) |*local| {local.*=Nil;}
         }
        ctxt.header = heap.Header.partialOnStack(selfOffset+baseSize);
        //ctxt.size = ctxt.calculatedSize(thread); // ToDo: only needed of there is a format method
        if (thread.needsCheck()) @panic("thread needsCheck");
       return .{.hp=hp,.ctxt=ctxt};
    }
    fn convertToProperHeapObject(self: ContextPtr, sp: [*]Object, thread: *Thread) void {
        if (self.isIncomplete(sp,thread)) {
            self.header = heap.header(4, Format.bothAP, class.Context_I,0,Age.stack);
            self.size = self.prevCtxt.calculatedSize(thread);
            self.addr = self.temps;
            self.prevCtxt.convertToProperHeapObject(sp, thread);
        }
    }
    pub inline fn isIncomplete(self: * const Self) bool {
        return @alignCast(8,&self.header).isIncompleteContext();
    }
    pub inline fn isInStack(self: * const Self) bool {
        return @alignCast(8,&self.header).isInStack();
    }
    inline fn endOfStack(self: ContextPtr, thread: *Thread) [*]Object {
        return if (self.isInStack()) self.asObjectPtr() else thread.endOfStack();
    }
    inline fn calculatedSize(self: ContextPtr, thread: *Thread) usize {
        return (@ptrToInt(self.prevCtxt.endOfStack(thread))-@ptrToInt(&self.temps))/@sizeOf(Object);
    }
    pub inline fn stack(self: *Self, sp: [*]Object, thread: *Thread) []Object {
        return sp[0..(@ptrToInt(self.endOfStack(thread))-@ptrToInt(sp))/@sizeOf(Object)];
    }
    pub inline fn allTemps(self: ContextPtr) []Object {
        @setRuntimeSafety(false);
        return self.temps[0..self.size-2];
    }
    pub inline fn getTPc(self: ContextPtr) [*]const Code {
        return self.tpc;
    }
    pub inline fn setTPc(self: ContextPtr, pc: [*]const Code) void {
        self.tpc = pc;
    }
    pub inline fn getNPc(self: ContextPtr) ThreadedFn {
        return self.npc;
    }
    pub inline fn setNPc(self: ContextPtr, pc: ThreadedFn) void {
        self.npc = pc;
    }
    pub inline fn getSelf(self: ContextPtr) Object {
        const wordsToDiscard = self.asHeapPtr().hash16();
        @setRuntimeSafety(false);
        return (self.asObjectPtr() + wordsToDiscard)[0];
    }
    pub inline fn getTemp(self: ContextPtr, n: usize) Object {
        @setRuntimeSafety(false);
        return self.temps[n];
    }
    pub inline fn setTemp(self: ContextPtr, n: usize, v: Object) void {
        @setRuntimeSafety(false);
        self.temps[n] = v;
    }
    pub inline fn previous(self: ContextPtr) ContextPtr {
        return self.prevCtxt;
    }
    pub inline fn asHeapPtr(self : ContextPtr) HeapPtr {
        return @ptrCast(HeapPtr,self);
    }
    pub inline fn asObjectPtr(self : ContextPtr) [*]Object {
        return @ptrCast([*]Object,self);
    }
    inline fn fromObjectPtr(op: [*]Object) ContextPtr {
        return @ptrCast(ContextPtr,op);
    }
    fn collectNursery(pc: [*]const Code, sp: [*]Object, hp: Hp, thread: *Thread, context: ContextPtr) MethodReturns {
        if (true) @panic("need to collect nursery");
        return @call(tailCall,push,.{pc,sp,hp,thread,context});
    }
    fn print(self: ContextPtr)void{ //,sp: [*]Object, thread: *Thread) void {
        const pr = std.debug.print;
        pr("Self: {} {any}\n",.{self.header,self.allTemps()});
        //        if (self.prevCtxt) |ctxt| {ctxt.print(sp,thread);}
    }
};
pub const TestExecution = struct {
    thread: Thread,
    ctxt: Context,
    sp: [*]Object,
    hp: Hp,
    pc: [*]const Code,
    const Self = @This();
    var endSp: [*]Object = undefined;
    var endHp: Hp = undefined;
    var endPc: [*]const Code = undefined;
    var baseMethod = CompiledMethod.init(Nil,0,2);
    pub fn new() Self {
        return Self {
            .thread = Thread.new(),
            .ctxt = Context.init(),
            .sp = undefined,
            .hp = undefined,
            .pc = undefined,
        };
    }
    pub fn init(self: *Self) void {
        self.thread.init();
    }
    fn end(pc: [*]const Code, sp: [*]Object, hp: Hp, _: *Thread, _: * Context) void {
        endPc = pc;
        endHp = hp;
        endSp = sp;
    }
    pub fn run(self: *Self, source: [] const Object, method: CompiledMethodPtr) []Object {
        const sp = self.thread.endOfStack() - source.len;
        for (source) |src,idx|
            sp[idx] = src;
//        const pc = method.codePtr();
        const hp = self.thread.getHeap();
        self.ctxt.setNPc(Self.end);
        endSp = sp;
        endHp = hp;
//        endPc = pc;
        method.execute(sp,hp,&self.thread,&self.ctxt);
        self.sp = endSp;
        self.hp = endHp;
        self.pc = endPc;
        return self.ctxt.stack(self.sp,&self.thread);
    }
};
// test "init context" {
//     const expectEqual = std.testing.expectEqual;
// //    const objs = comptime [_]Object{True,Object.from(42)};
//     var result = TestExecution.init();
//     const c = result.context;
//     c.print();
//     try expectEqual(result.o()[3].u(),4);
//     try expectEqual(result.o()[6],True);
//     var thread = result.thread;
//     var sp = thread.endOfStack();
//     c.convertToProperHeapObject(sp, &thread);
//     c.print();
// }
