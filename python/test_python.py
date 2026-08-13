import time
import unittest
from tachyon_edge import Tachyon

class TestTachyon(unittest.TestCase):
    def test_connection_failure(self):
        # Initialize node
        node = Tachyon(16000)
        node.start()
        
        # Expect RuntimeError when connecting to an invalid endpoint
        with self.assertRaises(RuntimeError):
            node.connect("invalid_endpoint_format", b'0' * 32)
            
    def test_p2p_transmission(self):
        node1 = Tachyon(16001, "test_secret")
        node2 = Tachyon(16002, "test_secret")
        node1.start()
        node2.start()
        
        received_vectors = []
        def on_vector(topic: str, vector: list[float]):
            received_vectors.append(vector)
            
        node2.start_listener(on_vector)
        
        # Connect Node 2 to Node 1 using the local IP
        node2.connect("tcp://127.0.0.1:16001", node1.get_public_key())
        time.sleep(0.5) # Wait for handshake
        
        # Broadcast vector
        node1.broadcast("test-topic", [1.5, 2.5, 3.5])
        time.sleep(0.5) # Wait for transmission
        
        # Verify receipt
        self.assertTrue(len(received_vectors) > 0, "Vector was not received!")
        self.assertEqual(received_vectors[0], [1.5, 2.5, 3.5])

if __name__ == '__main__':
    unittest.main()
