#!/bin/zsh
emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r NODE_BIN="${NODE_BIN:-$(command -v node)}"
typeset root=''
typeset service="com.oyyo.runtime.test.$$.${RANDOM}"
typeset account="test-installer-$$-${RANDOM}"
typeset security_command='/usr/bin/security'
typeset ephemeral_keychain=''
typeset -a security_override_args
security_override_args=()

if [[ "$(/usr/bin/uname -s)" != 'Darwin' ]]; then
  print -- 'SKIP install-macos: macOS is required.'
  exit 0
fi

typeset node_major="$($NODE_BIN --version | /usr/bin/sed -E 's/^v([0-9]+).*/\1/')"
if (( node_major < 22 )); then
  print -- 'SKIP install-macos: Node.js 22 or later is required.'
  exit 0
fi

root="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/oyyo-runner-test.XXXXXX")"
typeset support="$root/support"
typeset applications="$root/Applications"
typeset desktop="$root/Desktop"
/bin/mkdir -p -- "$support" "$applications" "$desktop"

cleanup() {
  typeset code="$?"
  trap - EXIT INT TERM HUP
  set +e
  "$security_command" delete-generic-password -a "$account" -s "$service" >/dev/null 2>&1
  if [[ -n "$ephemeral_keychain" ]]; then
    /usr/bin/security delete-keychain "$ephemeral_keychain" >/dev/null 2>&1
  fi
  [[ -n "$root" && "$root" == "${TMPDIR:-/private/tmp}"/oyyo-runner-test.* ]] && /bin/rm -rf -- "$root"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

typeset key="$($NODE_BIN --input-type=module -e 'import crypto from "node:crypto"; process.stdout.write(crypto.randomBytes(32).toString("hex"));')"

# Prove that a real Keychain can perform the exact stdin-only add/find path
# before running the integration test. The release gate uses an isolated,
# ephemeral Keychain; ordinary local runs may probe a uniquely named login item.
typeset real_keychain_ok=0
if [[ "${OYYO_TEST_USE_EPHEMERAL_KEYCHAIN:-0}" == '1' ]]; then
  ephemeral_keychain="$root/ephemeral-test.keychain"
  typeset ephemeral_password="$(/usr/bin/uuidgen)"
  /usr/bin/security create-keychain -p "$ephemeral_password" "$ephemeral_keychain"
  /usr/bin/security unlock-keychain -p "$ephemeral_password" "$ephemeral_keychain"
  /usr/bin/security set-keychain-settings -lut 3600 "$ephemeral_keychain"
  ephemeral_password=''
  typeset isolated_security="$root/isolated-security"
  # The production command continues to read its real key directly from stdin.
  # This guarded adapter converts only the disposable test key for an explicit
  # test Keychain because `security -w` cannot prompt and name a non-default
  # Keychain in the same invocation.
  /usr/bin/printf '%s\n' '#!/bin/zsh' 'emulate -LR zsh' 'setopt ERR_EXIT NO_UNSET' 'typeset keychain="${OYYO_TEST_KEYCHAIN_PATH:?}"' 'typeset operation="${1:-}"' 'shift || true' 'case "$operation" in' '  add-generic-password)' '    (( $# > 0 )) || exit 64' '    [[ "${@[-1]}" == "-w" ]] || exit 64' '    typeset -a args' '    args=("${@[1,-2]}")' '    typeset first="" second=""' '    IFS= read -r first' '    IFS= read -r second' '    [[ "$first" == "$second" && ${#first} -eq 64 && "$first" != *[^0-9a-fA-F]* ]] || exit 2' '    /usr/bin/security add-generic-password "${args[@]}" -w "$first" "$keychain"' '    typeset result=$?' '    first=""; second=""' '    exit $result' '    ;;' '  find-generic-password|delete-generic-password)' '    exec /usr/bin/security "$operation" "$@" "$keychain"' '    ;;' '  *) exit 64;;' 'esac' > "$isolated_security"
  /bin/chmod 0755 "$isolated_security"
  export OYYO_TEST_KEYCHAIN_PATH="$ephemeral_keychain"
  security_command="$isolated_security"
  security_override_args=(--test-security-command "$isolated_security")
  if printf '%s\n%s\n' "$key" "$key" | "$security_command" add-generic-password -a "$account" -s "$service" -l 'OYYO installer integration test' -w >/dev/null 2>&1; then
    typeset probe="$("$security_command" find-generic-password -a "$account" -s "$service" -w 2>/dev/null || true)"
    [[ "$probe" == "$key" ]] || { print -u2 -- 'The isolated Keychain item could not be read.'; exit 1; }
    real_keychain_ok=1
    print -- 'PASS install-macos: isolated ephemeral Keychain add/find round-trip verified.'
    probe=''
    "$security_command" delete-generic-password -a "$account" -s "$service" >/dev/null 2>&1 || true
  else
    print -u2 -- 'The isolated ephemeral Keychain rejected the stdin-only activation path.'
    exit 1
  fi
elif printf '%s\n%s\n' "$key" "$key" | /usr/bin/security add-generic-password -a "$account" -s "$service" -l 'OYYO installer integration test' -w >/dev/null 2>&1; then
  typeset probe="$(/usr/bin/security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || true)"
  if [[ "$probe" == "$key" ]]; then
    real_keychain_ok=1
    print -- 'PASS install-macos: real login Keychain stdin add/find round-trip verified.'
  else
    print -u2 -- 'The real test Keychain item could not be read; continuing with the guarded adapter.'
  fi
  probe=''
  /usr/bin/security delete-generic-password -a "$account" -s "$service" >/dev/null 2>&1 || true
fi
if (( real_keychain_ok == 0 )); then
  print -- 'SKIP install-macos Keychain round-trip: the login Keychain is locked or unavailable.'
  /usr/bin/security delete-generic-password -a "$account" -s "$service" >/dev/null 2>&1 || true
  typeset fake_security="$root/fake-security"
  typeset fake_keychain="$root/fake-keychain-item"
  /usr/bin/printf '%s\n' '#!/bin/zsh' 'emulate -LR zsh' 'setopt ERR_EXIT NO_UNSET' 'typeset state="${OYYO_TEST_KEYCHAIN_FILE:?}"' 'typeset operation="${1:-}"' 'case "$operation" in' '  add-generic-password)' '    typeset first="" second=""' '    IFS= read -r first' '    IFS= read -r second' '    [[ "$first" == "$second" && "$first" =~ '\''^[[:xdigit:]]{64}$'\'' ]] || exit 2' '    umask 077' '    print -rn -- "$first" > "$state"' '    ;;' '  find-generic-password)' '    [[ -f "$state" ]] || exit 44' '    if [[ " $* " == *" -w "* ]]; then /bin/cat -- "$state"; fi' '    ;;' '  delete-generic-password)' '    /bin/rm -f -- "$state"' '    ;;' '  *) exit 64;;' 'esac' > "$fake_security"
  /bin/chmod 0755 "$fake_security"
  export OYYO_TEST_KEYCHAIN_FILE="$fake_keychain"
  security_command="$fake_security"
  security_override_args=(--test-security-command "$fake_security")
