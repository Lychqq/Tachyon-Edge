# Tachyon Edge

**Tachyon Edge** is an ultra-fast, decentralized Peer-to-Peer (P2P) networking core built specifically for Edge AI, Large Language Models (LLMs), and embeddings synchronization.

Written in **100% pure Zig (v0.17)** without any external dependencies (no ZeroMQ, no bulky libraries).

## Features
- **Pure Zig Core**: Uses `std.Io` for asynchronous, high-performance networking.
- **Zero Configuration Discovery**: Automatic UDP-based local network peer discovery. Just call `start_discovery()` and nodes find each other on Wi-Fi.
- **End-to-End Encryption**: Every TCP connection is secured natively using **X25519** key exchange and **ChaCha20Poly1305** authenticated encryption.
- **Python Integration**: First-class support for Python (`pip install tachyon_edge`). Perfect for direct integration into LangChain, Ollama hooks, or any AI pipeline.
- **Cross-Platform**: Compiles out-of-the-box to Windows, Linux, and Android.

## Installation

Simply install the Python package globally or in your virtual environment:

```bash
cd python
pip install -e .
```

## Quick Start (Python / LangChain / Ollama)

Using `Tachyon` in your Python AI project requires only 5 lines of code:

```python
from tachyon_edge import Tachyon

# 1. Start the P2P node on a given port
node = Tachyon(port=17777)
node.start()

# 2. Automatically discover other nodes on the local Wi-Fi
node.start_discovery()

# 3. Broadcast your LLM embeddings or outputs to all peers
my_embedding = [0.12, -0.45, 0.88, 0.91]
node.broadcast("llm-output", my_embedding)

# 4. Listen for incoming AI data from other nodes
def on_received(topic, vector):
    print(f"Received from peer -> Topic: {topic}, Vector: {vector[:2]}...")

node.start_listener(on_received)
```

## Building the Zig Core

If you want to modify the core protocol, you can build the native libraries using the Zig 0.17 toolchain:

```bash
# Build static library
zig build -Doptimize=ReleaseSafe

# Build shared library for Android
zig build -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe

# Build shared library for Linux
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
```

## Architecture
- **P2P Transport**: Custom binary framing over TCP.
- **Discovery**: UDP Broadcast on `255.255.255.255` with `"EDGE"` magic headers.
- **Security**: Ephemeral X25519 keypairs generated on boot. No central authority.
- **Memory**: The Zig core manages its own memory and uses `ctypes` to safely pass arrays to Python without copying overhead.
