import time
from tachyon_edge import Tachyon

print("Starting Tachyon Node on Phone...")
node = Tachyon(17001, "test_secret")
print("INIT OK! No panic so far.")

time.sleep(1)

# node.start()
# print("START OK")

# node.start_discovery()
# print("DISCOVERY OK")