fi

typeset machine="$(/usr/bin/uname -m)"
typeset arch=''
if [[ "$machine" == 'arm64' ]]; then
  arch='arm64'
elif [[ "$machine" == 'x86_64' && "$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || print 0)" == '1' ]]; then
  arch='arm64'
else
  arch='x64'
fi

# Use an isolated non-ready fixture: public feeds may already be ready.
# Never let this unattended rejection test reach the production key dialog.
typeset non_ready_manifest="$root/release-non-ready.json"
"$NODE_BIN" --input-type=module -e '
  import fs from "node:fs";
  const [source, destination] = process.argv.slice(1);
  const value = JSON.parse(fs.readFileSync(source, "utf8"));
  Object.assign(value, { status: "awaiting-production-encryption", sha256: null, sizeBytes: 0 });
  fs.writeFileSync(destination, JSON.stringify(value));
' "$REPO_ROOT/release-macos-$arch.json" "$non_ready_manifest"
if OYYO_INSTALLER_TEST=1 /bin/zsh "$REPO_ROOT/Install-OYYO.command" \
  --test-manifest "$non_ready_manifest" \
  --test-support-root "$support" \
  --test-applications-dir "$applications" \
  --test-desktop-dir "$desktop" \
  --test-keychain-service "$service" \
  --test-keychain-account "$account" \
  "${security_override_args[@]}"; then
  print -u2 -- 'a non-ready public manifest unexpectedly installed'
  exit 1
fi

