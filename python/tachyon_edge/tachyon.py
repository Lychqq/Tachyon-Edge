import ctypes
import struct
import os
import sys

# Load the shared library
# We look for the library in the same directory as this script
current_dir = os.path.dirname(os.path.abspath(__file__))
base_dir = os.path.dirname(current_dir)

if sys.platform.startswith("win"):
    lib_path = os.path.join(current_dir, "p2p_sdk_shared.dll")
    # Fallback to zig-out if running locally in dev environment
    if not os.path.exists(lib_path):
        lib_path = os.path.join(base_dir, "zig-out", "bin", "p2p_sdk_shared.dll")
elif hasattr(sys, 'getandroidapilevel') or "ANDROID_ROOT" in os.environ:
    # Android detection
    lib_path = os.path.join(current_dir, "libp2p_sdk_shared_android.so")
elif sys.platform.startswith("linux"):
    lib_path = os.path.join(current_dir, "libp2p_sdk_shared_linux.so")
elif sys.platform.startswith("darwin"):
    lib_path = os.path.join(current_dir, "libp2p_sdk_shared_mac.dylib")
else:
    lib_path = os.path.join(current_dir, "libp2p_sdk_shared.so")

try:
    lib = ctypes.CDLL(lib_path)
except OSError as e:
    raise OSError(f"Could not load shared library {lib_path}. Error: {e}")

# Define C structures and function signatures
class CPacket(ctypes.Structure):
    _fields_ = [
        ("topic_ptr", ctypes.POINTER(ctypes.c_uint8)),
        ("topic_len", ctypes.c_size_t),
        ("vector_ptr", ctypes.POINTER(ctypes.c_uint16)), # f16 is represented as u16 in ctypes
        ("vector_len", ctypes.c_size_t),
    ]

# CFUNCTYPE for the C-callback bridging
CCallbackType = ctypes.CFUNCTYPE(None, CPacket)

# Map exported C functions
lib.node_init.argtypes = [ctypes.c_uint16, ctypes.c_char_p, ctypes.c_size_t]
lib.node_init.restype = ctypes.c_void_p

lib.node_deinit.argtypes = [ctypes.c_void_p]
lib.node_deinit.restype = None

lib.node_start.argtypes = [ctypes.c_void_p]
lib.node_start.restype = ctypes.c_int

lib.node_start_discovery.argtypes = [ctypes.c_void_p, ctypes.c_uint16]
lib.node_start_discovery.restype = ctypes.c_int

lib.node_connect.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t, ctypes.POINTER(ctypes.c_uint8)]
lib.node_connect.restype = ctypes.c_int

lib.node_get_public_key.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint8)]
lib.node_get_public_key.restype = None

lib.node_broadcast.argtypes = [
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_uint16),
    ctypes.c_size_t
]
lib.node_broadcast.restype = ctypes.c_int

lib.node_flush.argtypes = [ctypes.c_void_p]
lib.node_flush.restype = ctypes.c_int

lib.node_start_listener.argtypes = [ctypes.c_void_p, CCallbackType]
lib.node_start_listener.restype = ctypes.c_int

