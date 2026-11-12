"""Generate phone launcher icons from the supplied source logo.

Run from mobile/projekt_paragon: python tool/generate_launcher_icons.py
Requires Pillow (already used by the backend OCR environment).
"""

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "launcher" / "logo.png"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICONS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
BACKGROUND = (28, 18, 12, 255)


def main():
    logo = Image.open(SOURCE).convert("RGBA")
    if logo.width != logo.height:
        raise ValueError("Launcher logo must be square")

    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2,
                 "xxhdpi": 3, "xxxhdpi": 4}
    for density, scale in densities.items():
        folder = ANDROID_RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)

        # Legacy icon: same artwork, scaled to the density-specific icon size.
        size = round(48 * scale)
        logo.resize((size, size), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png")

        # Adaptive layer: the 58 dp artwork fits inside the 66 dp circular safe
        # zone. Launchers can apply round/squircle masks without cutting it off.
        layer_size = round(108 * scale)
        art_size = round(58 * scale)
        layer = Image.new("RGBA", (layer_size, layer_size), (0, 0, 0, 0))
        art = logo.resize((art_size, art_size), Image.Resampling.LANCZOS)
        layer.alpha_composite(art, ((layer_size - art_size) // 2,
                                    (layer_size - art_size) // 2))
        layer.save(folder / "ic_launcher_foreground.png")

    contents = json.loads((IOS_ICONS / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        width = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].removesuffix("x"))
        size = round(width * scale)
        icon = Image.new("RGBA", (size, size), BACKGROUND)
        # iOS icons must be opaque. Preserve the logo's proportions and use
        # the same warm dark background as Android's adaptive icon.
        art_size = round(size * 0.8)
        art = logo.resize((art_size, art_size), Image.Resampling.LANCZOS)
        icon.alpha_composite(art, ((size - art_size) // 2,
                                   (size - art_size) // 2))
        icon.convert("RGB").save(IOS_ICONS / entry["filename"])


if __name__ == "__main__":
    main()
