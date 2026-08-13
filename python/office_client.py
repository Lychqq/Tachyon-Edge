import time
import sys
from swarmvec import SwarmNode

print("==================================================")
print(" 💻  DEVELOPER LAPTOP (Sender) ")
print("==================================================")

# Initialize client node on an arbitrary port
node = SwarmNode(0)

# Read the server's public key
print("🔗 Reading GPU Server's CurveZMQ key (simulating Slack paste)...")
try:
    with open("server_key.bin", "rb") as f:
        server_key = f.read()
except FileNotFoundError:
    print("❌ Error: server_key.bin not found. Run office_server.py first!")
    sys.exit(1)

# Connect
server_ip = "127.0.0.1" # In a real office, this would be the LAN IP e.g., 192.168.1.50
print(f"🔌 Connecting securely to tcp://{server_ip}:15555...")
node.connect(f"tcp://{server_ip}:15555", server_key)

# Wait for Pure Zig crypto handshake
time.sleep(1.0)
print("✅ Connected!\n")

print("🚀 Generating code embedding for 'auth_module.zig'...")
# Fake embedding generation
embedding = [0.123, -0.456, 0.789, 0.999, -0.111, 0.555, 0.333, -0.777]

print(f"📤 Transmitting vector (dim={len(embedding)}) over P2P network...")
for _ in range(3):
    node.broadcast("task/code_analysis", embedding)
    node.flush()
    time.sleep(0.5)

print("🎯 Transmission complete!")
