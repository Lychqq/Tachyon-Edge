import time
import threading
import random
from tachyon_edge import Tachyon

NUM_NODES = 5
START_PORT = 17000

print(f"--- Starting P2P Mesh Simulation with {NUM_NODES} nodes ---")

nodes = []
# 1. Initialize all nodes
for i in range(NUM_NODES):
    port = START_PORT + i
    node = Tachyon(port)
    nodes.append({
        "id": i,
        "node": node,
        "port": port,
        "received_count": 0,
        "public_key": node.get_public_key()
    })
    print(f"[Node {i}] Initialized on port {port}")

# 2. Setup listeners for each node
def create_callback(node_info):
    def on_vector(topic: str, vector: list[float]):
        node_info["received_count"] += 1
        print(f"  -> [Node {node_info['id']}] Received from '{topic}': {vector[:2]}... (Total: {node_info['received_count']})")
    return on_vector

for node_info in nodes:
    node_info["node"].start_listener(create_callback(node_info))

# 3. Start auto-discovery for all nodes
print("\n--- Starting Auto-Discovery ---")
for node_info in nodes:
    node_info["node"].start()
    node_info["node"].start_discovery()

# Wait for discovery and handshakes to complete
time.sleep(3)
time.sleep(1)
print("\n--- Network is ready. Starting simulation ---\n")

# 4. Have random nodes broadcast data
for step in range(1, 4):
    sender_idx = random.randint(0, NUM_NODES - 1)
    sender = nodes[sender_idx]
    
    vec = [random.random(), random.random(), random.random()]
    topic = f"sensor-data-from-{sender_idx}"
    
    print(f"[*] Step {step}: Node {sender_idx} broadcasting {vec[:2]}...")
    sender["node"].broadcast(topic, vec)
    sender["node"].flush()
    
    # Wait a bit for messages to propagate to all other nodes
    time.sleep(0.5)

print("\n--- Simulation Summary ---")
for node_info in nodes:
    print(f"[Node {node_info['id']}] Processed {node_info['received_count']} messages.")

print("Cleaning up...")
# Cleanup is handled automatically by __del__ in SwarmNode
