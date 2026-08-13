const std = @import("std");
pub const math = @import("math.zig");
pub const p2p = @import("p2p.zig");
pub const capi = @import("capi.zig");
comptime {
    _ = capi;
}

// Export commonly used types to root namespace for easier access
pub const Node = p2p.Node;
pub const EmbeddingPacket = p2p.EmbeddingPacket;
pub const EmbeddingCallback = p2p.EmbeddingCallback;
pub const cosineSimilarity = math.cosineSimilarity;
pub const cosineDistance = math.cosineDistance;

test {
    _ = math;
    _ = p2p;
    _ = capi;
}
