const objc = @import("../objc.zig");

// Verify class creation APIs are accessible
comptime {
    _ = objc.allocateClassPair;
    _ = objc.registerClassPair;
    _ = objc.addMethod;
}
