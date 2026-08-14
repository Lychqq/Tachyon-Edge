const std = @import("std");
const p2p = @import("p2p.zig");

// Override std options to fix Android Python CDLL thread crash
pub const std_options = .{
    .page_size_min = 4096,
    .page_size_max = 65536,
};
const builtin = @import("builtin");

// Safe C-FFI representation of a packet
pub const CPacket = extern struct {
    topic_ptr: [*]const u8,
    topic_len: usize,
    vector_ptr: [*]const f16,
    vector_len: usize,
};

pub const CCallback = *const fn (packet: CPacket) callconv(.c) void;

// Thread-local or global reference to map C-callback to Zig callback
var current_c_callback: ?CCallback = null;

fn zigCallbackWrapper(packet: p2p.EmbeddingPacket) void {
    if (current_c_callback) |cb| {
        const c_packet = CPacket{
            .topic_ptr = packet.topic.ptr,
            .topic_len = packet.topic.len,
            .vector_ptr = packet.vector.ptr,
            .vector_len = packet.vector.len,
        };
        cb(c_packet);
    }
}

export fn node_init(pub_port: u16, secret_ptr: [*]const u8, secret_len: usize) ?*p2p.Node {
    const allocator = std.heap.page_allocator;
    const node_ptr = allocator.create(p2p.Node) catch return null;

    const secret = secret_ptr[0..secret_len];
    node_ptr.* = p2p.Node.init(allocator, pub_port, secret) catch {
        allocator.destroy(node_ptr);
        return null;
    };

    return node_ptr;
}

export fn node_deinit(node: ?*p2p.Node) void {
    if (node) |n| {
        n.deinit();
        std.heap.page_allocator.destroy(n);
    }
}

export fn node_start(node: ?*p2p.Node) c_int {
    if (node) |n| {
        n.start() catch return -1;
        return 0;
    }
    return -1;
}

export fn node_start_discovery(node: ?*p2p.Node, port: u16) c_int {
    if (node) |n| {
        n.startDiscovery(port) catch return -1;
        return 0;
    }
    return -1;
}

export fn node_connect(node: ?*p2p.Node, endpoint_ptr: [*]const u8, endpoint_len: usize, public_key_ptr: [*]const u8) c_int {
    if (node) |n| {
        const endpoint_full = endpoint_ptr[0..endpoint_len];
        // Parse "tcp://IP:PORT"
        const prefix = "tcp://";
        if (!std.mem.startsWith(u8, endpoint_full, prefix)) return -1;
        
        const ip_port = endpoint_full[prefix.len..];
        var parts = std.mem.splitScalar(u8, ip_port, ':');
        const ip = parts.next() orelse return -1;
        const port_str = parts.next() orelse return -1;
        const port = std.fmt.parseInt(u16, port_str, 10) catch return -1;
        
        const public_key = public_key_ptr[0..32]; // Pure X25519 is 32 bytes
        n.connect(ip, port, public_key) catch return -1;
        return 0;
    }
    return -1;
}

export fn node_get_public_key(node: ?*p2p.Node, out_key_ptr: [*]u8) void {
    if (node) |n| {
        @memcpy(out_key_ptr[0..32], n.public_key[0..32]);
    }
}

export fn node_broadcast(node: ?*p2p.Node, topic_ptr: [*]const u8, topic_len: usize, vector_ptr: [*]const f16, vector_len: usize) c_int {
    if (node) |n| {
        const topic = topic_ptr[0..topic_len];
        const vector = vector_ptr[0..vector_len];
        n.broadcastEmbedding(topic, vector) catch return -1;
        return 0;
    }
    return -1;
}

export fn node_flush(node: ?*p2p.Node) c_int {
    if (node) |n| {
        n.flush() catch return -1;
        return 0;
    }
    return -1;
}

export fn node_start_listener(node: ?*p2p.Node, callback: CCallback) c_int {
    if (node) |n| {
        current_c_callback = callback;
        n.startListener(zigCallbackWrapper) catch return -1;
        return 0;
    }
    return -1;
}
