#!/bin/bash
# Build audio_common_msgs for Isaac Sim's ROS2 bridge (jazzy, Python 3.11)
#
# Isaac Sim 5.1.0 uses Python 3.11, but ros:jazzy ships Python 3.12.
# This script installs Python 3.11 in the build container and tells
# colcon/cmake to generate bindings for 3.11.
#
# Produces pre-built artifacts in ./install/ that can be mounted
# into the Isaac Sim container alongside the bridge's rclpy packages.
#
# Usage: ./build_for_isaacsim.sh
# Output: ./install/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Clean previous build (Python version may have changed)
# Docker builds as root, so artifacts may be root-owned — use docker to clean
if [[ -d "$SCRIPT_DIR/install" ]]; then
    echo "Cleaning previous build..."
    docker run --rm -v "$SCRIPT_DIR:/work" ros:jazzy rm -rf /work/install /work/build /work/log
fi

echo "Building audio_common_msgs for Isaac Sim (jazzy + Python 3.11)..."

docker run --rm \
  -v "$SCRIPT_DIR/audio_common_msgs:/ws/src/audio_common_msgs:ro" \
  -v "$SCRIPT_DIR/install:/ws/install" \
  ros:jazzy \
  bash -c '
    set -e

    # Install Python 3.11 (Isaac Sim uses 3.11, not the default 3.12)
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq software-properties-common > /dev/null 2>&1
    add-apt-repository -y ppa:deadsnakes/ppa > /dev/null 2>&1
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq python3.11-dev python3.11-venv > /dev/null 2>&1
    echo "Python 3.11 installed: $(python3.11 --version)"

    # NumPy for Python 3.11 (isolated from system 3.12 numpy)
    python3.11 -m ensurepip > /dev/null 2>&1
    python3.11 -m pip install -q --target=/opt/py311-pkgs numpy 2>/dev/null
    NUMPY_INCLUDE=$(PYTHONPATH=/opt/py311-pkgs python3.11 -c "import numpy; print(numpy.get_include())")
    echo "NumPy include: $NUMPY_INCLUDE"

    cd /ws
    source /opt/ros/jazzy/setup.bash

    colcon build \
      --packages-select audio_common_msgs \
      --merge-install \
      --cmake-args \
        -DPython3_EXECUTABLE=/usr/bin/python3.11 \
        -DPython3_INCLUDE_DIR=/usr/include/python3.11 \
        -DPython3_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.11.so \
        -DPython3_NumPy_INCLUDE_DIR=$NUMPY_INCLUDE

    echo ""
    echo "Build complete. Checking Python version in artifacts:"
    ldd install/lib/libaudio_common_msgs__rosidl_generator_py.so | grep python || true
    echo ""
    ls -la install/lib/python*/site-packages/audio_common_msgs/
  '

echo ""
echo "Done. Built artifacts in: $SCRIPT_DIR/install/"
