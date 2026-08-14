from pathlib import Path

from PIL import Image, ImageDraw

SRC = Path(r"C:\Users\VCLOUD\Downloads\ChatGPT Image 2026年8月13日 18_11_43.png")
ROOT = Path(__file__).resolve().parents[1]
RADIUS_RATIO = 0.22


def rounded(image, radius_ratio=RADIUS_RATIO):
    image = image.convert("RGBA")
    width, height = image.size
    scale = 4
    mask = Image.new("L", (width * scale, height * scale), 0)
    draw = ImageDraw.Draw(mask)
    radius = int(min(width, height) * radius_ratio * scale)
    draw.rounded_rectangle(
        (0, 0, width * scale - 1, height * scale - 1),
        radius=radius,
        fill=255,
    )
    mask = mask.resize((width, height), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out.paste(image, (0, 0))
    out.putalpha(mask)
    return out


def fit(image, size):
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main():
    master = rounded(Image.open(SRC))

    brand_dir = ROOT / "assets" / "brand"
    brand_dir.mkdir(parents=True, exist_ok=True)
    fit(master, 1024).save(brand_dir / "logo.png", "PNG")

    win_dir = ROOT / "windows" / "runner" / "resources"
    win_dir.mkdir(parents=True, exist_ok=True)
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    fit(master, 256).save(win_dir / "app_icon.ico", format="ICO", sizes=ico_sizes)

    mac_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        fit(master, size).save(mac_dir / f"app_icon_{size}.png", "PNG")

    linux_dir = ROOT / "linux" / "runner" / "resources"
    linux_dir.mkdir(parents=True, exist_ok=True)
    fit(master, 512).save(linux_dir / "app_icon.png", "PNG")


if __name__ == "__main__":
    main()
