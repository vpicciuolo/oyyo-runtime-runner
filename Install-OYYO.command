#!/bin/zsh

# Public macOS bootstrap for the encrypted OYYO runtime package. Secrets are
# accepted only by a masked local dialog (or guarded test stdin), sent to the
# decryptor over stdin, and stored in the user's login Keychain without ever
# appearing in argv, environment variables, manifests or logs.
emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset -r SCRIPT_DIR="${0:A:h}"
typeset -r DEFAULT_KEYCHAIN_SERVICE='com.oyyo.runtime.package-key'
typeset -r DEFAULT_KEYCHAIN_ACCOUNT='demo-package-key'
typeset test_mode="${OYYO_INSTALLER_TEST:-0}"
typeset explicit_update=0
typeset no_launch=0
typeset test_key_stdin=0
typeset test_fail_after_registration=0
typeset manifest_override=''
typeset package_override=''
typeset support_override=''
typeset applications_override=''
typeset desktop_override=''
typeset keychain_service="$DEFAULT_KEYCHAIN_SERVICE"
typeset keychain_account="$DEFAULT_KEYCHAIN_ACCOUNT"
typeset security_command='/usr/bin/security'
typeset current_install_hint=''

usage() {
  print -u2 -- 'Usage: Install-OYYO.command [--update] [--current-install-directory PATH] [--no-launch]'
}

die() {
  print -u2 -- "OYYO installation stopped: $1"
  exit 1
}

require_value() {
  (( $# >= 2 )) || die "Missing value for $1."
}

while (( $# > 0 )); do
  case "$1" in
    --update)
      explicit_update=1
      shift
      ;;
    --current-install-directory)
      require_value "$@"
      current_install_hint="$2"
      shift 2
      ;;
    --no-launch)
      no_launch=1
      shift
      ;;
    --test-manifest)
      require_value "$@"
      manifest_override="$2"
      shift 2
      ;;
    --test-package)
      require_value "$@"
      package_override="$2"
      shift 2
      ;;
    --test-support-root)
      require_value "$@"
      support_override="$2"
      shift 2
      ;;
    --test-applications-dir)
      require_value "$@"
      applications_override="$2"
      shift 2
      ;;
    --test-desktop-dir)
      require_value "$@"
      desktop_override="$2"
      shift 2
      ;;
    --test-keychain-service)
      require_value "$@"
      keychain_service="$2"
      shift 2
      ;;
    --test-keychain-account)
      require_value "$@"
      keychain_account="$2"
      shift 2
      ;;
    --test-security-command)
      require_value "$@"
      security_command="$2"
      shift 2
      ;;
    --test-key-stdin)
      test_key_stdin=1
      shift
      ;;
    --test-fail-after-registration)
      test_fail_after_registration=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown option: $1"
      ;;
  esac
done

if [[ "$test_mode" != '1' ]]; then
  [[ -z "$manifest_override" && -z "$package_override" && -z "$support_override" && -z "$applications_override" && -z "$desktop_override" ]] || die 'Test path overrides are disabled.'
  [[ "$keychain_service" == "$DEFAULT_KEYCHAIN_SERVICE" && "$keychain_account" == "$DEFAULT_KEYCHAIN_ACCOUNT" && "$security_command" == '/usr/bin/security' && "$test_key_stdin" == '0' && "$test_fail_after_registration" == '0' ]] || die 'Test activation overrides are disabled.'
else
  no_launch=1
  [[ "$keychain_service" == com.oyyo.runtime.test.* ]] || die 'A test Keychain service must start with com.oyyo.runtime.test.'
  [[ "$keychain_account" == test-* ]] || die 'A test Keychain account must start with test-.'
  [[ -x "$security_command" ]] || die 'The guarded test security command is not executable.'
fi

[[ "$(/usr/bin/uname -s)" == 'Darwin' ]] || die 'This installer requires macOS.'

typeset machine="$(/usr/bin/uname -m)"
typeset arch=''
if [[ "$machine" == 'arm64' ]]; then
  arch='arm64'
