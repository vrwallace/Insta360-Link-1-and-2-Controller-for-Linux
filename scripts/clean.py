from pathlib import Path
root = Path(__file__).resolve().parents[1]
for name in ("linkctl", "insta360linkgui"):
    (root / name).unlink(missing_ok=True)
for folder in (root, root / "lib"):
    paths = folder.glob("*") if folder == root else folder.rglob("*")
    for path in paths:
        if path.is_file() and path.suffix in {".o", ".ppu", ".or", ".compiled"}:
            path.unlink()
