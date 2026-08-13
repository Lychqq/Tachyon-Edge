const std = @import("std");
const crypto = std.crypto;
const mem = std.mem;
const Io = std.Io;
const X25519 = crypto.dh.X25519;
const builtin = @import("builtin");
const Aead = crypto.aead.chacha_poly.ChaCha20Poly1305;

pub const EmbeddingPacket = struct {
    topic: []const u8,
    vector: []const f16,
};

pub const EmbeddingCallback = *const fn (packet: EmbeddingPacket) void;

// Simple custom framing and encryption
const PREFIX_LEN = 4;
const MAC_LEN = Aead.tag_length;

pub const Peer = struct {
    allocator: mem.Allocator,
    io: Io,
    socket: Io.net.Socket,
    rx_nonce: [12]u8 = std.mem.zeroes([12]u8),
    tx_nonce: [12]u8 = std.mem.zeroes([12]u8),
    rx_key: [32]u8,
    tx_key: [32]u8,
    peer_pub_key: [32]u8,
    is_server: bool,
    listen_thread: ?std.Thread = null,
    callback: ?EmbeddingCallback = null,
    
    pub fn init(allocator: mem.Allocator, io: Io, sock: Io.net.Socket, shared_secret: [32]u8, is_server: bool, peer_pub_key: [32]u8) !*Peer {
        const peer = try allocator.create(Peer);
        peer.* = .{
            .allocator = allocator,
            .io = io,
            .socket = sock,
            .is_server = is_server,
            .peer_pub_key = peer_pub_key,
            .rx_key = undefined,
            .tx_key = undefined,
        };
        
        // Derive directional keys to avoid nonce reuse
        var c2s_key: [32]u8 = undefined;
        var s2c_key: [32]u8 = undefined;
        crypto.hash.Blake3.hash(shared_secret ++ "client_to_server", &c2s_key, .{});
        crypto.hash.Blake3.hash(shared_secret ++ "server_to_client", &s2c_key, .{});
        
        if (is_server) {
            peer.rx_key = c2s_key;
            peer.tx_key = s2c_key;
        } else {
            peer.rx_key = s2c_key;
            peer.tx_key = c2s_key;
        }
        
        return peer;
    }
    
    pub fn deinit(self: *Peer) void {
        self.io.vtable.netClose(self.io.userdata, &.{self.socket});
        if (self.listen_thread) |*t| t.join();
        self.allocator.destroy(self);
    }
    
    fn incrementNonce(nonce: *[12]u8) void {
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            nonce[i] +%= 1;
            if (nonce[i] != 0) break;
        }
    }
    
    pub fn send(self: *Peer, topic: []const u8, vector: []const f16) !void {
        const pt_len = 2 + topic.len + 4 + vector.len * @sizeOf(f16);
        const ct_len = pt_len + MAC_LEN;
        var out_buf = try self.allocator.alloc(u8, PREFIX_LEN + ct_len);
        defer self.allocator.free(out_buf);
        
        mem.writeInt(u32, out_buf[0..4], @intCast(ct_len), .little);
        
        const pt = out_buf[PREFIX_LEN .. PREFIX_LEN + pt_len];
        mem.writeInt(u16, pt[0..2], @intCast(topic.len), .little);
        @memcpy(pt[2 .. 2 + topic.len], topic);
        mem.writeInt(u32, pt[2 + topic.len .. 2 + topic.len + 4][0..4], @intCast(vector.len), .little);
        @memcpy(pt[2 + topic.len + 4 .. pt_len], mem.sliceAsBytes(vector));
        
        var tag: [MAC_LEN]u8 = undefined;
        Aead.encrypt(out_buf[PREFIX_LEN .. PREFIX_LEN + pt_len], &tag, pt, "", self.tx_nonce, self.tx_key);
        @memcpy(out_buf[PREFIX_LEN + pt_len ..], &tag);
        incrementNonce(&self.tx_nonce);
        
        _ = try self.io.vtable.netWrite(self.io.userdata, self.socket.handle, &[_]u8{}, &[_][]const u8{out_buf}, 1);
    }
    
    pub fn listenLoop(self: *Peer) void {
        while (true) {
            var len_buf: [4]u8 = undefined;
            var len_data_arr = [_][]u8{&len_buf};
            const len_data: [][]u8 = &len_data_arr;
            
            const op_res = self.io.operate(.{ .net_read = .{ .socket_handle = self.socket.handle, .data = len_data } }) catch break;
            const bytes_read = op_res.net_read catch break;
            if (bytes_read != 4) break;
            
            const ct_len = mem.readInt(u32, &len_buf, .little);
            if (ct_len > 1024 * 1024 * 10) break; // 10MB limit
            
            const ct = self.allocator.alloc(u8, ct_len) catch break;
            defer self.allocator.free(ct);
            
            var ct_data_arr = [_][]u8{ct};
            const ct_data: [][]u8 = &ct_data_arr;
            const op_res2 = self.io.operate(.{ .net_read = .{ .socket_handle = self.socket.handle, .data = ct_data } }) catch break;
            const ct_read = op_res2.net_read catch break;
            if (ct_read != ct_len) break;
            
            const pt = self.allocator.alloc(u8, ct_len - MAC_LEN) catch break;
            defer self.allocator.free(pt);
            
            var tag: [MAC_LEN]u8 = undefined;
            @memcpy(&tag, ct[ct_len - MAC_LEN ..]);
            Aead.decrypt(pt, ct[0 .. ct_len - MAC_LEN], tag, "", self.rx_nonce, self.rx_key) catch break;
            incrementNonce(&self.rx_nonce);
            
            // Deserialize
            if (pt.len < 2) continue;
            const topic_len = mem.readInt(u16, pt[0..2], .little);
            if (pt.len < 2 + topic_len + 4) continue;
            
            const topic = pt[2 .. 2 + topic_len];
            const vec_len = mem.readInt(u32, pt[2 + topic_len .. 2 + topic_len + 4][0..4], .little);
            
            const vec_byte_len = vec_len * @sizeOf(f16);
            if (pt.len < 2 + topic_len + 4 + vec_byte_len) continue;
            
            const vec_bytes = pt[2 + topic_len + 4 .. 2 + topic_len + 4 + vec_byte_len];
            const aligned_vec = self.allocator.alloc(f16, vec_len) catch continue;
            defer self.allocator.free(aligned_vec);
            @memcpy(mem.sliceAsBytes(aligned_vec), vec_bytes);
            
            if (self.callback) |cb| {
                cb(.{ .topic = topic, .vector = aligned_vec });
            }
        }
    }
};