elif [[ "$machine" == 'x86_64' ]]; then
  typeset translated='0'
  translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || print -r -- '0')"
  if [[ "$translated" == '1' ]]; then arch='arm64'; else arch='x64'; fi
else
  die "Unsupported Mac architecture: $machine"
fi

typeset support_root="${support_override:-$HOME/Library/Application Support/OYYO}"
typeset applications_dir="${applications_override:-$HOME/Applications}"
typeset desktop_dir="${desktop_override:-$HOME/Desktop}"
typeset versions_root="$support_root/versions"
typeset data_root="$support_root/data"
typeset install_record="$support_root/install.json"

if [[ "$test_mode" == '1' ]]; then
  typeset temp_prefix="${TMPDIR:-/private/tmp}"
  for test_path in "$support_root" "$applications_dir" "$desktop_dir"; do
    typeset absolute_test_path="${test_path:A}"
    if [[ "$absolute_test_path" != /private/tmp/* && "$absolute_test_path" != "${temp_prefix:A}"/* ]]; then
      die "Test paths must remain below the macOS temporary directory: $absolute_test_path"
    fi
  done
fi

/bin/mkdir -p -- "$support_root" "$versions_root" "$data_root" "$applications_dir"
[[ -d "$support_root" && -d "$versions_root" && -d "$data_root" && -d "$applications_dir" ]] || die 'Could not prepare the per-user OYYO directories.'

# Normalize once the directories exist so update-path containment checks are
# stable even when macOS supplies TMPDIR with a trailing slash or a symlink.
support_root="${support_root:A}"
applications_dir="${applications_dir:A}"
[[ -d "$desktop_dir" ]] && desktop_dir="${desktop_dir:A}"
versions_root="$support_root/versions"
data_root="$support_root/data"
install_record="$support_root/install.json"

typeset lock_dir="$support_root/.installer.lock"
acquire_lock() {
  if /bin/mkdir -- "$lock_dir" 2>/dev/null; then
    print -r -- "$$" > "$lock_dir/pid"
    return
  fi
  typeset owner=''
  [[ -f "$lock_dir/pid" ]] && owner="$(<"$lock_dir/pid")"
  if [[ "$owner" == <-> ]] && /bin/kill -0 "$owner" 2>/dev/null; then
    die "Another OYYO installer is already running (PID $owner)."
  fi
  /bin/rm -f -- "$lock_dir/pid"
  /bin/rmdir -- "$lock_dir" 2>/dev/null || die 'The OYYO installer lock could not be retired safely.'
  /bin/mkdir -- "$lock_dir" || die 'Could not acquire the OYYO installer lock.'
  print -r -- "$$" > "$lock_dir/pid"
}
acquire_lock

typeset temp_root=''
typeset candidate_root=''
typeset staging_root=''
typeset temporary_link=''
typeset temporary_desktop_link=''
typeset key_material=''
typeset key_added=0
typeset registration_succeeded=0
typeset committed=0

safe_remove_candidate() {
  typeset target="$1"
  [[ -n "$target" && "$target" != "$versions_root" && "$target" == "$versions_root"/* ]] || return 0
  /bin/rm -rf -- "$target"
}

cleanup() {
  typeset code="$?"
  trap - EXIT INT TERM HUP
  set +e
  key_material=''
  if (( code != 0 && key_added == 1 && committed == 0 && registration_succeeded == 0 )); then
    "$security_command" delete-generic-password -a "$keychain_account" -s "$keychain_service" >/dev/null 2>&1
  fi
  [[ -n "$temporary_link" && -L "$temporary_link" ]] && /bin/rm -f -- "$temporary_link"
  [[ -n "$temporary_desktop_link" && -L "$temporary_desktop_link" ]] && /bin/rm -f -- "$temporary_desktop_link"
  # Once the inner registrar succeeds, Codex points at this exact version root.
  # Retain it on a later filesystem failure instead of leaving that registration
  # dangling. The next installer run will stop for repair because no install
  # record was committed.
  if (( committed == 0 && registration_succeeded == 0 )) && [[ -n "$candidate_root" ]]; then safe_remove_candidate "$candidate_root"; fi
  if (( committed == 0 )) && [[ -n "$staging_root" ]]; then safe_remove_candidate "$staging_root"; fi
  if [[ -n "$temp_root" && "$temp_root" == "${TMPDIR:-/private/tmp}"/oyyo-install.* ]]; then /bin/rm -rf -- "$temp_root"; fi
  if (( code != 0 && explicit_update == 1 )) && [[ "$test_mode" != '1' ]]; then
    print -r -- 'The OYYO updater stopped safely. The current installation and shared data were preserved.' > "$SCRIPT_DIR/installer-error.log"
  fi
  /bin/rm -f -- "$lock_dir/pid"
  /bin/rmdir -- "$lock_dir" 2>/dev/null
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

typeset -a node_candidates
node_candidates=()
typeset path_node="$(command -v node 2>/dev/null || true)"
[[ -n "$path_node" ]] && node_candidates+=("$path_node")
node_candidates+=(
  "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
  '/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node'
  '/Applications/Codex.app/Contents/Resources/cua_node/bin/node'
  "$HOME/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
  "$HOME/Applications/Codex.app/Contents/Resources/cua_node/bin/node"
)
typeset node_bin=''
for candidate in "${node_candidates[@]}"; do
  [[ -x "$candidate" ]] || continue
  typeset node_version="$($candidate --version 2>/dev/null || true)"
  typeset node_major="${${node_version#v}%%.*}"
  if [[ "$node_major" == <-> ]] && (( node_major >= 22 )); then
    node_bin="$candidate"
    break
  fi
done
[[ -n "$node_bin" ]] || die 'Install and open Codex first. OYYO needs its local Node runtime or Node.js 22 or later.'

typeset manifest_path="${manifest_override:-$SCRIPT_DIR/release-macos-$arch.json}"
[[ -f "$manifest_path" ]] || die "The macOS $arch release manifest is missing."

typeset manifest_output
manifest_output="$($node_bin --input-type=module -e '
  import fs from "node:fs";
  const [file, arch] = process.argv.slice(1);
  try {
    const value = JSON.parse(fs.readFileSync(file, "utf8"));
    const versionOk = /^\d+\.\d+\.\d+$/.test(value.version ?? "");
    if (value.status !== "ready") throw new Error(`The macOS ${arch} release is not ready (${value.status ?? "missing status"}).`);
    if (!versionOk) throw new Error("The Mac release version is invalid.");
    if (value.platform !== `macos-${arch}`) throw new Error("The Mac release platform does not match this computer.");
    if (value.format !== "OYYOPKG1" || value.encryption !== "AES-256-GCM") throw new Error("The Mac release encryption contract is invalid.");
    if (value.payloadArchive !== "tar.gz") throw new Error("The Mac release payload must be a tar.gz archive.");
    if (!/^[a-f0-9]{64}$/.test(value.sha256 ?? "")) throw new Error("The Mac release SHA-256 is invalid.");
    if (!Number.isSafeInteger(value.sizeBytes) || value.sizeBytes <= 36) throw new Error("The Mac release byte count is invalid.");
    const expected = `https://github.com/vpicciuolo/oyyo-runtime-runner/releases/download/v${value.version}/oyyo-macos-${arch}-demo-${value.version}.oyyo`;
    if (value.url !== expected) throw new Error("The Mac release URL is not the approved immutable GitHub asset URL.");
    console.log([value.version, value.url, value.sha256, String(value.sizeBytes), value.payloadArchive, value.platform].join("\n"));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
' "$manifest_path" "$arch")" || die 'The Mac release manifest was rejected.'

typeset -a manifest_fields
manifest_fields=("${(@f)manifest_output}")
(( ${#manifest_fields[@]} == 6 )) || die 'The Mac release manifest did not produce the expected fields.'
typeset version="${manifest_fields[1]}"
typeset package_url="${manifest_fields[2]}"
typeset expected_sha="${manifest_fields[3]}"
typeset expected_size="${manifest_fields[4]}"

typeset update_mode=0
if [[ -f "$install_record" ]]; then update_mode=1; fi
if (( explicit_update == 1 )); then
  [[ -f "$install_record" ]] || die 'No completed OYYO installation was found to update.'
  update_mode=1
fi

typeset previous_root=''
typeset previous_config=''
typeset stable_app="$applications_dir/OYYO.app"
if (( update_mode == 1 )); then
  previous_root="$($node_bin --input-type=module -e '
    import fs from "node:fs";
    try {
      const record = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      if (typeof record.installedRoot !== "string" || !record.installedRoot) throw new Error("missing installedRoot");
      process.stdout.write(record.installedRoot);
    } catch { process.exit(1); }
  ' "$install_record")" || die 'The existing OYYO install record is invalid.'
  [[ "${previous_root:A}" == "$versions_root"/* ]] || die 'The existing OYYO install record points outside the versioned install root.'
  previous_root="${previous_root:A}"
  previous_config="$previous_root/plugins/oyyo/config.local.json"
  [[ -f "$previous_config" ]] || die 'The existing OYYO settings were not found. Update stopped to protect your data.'
  [[ -L "$stable_app" ]] || die 'The stable OYYO application link is missing or was replaced. Update stopped safely.'
  if [[ -n "$current_install_hint" && "${current_install_hint:A}" != "$previous_root" ]]; then
    die 'The running OYYO version does not match the recorded installation. Update stopped safely.'
  fi
else
  [[ ! -e "$stable_app" && ! -L "$stable_app" ]] || die 'An OYYO application already exists but has no valid install record. Repair it before installing.'
  if "$security_command" find-generic-password -a "$keychain_account" -s "$keychain_service" >/dev/null 2>&1; then
    die 'An OYYO activation exists without a completed install record. Repair it before installing.'
  fi
fi

if (( explicit_update == 1 )) && [[ "$test_mode" != '1' ]]; then
  print -r -- "{\"pid\":$$}" > "$SCRIPT_DIR/installer-ready.json"
fi

prompt_for_key() {
  if (( test_key_stdin == 1 )); then
    IFS= read -r key_material || die 'The guarded test key was not provided on stdin.'
  else
    key_material="$(/usr/bin/osascript <<'APPLESCRIPT'
try
  set response to display dialog "Enter your 64-character OYYO demo key. It stays on this Mac and is not sent to GitHub." with title "Install OYYO" default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel"
  return text returned of response
on error number -128
  error number -128
end try
APPLESCRIPT
    )" || die 'Installation was cancelled before activation.'
  fi
  [[ "$key_material" =~ '^[[:xdigit:]]{64}$' ]] || die 'Enter the 64-character hexadecimal OYYO demo key.'
}

if (( update_mode == 1 )); then
  key_material="$("$security_command" find-generic-password -a "$keychain_account" -s "$keychain_service" -w 2>/dev/null)" || die 'The saved OYYO activation is unavailable. Unlock your login Keychain and try again.'
  [[ "$key_material" =~ '^[[:xdigit:]]{64}$' ]] || die 'The saved OYYO activation is invalid. Repair activation with the original key.'
else
  prompt_for_key
fi

temp_root="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/oyyo-install.XXXXXX")" || die 'Could not create a private installer workspace.'
typeset encrypted_path="$temp_root/package.oyyo"
typeset archive_path="$temp_root/package.tar.gz"
staging_root="$versions_root/.staging-$version-$arch-$$"
typeset install_nonce="$(/usr/bin/uuidgen)"
install_nonce="${install_nonce//-/}"
candidate_root="$versions_root/$version-$arch-$install_nonce"
[[ ! -e "$staging_root" && ! -e "$candidate_root" ]] || die 'The selected versioned install path already exists.'

if [[ -n "$package_override" ]]; then
  [[ "$test_mode" == '1' && -f "$package_override" ]] || die 'The guarded test package is unavailable.'
  /bin/cp -p -- "$package_override" "$encrypted_path"
else
  print -- "Downloading authenticated OYYO $version for macOS $arch..."
  /usr/bin/curl --proto '=https' --tlsv1.2 --location --fail --retry 2 --connect-timeout 20 --output "$encrypted_path" "$package_url" || die 'The OYYO package download failed.'
fi

typeset actual_size="$(/usr/bin/stat -f '%z' "$encrypted_path")"
[[ "$actual_size" == "$expected_size" ]] || die 'Package byte count mismatch. Installation stopped.'
typeset actual_sha="$($node_bin --input-type=module -e '
  import crypto from "node:crypto"; import fs from "node:fs";
  const hash = crypto.createHash("sha256");
  const stream = fs.createReadStream(process.argv[1]);
  stream.on("data", chunk => hash.update(chunk));
  stream.on("end", () => process.stdout.write(hash.digest("hex")));
  stream.on("error", () => process.exit(1));
' "$encrypted_path")" || die 'Could not hash the downloaded package.'
[[ "$actual_sha" == "$expected_sha" ]] || die 'Package checksum mismatch. Installation stopped.'

print -- 'Authenticating the encrypted package...'
print -r -- "$key_material" | "$node_bin" "$SCRIPT_DIR/decrypt-macos.mjs" "$encrypted_path" "$archive_path" "$expected_sha" || die 'Demo-key verification failed. Nothing was installed.'

if (( update_mode == 0 )); then
  # `security -w` as the final option prompts on stdin, so the secret never
  # appears in the process list. Two lines satisfy new-item confirmation.
  printf '%s\n%s\n' "$key_material" "$key_material" | "$security_command" add-generic-password -a "$keychain_account" -s "$keychain_service" -l 'OYYO runtime activation' -j 'Encrypted package activation; updates only' -w >/dev/null || die 'Could not save OYYO activation in the login Keychain.'
  key_added=1
fi
key_material=''

typeset member_list="$temp_root/archive-members.txt"
typeset member_details="$temp_root/archive-members-verbose.txt"
/usr/bin/tar -tzf "$archive_path" > "$member_list" || die 'The authenticated package is not a readable tar.gz archive.'
/usr/bin/tar -tvzf "$archive_path" > "$member_details" || die 'The authenticated package metadata is unreadable.'
"$node_bin" --input-type=module -e '
  import fs from "node:fs";
  const [nameFile, detailFile] = process.argv.slice(1);
  const names = fs.readFileSync(nameFile, "utf8").split(/\r?\n/).filter(Boolean);
  if (!names.length) throw new Error("empty archive");
  for (const raw of names) {
    if (raw.includes("\\") || raw.startsWith("/") || raw.includes("\0")) throw new Error("unsafe archive path");
    const parts = raw.replace(/^\.\//, "").split("/");
    if (parts.some(part => part === "..")) throw new Error("unsafe archive traversal");
  }
  const details = fs.readFileSync(detailFile, "utf8").split(/\r?\n/).filter(Boolean);
  if (details.length !== names.length) throw new Error("archive listing mismatch");
  if (details.some(line => /^[lh]/.test(line))) throw new Error("archive links are not permitted");
' "$member_list" "$member_details" || die 'The authenticated package contains an unsafe path or link.'

/bin/mkdir -- "$staging_root"
/usr/bin/tar -xzf "$archive_path" -C "$staging_root" || die 'The authenticated package could not be extracted.'
[[ -x "$staging_root/Install-OYYO.command" ]] || die 'The authenticated package is missing its executable Mac registrar.'
/bin/mv -- "$staging_root" "$candidate_root"

validate_candidate_app() {
  typeset app="$candidate_root/OYYO.app"
  [[ -d "$app/Contents" && -f "$app/Contents/Info.plist" ]] || die 'The authenticated package does not contain OYYO.app.'
  typeset executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ -n "$executable" && "$executable" != */* && -x "$app/Contents/MacOS/$executable" ]] || die 'OYYO.app does not contain its declared executable.'
}
validate_candidate_app

