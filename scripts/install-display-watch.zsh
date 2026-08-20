#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
label="com.lucien.e01-codex-ring"
agent_path="${HOME}/Library/LaunchAgents/${label}.plist"
runtime_dir="${HOME}/.local/state/e01-codex-ring"
install_root="${HOME}/.local/lib/e01-codex-ring"
bundle_id="com.lucien.e01-codex-ring"
application_name="CodexRing.app"
application_path="${install_root}/${application_name}"
binary_path="${application_path}/Contents/MacOS/codex-ring"
resource_name="CodexRing_CodexRingCore.bundle"
build_binary="${E01_BUILD_BINARY:-${repo_root}/.build/release/codex-ring}"
build_resources="${E01_BUILD_RESOURCES:-${repo_root}/.build/release/${resource_name}}"
sessions_path="${CODEX_SESSIONS_DIR:-${HOME}/.codex/sessions}"
known_device_path="${HOME}/.codex/e01-known-device-id"

stage_runtime() {
    local destination=$1
    local staged_application="${destination}/${application_name}"
    local staged_contents="${staged_application}/Contents"
    local staged_macos="${staged_contents}/MacOS"
    local staged_resources="${staged_contents}/Resources"
    local staged_info="${staged_contents}/Info.plist"
    if [[ ! -d "${build_resources}" ]]; then
        print -u2 "Missing SwiftPM resource bundle: ${build_resources}"
        return 1
    fi
    mkdir -p "${staged_macos}" "${staged_resources}"
    if [[ -e "${staged_macos}/${resource_name}" ]]; then
        /bin/rm -rf "${staged_macos}/${resource_name}"
    fi
    /usr/bin/install -m 0755 "${build_binary}" "${staged_macos}/codex-ring"
    /usr/bin/install -m 0644 \
        "${build_resources}/jl_auth_2.0.0.js" \
        "${staged_resources}/jl_auth_2.0.0.js"
    /usr/bin/plutil -create xml1 "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${bundle_id}" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string codex-ring" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string CodexRing" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Codex Ring" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :LSUIElement bool false" "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :NSBluetoothAlwaysUsageDescription string Syncs quota cards to the E01 display." "${staged_info}"
    /usr/libexec/PlistBuddy -c "Add :NSBluetoothPeripheralUsageDescription string Syncs quota cards to the E01 display." "${staged_info}"
}

if [[ "${1:-}" == "--reset-device" && -f "${known_device_path}" ]]; then
    backup_path="${known_device_path}.backup.$(date +%Y%m%d%H%M%S)"
    mv "${known_device_path}" "${backup_path}"
    print "Backed up the previous device identifier to ${backup_path}"
fi

mkdir -p "${runtime_dir}" "${install_root}" "${HOME}/Library/LaunchAgents"
if [[ "${1:-}" == "--stage-runtime" ]]; then
    if [[ -z "${2:-}" ]]; then
        print -u2 "Usage: $0 --stage-runtime DESTINATION"
        exit 2
    fi
    stage_runtime "$2"
    print "Staged runtime in $2"
    exit 0
fi
cd "${repo_root}"
swift build -c release
stage_runtime "${install_root}"
/usr/bin/codesign --force --sign - --identifier "${bundle_id}" "${application_path}"

launchctl bootout "gui/${UID}/${label}" 2>/dev/null || true

log_stamp=$(date +%Y%m%d%H%M%S)
for log_path in "${runtime_dir}/display-watch.log" "${runtime_dir}/display-watch.error.log"; do
    if [[ -f "${log_path}" ]]; then
        mv "${log_path}" "${log_path}.backup.${log_stamp}"
    fi
done

/usr/bin/plutil -create xml1 "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :Label string ${label}" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${binary_path}" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string display-watch" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string --sessions" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:3 string ${sessions_path}" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:4 string --output" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:5 string ${runtime_dir}/codex-ring-preview.png" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:6 string --interval" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:7 string 30" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:8 string --timeout" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:9 string 30" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :WorkingDirectory string ${install_root}" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :KeepAlive bool true" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ProcessType string Background" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :ThrottleInterval integer 10" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string ${runtime_dir}/display-watch.log" "${agent_path}"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string ${runtime_dir}/display-watch.error.log" "${agent_path}"

/usr/bin/plutil -lint "${agent_path}"
launchctl bootstrap "gui/${UID}" "${agent_path}"
launchctl enable "gui/${UID}/${label}"
launchctl kickstart -k "gui/${UID}/${label}"

print "Installed ${label}"
print "The watcher will reconnect automatically while the E01 is available."
print "Logs: ${runtime_dir}/display-watch.log"
