#!/data/data/com.termux/files/usr/bin/bash
# Read-only comparison of the bundled PRoot and Termux's known-good PRoot.
# Usage: bash diagnose_proot_seccomp.sh /path/to/extracted/engine [log-file]
set -uo pipefail

ENGINE_DIR="$HOME/bisho-engine"
if [ "$#" -ge 1 ]; then
  ENGINE_DIR="$1"
else
  mapfile -t ENGINE_CANDIDATES < <(find "$HOME" -type f -path '*/runtime/proot' -print 2>/dev/null)
  if [ "${#ENGINE_CANDIDATES[@]}" -eq 1 ]; then
    ENGINE_DIR="$(dirname "$(dirname "${ENGINE_CANDIDATES[0]}")")"
  elif [ "${#ENGINE_CANDIDATES[@]}" -gt 1 ]; then
    echo "Multiple engine bundles found; pass the exact engine directory as argument 1."
    printf '%s\n' "${ENGINE_CANDIDATES[@]}"
    exit 2
  fi
fi
LOG_FILE="$HOME/bisho-proot-seccomp-diagnostic.log"
if [ "$#" -ge 2 ]; then LOG_FILE="$2"; fi
ROOTFS="$ENGINE_DIR/rootfs"
BUNDLE_PROOT="$ENGINE_DIR/runtime/proot"
TERMUX_PROOT="$(command -v proot 2>/dev/null || true)"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

printf 'Bisho PRoot seccomp diagnostic (read-only)\n'
printf 'Device: %s\n' "$(getprop ro.product.model 2>/dev/null || echo Android)"
printf 'Android: %s / SDK %s\n' "$(getprop ro.build.version.release 2>/dev/null || echo unknown)" "$(getprop ro.build.version.sdk 2>/dev/null || echo unknown)"
printf 'Kernel: %s\n' "$(uname -a)"
printf 'PROOT_ASSUME_NEW_SECCOMP=%s\n' "$(printenv PROOT_ASSUME_NEW_SECCOMP 2>/dev/null || echo unset)"
printf 'RootFS: %s\nLog: %s\n' "$ROOTFS" "$LOG_FILE"

if [ ! -d "$ROOTFS" ] || [ ! -x "$ROOTFS/bin/sh" ]; then
  echo "ERROR: RootFS shell is missing."
  exit 1
fi

run_case() {
  local label="$1"
  local proot_path="$2"
  local status
  printf '\n===== %s =====\n' "$label"
  if [ ! -x "$proot_path" ]; then
    echo "SKIP: executable not found: $proot_path"
    return 0
  fi
  printf 'Binary: %s\n' "$proot_path"
  "$proot_path" --version
  status=$?
  echo "VERSION_EXIT=$status"
  if command -v timeout >/dev/null 2>&1; then
    timeout 30s "$proot_path" -v 4 -0 -r "$ROOTFS" \
      -b /dev -b /proc \
      /bin/sh -c 'pwd; if [ -x /bin/busybox ]; then /bin/busybox echo BISHO_PROOT_DIAG_OK; else echo BISHO_PROOT_DIAG_OK; fi'
  else
    "$proot_path" -v 4 -0 -r "$ROOTFS" \
      -b /dev -b /proc \
      /bin/sh -c 'pwd; if [ -x /bin/busybox ]; then /bin/busybox echo BISHO_PROOT_DIAG_OK; else echo BISHO_PROOT_DIAG_OK; fi'
  fi
  status=$?
  echo "ROOTFS_COMMAND_EXIT=$status"
}

run_case "Bundled PRoot (engine)" "$BUNDLE_PROOT"
if [ -n "$TERMUX_PROOT" ] && [ "$TERMUX_PROOT" != "$BUNDLE_PROOT" ]; then
  run_case "Termux PRoot (known-good comparison)" "$TERMUX_PROOT"
else
  echo "Termux PRoot comparison skipped: command not found or same path."
fi

SOURCE_ROOT="$(printenv PROOT_SOURCE_DIR 2>/dev/null || true)"
if [ -z "$SOURCE_ROOT" ]; then
  SOURCE_EVENT=""
  for candidate in "$HOME"/proot*/src/tracee/event.c "$HOME"/*/src/tracee/event.c; do
    if [ -f "$candidate" ]; then SOURCE_EVENT="$candidate"; break; fi
  done
  if [ -n "$SOURCE_EVENT" ]; then
    SOURCE_ROOT="$(dirname "$(dirname "$(dirname "$SOURCE_EVENT")")")"
  fi
fi
printf '\n===== LOCAL PRoot SOURCE EXCERPTS (read-only) =====\n'
if [ -n "$SOURCE_ROOT" ] && [ -f "$SOURCE_ROOT/src/tracee/event.c" ]; then
  printf 'SOURCE_ROOT=%s\n' "$SOURCE_ROOT"
  echo '--- event.c: seccomp events and SIGSYS ---'
  grep -n -C 8 -E 'PTRACE_EVENT_SECCOMP|SIGSYS|seccomp_after_ptrace_enter|skip_next_seccomp_signal|SYSCALL_AVOIDER' "$SOURCE_ROOT/src/tracee/event.c" || true
  echo '--- reg.c: register-set access ---'
  grep -n -C 5 -E 'fetch_regs|NT_PRSTATUS|NT_ARM_SYSTEM_CALL' "$SOURCE_ROOT/src/tracee/reg.c" || true
  echo '--- arch.h: syscall avoider value ---'
  grep -n -C 3 'SYSCALL_AVOIDER' "$SOURCE_ROOT/src/arch.h" || true
else
  echo 'No local PRoot source checkout found under HOME. Pinned upstream and Termux sources were compared from GitHub.'
fi

printf '\n===== END =====\n'
printf 'LOG_FILE=%s\n' "$LOG_FILE"
if command -v termux-clipboard-set >/dev/null 2>&1; then
  termux-clipboard-set < "$LOG_FILE" && echo "Full diagnostic copied to clipboard."
fi
