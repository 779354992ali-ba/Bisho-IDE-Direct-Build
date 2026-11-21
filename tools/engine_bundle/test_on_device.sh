#!/data/data/com.termux/files/usr/bin/bash
# Run in Termux against an extracted Bisho ARM64 engine bundle.
# Usage: bash test_on_device.sh /path/to/engine [log-file]
set -uo pipefail

ENGINE_DIR="$HOME/bisho-engine"
if [ "$#" -ge 1 ]; then ENGINE_DIR="$1"; fi
LOG_FILE="$HOME/bisho-engine-device-test-$(date +%Y%m%d-%H%M%S).log"
if [ "$#" -ge 2 ]; then LOG_FILE="$2"; fi

ROOTFS="$ENGINE_DIR/rootfs"
PROOT="$ENGINE_DIR/runtime/proot"
TEST_HOME="$ENGINE_DIR/.device-test-home"
PROOT_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp/bisho-proot-tmp"
PROJECT="$ENGINE_DIR/.device-test-project"
APK="$PROJECT/build/app/outputs/flutter-apk/app-debug.apk"
PASS_COUNT=0
FAIL_COUNT=0

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL: %s\n' "$1"; }

finish() {
  printf '\n===== SUMMARY =====\nPASS=%s FAIL=%s\n' "$PASS_COUNT" "$FAIL_COUNT"
  printf 'LOG_FILE=%s\n' "$LOG_FILE"
  if command -v termux-clipboard-set >/dev/null 2>&1; then
    termux-clipboard-set < "$LOG_FILE" && echo "Full test log copied to clipboard."
  fi
  [ "$FAIL_COUNT" -eq 0 ]
}

run_host_stage() {
  local label="$1"
  shift
  printf '\n===== %s =====\n' "$label"
  if "$@"; then pass "$label"; else fail "$label"; fi
}

guest() {
  env -u LD_PRELOAD BISHO_PROOT_TMPDIR="$PROOT_TMP" TMPDIR="$PROOT_TMP" "$PROOT" -0 -r "$ROOTFS" \
    -b /dev -b /proc \
    -b "$TEST_HOME:/bisho-home" \
    -b "$PROJECT:/workspace/project" \
    -w /workspace/project /bin/sh -lc "$1"
}

run_guest_stage() {
  local label="$1"
  local script="$2"
  printf '\n===== %s =====\n' "$label"
  if guest "$script"; then pass "$label"; else fail "$label"; fi
}

printf 'Bisho IDE ARM64 on-device engine test\n'
printf 'Engine: %s\nDevice: %s\nLog: %s\n' "$ENGINE_DIR" "$(getprop ro.product.model 2>/dev/null || echo Android)" "$LOG_FILE"

if [ ! -x "$PROOT" ] || [ ! -x "$ROOTFS/bin/sh" ]; then
  fail "Engine paths"
  printf 'Expected executable files: %s and %s\n' "$PROOT" "$ROOTFS/bin/sh"
  finish || true
  exit 1
