#!/usr/bin/env bash
# Build a reproducible Bisho IDE engine ZIP from an already provisioned ARM64 rootfs.
# This script deliberately does not download or redistribute Flutter/Android SDK licenses.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate_and_pack.sh RUNTIME_DIR OUTPUT_ZIP

RUNTIME_DIR must contain:
  runtime/proot
  rootfs/bin/sh
  rootfs/opt/flutter/bin/flutter
  rootfs/usr/lib/jvm/java-17/bin/java (or edit the manifest below)
  rootfs/opt/android-sdk/{platforms,build-tools,platform-tools,licenses,cmdline-tools/latest/bin}

Run this on a native Linux ARM64 host; guest validation uses chroot, while the bundled Android PRoot is retained for the device runtime.
EOF
}
[[ $# -eq 2 ]] || { usage >&2; exit 2; }
source_dir=$(realpath "$1")
output_zip=$(realpath -m "$2")
rootfs="$source_dir/rootfs"
smoke_dir=""
stage=""
smoke_mounted=false

[[ -x "$rootfs/bin/sh" ]] || { echo "guest rootfs shell is missing" >&2; exit 2; }
guest_exec() { chroot "$rootfs" /bin/sh -lc "$1"; }

stop_guest_processes() {
  local proc_dir target pid
  local -a pids=()
  for proc_dir in /proc/[0-9]*; do
    target=$(readlink -f "$proc_dir/root" 2>/dev/null || true)
    [[ "$target" == "$rootfs" ]] || continue
    pids+=("${proc_dir##*/}")
  done
  (("${#pids[@]}" == 0)) && return 0
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  sleep 3
  for pid in "${pids[@]}"; do
    [[ -d "/proc/$pid" ]] || continue
    target=$(readlink -f "/proc/$pid/root" 2>/dev/null || true)
    [[ "$target" == "$rootfs" ]] && kill -KILL "$pid" 2>/dev/null || true
  done
}

umount_checked() {
  local target=$1
  mountpoint -q "$target" || return 0
  if ! umount "$target"; then
    echo "ERROR: cannot unmount $target; a guest process may still be using it." >&2
    return 1
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  stop_guest_processes
  if [[ -n "$rootfs" ]]; then
    umount_checked "$rootfs/tmp/bisho-engine-smoke" || { [[ $status -ne 0 ]] || status=1; }
    umount_checked "$rootfs/proc" || { [[ $status -ne 0 ]] || status=1; }
    umount_checked "$rootfs/dev" || { [[ $status -ne 0 ]] || status=1; }
  fi
  [[ -z "$stage" ]] || rm -rf "$stage"
  if [[ -n "$smoke_dir" ]] && ! mountpoint -q "$rootfs/tmp/bisho-engine-smoke"; then
    rm -rf "$smoke_dir"
  fi
  exit "$status"
}
trap cleanup EXIT
[[ -d "$source_dir" ]] || { echo "runtime directory not found" >&2; exit 2; }
[[ "$(uname -m)" == aarch64 || "$(uname -m)" == arm64 ]] || {
  echo "must run on Linux ARM64; host is $(uname -m)" >&2; exit 2;
}
command -v file >/dev/null || { echo "the 'file' utility is required for ELF architecture checks" >&2; exit 2; }
command -v zip >/dev/null || { echo "the 'zip' utility is required to create the engine archive" >&2; exit 2; }
[[ "$output_zip" != "$source_dir" && "$output_zip" != "$source_dir"/* ]] || {
  echo "output ZIP must be outside RUNTIME_DIR" >&2; exit 2;
}

required=(
  runtime/proot
  rootfs/bin/sh
  rootfs/opt/flutter/bin/flutter
  rootfs/usr/lib/jvm/java-17/bin/java
  rootfs/opt/android-sdk/platforms
  rootfs/opt/android-sdk/build-tools
  rootfs/opt/android-sdk/platform-tools
  rootfs/opt/android-sdk/licenses
  rootfs/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager
)
for item in "${required[@]}"; do
  [[ -e "$source_dir/$item" ]] || { echo "missing required engine path: $item" >&2; exit 3; }
done

chmod +x "$source_dir/runtime/proot" "$source_dir/rootfs/bin/sh" \
  "$source_dir/rootfs/opt/flutter/bin/flutter" "$source_dir/rootfs/usr/lib/jvm/java-17/bin/java" \
  "$source_dir/rootfs/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager"

# Check runtime execution instead of trusting executable bits or ELF names.
file "$source_dir/runtime/proot" | grep -Eqi 'ARM aarch64|ARM64' || {
  echo "PRoot launcher is not a Linux ARM64 executable" >&2; exit 3;
}
file "$source_dir/rootfs/usr/lib/jvm/java-17/bin/java" | grep -Eqi 'ARM aarch64|ARM64' || {
  echo "Java executable is not a Linux ARM64 executable" >&2; exit 3;
}
file "$source_dir/rootfs/opt/flutter/bin/cache/dart-sdk/bin/dart" | grep -Eqi 'ARM aarch64|ARM64' || {
  echo "Flutter's Dart VM is missing or not a Linux ARM64 executable" >&2; exit 3;
}
guest_exec "set -eu; /bin/sh -c 'echo ROOTFS_OK'; /opt/flutter/bin/flutter --version; /usr/lib/jvm/java-17/bin/java -version; /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --version"

sdk="$source_dir/rootfs/opt/android-sdk"
[[ -s "$sdk/licenses/android-sdk-license" ]] || {
  echo "Android SDK license acceptance file is missing; run sdkmanager --licenses on the ARM64 build host" >&2; exit 4;
}
find "$sdk/platforms" -mindepth 2 -maxdepth 2 -name android.jar -type f -print -quit | grep -q . || {
  echo "Android SDK has no installed platform android.jar" >&2; exit 4;
}
found_tools=0
selected_build_tools=""
for build_tools in $(printf '%s\n' "$sdk"/build-tools/* | sort -Vr); do
  [[ -d "$build_tools" ]] || continue
  for tool in aapt2 aidl zipalign split-select apksigner; do
    [[ -x "$build_tools/$tool" ]] || { echo "missing executable $tool in $build_tools" >&2; exit 4; }
  done
  for tool in aapt2 aidl zipalign split-select; do
    file "$build_tools/$tool" | grep -Eqi 'ARM aarch64|ARM64' || {
      echo "$tool is not an ARM64 Linux executable: $build_tools/$tool" >&2; exit 4;
    }
  done
  version=${build_tools##*/}
  guest_exec "export JAVA_HOME=/usr/lib/jvm/java-17; export PATH=\$JAVA_HOME/bin:/usr/bin:/bin; /opt/android-sdk/build-tools/$version/aapt2 version; /opt/android-sdk/build-tools/$version/aidl --version; /opt/android-sdk/build-tools/$version/zipalign -h >/dev/null 2>&1 || test \$? -le 2; /opt/android-sdk/build-tools/$version/split-select --help >/dev/null 2>&1 || test \$? -le 2; /opt/android-sdk/build-tools/$version/apksigner version" >/dev/null
  found_tools=1
  selected_build_tools="$version"
  break
done
[[ $found_tools -eq 1 ]] || { echo "no executable ARM64 Android build-tools set found" >&2; exit 4; }

# Do not package a merely extractable runtime: build a fresh Flutter app in
# the guest and verify its APK before accepting the Debug toolchain.
for mount_name in dev proc; do
  mountpoint -q "$rootfs/$mount_name" || {
    echo "required guest mount is missing: $rootfs/$mount_name" >&2; exit 2;
  }
done
smoke_dir=$(mktemp -d)
mkdir -p "$source_dir/rootfs/tmp/bisho-engine-smoke" "$smoke_dir/project" "$smoke_dir/home" "$smoke_dir/pub-cache" "$smoke_dir/gradle"
smoke_script="set -eu; export HOME=/tmp/bisho-engine-smoke/home; export PUB_CACHE=/tmp/bisho-engine-smoke/pub-cache; export GRADLE_USER_HOME=/tmp/bisho-engine-smoke/gradle; export JAVA_HOME=/usr/lib/jvm/java-17; export ANDROID_HOME=/opt/android-sdk; export ANDROID_SDK_ROOT=/opt/android-sdk; export GRADLE_OPTS=-Dorg.gradle.daemon=false; export JAVA_TOOL_OPTIONS=-XX:ActiveProcessorCount=2; export PATH=/opt/flutter/bin:/usr/lib/jvm/java-17/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/bin:/bin; export FLUTTER_SUPPRESS_ANALYTICS=true; printf 'android.aapt2FromMavenOverride=/opt/android-sdk/build-tools/$selected_build_tools/aapt2\\norg.gradle.daemon=false\\nkotlin.compiler.execution.strategy=in-process\\norg.gradle.workers.max=2\\norg.gradle.parallel=false\\n' > /tmp/bisho-engine-smoke/gradle/gradle.properties; /opt/flutter/bin/flutter precache --android; /opt/flutter/bin/flutter create --platforms=android --project-name bisho_engine_smoke /tmp/bisho-engine-smoke/project; cd /tmp/bisho-engine-smoke/project; /opt/flutter/bin/flutter pub get; /opt/flutter/bin/flutter build apk --debug --target-platform android-arm64; APK=build/app/outputs/flutter-apk/app-debug.apk; /opt/android-sdk/build-tools/$selected_build_tools/apksigner verify --verbose \$APK; /opt/android-sdk/build-tools/$selected_build_tools/zipalign -c -v 4 \$APK; /opt/android-sdk/build-tools/$selected_build_tools/aapt2 dump badging \$APK | grep -q '^package:'"
echo "Running native Linux ARM64 chroot Debug smoke build (up to 60 minutes); this does not certify Android PRoot..."
mkdir -p "$rootfs/tmp/bisho-engine-smoke"
mount --bind "$smoke_dir" "$rootfs/tmp/bisho-engine-smoke"
smoke_mounted=true
timeout 60m chroot "$rootfs" /bin/sh -lc "$smoke_script"
[[ -s "$smoke_dir/project/build/app/outputs/flutter-apk/app-debug.apk" ]] || {
  echo "Debug smoke build did not produce a non-empty APK" >&2; exit 5;
}
echo "Debug smoke build, APK signature, ZIP alignment and badging: PASS"

# Release is accepted only if the exact ARM64 Android AOT host artifact works
# in a full Release build, not merely because a file with that name exists.
aot="$source_dir/rootfs/opt/flutter/bin/cache/artifacts/engine/android-arm64-release/linux-arm64/gen_snapshot"
release_supported=false
if [[ -x "$aot" ]]; then
  release_script="set -eu; export HOME=/tmp/bisho-engine-smoke/home; export PUB_CACHE=/tmp/bisho-engine-smoke/pub-cache; export GRADLE_USER_HOME=/tmp/bisho-engine-smoke/gradle; export JAVA_HOME=/usr/lib/jvm/java-17; export ANDROID_HOME=/opt/android-sdk; export ANDROID_SDK_ROOT=/opt/android-sdk; export GRADLE_OPTS=-Dorg.gradle.daemon=false; export JAVA_TOOL_OPTIONS=-XX:ActiveProcessorCount=2; export PATH=/opt/flutter/bin:/usr/lib/jvm/java-17/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/bin:/bin; cd /tmp/bisho-engine-smoke/project; /opt/flutter/bin/flutter build apk --release --target-platform android-arm64; /opt/android-sdk/build-tools/$selected_build_tools/apksigner verify --verbose build/app/outputs/flutter-apk/app-release.apk; /opt/android-sdk/build-tools/$selected_build_tools/zipalign -c -v 4 build/app/outputs/flutter-apk/app-release.apk; /opt/android-sdk/build-tools/$selected_build_tools/aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | grep -q '^package:'"
  if timeout 60m chroot "$rootfs" /bin/sh -lc "$release_script"; then
    [[ -s "$smoke_dir/project/build/app/outputs/flutter-apk/app-release.apk" ]] && release_supported=true
  fi
fi
if [[ "$release_supported" == true ]]; then
  echo "Release/AOT smoke build, APK signature and ZIP alignment: PASS"
else
  echo "WARNING: Release/AOT is not certified by this engine bundle; Debug remains available."
fi

stop_guest_processes
umount_checked "$rootfs/tmp/bisho-engine-smoke"
smoke_mounted=false
umount_checked "$rootfs/proc"
umount_checked "$rootfs/dev"

# Never ship the runner's resolver address. Android writes current DNS servers
# from ConnectivityManager before each PRoot invocation.
rm -f "$rootfs/etc/resolv.conf"
printf '# Generated from Android LinkProperties at runtime by Bisho IDE.\\n' > "$rootfs/etc/resolv.conf"

stage=$(mktemp -d)
mkdir -p "$stage/runtime" "$stage/rootfs"
# Dereference symlinks: ZIP extraction on Android must not depend on symlink metadata.
cp -aL "$source_dir/runtime/." "$stage/runtime/"
cp -aL "$source_dir/rootfs/." "$stage/rootfs/"
sha256_of() { sha256sum "$1" | awk '{print $1}'; }
PROOT_SHA=$(sha256_of "$stage/runtime/proot")
SHELL_SHA=$(sha256_of "$stage/rootfs/bin/sh")
FLUTTER_SHA=$(sha256_of "$stage/rootfs/opt/flutter/bin/flutter")
DART_SHA=$(sha256_of "$stage/rootfs/opt/flutter/bin/cache/dart-sdk/bin/dart")
JAVA_SHA=$(sha256_of "$stage/rootfs/usr/lib/jvm/java-17/bin/java")
SDKMANAGER_SHA=$(sha256_of "$stage/rootfs/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager")
AAPT2_SHA=$(sha256_of "$stage/rootfs/opt/android-sdk/build-tools/$selected_build_tools/aapt2")
AIDL_SHA=$(sha256_of "$stage/rootfs/opt/android-sdk/build-tools/$selected_build_tools/aidl")
ZIPALIGN_SHA=$(sha256_of "$stage/rootfs/opt/android-sdk/build-tools/$selected_build_tools/zipalign")
APKSIGNER_SHA=$(sha256_of "$stage/rootfs/opt/android-sdk/build-tools/$selected_build_tools/apksigner")
cat > "$stage/engine-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "abi": "arm64-v8a",
  "runtimeLauncher": "runtime/proot",
  "rootfsDirectory": "rootfs",
  "flutterExecutable": "rootfs/opt/flutter/bin/flutter",
  "javaExecutable": "rootfs/usr/lib/jvm/java-17/bin/java",
  "androidSdkDirectory": "rootfs/opt/android-sdk",
  "androidBuildToolsVersion": "$selected_build_tools",
  "debugBuildSupported": true,
  "releaseAotSupported": $release_supported,
  "deviceRuntimeTestRequired": true,
  "criticalFileSha256": {
    "runtime/proot": "$PROOT_SHA",
    "rootfs/bin/sh": "$SHELL_SHA",
    "rootfs/opt/flutter/bin/flutter": "$FLUTTER_SHA",
    "rootfs/opt/flutter/bin/cache/dart-sdk/bin/dart": "$DART_SHA",
    "rootfs/usr/lib/jvm/java-17/bin/java": "$JAVA_SHA",
    "rootfs/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager": "$SDKMANAGER_SHA",
    "rootfs/opt/android-sdk/build-tools/$selected_build_tools/aapt2": "$AAPT2_SHA",
    "rootfs/opt/android-sdk/build-tools/$selected_build_tools/aidl": "$AIDL_SHA",
    "rootfs/opt/android-sdk/build-tools/$selected_build_tools/zipalign": "$ZIPALIGN_SHA",
    "rootfs/opt/android-sdk/build-tools/$selected_build_tools/apksigner": "$APKSIGNER_SHA"
  }
}
EOF

# Explicit executable inventory; no wildcard expansion is written to the manifest.
(
  cd "$stage"
  find runtime rootfs -type f -perm /111 -print | LC_ALL=C sort > engine-executables.txt
  [[ -s engine-executables.txt ]]
  mkdir -p "$(dirname "$output_zip")"
  rm -f "$output_zip"
  zip -X -q -r "$output_zip" engine-manifest.json engine-executables.txt runtime rootfs
)
sha256sum "$output_zip"
echo "Engine archive created: $output_zip"
echo "Release AOT artifact present: $release_supported"
