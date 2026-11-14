# Parallels Desktop 26.2.2 update dialog hook

A small Qt 5 interposer for Parallels Desktop **26.2.2 (57373)**. It returns `QDialog::Rejected` when `QDialog::exec()` is called on a `CUpdateDialog`. Other dialogs pass through to Qt. The hook is loaded from the application bundle by an `LC_LOAD_DYLIB` command, so launching the app from Finder or the Dock does not require a wrapper script.

This is an independent, version-specific experiment. It does not disable network requests or change the application's update settings. Any update dialog using `CUpdateDialog`, including one opened manually, may be suppressed. Other update UI paths are outside its scope. A future Parallels release may change the Qt ABI, dialog name, or binary layout.

**No installer, Parallels executable, hook binary, license information, or settings backup is distributed in this repository.** Use an application or installer that you are entitled to use. The scripts only accept a 26.2.2 (57373) `prl_client_app` whose SHA-256 is `b3e7badd0e692149c5c0995385e0443747ef0bd1cf60e86864ef73c513127e7b`.

## Requirements

- macOS, Xcode Command Line Tools (`clang++`, `codesign`, `otool`, `lipo`), Python 3, and `zsh`.
- The matching Parallels Desktop application with its Qt 5 frameworks. Both arm64 and x86_64 slices are built.
- Free disk space for a local copy of the executable and, when building a DMG, a copy of the installer contents.

## Patch an installed application

Quit Parallels Desktop completely, then run from the checkout:

```sh
./scripts/patch-installed.command
```

On a fresh checkout this builds the hook from the installed application's Qt frameworks, stores local build artifacts in the ignored `prebuilt/` directory, and patches `/Applications/Parallels Desktop.app`. If the application is not writable, `sudo` requests an administrator password. You can pass another `.app` path as the first argument. The script refuses an unexpected version or executable hash. The app is signed locally with an ad hoc signature; that changes its original code signing identity and may affect macOS permissions or application behavior.

For a separate build step:

```sh
./scripts/build-prebuilt.command '/path/to/Parallels Desktop.app'
```

Build from an **unmodified** matching application. Do not delete `prebuilt/` until you have restored the app: it also contains the original executable and signature resource file needed by the restore script. Keep this directory private.

## Restore

Quit the app and run:

```sh
./scripts/restore-installed.command
```

The restore script checks the application version, its hook load command, and the hook library before restoring the saved original executable and signature resource file from `prebuilt/`. It refuses to overwrite a different version or a changed hook. A reinstall from your own installer is another way to undo the patch.

## Build a local patched DMG

```sh
./scripts/make-patched-dmg.command '/path/to/your/installer.dmg' '/path/to/output.dmg'
```

The installer DMG must contain `Parallels Desktop.app` and `Install.app` at its root. The command copies the image contents, builds the hook from the bundled application, patches that copy, verifies its signature, then creates and checks a new DMG. It refuses to overwrite an output file. The result stays on your machine; do not publish third-party installer contents. The image and patched bundle were verified in a local build, but a complete uninstall and reinstall through `Install.app` has **not** been tested. The installer might replace the patched bundle during installation; use the installed-app script if it does.

## Layout

- `src/block.cpp`: Qt dialog interposer.
- `src/add_load_dylib.py`: adds the load command to both slices of the known universal Mach-O executable.
- `scripts/build-prebuilt.command`: local build and input checks.
- `scripts/patch-installed.command`, `scripts/install-root.sh`: patch entry point and privileged file replacement.
- `scripts/restore-installed.command`, `scripts/restore-root.sh`: restore entry point and checks.
- `scripts/make-patched-dmg.command`: optional local installer image builder.
- `scripts/backup-settings.py`: optional local snapshot of preference and VM configuration metadata. It does **not** copy virtual disks or snapshots. Its ignored `backups/` directory may contain sensitive data.

All generated files and local backups are ignored by Git. The scripts never remove virtual machines. Use at your own risk on a copy or backed-up installation.
