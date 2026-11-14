#!/usr/bin/env python3
"""Snapshot this Mac's Parallels preferences and VM configuration metadata."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
from datetime import datetime
from pathlib import Path


def copy_item(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    if os.geteuid() == 0:
        raise SystemExit("Run this script as the logged-in user, not with sudo.")

    home = Path.home()
    project = Path(__file__).resolve().parent.parent
    backups = project / "backups"
    backups.mkdir(exist_ok=True)
    backups.chmod(0o700)
    stamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    snapshot = backups / f"settings-{stamp}"
    snapshot.mkdir(mode=0o700)

    items: list[tuple[Path, Path]] = []
    user_prefs = home / "Library/Preferences"
    for source in sorted(user_prefs.glob("com.parallels*.plist")):
        items.append((source, Path("user/Library/Preferences") / source.name))
    items.append((user_prefs / "Parallels", Path("user/Library/Preferences/Parallels")))

    support = home / "Library/Application Support/com.parallels.desktop.console"
    items.append((support, Path("user/Library/Application Support/com.parallels.desktop.console")))

    items.append((Path("/Library/Preferences/Parallels"), Path("system/Library/Preferences/Parallels")))

    vm_names = ("VmInfo.pvi", "config.pvs", "config.pvs.backup", "NVRAM.dat", "NVRAM.tnvs", "NVRAM.tnvs.old")
    for vm in sorted((home / "Parallels").glob("*.pvm")):
        for name in vm_names:
            source = vm / name
            if source.is_file():
                items.append((source, Path("vm-configs") / vm.name / name))

    included = []
    missing = []
    for source, relative in items:
        if not source.exists():
            missing.append(str(source))
            continue
        copy_item(source, snapshot / relative)
        included.append({"source": str(source), "snapshot": str(relative)})

    files = []
    for path in sorted(snapshot.rglob("*")):
        if path.is_symlink():
            files.append({"path": str(path.relative_to(snapshot)), "symlink": os.readlink(path)})
        elif path.is_file():
            files.append({"path": str(path.relative_to(snapshot)), "size": path.stat().st_size, "sha256": sha256(path)})

    manifest = {
        "created_at": datetime.now().astimezone().isoformat(),
        "included": included,
        "missing": missing,
        "files": files,
        "excluded": ["virtual hard disks and snapshots", "logs", "Keychain items", "macOS-protected container metadata"],
    }
    (snapshot / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    for path in sorted(snapshot.rglob("*"), reverse=True):
        if path.is_symlink():
            continue
        path.chmod(0o700 if path.is_dir() else 0o600)
    snapshot.chmod(0o700)

    print(f"Backup: {snapshot}")
    print(f"Copied: {len(included)} sources, {len(files)} files")
    if missing:
        print(f"Missing optional paths: {len(missing)}")


if __name__ == "__main__":
    main()
