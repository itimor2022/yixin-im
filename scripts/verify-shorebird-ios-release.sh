#!/usr/bin/env bash
# 只读检查 IPA/XCARCHIVE 的版本、构建号、Bundle ID 和代码签名。
# 未传 --artifact 时会从 build/ios 自动选择产物；存在多个产物时应显式指定，
# 避免验证到旧包。临时解包目录由 EXIT trap 清理。
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact=""
expected_version=""
expected_build=""

while (($#)); do
  case "$1" in
    --artifact) artifact="$2"; shift 2 ;;
    --expected-version) expected_version="$2"; shift 2 ;;
    --expected-build) expected_build="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--artifact IPA_OR_XCARCHIVE] [--expected-version V] [--expected-build N]"
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

pubspec_version="$(sed -nE 's/^[[:space:]]*version:[[:space:]]*([^[:space:]]+).*/\1/p' "$project_root/pubspec.yaml" | head -1)"
[[ -n "$expected_version" ]] || expected_version="${pubspec_version%%+*}"
[[ -n "$expected_build" ]] || expected_build="${pubspec_version##*+}"

if [[ -z "$artifact" ]]; then
  artifact="$(find "$project_root/build/ios" -type f -name '*.ipa' -print 2>/dev/null | head -1 || true)"
  [[ -n "$artifact" ]] || artifact="$project_root/build/ios/archive/Runner.xcarchive"
fi
[[ -e "$artifact" ]] || { echo "iOS artifact not found: $artifact" >&2; exit 1; }

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shorebird-ios-verify.XXXXXX")"
# 所有退出路径都清理临时 IPA 解包内容，避免签名产物残留在共享机器。
cleanup() { rm -rf "$temp_dir"; }
trap cleanup EXIT

if [[ "$artifact" == *.ipa ]]; then
  unzip -q "$artifact" -d "$temp_dir"
  app_path="$(find "$temp_dir/Payload" -maxdepth 1 -type d -name '*.app' -print | head -1)"
else
  app_path="$artifact/Products/Applications/Runner.app"
fi
[[ -d "$app_path" ]] || { echo "App bundle not found in artifact." >&2; exit 1; }

info_plist="$app_path/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"

[[ "$version" == "$expected_version" ]] || { echo "Version mismatch: expected $expected_version, got $version" >&2; exit 1; }
[[ "$build" == "$expected_build" ]] || { echo "Build mismatch: expected $expected_build, got $build" >&2; exit 1; }
codesign --verify --deep --strict "$app_path"

echo "Artifact: $artifact"
echo "Bundle ID: $bundle_id"
echo "Version: $version+$build"
if [[ -f "$artifact" ]]; then
  echo "SHA256: $(shasum -a 256 "$artifact" | awk '{print $1}')"
fi
codesign -dv --verbose=2 "$app_path" 2>&1 | sed -nE '/^(Authority|TeamIdentifier|Identifier)=/p'
echo "Verification passed. Confirm the same artifact is uploaded to TestFlight/App Store Connect."
