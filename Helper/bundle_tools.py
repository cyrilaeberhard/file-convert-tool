"""Kopiert Homebrew-Tools samt Nicht-System-Bibliotheken in <dest> (relocatable).
Aufruf: bundle_tools.py <dest> <tool>...   (gs bringt zusätzlich share/ghostscript mit)"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

BREW_BIN = Path("/opt/homebrew/bin")
SHARE = Path("/opt/homebrew/share/ghostscript")
SYSTEM = ("/usr/lib", "/System")


def entries(binary: Path) -> list[str]:
    out = subprocess.run(["otool", "-L", str(binary)], capture_output=True, text=True, check=True).stdout
    return [e for e in re.findall(r"^\s+(\S+) \(", out, re.M) if not e.startswith(SYSTEM)]


def resolve(entry: str, owner: Path) -> Path:
    if entry.startswith("@rpath/"):
        for base in (owner.parent, Path("/opt/homebrew/lib")):
            if (base / entry[7:]).exists():
                return (base / entry[7:]).resolve()
        raise FileNotFoundError(entry)
    return Path(entry).resolve()


def main(dest: Path, tools: list[str]) -> None:
    bin_dir, lib_dir = dest / "bin", dest / "lib"
    bin_dir.mkdir(parents=True)
    lib_dir.mkdir()
    binaries = {}
    copied = {}
    todo = []
    for name in tools:
        original = (BREW_BIN / name).resolve()
        target = bin_dir / name
        shutil.copy2(original, target)
        binaries[name] = target
        todo.append((target, original))
    while todo:
        target, original = todo.pop()
        is_bin = target.parent == bin_dir
        prefix = "@executable_path/../lib/" if is_bin else "@loader_path/"
        if not is_bin:
            subprocess.run(["install_name_tool", "-id", f"@loader_path/{target.name}", str(target)], check=True, capture_output=True)
        for entry in entries(original):
            lib = resolve(entry, original)
            if lib.name not in copied:
                copied[lib.name] = lib_dir / lib.name
                shutil.copy2(lib, copied[lib.name])
                copied[lib.name].chmod(0o755)
                todo.append((copied[lib.name], lib))
            subprocess.run(["install_name_tool", "-change", entry, prefix + lib.name, str(target)], check=True, capture_output=True)
    # install_name_tool macht Signaturen ungültig; arm64 beendet unsignierte Binaries sofort
    for f in [*binaries.values(), *copied.values()]:
        subprocess.run(["codesign", "--force", "--sign", "-", str(f)], check=True, capture_output=True)
    if "gs" in tools:
        shutil.copytree(SHARE, dest / "share" / "ghostscript")


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2:])
