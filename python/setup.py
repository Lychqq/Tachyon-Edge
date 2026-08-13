from setuptools import setup, find_packages

setup(
    name="tachyon_edge",
    version="0.1.0",
    description="P2P Edge AI networking core using pure Zig and X25519",
    packages=find_packages(),
    include_package_data=True, # This ensures the .so and .dll files are included!
    package_data={
        "tachyon_edge": ["*.so", "*.dll", "*.dylib"],
    },
    install_requires=[],
)