make_fixture() {
  typeset label="$1"
  typeset should_fail="$2"
  typeset unsafe_link="${3:-0}"
  typeset payload="$root/payload-$label"
  typeset archive="$root/payload-$label.tar.gz"
  typeset encrypted="$root/payload-$label.oyyo"
  typeset manifest="$root/release-$label.json"
  /bin/mkdir -p -- "$payload/OYYO.app/Contents/MacOS" "$payload/plugins/oyyo" "$payload/test"

  /usr/bin/printf '%s\n' '#!/bin/zsh' 'exit 0' > "$payload/OYYO.app/Contents/MacOS/OYYO"
  /bin/chmod 0755 "$payload/OYYO.app/Contents/MacOS/OYYO"
  /usr/bin/printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0"><dict>' '<key>CFBundleExecutable</key><string>OYYO</string>' '<key>CFBundleIdentifier</key><string>com.oyyo.runtime.test</string>' '<key>CFBundleName</key><string>OYYO</string>' '<key>CFBundlePackageType</key><string>APPL</string>' '</dict></plist>' > "$payload/OYYO.app/Contents/Info.plist"
  /usr/bin/printf '%s\n' "$label" > "$payload/test/revision.txt"
  [[ "$should_fail" == '1' ]] && /usr/bin/touch "$payload/test/fail-registration"
  [[ "$unsafe_link" == '1' ]] && /bin/ln -s ../../outside "$payload/test/escape-link"

  /usr/bin/printf '%s\n' '#!/bin/zsh' 'emulate -LR zsh' 'setopt ERR_EXIT NO_UNSET PIPE_FAIL' 'typeset package_root="" data_dir="" existing_config="" no_launch=0 test_no_registration=0' 'while (( $# )); do case "$1" in --package-root) package_root="$2"; shift 2;; --data-dir) data_dir="$2"; shift 2;; --existing-config) existing_config="$2"; shift 2;; --no-launch) no_launch=1; shift;; --test-no-registration) test_no_registration=1; shift;; *) exit 64;; esac; done' '[[ -n "$package_root" && -n "$data_dir" ]] || exit 65' '[[ -z "$existing_config" || -f "$existing_config" ]] || exit 66' '[[ "$test_no_registration" == 1 && "${OYYO_INSTALL_TEST_MODE:-}" == 1 ]] || exit 67' '[[ ! -f "$package_root/test/fail-registration" ]] || exit 23' '/bin/mkdir -p -- "$data_dir" "$package_root/plugins/oyyo"' '/usr/bin/printf "{\"dataDir\":\"%s\",\"packageRoot\":\"%s\"}\n" "$data_dir" "$package_root" > "$package_root/plugins/oyyo/config.local.json"' '/usr/bin/touch "$package_root/test/registered"' > "$payload/Install-OYYO.command"
  /bin/chmod 0755 "$payload/Install-OYYO.command"

  /usr/bin/tar -czf "$archive" -C "$payload" .
  typeset metadata="$(printf '%s\n' "$key" | "$NODE_BIN" "$REPO_ROOT/tests/make-test-package.mjs" "$archive" "$encrypted")"
  "$NODE_BIN" --input-type=module -e '
    import fs from "node:fs";
    const [file, arch, metadata] = process.argv.slice(1);
    const encrypted = JSON.parse(metadata);
    const version = "0.1.10";
    const value = {
      version, platform: `macos-${arch}`, format: "OYYOPKG1", encryption: "AES-256-GCM",
      payloadArchive: "tar.gz", status: "ready",
      url: `https://github.com/vpicciuolo/oyyo-runtime-runner/releases/download/v${version}/oyyo-macos-${arch}-demo-${version}.oyyo`,
      sha256: encrypted.sha256, sizeBytes: encrypted.sizeBytes, notes: "ephemeral integration fixture"
    };
    fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
  ' "$manifest" "$arch" "$metadata"
  print -r -- "$manifest|$encrypted"
}

run_installer() {
  typeset manifest="$1"
  typeset package="$2"
  shift 2
  OYYO_INSTALLER_TEST=1 /bin/zsh "$REPO_ROOT/Install-OYYO.command" \
    --test-manifest "$manifest" \
    --test-package "$package" \
    --test-support-root "$support" \
    --test-applications-dir "$applications" \
    --test-desktop-dir "$desktop" \
    --test-keychain-service "$service" \
    --test-keychain-account "$account" \
    "${security_override_args[@]}" \
    "$@"
}

typeset initial="$(make_fixture initial 0)"
typeset initial_manifest="${initial%%|*}"
typeset initial_package="${initial#*|}"
printf '%s\n' "$key" | run_installer "$initial_manifest" "$initial_package" --test-key-stdin

[[ -L "$applications/OYYO.app" ]] || { print -u2 -- 'missing stable application link'; exit 1; }
[[ -L "$desktop/OYYO.app" ]] || { print -u2 -- 'missing Desktop application link'; exit 1; }
typeset first_app="$(/usr/bin/readlink "$applications/OYYO.app")"
typeset first_root="${first_app%/OYYO.app}"
[[ -f "$first_root/test/registered" && "$(<"$first_root/test/revision.txt")" == 'initial' ]] || { print -u2 -- 'initial registration did not finish'; exit 1; }
typeset stored_key="$("$security_command" find-generic-password -a "$account" -s "$service" -w 2>/dev/null)"
[[ "$stored_key" == "$key" ]] || { print -u2 -- 'Keychain activation mismatch'; exit 1; }
stored_key=''
/usr/bin/printf '%s\n' 'keep-this-data' > "$support/data/preservation-sentinel.txt"

