import time
from tachyon_edge import Tachyon

print("Starting Tachyon Node on Phone...")
node = Tachyon(17001, "test_secret")
node.start()
node.start_discovery()

print("Searching for PC over Wi-Fi...")
time.sleep(1)

print("Sending vector [9.9, 8.8, 7.7]...")
node.broadcast("hello-from-phone", [9.9, 8.8, 7.7])
print("Vector sent!")
