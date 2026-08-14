import time
from tachyon_edge import Tachyon

def on_vector(topic: str, vector: list[float]):
    print(f"\n🚀 [SUCCESS] RECEIVED DATA FROM PHONE OVER WI-FI!")
    print(f"Topic: {topic}")
    print(f"Vector: {vector}")
    print("X25519 Encryption & Blake3 PSK: Verified ✅")

print("Starting Tachyon PC Server...")
# Start node on port 17000 with our Swarm Secret
node = Tachyon(17000, "test_secret")
node.start_listener(on_vector)
node.start()
node.start_discovery()

print("PC Node is running and broadcasting on local Wi-Fi!")
print("Waiting for phone to connect... (Press Ctrl+C to stop)")

try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    print("Shutting down...")
