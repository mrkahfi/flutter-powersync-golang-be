import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE_DIR = "/Users/mrkahvi/android-projects/flutter_powersync/assets/map"
SPRITE_DIR = os.path.join(BASE_DIR, "sprites")
FONT_DIR = os.path.join(BASE_DIR, "fonts")

os.makedirs(SPRITE_DIR, exist_ok=True)
os.makedirs(FONT_DIR, exist_ok=True)

# 1. Download Sprites
sprite_urls = [
    "https://tiles.openfreemap.org/sprites/ofm_f384/ofm.json",
    "https://tiles.openfreemap.org/sprites/ofm_f384/ofm.png",
    "https://tiles.openfreemap.org/sprites/ofm_f384/ofm@2x.json",
    "https://tiles.openfreemap.org/sprites/ofm_f384/ofm@2x.png",
]

def download_file(url, path):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as response:
            data = response.read()
            with open(path, "wb") as f:
                f.write(data)
    except Exception as e:
        # PBFs that don't exist return 404/403 often, we just ignore missing ones
        pass

tasks = []
for url in sprite_urls:
    filename = url.split("/")[-1]
    tasks.append((url, os.path.join(SPRITE_DIR, filename)))

fonts = ['Noto Sans Regular', 'Noto Sans Bold', 'Noto Sans Italic']
for font in fonts:
    d = os.path.join(FONT_DIR, font)
    os.makedirs(d, exist_ok=True)
    for i in range(0, 65536, 256):
        start = i
        end = i + 255
        r = f"{start}-{end}"
        url = f"https://tiles.openfreemap.org/fonts/{font.replace(' ', '%20')}/{r}.pbf"
        path = os.path.join(d, f"{r}.pbf")
        tasks.append((url, path))

print(f"Starting {len(tasks)} downloads...")
with ThreadPoolExecutor(max_workers=30) as executor:
    for url, path in tasks:
        executor.submit(download_file, url, path)
print("Done downloading assets.")