typeset update="$(make_fixture update 0)"
typeset update_manifest="${update%%|*}"
typeset update_package="${update#*|}"
run_installer "$update_manifest" "$update_package" --update --current-install-directory "$first_root"

typeset second_app="$(/usr/bin/readlink "$applications/OYYO.app")"
typeset second_root="${second_app%/OYYO.app}"
[[ "$second_root" != "$first_root" && -d "$first_root" ]] || { print -u2 -- "update did not preserve and switch version roots (first=$first_root second=$second_root)"; exit 1; }
[[ "$(<"$second_root/test/revision.txt")" == 'update' ]] || { print -u2 -- 'updated revision is not active'; exit 1; }
[[ "$(<"$support/data/preservation-sentinel.txt")" == 'keep-this-data' ]] || { print -u2 -- 'shared data was not preserved'; exit 1; }

typeset unsafe="$(make_fixture unsafe-link 0 1)"
typeset unsafe_manifest="${unsafe%%|*}"
typeset unsafe_package="${unsafe#*|}"
if run_installer "$unsafe_manifest" "$unsafe_package" --update --current-install-directory "$second_root"; then
  print -u2 -- 'an authenticated archive link unexpectedly passed validation'
  exit 1
fi
[[ "$(/usr/bin/readlink "$applications/OYYO.app")" == "$second_app" ]] || { print -u2 -- 'unsafe archive changed the stable app'; exit 1; }
[[ "$(<"$support/data/preservation-sentinel.txt")" == 'keep-this-data' ]] || { print -u2 -- 'unsafe archive changed shared data'; exit 1; }

typeset failed="$(make_fixture failed 1)"
typeset failed_manifest="${failed%%|*}"
typeset failed_package="${failed#*|}"
if run_installer "$failed_manifest" "$failed_package" --update --current-install-directory "$second_root"; then
  print -u2 -- 'a failing inner registrar unexpectedly succeeded'
  exit 1
fi
[[ "$(/usr/bin/readlink "$applications/OYYO.app")" == "$second_app" ]] || { print -u2 -- 'failed update changed the stable app'; exit 1; }
typeset recorded_root="$($NODE_BIN --input-type=module -e 'import fs from "node:fs"; process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).installedRoot)' "$support/install.json")"
[[ "$recorded_root" == "$second_root" ]] || { print -u2 -- 'failed update changed install metadata'; exit 1; }
[[ "$(<"$support/data/preservation-sentinel.txt")" == 'keep-this-data' ]] || { print -u2 -- 'failed update changed shared data'; exit 1; }

# If a filesystem operation fails after the inner registrar succeeds, the new
# version root and activation must remain because Codex already points at that
# exact root. The stable app and committed install record still remain on the
# previous version for safe recovery.
typeset post_registration="$(make_fixture post-registration 0)"
typeset post_registration_manifest="${post_registration%%|*}"
typeset post_registration_package="${post_registration#*|}"
if run_installer "$post_registration_manifest" "$post_registration_package" --update --current-install-directory "$second_root" --test-fail-after-registration; then
  print -u2 -- 'the guarded post-registration failure unexpectedly succeeded'
  exit 1