pub const Node = struct {
    allocator: mem.Allocator,
    threaded_io: *Io.Threaded,
    io: Io,
    keypair: X25519.KeyPair,
    public_key: [32]u8, // Only 32 bytes for pure X25519!
    tcp_port: u16,
    server_socket: ?Io.net.Socket = null,
    discovery_socket: ?Io.net.Socket = null,
    peers: std.ArrayListUnmanaged(*Peer),
    peers_mutex: Io.RwLock,
    callback: ?EmbeddingCallback = null,
    accept_thread: ?std.Thread = null,
    discovery_recv_thread: ?std.Thread = null,
    discovery_send_thread: ?std.Thread = null,
    stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    
    pub fn init(allocator: mem.Allocator, listen_port: u16) !Node {
        const threaded_io = try allocator.create(Io.Threaded);
        threaded_io.* = Io.Threaded.init(allocator, .{});
        const io = threaded_io.io();
        
        const keypair = X25519.KeyPair.generate(io);
        var self = Node{
            .allocator = allocator,
            .threaded_io = threaded_io,
            .io = io,
            .keypair = keypair,
            .public_key = keypair.public_key,
            .tcp_port = listen_port,
            .peers = std.ArrayListUnmanaged(*Peer).empty,
            .peers_mutex = Io.RwLock.init,
        };
        
        if (listen_port != 0) {
            const address = try Io.net.IpAddress.parseIp4("0.0.0.0", listen_port);
            self.server_socket = try io.vtable.netListenIp(io.userdata, &address, .{});
        }
        
        return self;
    }
    
    pub fn deinit(self: *Node) void {
        self.stop_signal.store(true, .seq_cst);
        if (self.server_socket) |s| {
            self.io.vtable.netClose(self.io.userdata, &.{s});
        }
        if (self.discovery_socket) |s| {
            self.io.vtable.netClose(self.io.userdata, &.{s});
        }
        if (self.accept_thread) |*t| t.join();
        if (self.discovery_recv_thread) |*t| t.join();
        if (self.discovery_send_thread) |*t| t.join();
        
        self.peers_mutex.lockUncancelable(self.io);
        for (self.peers.items) |peer| {
            peer.deinit();
        }
        self.peers.deinit(self.allocator);
        self.peers_mutex.unlock(self.io);
        
        self.threaded_io.deinit();
        self.allocator.destroy(self.threaded_io);
    }
    
    pub fn connect(self: *Node, endpoint_ip: []const u8, endpoint_port: u16, server_pub_key: []const u8) !void {
        if (server_pub_key.len != 32) return error.InvalidKeyLength;
        const address = try Io.net.IpAddress.parseIp4(endpoint_ip, endpoint_port);
        
        var server_pub_arr: [32]u8 = undefined;
        @memcpy(&server_pub_arr, server_pub_key);
        
        try self.connectAddr(address, server_pub_arr);
    }
    
    pub fn connectAddr(self: *Node, address: Io.net.IpAddress, target_pub: [32]u8) !void {
        const sock = try self.io.vtable.netConnectIp(self.io.userdata, &address, .{ .mode = .stream, .protocol = null });
        
        _ = try self.io.vtable.netWrite(self.io.userdata, sock.handle, &[_]u8{}, &[_][]const u8{&self.public_key}, 1);
        
        const shared_secret = try X25519.scalarmult(self.keypair.secret_key, target_pub);
        
        const peer = try Peer.init(self.allocator, self.io, sock, shared_secret, false, target_pub);
        peer.callback = self.callback;
        
        peer.listen_thread = try std.Thread.spawn(.{}, Peer.listenLoop, .{peer});
        
        self.peers_mutex.lockUncancelable(self.io);
        defer self.peers_mutex.unlock(self.io);
        try self.peers.append(self.allocator, peer);
    }
    
    pub fn startListener(self: *Node, callback: EmbeddingCallback) !void {
        self.callback = callback;
        if (self.server_socket != null) {
            self.accept_thread = try std.Thread.spawn(.{}, Node.acceptLoop, .{self});
        }
    }
    
    pub fn start(self: *Node) !void {
        if (self.server_socket != null) {
            self.accept_thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
        }
    }
    
    fn acceptLoop(self: *Node) void {
        while (!self.stop_signal.load(.seq_cst)) {
            const srv = self.server_socket orelse break;
            const client_sock = switch (builtin.os.tag) {
                .windows => self.io.vtable.netAccept(self.io.userdata, srv.handle, .{ .mode = .stream, .protocol = null }) catch continue,
                else => self.io.vtable.netAccept(self.io.userdata, srv.handle, {}) catch continue,
            };
            
            // Handshake (Server)
            // 1. Read client public key
            var client_pub_key: [32]u8 = undefined;
            var client_pub_data_arr = [_][]u8{&client_pub_key};
            const client_pub_data: [][]u8 = &client_pub_data_arr;
            const op_res = self.io.operate(.{ .net_read = .{ .socket_handle = client_sock.handle, .data = client_pub_data } }) catch {
                self.io.vtable.netClose(self.io.userdata, &.{client_sock});
                continue;
            };
            const pub_read = op_res.net_read catch {
                self.io.vtable.netClose(self.io.userdata, &.{client_sock});
                continue;
            };
            if (pub_read != 32) {
                self.io.vtable.netClose(self.io.userdata, &.{client_sock});
                continue;
            }
            
            // 2. Compute shared secret
            const shared_secret = X25519.scalarmult(self.keypair.secret_key, client_pub_key) catch {
                self.io.vtable.netClose(self.io.userdata, &.{client_sock});
                continue;
            };
            
            const peer = Peer.init(self.allocator, self.io, client_sock, shared_secret, true, client_pub_key) catch {
                self.io.vtable.netClose(self.io.userdata, &.{client_sock});
                continue;
            };
            peer.callback = self.callback;
            peer.listen_thread = std.Thread.spawn(.{}, Peer.listenLoop, .{peer}) catch {
                peer.deinit();
                continue;
            };
            
            self.peers_mutex.lockUncancelable(self.io);
            self.peers.append(self.allocator, peer) catch { peer.deinit(); };
            self.peers_mutex.unlock(self.io);
        }
    }
    
    pub fn broadcastEmbedding(self: *Node, topic: []const u8, vector: []const f16) !void {
        self.peers_mutex.lockSharedUncancelable(self.io);
        defer self.peers_mutex.unlockShared(self.io);
        
        for (self.peers.items) |peer| {
            // We ignore send errors so one dead peer doesn't block broadcasting to others
            peer.send(topic, vector) catch {};
        }
    }
    
    pub fn flush(self: *Node) !void {
        _ = self;
    }
    
    pub fn startDiscovery(self: *Node, port: u16) !void {
        var address = try Io.net.IpAddress.parseIp4("0.0.0.0", port);
        
        self.discovery_socket = self.io.vtable.netBindIp(self.io.userdata, &address, .{ .mode = .dgram, .protocol = .udp, .allow_broadcast = true }) catch blk: {
            address.setPort(0);
            break :blk try self.io.vtable.netBindIp(self.io.userdata, &address, .{ .mode = .dgram, .protocol = .udp, .allow_broadcast = true });
        };
        
        self.discovery_recv_thread = try std.Thread.spawn(.{}, discoveryRecvLoop, .{self});
        self.discovery_send_thread = try std.Thread.spawn(.{}, discoverySendLoop, .{self, port});
    }

    fn discoverySendLoop(self: *Node, port: u16) void {
        const target = Io.net.IpAddress.parseIp4("255.255.255.255", port) catch return;
        
        var packet: [38]u8 = undefined;
        @memcpy(packet[0..4], "EDGE");
        mem.writeInt(u16, packet[4..6], self.tcp_port, .little);
        @memcpy(packet[6..38], &self.public_key);
        
        var out_msgs = [_]Io.net.OutgoingMessage{
            .{
                .address = &target,
                .data_ptr = &packet,
                .data_len = packet.len,
                .control = &.{},
            },
        };
        
        while (!self.stop_signal.load(.seq_cst)) {
            var i: usize = 0;
            while (i < 20000000) : (i += 1) {
                if (self.stop_signal.load(.seq_cst)) return;
            }
            
            if (self.discovery_socket) |sock| {
                _ = self.io.operate(.{
                    .net_send = .{
                        .socket_handle = sock.handle,
                        .messages = &out_msgs,
                        .flags = .{},
                    }
                }) catch continue;
            }
        }
    }

    fn discoveryRecvLoop(self: *Node) void {
        var data_buf: [1024]u8 = undefined;
        var in_msgs = [_]Io.net.IncomingMessage{ Io.net.IncomingMessage.init };
        
        while (!self.stop_signal.load(.seq_cst)) {
            const sock = self.discovery_socket orelse break;
            
            const op_res = self.io.operate(.{
                .net_receive = .{
                    .socket_handle = sock.handle,
                    .message_buffer = &in_msgs,
                    .data_buffer = &data_buf,
                    .flags = .{},
                }
            }) catch {
                if (self.stop_signal.load(.seq_cst)) break;
                continue;
            };
            
            const bytes_read = op_res.net_receive[1];
            if (bytes_read != 1 or in_msgs[0].data.len != 38) continue;
            
            const msg = in_msgs[0];
            if (!mem.eql(u8, msg.data[0..4], "EDGE")) continue;
            
            const peer_tcp_port = mem.readInt(u16, msg.data[4..6][0..2], .little);
            var peer_pub: [32]u8 = undefined;
            @memcpy(&peer_pub, msg.data[6..38]);
            
            if (mem.eql(u8, &peer_pub, &self.public_key)) continue;
            
            var already_connected = false;
            self.peers_mutex.lockSharedUncancelable(self.io);
            for (self.peers.items) |p| {
                if (mem.eql(u8, &p.peer_pub_key, &peer_pub)) {
                    already_connected = true;
                    break;
                }
            }
            self.peers_mutex.unlockShared(self.io);
            
            if (already_connected) continue;
            
            var peer_addr = msg.from;
            peer_addr.setPort(peer_tcp_port);
            
            self.connectAddr(peer_addr, peer_pub) catch continue;
        }
    }
};
