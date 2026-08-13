import time
from swarmvec import SwarmNode

# Initialize Node 1
node1 = SwarmNode(16000)

# Initialize Node 2
node2 = SwarmNode(16001)

# Connect Node 2 to Node 1
node2.connect("tcp://127.0.0.1:16000", node1.get_public_key())

received_vectors = []

def on_vector(topic: str, vector: list[float]):
    print(f"Received! Topic: {topic}, Vector length: {len(vector)}, First value: {vector[0] if vector else 0.0}")
    received_vectors.append(vector)

# Node 2 listens
node2.start_listener(on_vector)

print("Wait for connection...")
time.sleep(1)

# Node 1 sends
vec = [1.5, 2.5, 3.5, -4.5]
print(f"Sending: {vec}")
node1.broadcast("test-topic-python", vec)
node1.flush()

# Wait for receipt
time.sleep(1)

if received_vectors:
    print("Success: Vector received in Python!")
else:
    print("Warning: Vector not received. Check discovery or zmq pub/sub setup.")