class Tachyon:
    def __init__(self, port: int, swarm_secret: str = ""):
        """Initializes a new Tachyon node on the given port."""
        secret_bytes = swarm_secret.encode('utf-8')
        self._node_ptr = lib.node_init(port, secret_bytes, len(secret_bytes))
        if not self._node_ptr:
            raise RuntimeError("Failed to initialize ZeroMQ Node.")

        self._callback = None
        self._c_callback_wrapper = None
        self._active_payloads = []

    def get_public_key(self) -> bytes:
        """Gets the X25519 public key for this node."""
        key_buffer = (ctypes.c_uint8 * 32)()
        lib.node_get_public_key(self._node_ptr, ctypes.cast(key_buffer, ctypes.POINTER(ctypes.c_uint8)))
        return bytes(key_buffer)

    def connect(self, endpoint: str, server_public_key: bytes):
        """Manually connects to a peer without UDP discovery."""
        endpoint_bytes = endpoint.encode('utf-8')
        ep_ptr = ctypes.cast(ctypes.c_char_p(endpoint_bytes), ctypes.POINTER(ctypes.c_uint8))
        key_ptr = ctypes.cast((ctypes.c_uint8 * 32).from_buffer_copy(server_public_key), ctypes.POINTER(ctypes.c_uint8))
        if lib.node_connect(self._node_ptr, ep_ptr, len(endpoint_bytes), key_ptr) != 0:
            raise RuntimeError(f"Failed to connect to {endpoint}")

    def start(self):
        """Start listening for incoming connections."""
        if lib.node_start(self._node_ptr) != 0:
            raise RuntimeError("Failed to start node")

    def start_discovery(self, port: int = 17777):
        """Starts background UDP auto-discovery."""
        if lib.node_start_discovery(self._node_ptr, port) != 0:
            raise RuntimeError("Failed to start discovery")

    def broadcast(self, topic: str, vector: list[float]):
        """Broadcasts a vector array to the given topic."""
        topic_bytes = topic.encode('utf-8')

        # We must keep references alive until flush happens on Zig side.
        # In a real async/batching system, we'd need a deeper queue, but for
        # C-FFI safety here we append to a python-side list to prevent GC UAF.

        buffer = struct.pack(f"{len(vector)}e", *vector)
        encoded_arr = (ctypes.c_uint16 * len(vector)).from_buffer_copy(buffer)

        # Keep refs
        self._active_payloads.append((topic_bytes, encoded_arr))

        topic_ptr = ctypes.cast(ctypes.c_char_p(topic_bytes), ctypes.POINTER(ctypes.c_uint8))
        topic_len = len(topic_bytes)

        vec_ptr = ctypes.cast(encoded_arr, ctypes.POINTER(ctypes.c_uint16))
        vec_len = len(vector)

        if lib.node_broadcast(self._node_ptr, topic_ptr, topic_len, vec_ptr, vec_len) != 0:
            raise RuntimeError("Failed to broadcast vector.")

    def flush(self):
        """Forces flushing the current batch of vectors."""
        if lib.node_flush(self._node_ptr) != 0:
            raise RuntimeError("Failed to flush vector batch.")

    def start_listener(self, callback_fn):
        """
        Starts listening for incoming vectors.
        callback_fn should accept (topic: str, vector: list[float])
        """
        self._callback = callback_fn

        # We must keep a reference to the C callback so it doesn't get garbage collected
        @CCallbackType
        def internal_callback(c_packet):
            try:
                # SECURITY: Sanity checks to prevent CTypes out-of-bounds reads
                if c_packet.topic_len < 0 or c_packet.topic_len > 1024:
                    print("⚠️ Blocked malformed topic length at C boundary")
                    return
                if c_packet.vector_len < 0 or c_packet.vector_len > 10_000_000:
                    print("⚠️ Blocked malformed vector length at C boundary")
                    return

                # Safely copy memory out of the C struct before returning
                topic_bytes = ctypes.string_at(c_packet.topic_ptr, c_packet.topic_len)
                topic_str = topic_bytes.decode('utf-8')

                # Unpack f16s
                buffer = bytes(ctypes.cast(c_packet.vector_ptr, ctypes.POINTER(ctypes.c_uint16 * c_packet.vector_len)).contents)
                vector = list(struct.unpack(f"{c_packet.vector_len}e", buffer))

                if self._callback:
                    self._callback(topic_str, vector)
            except Exception as e:
                print(f"Error in python callback: {e}", file=sys.stderr)

        self._c_callback_wrapper = internal_callback

        if lib.node_start_listener(self._node_ptr, self._c_callback_wrapper) != 0:
            raise RuntimeError("Failed to start ZeroMQ listener.")

    def __del__(self):
        """Cleans up C resources."""
        if hasattr(self, '_node_ptr') and self._node_ptr:
            lib.node_deinit(self._node_ptr)
            self._node_ptr = None
