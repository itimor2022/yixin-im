#!/usr/bin/env bash
# 为既有 iOS Shorebird Release 创建补丁，默认先发布到 staging track。
# 补丁必须使用与基线 Release 相同的服务地址和导出配置；原生代码或不受支持
# 的资源差异不能通过 Dart 补丁交付。正式执行前应先使用 --print-only。
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_version=""
track="staging"
baseline_ref=""
server_url=""
ws_url=""
bootstrap_url=""
export_options="$project_root/ios/ExportOptions.plist"
target="lib/main.dart"
dry_run=false
print_only=false
allow_http=false
declare -a extra_defines=()
extra_defines_count=0

usage() {
  echo "Usage: $0 --release-version VERSION+BUILD --server-url URL [options]"
  echo "  --track staging|stable      Defaults to staging"
  echo "  --baseline-ref GIT_REF      Defaults to shorebird-ios-VERSION+BUILD"
  echo "  --ws-url URL | --bootstrap-url URL | --export-options-plist PATH"
  echo "  --extra-dart-define K=V     Repeatable"
  echo "  --dry-run | --print-only | --allow-http"
}

while (($#)); do
  case "$1" in
    --release-version) release_version="$2"; shift 2 ;;
    --track) track="$2"; shift 2 ;;
    --baseline-ref) baseline_ref="$2"; shift 2 ;;
    --server-url) server_url="$2"; shift 2 ;;
    --ws-url) ws_url="$2"; shift 2 ;;
    --bootstrap-url) bootstrap_url="$2"; shift 2 ;;
    --export-options-plist) export_options="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --extra-dart-define) extra_defines+=("$2"); extra_defines_count=$((extra_defines_count + 1)); shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --print-only) print_only=true; shift ;;
    --allow-http) allow_http=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "iOS patching requires macOS." >&2; exit 1; }
# VERSION+BUILD 与 baseline-ref 共同锁定补丁基线，避免误向另一安装包版本投放。
[[ -n "$release_version" && "$release_version" == *+* ]] || { echo "--release-version must be NAME+BUILD." >&2; exit 2; }
[[ -n "$server_url" ]] || { echo "--server-url is required and must match the baseline release." >&2; exit 2; }
[[ "$track" == "staging" || "$track" == "stable" ]] || { echo "--track must be staging or stable." >&2; exit 2; }
[[ -f "$export_options" ]] || { echo "Export options not found: $export_options" >&2; exit 1; }
if [[ "$allow_http" != true && "$server_url" != https://* ]]; then
  echo "Patch server URL must use HTTPS (or pass --allow-http for a deliberate test build)." >&2
  exit 2
fi

[[ -n "$baseline_ref" ]] || baseline_ref="shorebird-ios-$release_version"
git -C "$project_root" rev-parse --verify "$baseline_ref^{commit}" >/dev/null 2>&1 || {
  echo "Baseline git ref not found: $baseline_ref" >&2
  echo "Tag the exact App Store Shorebird release source before creating patches." >&2
  exit 1
}
git -C "$project_root" merge-base --is-ancestor "$baseline_ref" HEAD || {
  echo "Baseline ref is not an ancestor of HEAD: $baseline_ref" >&2
  echo "Create patches from the committed source history that contains the App Store baseline." >&2
  exit 1
}

pubspec_version="$(sed -nE 's/^[[:space:]]*version:[[:space:]]*([^[:space:]]+).*/\1/p' "$project_root/pubspec.yaml" | head -1)"
[[ "$pubspec_version" == "$release_version" ]] || {
  echo "Version mismatch: pubspec.yaml is $pubspec_version but patch target is $release_version." >&2
  exit 1
}

app_dirty="$(git -C "$project_root" status --short -- ios lib assets pubspec.yaml pubspec.lock shorebird.yaml)"
[[ -z "$app_dirty" ]] || {
  echo "Patch blocked: iOS application source has uncommitted changes:" >&2
  printf '%s\n' "$app_dirty" >&2
  echo "Commit the patch source before publishing so the uploaded artifact is reproducible." >&2
  exit 1
}

changed_files="$(git -C "$project_root" diff --name-only "$baseline_ref"...HEAD | sort -u)"
risky_files="$(printf '%s\n' "$changed_files" | awk '
  /^ios\// || /^assets\// || /^pubspec\.yaml$/ || /^pubspec\.lock$/ ||
  /^shorebird\.yaml$/ || /^\.flutter-version$/ || /^\.fvm\// ||
  /(^|\/)Podfile(\.lock)?$/ { print }
')"
if [[ -n "$risky_files" ]]; then
  echo "Patch blocked: native, dependency, Flutter toolchain, or bundled asset changes detected:" >&2
  printf '%s\n' "$risky_files" >&2
  echo "Publish a new App Store Shorebird baseline for these changes." >&2
  exit 1
fi

for tool in shorebird xcodebuild pod; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
if [[ -z "$ws_url" ]]; then
  ws_url="${server_url%/}/api/v1/ws"
  ws_url="${ws_url/#https:/wss:}"
  ws_url="${ws_url/#http:/ws:}"
fi

declare -a args=(patch ios --release-version "$release_version" --track "$track" --target "$target" --export-options-plist "$export_options")
args+=(--dart-define "GENERIC_IM_SERVER_URL=$server_url" --dart-define "GENERIC_IM_WS_URL=$ws_url")
[[ -n "$bootstrap_url" ]] && args+=(--dart-define "GENERIC_IM_BOOTSTRAP_URL=$bootstrap_url")
if ((extra_defines_count > 0)); then
  for define in "${extra_defines[@]}"; do args+=(--dart-define "$define"); done
fi
[[ "$dry_run" == true ]] && args+=(--dry-run)

echo "iOS Shorebird patch: release=$release_version track=$track"
echo "Baseline ref: $baseline_ref"
echo "Commit: $(git -C "$project_root" rev-parse HEAD)"
echo "Created at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'Command:'; printf ' %q' shorebird "${args[@]}"; echo

[[ "$print_only" == true ]] && exit 0
shorebird doctor
(cd "$project_root" && shorebird "${args[@]}")

if [[ "$track" == "staging" && "$dry_run" != true ]]; then
  echo "Next: verify on a physical iPhone with shorebird preview --track=staging."
  echo "Then inspect 'shorebird patches promote --help' and promote this exact patch to stable."
fi
