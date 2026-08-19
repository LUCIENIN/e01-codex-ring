#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
label="com.lucien.e01-codex-ring"
agent_path="${HOME}/Library/LaunchAgents/${label}.plist"
runtime_dir="${repo_root}/.runtime"
binary_path="${repo_root}/.build/release/codex-ring"
sessions_path="${CODEX_SESSIONS_DIR:-${HOME}/.codex/sessions}"
known_device_path="${HOME}/.codex/e01-known-device-id"

if [[ "${1:-}" == "--reset-device" && -f "${known_device_path}" ]]; then
    backup_path="${known_device_path}.backup.$(date +%Y%m%d%H%M%S)"
    mv "${known_device_path}" "${backup_path}"
    print "Backed up the previous device identifier to ${backup_path}"
fi

mkdir -p "${runtime_dir}" "${HOME}/Library/LaunchAgents"
cd "${repo_root}"
swift build -c release

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
/usr/libexec/PlistBuddy -c "Add :WorkingDirectory string ${repo_root}" "${agent_path}"
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
print "Turn off phone Bluetooth, then power-cycle the E01 once."
print "Logs: ${runtime_dir}/display-watch.log"
