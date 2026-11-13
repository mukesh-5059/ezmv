#!/usr/bin/env bash
set -e

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export ANDROID_HOME=/opt/android-sdk
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH

AVD_DIR="$HOME/.android/avd/MiTV_720p.avd"
EMULATOR_BIN="/opt/android-sdk/emulator/emulator"

# Fast path: If AVD already exists, launch immediately
if [ -d "$AVD_DIR" ]; then
  echo "==> Starting 'MiTV_720p' Android TV Emulator..."
  exec "$EMULATOR_BIN" -avd MiTV_720p -gpu host
fi

echo "==> AVD not found. Initializing Android TV 720p setup..."
echo "==> Verifying Android TV x86_64 image..."
sdkmanager "system-images;android-36;android-tv;x86_64"
sdkmanager "emulator"

echo "==> Creating AVD 'MiTV_720p'..."
echo "no" | avdmanager create avd -n MiTV_720p -k "system-images;android-36;android-tv;x86_64" -d tv_720p --force

echo "==> Configuring 1024MB RAM & Keyboard D-pad..."
AVD_CONFIG="$AVD_DIR/config.ini"
if [ -f "$AVD_CONFIG" ]; then
  sed -i '/^hw.ramSize/d' "$AVD_CONFIG"
  echo "hw.ramSize=1024" >> "$AVD_CONFIG"
  sed -i 's/^hw.keyboard=.*/hw.keyboard=yes/' "$AVD_CONFIG"
fi

echo "==> Launching Android TV Emulator with host GPU acceleration..."
exec "$EMULATOR_BIN" -avd MiTV_720p -gpu host