fi
if [ ! -x "$ROOTFS/opt/flutter/bin/flutter" ] ||
   [ ! -x "$ROOTFS/usr/lib/jvm/java-17/bin/java" ] ||
   [ ! -x "$ROOTFS/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]; then
  fail "Flutter/JDK/SDK files"
  finish || true
  exit 1
fi

mkdir -p "$TEST_HOME" "$PROJECT" "$PROOT_TMP"
chmod 700 "$PROOT_TMP"
export BISHO_PROOT_TMPDIR="$PROOT_TMP" TMPDIR="$PROOT_TMP"
run_host_stage "PRoot --version" env -u LD_PRELOAD BISHO_PROOT_TMPDIR="$PROOT_TMP" TMPDIR="$PROOT_TMP" "$PROOT" --version
run_guest_stage "RootFS shell and echo" 'set -eu; echo ROOTFS_OK; test -x /bin/sh'

# Android DNS is device-specific. Never reuse the CI runner's resolv.conf.
GETPROP="$(command -v getprop 2>/dev/null || printf '/system/bin/getprop')"
DNS_LIST=""
DNS_COUNT=0
for key in net.dns1 net.dns2 net.dns3 net.dns4; do
  value="$("$GETPROP" "$key" 2>/dev/null || true)"
  if [ -n "$value" ]; then DNS_LIST="$DNS_LIST $value"; DNS_COUNT=$((DNS_COUNT + 1)); fi
done
if [ "$DNS_COUNT" -eq 0 ] && [ -r "$PREFIX/etc/resolv.conf" ]; then
  while read -r kind address _; do
    if [ "$kind" = "nameserver" ] && [ -n "$address" ]; then
      DNS_LIST="$DNS_LIST $address"
      DNS_COUNT=$((DNS_COUNT + 1))
    fi
  done < "$PREFIX/etc/resolv.conf"
fi
printf '\n===== Refresh Android DNS =====\n'
if [ "$DNS_COUNT" -gt 0 ]; then
  mkdir -p "$ROOTFS/etc"
  : > "$ROOTFS/etc/resolv.conf"
  for address in $DNS_LIST; do printf 'nameserver %s\n' "$address" >> "$ROOTFS/etc/resolv.conf"; done
  pass "Refresh Android DNS"
else
  fail "Refresh Android DNS"
fi

BASE='set -eu; export HOME=/bisho-home; export TMPDIR=/tmp; export PUB_CACHE=/bisho-home/.pub-cache; export GRADLE_USER_HOME=/bisho-home/.gradle; export JAVA_HOME=/usr/lib/jvm/java-17; export ANDROID_HOME=/opt/android-sdk; export ANDROID_SDK_ROOT=/opt/android-sdk; export FLUTTER_SUPPRESS_ANALYTICS=true; export CI=true; export JAVA_TOOL_OPTIONS=-XX:ActiveProcessorCount=2; export PATH=/opt/flutter/bin:/usr/lib/jvm/java-17/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/bin:/bin;'

run_guest_stage "Flutter --version" "$BASE /opt/flutter/bin/flutter --version"
run_guest_stage "Java --version" "$BASE /usr/lib/jvm/java-17/bin/java -version"
run_guest_stage "sdkmanager --version" "$BASE /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --version"
run_guest_stage "Flutter Android precache" "$BASE /opt/flutter/bin/flutter precache --android"

rm -rf "$PROJECT"
mkdir -p "$PROJECT"
run_guest_stage "Create Flutter Android smoke project" "$BASE /opt/flutter/bin/flutter create --platforms=android --project-name bisho_phone_smoke --no-pub /workspace/project"
run_guest_stage "Flutter pub get" "$BASE cd /workspace/project && /opt/flutter/bin/flutter pub get"

run_guest_stage "Flutter build apk --debug" "$BASE export GRADLE_OPTS=-Dorg.gradle.daemon=false; mkdir -p /bisho-home/.gradle; printf 'org.gradle.daemon=false\nkotlin.compiler.execution.strategy=in-process\norg.gradle.workers.max=2\norg.gradle.parallel=false\n' > /bisho-home/.gradle/gradle.properties; cd /workspace/project && /opt/flutter/bin/flutter build apk --debug --target-platform android-arm64"

TOOLS_SCRIPT='TOOLS=; for candidate in $(printf "%s\n" /opt/android-sdk/build-tools/* | sort -Vr); do if [ -x "$candidate/aapt2" ] && [ -x "$candidate/aidl" ] && [ -x "$candidate/zipalign" ] && [ -x "$candidate/apksigner" ]; then TOOLS="$candidate"; break; fi; done; test -n "$TOOLS"; APK=/workspace/project/build/app/outputs/flutter-apk/app-debug.apk; test -s "$APK"'
run_guest_stage "Resolve Build Tools and APK" "$BASE $TOOLS_SCRIPT"
run_guest_stage "apksigner verify" "$BASE $TOOLS_SCRIPT; \"\$TOOLS/apksigner\" verify --verbose \"\$APK\""
run_guest_stage "zipalign -c -v 4" "$BASE $TOOLS_SCRIPT; \"\$TOOLS/zipalign\" -c -v 4 \"\$APK\""
run_guest_stage "aapt2 dump badging" "$BASE $TOOLS_SCRIPT; BADGING=\$(\"\$TOOLS/aapt2\" dump badging \"\$APK\"); printf '%s\n' \"\$BADGING\" | tee /bisho-home/aapt-badging.txt | grep -q '^package:'"

PACKAGE_NAME="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" "$TEST_HOME/aapt-badging.txt" 2>/dev/null | head -n 1)"
ACTIVITY_NAME="$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" "$TEST_HOME/aapt-badging.txt" 2>/dev/null | head -n 1)"

install_and_launch() {
  if [ -z "$PACKAGE_NAME" ] || [ -z "$ACTIVITY_NAME" ] || [ ! -s "$APK" ]; then
    echo "Missing package/activity metadata or APK."
    return 1
  fi
  if pm list packages 2>/dev/null | grep -Fxq "package:$PACKAGE_NAME"; then
    echo "Uninstall the previous smoke app first, then rerun this script."
    return 1
  fi
  echo "Opening Android package installer. Confirm Install on the phone."
  if command -v termux-open >/dev/null 2>&1; then
    termux-open "$APK" || return 1
  else
    am start -a android.intent.action.VIEW -d "file://$APK" -t application/vnd.android.package-archive || return 1
  fi
  local installed=false
  for _ in $(seq 1 180); do
    if pm list packages 2>/dev/null | grep -Fxq "package:$PACKAGE_NAME"; then
      installed=true
      break
    fi
    sleep 1
  done
  if [ "$installed" != true ]; then
    echo "Package was not detected. Allow Termux to install unknown apps and confirm the installer prompt."
    return 1
  fi
  echo "Installed package: $PACKAGE_NAME"
  am start -W -n "$PACKAGE_NAME/$ACTIVITY_NAME" || return 1
  sleep 3
  if ps -A 2>/dev/null | grep -F "$PACKAGE_NAME" | grep -v grep >/dev/null; then
    echo "Application process is running."
    return 0
  fi
  echo "Package installed but its process was not observed after launch."
  return 1
}
run_host_stage "Install and launch smoke APK (confirm on device)" install_and_launch

finish