typeset -a inner_args
inner_args=(--package-root "$candidate_root" --data-dir "$data_root" --no-launch)
if (( update_mode == 1 )); then inner_args+=(--existing-config "$previous_config"); fi
print -- 'Registering the native OYYO runtime with Codex...'
if [[ "$test_mode" == '1' ]]; then
  inner_args+=(--test-no-registration)
  OYYO_INSTALL_TEST_MODE=1 /bin/zsh "$candidate_root/Install-OYYO.command" "${inner_args[@]}" || die 'OYYO registration failed. The previous stable app and data were preserved.'
else
  /bin/zsh "$candidate_root/Install-OYYO.command" "${inner_args[@]}" || die 'OYYO registration failed. The previous stable app and data were preserved.'
fi
registration_succeeded=1
if (( test_fail_after_registration == 1 )); then
  die 'Guarded test failure after successful registration.'
fi

typeset candidate_app="$candidate_root/OYYO.app"
validate_candidate_app

typeset old_stable_target=''
[[ -L "$stable_app" ]] && old_stable_target="$(/usr/bin/readlink "$stable_app")"
temporary_link="$applications_dir/.OYYO.app.new.$$"
/bin/ln -s -- "$candidate_app" "$temporary_link"

typeset record_tmp="$support_root/.install.json.new.$$"
"$node_bin" --input-type=module -e '
  import fs from "node:fs";
  const [file, version, arch, installedRoot, dataRoot, stableApp, sha256] = process.argv.slice(1);
  const record = { schemaVersion: 1, version, arch, installedRoot, dataRoot, stableApp, sha256, installedAt: new Date().toISOString() };
  fs.writeFileSync(file, `${JSON.stringify(record, null, 2)}\n`, { flag: "wx", mode: 0o600 });
