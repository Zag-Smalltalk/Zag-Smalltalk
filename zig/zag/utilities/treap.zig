// Implementation of a treap
const std = @import("std");
const math = std.math;
const Order = math.Order;
const mem = std.mem;
const includeStdTest = false;
pub fn Treap(comptime Key:type, comptime Index:type,comptime Value:type) type {
    const ElementS = struct {
        key: Key,
        left: Index,
        right: Index,
        value: Value,
    };
    const Compare = * const fn (Key,Key) Order;
    return struct {
        table: []ElementS,
        compare: Compare,
        empty: Key,
        const Element = ElementS;
        pub const elementSize = @sizeOf(Element);
        const Self = @This();
        const Equal = Order.eq;
        const Less = Order.lt;
        const Greater = Order.gt;
        const _priority = if (includeStdTest) struct {
            inline fn priority(pos:Index) Index { // "random" number based on position in the array
                return rands[pos];
            }
            const rands = [_]u8{200,73,48,92,21,50,55,44};
        } else struct {
            inline fn priority(pos:Index) Index { // "random" number based on position in the array
                return pos *% randomizer;
            }
            const randomizer = @import("general.zig").inversePhi(Index);
        };
        const priority = _priority.priority;
        pub fn init(memory: []u8, compare: Compare, empty: Key) Self {
            // if this is allocated on an object heap, left,right as an object will together look like an f64 so it will be ignored by garbage collection
            var treap = ref(memory,compare,empty);
            treap.setRoot(0);
            treap.extend(1);
            return treap;
        }
        pub fn ref(memory: []u8, compare: Compare, empty: Key) Self {
            return Self {
                .table = mem.bytesAsSlice(Element,@alignCast(@alignOf(ElementS),memory)),
                .compare = compare,
                .empty = empty,
            };
        }
        pub fn initEmpty(compare: Compare, empty: Key) Self {
            return Self {
                .table =  &[0]ElementS{},
                .compare = compare,
                .empty = empty,
            };
        }
        pub fn extend(self: *Self, start: Index) void {
            self.setFree(start);
            var index = start+1;
            for (self.table[start..]) |*element| {
                element.key=self.empty;
                element.left=index;
                element.right=0;
                element.value=undefined;
                index += 1;
            }
            self.table[self.table.len-1].left=0;
        }
        pub fn resize(self: *Self, memory: []u8) Self {
            var treap = ref(memory,self.compare,self.empty);
            for (self.table,0..) | element,i | treap.table[i] = element;
            treap.extend(@intCast(Index,self.table.len));
            return treap;
        }
        inline fn root(self: *const Self) Index {
            return self.table[0].right;
        }
        inline fn setRoot(self: *Self,r: Index) void {
            self.table[0].right=r;
        }
        pub fn hasRoom(self: *Self,_n: usize) bool {
            if (self.table.len==0) return false;
            var free =self.getFree();
            var n = _n;
            while (n > 0 and free > 0) {
                n -= 1;
                free = self.table[free].left;
            }
            return n == 0;
        }
        inline fn setFree(self: *Self,f: Index) void {
            self.table[0].left=f;
        }
        fn getFree(self: *Self) Index {
            if (self.table.len==0) return 0;
            return self.table[0].left;
        }
        pub fn nextFree(self: *Self) !Index {
            const pos = self.getFree();
            if (pos==0) return error.OutOfSpace;
            self.setFree(self.table[pos].left);
            self.table[pos].left=0;
            return pos;
        }
        pub fn getKey(self: *Self, index: Index) Key {
            return self.table[index].key;
        }
        pub fn getValue(self: *Self, index: Index) Value {
            return self.table[index].value;
        }
        pub fn setValue(self: *Self, index: Index, value: Value) void {
            self.table[index].value = value;
        }
        pub inline fn lookup(self: *const Self, key: Key) Index {
            return self.lookupElement(self.root(),key);
        }
        fn lookupElement(self: *const Self,current:Index,key:Key) Index {
            if (current==0) {
                return 0;
            } else switch (self.compare(self.table[current].key,key)) {
                Equal => return current,
                Less => return self.lookupElement(self.table[current].right,key),
                Greater => return self.lookupElement(self.table[current].left ,key),
            }
        }
        pub inline fn greaterEqual(self: *const Self, key: Key) Index {
            return self.lookupElementGE(self.root(),key,0);
        }
        fn lookupElementGE(self: *const Self,current:Index,key:Key,left:Index) Index {
            if (current==0) {
                return left;
            } else switch (self.compare(self.table[current].key,key)) {
                Equal => return current,
                Less => return self.lookupElementGE(self.table[current].right,key,current),
                Greater => return self.lookupElementGE(self.table[current].left,key,left),
            }
        }
        pub fn insert(self: *Self,key: Key) !Index {
            const result = self.lookup(key);
            if (result>0) {
                // might have been added while waiting for the write lock
                return result;
            }
            const pos = try self.nextFree();
            self.table[pos].key=key;
            self.setRoot(self.insertElement(pos,self.root()));
            return pos;
        }
        fn insertElement(self: *Self,target:Index,current:Index) Index {
            if (current==0)
                return target;
            switch (self.compare(self.table[target].key,self.table[current].key)) {
                Equal => @panic("shouldn't be inserting an existing key"),
                Less => {
                    self.table[current].left = self.insertElement(target,self.table[current].left);
                    // Fix Heap property if it is violated
                    if (priority(self.table[current].left) > priority(current)) {
                        return self.rightRotate(current);
                    } else
                        return current;
                },
                Greater => {
                    self.table[current].right = self.insertElement(target,self.table[current].right);
                    // Fix Heap property if it is violated
                    if (priority(self.table[current].right) > priority(current)) {
                        return self.leftRotate(current);
                    } else
                        return current;
                },
            }
        }
        // T1, T2 and T3 are subtrees of the tree rooted with y
        // (on left side) or x (on right side)
        //           y                               x
        //          / \     Right Rotation          /  \
        //         x   T3   – – – – – – – >        T1   y
        //        / \       < - - - - - - -            / \
        //       T1  T2     Left Rotation            T2  T3
        //
        fn rightRotate(self: *Self,y:Index) Index {
            const x = self.table[y].left;
            const t2 = self.table[x].right;
            // Perform rotation
            self.table[x].right = y;
            self.table[y].left = t2;
            return x;
        }
        fn leftRotate(self: *Self,x:Index) Index {
            const y = self.table[x].right;
            const t2 = self.table[y].left;
            // Perform rotation
            self.table[y].left = x;
            self.table[x].right = t2;
            return y;
        }
        pub fn remove(self: *Self, key:Key) void {
            self.setRoot(self.removeKey(self.root(),key));
        }
        fn removeKey(self: *Self, pos: Index, key: Key) Index {
            if (pos==0) return 0;
            const node = &self.table[pos];
            switch (self.compare(key,node.key)) {
                Less => {
                    node.left = self.removeKey(node.left,key);
                    return pos;
                },
                Greater => {
                    node.right = self.removeKey(node.right,key);
                    return pos;
                },
                Equal => {
                    if (node.left == 0) {
                        const temp = node.right;
                        self.delete(pos);
                        return temp;
                    }
                    if (node.right == 0) {
                        const temp = node.left;
                        self.delete(pos);
                        return temp;
                    }
                    if (priority(node.left) < priority(node.right)) {
                        const temp = self.leftRotate(pos);
                        self.table[temp].left = self.removeKey(self.table[temp].left, key);
                        return temp;
                    } else {
                        const temp = self.rightRotate(pos);
                        self.table[temp].right = self.removeKey(self.table[temp].right, key);
                        return temp;
                    }
                },
            }
            unreachable;
        }
        fn delete(self: *Self, pos: Index) void {
            const node = &self.table[pos];
            node.key = self.empty;
            node.left = self.getFree();
            node.right = 0;
            node.value = undefined;
            self.setFree(pos);
        }
        // Only for tests
        pub fn inorderPrint(self: *Self) void {
            std.debug.print("root: {}\n",.{self.root()});
            self.inorderWalkPrint(self.root());
        }
        fn inorderWalkPrint(self: *const Self, pos: Index) void {
            if (pos>0) {
                const node = self.table[pos];
                self.inorderWalkPrint(node.left);
                std.debug.print("pos:{:3}({})",.{pos,node.key});
                if (node.left>0) std.debug.print(" | left: {:3}({})",.{node.left,self.table[node.left].key});
                if (node.right>0) std.debug.print(" | right:{:3}({})",.{node.right,self.table[node.right].key});
                std.debug.print(" priority: {:10}\n",.{priority(pos)});
                self.inorderWalkPrint(node.right);
            }
        }
        fn depths(self: *Self, data: []Index) void {
            self.walk(self.root(),1,data);
        }
        fn walk(self: *Self, pos: Index, depth: Index, data: []Index) void {
            data[pos]=depth;
            if (self.table[pos].left>0) {
                self.walk(self.table[pos].left,depth+1,data);
                if (self.table[pos].right>0)
                    self.walk(self.table[pos].right,depth+1,data);
            } else if (self.table[pos].right>0) {
                self.walk(self.table[pos].right,depth+1,data);
            }
        }
    };
}
fn compareU64(l: u64, r: u64) Order {
    return math.order(l,r);
}
const Treap_u64 = Treap(u64,u32,u0);
test "treap element sizes" {
    const expectEqual = @import("std").testing.expectEqual;
    try expectEqual(@sizeOf(Treap_u64.Element),16);
    try expectEqual(@sizeOf(Treap(u32,u16,u32).Element),12);
    try expectEqual(@sizeOf(Treap(u32,u16,u0).Element),8);
    try expectEqual(@sizeOf(Treap(u32,u16,u8).Element),12);
}
test "from https://www.geeksforgeeks.org/treap-set-2-implementation-of-search-insert-and-delete/" {
    if (includeStdTest) {
        const n = 20;
        var memory = [_]u8{0} ** ((n+1)*Treap_u64.elementSize);
        var treap = Treap_u64.init(memory[0..],compareU64,0);
        _ = try treap.insert(50);
        _ = try treap.insert(30);
        _ = try treap.insert(20);
        _ = try treap.insert(40);
        _ = try treap.insert(70);
        _ = try treap.insert(60);
        _ = try treap.insert(80);
        std.debug.print("\nInorder traversal of the given tree \n",.{});
        treap.inorderPrint();
        treap.remove(20);
        std.debug.print("Inorder traversal of the tree after remove 20 \n",.{});
        treap.inorderPrint();
        treap.remove(30);
        std.debug.print("Inorder traversal of the tree after remove 20,30 \n",.{});
        treap.inorderPrint();
        treap.remove(50);
        std.debug.print("Inorder traversal of the tree after remove 20,30,50 \n",.{});
        treap.inorderPrint();
        _ = try treap.insert(20);
        _ = try treap.insert(30);
        _ = try treap.insert(50);
        std.debug.print("Inorder traversal of the tree after added back \n",.{});
        treap.inorderPrint();
    } else
        std.debug.print(" - Set includeStdTest=true to include this test ",.{});
}
test "simple u64 treap alloc with nextFree" {
    const expectEqual = @import("std").testing.expectEqual;
    var memory = [_]u8{0} ** (4*Treap_u64.elementSize);
    var treap = Treap_u64.init(memory[0..],compareU64,0);
    try expectEqual(treap.hasRoom(3),true);
    try expectEqual(treap.hasRoom(4),false);
    const f2 = try treap.insert(42);
    try expectEqual(f2,1);
    std.debug.print("\ntreap = {*}",.{treap.table[0..]});
    try expectEqual(treap.hasRoom(1),true);
    try expectEqual(treap.nextFree(),2);
    const f1 = try treap.insert(17);
    try expectEqual(f1,3);
    try expectEqual(treap.hasRoom(1),false);
}
test "simple u64 treap with values" {
    const expectEqual = @import("std").testing.expectEqual;
    const Treap_u64V = Treap(u64,u32,u64);
    var memory = [_]u8{0} ** (4*Treap_u64V.elementSize);
    var treap = Treap_u64V.init(memory[0..],compareU64,0);
    const f2 = try treap.insert(42);
    treap.setValue(f2,92);
    try expectEqual(f2,1);
    try expectEqual(treap.nextFree(),2);
    const f1 = try treap.insert(17);
    try expectEqual(f1,3);
    treap.setValue(f1,99);
    try expectEqual(treap.getValue(f2),92);
}
test "resize u64 treap with values" {
    const expectEqual = @import("std").testing.expectEqual;
    const Treap_u64V = Treap(u64,u32,u64);
    var memory = [_]u8{0} ** (4*Treap_u64V.elementSize);
    var treap = Treap_u64V.init(memory[0..],compareU64,0);
    try expectEqual(treap.table.len,4);
    const f2 = try treap.insert(42);
    treap.setValue(f2,92);
    try expectEqual(f2,1);
    try expectEqual(treap.nextFree(),2);
    const f1 = try treap.insert(17);
    try expectEqual(f1,3);
    treap.setValue(f1,99);
    try expectEqual(treap.getValue(f2),92);
    try expectEqual(treap.hasRoom(1),false);
    var memory2 = [_]u8{0} ** (6*Treap_u64V.elementSize);
    var treap2 = treap.resize(memory2[0..]);
    try expectEqual(treap2.table.len,6);
    try expectEqual(treap2.hasRoom(2),true);
    try expectEqual(treap2.hasRoom(3),false);
    const f3 = try treap2.insert(19);
    try expectEqual(try treap2.insert(17),f1);
    try expectEqual(treap2.hasRoom(1),true);
    try expectEqual(treap2.hasRoom(2),false);
    try expectEqual(f3,4);
    try expectEqual(treap2.getValue(f2),92);
}
test "simple u64 treap alloc" {
    const expectEqual = @import("std").testing.expectEqual;
    const n = 5;
    var memory align(@alignOf(Treap_u64.Element)) = [_]u8{0} ** ((n+1)*Treap_u64.elementSize);
    var treap = Treap_u64.init(memory[0..],compareU64,0);
    try expectEqual(treap.lookup(42),0);
    const f2 = try treap.insert(42);
    try expectEqual(f2,1);
    try expectEqual(treap.lookup(42),1);
    try expectEqual(treap.getKey(f2),42);
    const f1 = try treap.insert(17);
    try expectEqual(f1,2);
    const f3 = try treap.insert(94);
    const t3 = try treap.insert(94);
    try expectEqual(f3,3);
    try expectEqual(f3,t3);
    try expectEqual(treap.getKey(f3),94);
    _ = try treap.insert(43);
    _ = try treap.insert(44);
    try expectEqual(treap.lookup(44),5);
    var depths = [_]u32{0} ** ((n+1)*3);
    treap.depths(depths[0..]);
    // std.debug.print("treap={}\n",.{treap});
    // std.debug.print("depths={any}\n",.{depths});
}
test "full u64 treap alloc" {
    if (includeStdTest) {
        std.debug.print(" - Set includeStdTest=false to include this test ",.{});
    } else {
        const expectEqual = @import("std").testing.expectEqual;
        const n = 21;
        var memory = [_]u8{0} ** ((n+1)*Treap_u64.elementSize);
        var treap = Treap_u64.init(memory[0..],compareU64,0);
        var index : u64 = 1;
        while (treap.hasRoom(1)) : (index += 1) {
            _ = try treap.insert(index);
        }
        try expectEqual(treap.lookup(20),20);
        var depths = [_]u32{0} ** (n+1);
        treap.depths(depths[0..]);
        // std.debug.print("depths={any}\n",.{depths});
        // std.debug.print("treap={}\n",.{treap});
    }
}
test "simple u64 treap range" {
    const expectEqual = @import("std").testing.expectEqual;
    const n = 4;
    var memory = [_]u8{0} ** ((n+1)*Treap_u64.elementSize);
    var treap = Treap_u64.init(memory[0..],compareU64,0);
    const f10 = try treap.insert(10);
    const f20 = try treap.insert(20);
    _ = try treap.insert(30);
    const f40 = try treap.insert(40);
    try expectEqual(treap.greaterEqual(10),f10);
    try expectEqual(treap.greaterEqual(20),f20);
    try expectEqual(treap.greaterEqual(11),f10);
    try expectEqual(treap.greaterEqual(29),f20);
    try expectEqual(treap.greaterEqual(9),0);
    try expectEqual(treap.greaterEqual(100),f40);

}
