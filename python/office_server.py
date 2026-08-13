import time
from swarmvec import SwarmNode

print("==================================================")
print(" 🖥️  GPU SERVER (Office AI Machine) ")
print("==================================================")

# Initialize node on port 15555
node = SwarmNode(15555)
# Save the public key to a file to simulate sending it via Slack/Email
key = node.get_public_key()
with open("server_key.bin", "wb") as f:
    f.write(key)

print("[INFO] P2P Node started on port 15555.")
print("[INFO] Public key exported to 'server_key.bin'.")
print("⏳ Waiting for incoming embeddings from developer machines...\n")

def on_embedding(topic: str, vector: list[float]):
    print(f"\n📥 [GPU-Server] RECV: Incoming P2P task on topic: '{topic}'")
    print(f"   -> Received embedding dimension: {len(vector)}")
    print(f"   -> Vector data snippet: {vector[:4]} ...")
    print(f"🧠 [GPU-Server] FEED: Processing embedding through local LLM...")
    time.sleep(1)
    print(f"✅ [GPU-Server] DONE: Context analyzed.\n")

# Start listening
node.start_listener(on_embedding)

# Keep process alive
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    print("Shutting down...")