' "$record_tmp" "$version" "$arch" "$candidate_root" "$data_root" "$stable_app" "$expected_sha" || die 'Could not prepare the atomic OYYO install record.'

rollback_stable_link() {
  if [[ -n "$old_stable_target" ]]; then
    typeset rollback_link="$applications_dir/.OYYO.app.rollback.$$"
    /bin/ln -s -- "$old_stable_target" "$rollback_link" && /bin/mv -fh -- "$rollback_link" "$stable_app"
  elif [[ -L "$stable_app" ]]; then
    /bin/rm -f -- "$stable_app"
  fi
}

/bin/mv -fh -- "$temporary_link" "$stable_app" || die 'Could not switch the stable OYYO application link.'
temporary_link=''
if ! /bin/mv -f -- "$record_tmp" "$install_record"; then
  rollback_stable_link
  die 'Could not commit the OYYO install record; the stable app link was rolled back.'
fi
committed=1

if [[ -d "$desktop_dir" ]]; then
  typeset desktop_app="$desktop_dir/OYYO.app"
  if [[ ! -e "$desktop_app" && ! -L "$desktop_app" ]]; then
    temporary_desktop_link="$desktop_dir/.OYYO.app.new.$$"
    if /bin/ln -s -- "$stable_app" "$temporary_desktop_link" && /bin/mv -fh -- "$temporary_desktop_link" "$desktop_app"; then
      temporary_desktop_link=''
    else
      print -u2 -- 'OYYO was installed, but the optional Desktop alias could not be created.'
    fi
  elif [[ -L "$desktop_app" && "$(/usr/bin/readlink "$desktop_app")" == "$stable_app" ]]; then
    :
  else
    print -u2 -- 'OYYO left the existing Desktop item unchanged.'
  fi
fi

print -- "OYYO $version is installed at $stable_app"
print -- "Shared models, chats, memory and settings remain under $data_root"
if (( no_launch == 0 )); then
  /usr/bin/open "$stable_app" || print -u2 -- 'OYYO is installed, but macOS could not open it automatically.'
fi
