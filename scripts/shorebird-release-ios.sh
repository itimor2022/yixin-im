#!/usr/bin/env bash
# 创建 iOS Shorebird Release，并可在成功后写入对应 Git 基线标签。
# 必须在 macOS、有效签名和 App Store Connect 已确认构建号的环境运行。
# 正式发布前先使用 --print-only 或 --dry-run 核对端点、版本和导出配置。
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_name=""
build_number=""
server_url=""
ws_url=""
bootstrap_url=""
export_options="$project_root/ios/ExportOptions.plist"
flutter_version=""
target="lib/main.dart"
dry_run=false
print_only=false
allow_http=false
create_tag=true
declare -a extra_defines=()
extra_defines_count=0

usage() {
  echo "Usage: $0 --server-url URL [options]"
  echo "  --build-name VERSION        Defaults to pubspec.yaml"
  echo "  --build-number NUMBER       Required; must exceed App Store Connect history"
  echo "  --ws-url URL                Derived from --server-url when omitted"
  echo "  --bootstrap-url URL         Optional runtime bootstrap endpoint"
  echo "  --export-options-plist PATH Defaults to ios/ExportOptions.plist"
  echo "  --flutter-version VERSION   Pin Shorebird's Flutter version"
  echo "  --extra-dart-define K=V     Repeatable"
  echo "  --dry-run | --print-only | --allow-http | --no-tag"
}

while (($#)); do
  case "$1" in
    --build-name) build_name="$2"; shift 2 ;;
    --build-number) build_number="$2"; shift 2 ;;
    --server-url) server_url="$2"; shift 2 ;;
    --ws-url) ws_url="$2"; shift 2 ;;
    --bootstrap-url) bootstrap_url="$2"; shift 2 ;;
    --export-options-plist) export_options="$2"; shift 2 ;;
    --flutter-version) flutter_version="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --extra-dart-define) extra_defines+=("$2"); extra_defines_count=$((extra_defines_count + 1)); shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --print-only) print_only=true; shift ;;
    --allow-http) allow_http=true; shift ;;
    --no-tag) create_tag=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "iOS release requires macOS." >&2; exit 1; }
# Release 是后续补丁的不可变基线，禁止依赖隐式服务地址或重复构建号。
[[ -n "$server_url" ]] || { echo "--server-url is required; do not build a store release with an implicit endpoint." >&2; exit 2; }
[[ -n "$build_number" ]] || { echo "--build-number is required; verify it in App Store Connect first." >&2; exit 2; }
if [[ "$allow_http" != true && "$server_url" != https://* ]]; then
  echo "App Store release server URL must use HTTPS (or pass --allow-http for a deliberate test build)." >&2
  exit 2
fi
[[ -f "$export_options" ]] || { echo "Export options not found: $export_options" >&2; exit 1; }

pubspec_version="$(sed -nE 's/^[[:space:]]*version:[[:space:]]*([^[:space:]]+).*/\1/p' "$project_root/pubspec.yaml" | head -1)"
[[ "$pubspec_version" == *+* ]] || { echo "pubspec.yaml version must be NAME+NUMBER." >&2; exit 1; }
[[ -n "$build_name" ]] || build_name="${pubspec_version%%+*}"
expected_version="$build_name+$build_number"
[[ "$pubspec_version" == "$expected_version" ]] || {
  echo "Version mismatch: pubspec.yaml is $pubspec_version but the requested release is $expected_version." >&2
  echo "Update pubspec.yaml first so the tagged source exactly describes the App Store build." >&2
  exit 1
}

if [[ -z "$ws_url" ]]; then
  ws_url="${server_url%/}/api/v1/ws"
  ws_url="${ws_url/#https:/wss:}"
  ws_url="${ws_url/#http:/ws:}"
fi

for tool in shorebird xcodebuild pod plutil codesign; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

bundle_id="$(sed -nE 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/\1/p' "$project_root/ios/Runner.xcodeproj/project.pbxproj" | head -1)"
team_id="$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$export_options")"
app_dirty="$(git -C "$project_root" status --short -- ios lib assets pubspec.yaml pubspec.lock shorebird.yaml)"
[[ -z "$app_dirty" ]] || {
  echo "Release blocked: iOS application source has uncommitted changes:" >&2
  printf '%s\n' "$app_dirty" >&2
  echo "Commit the exact application source before creating a Shorebird baseline." >&2
  exit 1
}

baseline_tag="shorebird-ios-$expected_version"
if [[ "$create_tag" == true ]] && git -C "$project_root" rev-parse --verify "$baseline_tag^{commit}" >/dev/null 2>&1; then
  echo "Baseline tag already exists: $baseline_tag" >&2
  exit 1
fi

declare -a args=(release ios --build-name "$build_name" --build-number "$build_number" --target "$target" --export-options-plist "$export_options")
[[ -n "$flutter_version" ]] && args+=(--flutter-version "$flutter_version")
args+=(--dart-define "GENERIC_IM_SERVER_URL=$server_url" --dart-define "GENERIC_IM_WS_URL=$ws_url")
[[ -n "$bootstrap_url" ]] && args+=(--dart-define "GENERIC_IM_BOOTSTRAP_URL=$bootstrap_url")
if ((extra_defines_count > 0)); then
  for define in "${extra_defines[@]}"; do args+=(--dart-define "$define"); done
fi
[[ "$dry_run" == true ]] && args+=(--dry-run)

echo "iOS Shorebird baseline: $build_name+$build_number"
echo "Bundle ID: $bundle_id"
echo "Team ID: $team_id"
echo "Server URL: $server_url"
echo "WebSocket URL: $ws_url"
printf 'Command:'; printf ' %q' shorebird "${args[@]}"; echo

[[ "$print_only" == true ]] && exit 0
shorebird doctor
(cd "$project_root" && shorebird "${args[@]}")

if [[ "$dry_run" != true ]]; then
  "$project_root/scripts/verify-shorebird-ios-release.sh" \
    --expected-version "$build_name" --expected-build "$build_number"
  if [[ "$create_tag" == true ]]; then
    git -C "$project_root" tag -a "$baseline_tag" -m "Shorebird iOS baseline $expected_version"
    echo "Created baseline tag: $baseline_tag"
  else
    echo "Baseline tag creation skipped (--no-tag)."
  fi
fi