fi
[[ "$(/usr/bin/readlink "$applications/OYYO.app")" == "$second_app" ]] || { print -u2 -- 'post-registration failure changed the stable app'; exit 1; }
recorded_root="$($NODE_BIN --input-type=module -e 'import fs from "node:fs"; process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).installedRoot)' "$support/install.json")"
[[ "$recorded_root" == "$second_root" ]] || { print -u2 -- 'post-registration failure changed install metadata'; exit 1; }
typeset -a retained_registered_roots
retained_registered_roots=("$support"/versions/*/test/registered(N))
(( ${#retained_registered_roots[@]} == 3 )) || { print -u2 -- "post-registration candidate was not retained (${#retained_registered_roots[@]} roots found)"; exit 1; }
stored_key="$("$security_command" find-generic-password -a "$account" -s "$service" -w 2>/dev/null)"
[[ "$stored_key" == "$key" ]] || { print -u2 -- 'post-registration failure removed the saved activation'; exit 1; }
stored_key=''

if [[ -n "${OYYO_FULL_MACOS_ARCHIVE:-}" ]]; then
  typeset full_archive="${OYYO_FULL_MACOS_ARCHIVE:A}"
  [[ -f "$full_archive" ]] || { print -u2 -- 'OYYO_FULL_MACOS_ARCHIVE is not a file'; exit 1; }

  "$security_command" delete-generic-password -a "$account" -s "$service" >/dev/null 2>&1 || true
  service="com.oyyo.runtime.test.full.$$.${RANDOM}"
  account="test-full-installer-$$-${RANDOM}"
  support="$root/full-support"
  applications="$root/FullApplications"
  desktop="$root/FullDesktop"
  /bin/mkdir -p -- "$support" "$applications" "$desktop"

  typeset full_encrypted="$root/full-package.oyyo"
  typeset full_manifest="$root/full-release.json"
  typeset full_metadata="$(printf '%s\n' "$key" | "$NODE_BIN" "$REPO_ROOT/tests/make-test-package.mjs" "$full_archive" "$full_encrypted")"
  "$NODE_BIN" --input-type=module -e '
    import fs from "node:fs";
    const [file, arch, metadata] = process.argv.slice(1);
    const encrypted = JSON.parse(metadata);
    const version = "0.1.10";
    fs.writeFileSync(file, `${JSON.stringify({
      version, platform: `macos-${arch}`, format: "OYYOPKG1", encryption: "AES-256-GCM",
      payloadArchive: "tar.gz", status: "ready",
      url: `https://github.com/vpicciuolo/oyyo-runtime-runner/releases/download/v${version}/oyyo-macos-${arch}-demo-${version}.oyyo`,
      sha256: encrypted.sha256, sizeBytes: encrypted.sizeBytes, notes: "ephemeral full-package acceptance"
    }, null, 2)}\n`);
  ' "$full_manifest" "$arch" "$full_metadata"

  printf '%s\n' "$key" | run_installer "$full_manifest" "$full_encrypted" --test-key-stdin
  typeset full_app="$(/usr/bin/readlink "$applications/OYYO.app")"
  typeset full_root="${full_app%/OYYO.app}"
  typeset full_config="$full_root/plugins/oyyo/config.local.json"
  [[ -f "$full_config" && -f "$full_root/build-manifest.json" ]] || { print -u2 -- 'full package did not configure'; exit 1; }
  "$NODE_BIN" --input-type=module -e '
    import fs from "node:fs";
    const [configFile, manifestFile] = process.argv.slice(1);
    const config = JSON.parse(fs.readFileSync(configFile, "utf8"));
    const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
    if (config.packageVersion !== "0.1.10" || manifest.version !== "0.1.10" || manifest.platform !== "macos-arm64") process.exit(1);
    if (config.speech?.modelSha256 !== "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21") process.exit(1);
  ' "$full_config" "$full_root/build-manifest.json"
  "$full_root/plugins/oyyo/bin/oyyo" --version | /usr/bin/grep -q '0.1.10'
  "$full_root/plugins/oyyo/runtime/python/bin/python3" -c 'import docx, openpyxl, pdfplumber, pypdf, pptx, reportlab'
  /usr/bin/codesign --verify --deep --strict "$full_root/OYYO.app"

  /usr/bin/printf '%s\n' 'keep-full-package-data' > "$support/data/full-preservation-sentinel.txt"
  "$NODE_BIN" --input-type=module -e '
    import fs from "node:fs";
    const file = process.argv[1];
    const value = JSON.parse(fs.readFileSync(file, "utf8"));
    value.threads = 3;
    fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
  ' "$full_config"

  run_installer "$full_manifest" "$full_encrypted" --update --current-install-directory "$full_root"
  typeset full_updated_app="$(/usr/bin/readlink "$applications/OYYO.app")"
  typeset full_updated_root="${full_updated_app%/OYYO.app}"
  [[ "$full_updated_root" != "$full_root" && -d "$full_root" ]] || { print -u2 -- 'full keyless update did not switch and preserve roots'; exit 1; }
  [[ "$(<"$support/data/full-preservation-sentinel.txt")" == 'keep-full-package-data' ]] || { print -u2 -- 'full keyless update lost shared data'; exit 1; }
  "$NODE_BIN" --input-type=module -e '
    import fs from "node:fs";
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (value.threads !== 3 || value.packageVersion !== "0.1.10") process.exit(1);
  ' "$full_updated_root/plugins/oyyo/config.local.json"
  print -- 'PASS install-macos: complete native package first install and keyless update verified.'
fi

key=''
print -- 'PASS install-macos: first install, Keychain activation, keyless update, data preservation, unsafe-link rejection, rollback and post-registration recovery verified.'
