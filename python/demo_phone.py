import time
from tachyon_edge import Tachyon

print("Starting Tachyon Node on Phone...")
node = Tachyon(17001, "test_secret")
print("INIT OK!")

node.start()
print("START OK!")

node.start_discovery()
print("DISCOVERY OK! Searching for PC over Wi-Fi...")

time.sleep(30)
print("Done.")
node.stop()
