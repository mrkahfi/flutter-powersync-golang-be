# Offline Map Implementation Guide

This document explains how the offline map is implemented in this Flutter application, and provides step-by-step instructions on how to manage (add, update, or delete) the map territory.

---

## 🏗️ Architecture Overview

Our offline map solution relies on MapLibre GL and is composed of three main local pillars:

### 1. Vector Map Data (`tiles.mbtiles`)
- **What it is:** A SQLite-based `MBTiles` file that stores the raw geographical vector data (polygons for land/water, lines for roads, and points for places).
- **Where it lives:** `assets/map/tiles.mbtiles`.
- **How it works:** When the map screen is initialized, the app checks if this asset has been copied to the device's application documents directory. If not (or if the asset size changed), it copies it over. MapLibre then dynamically loads it using the `mbtiles://` protocol.

### 2. Styling Assets (Fonts & Sprites)
MapLibre requires fonts (glyphs) to render text like street names, and sprites to render icons like park trees or hospital crosses.
- **Where they live:** `assets/map/fonts/` and `assets/map/sprites/`.
- **How it works:** Due to a known limitation in the MapLibre engine regarding `asset://` resolution (specifically dealing with URL-encoded spaces in font names), we use a custom `LocalAssetServer`.
- **`LocalAssetServer`:** Runs on `http://127.0.0.1:8080` internally within the app and intercepts HTTP requests for fonts and sprites, seamlessly serving the local assets without ever hitting the internet.

### 3. Style Theme (`style.json`)
- **What it is:** The JSON configuration dictates the visual look of the map (colors, layer visibility, what fonts to use).
- **Where it lives:** `assets/map/style.json`.
- **How it works:** Loaded at runtime. The app dynamically replaces `{path_to_mbtiles}` with the absolute path of the copied `MBTiles` file, and points all font/sprite requests to `http://127.0.0.1:8080`.

---

## 🗺️ Managing Map Territories

The "Territory" or geographical area that is available offline is entirely dictated by the contents of the `tiles.mbtiles` file.

To "Update", "Add", or "Delete" territories, you are essentially modifying or replacing the `tiles.mbtiles` file with a new dataset.

### 🔄 Updating / Changing the Territory

To change your current map bounds to a new city, country, or bounding box, you need a new `.mbtiles` file.

**Step 1: Obtain a new `mbtiles` file.**
*   **Generate from OpenStreetMap:** You can use tools like [Tilemaker](https://tilemaker.org/) or [Planetiler](https://github.com/onthegomap/planetiler) to parse `.osm.pbf` files into vector `.mbtiles`.
*   **Download Pre-generated regions:** Providers like OpenMapTiles, MapTiler, or Protomaps offer region-specific vector tile downloads. *(Ensure they are in the `mbtiles` format and have a schema compatible with OpenMapTiles, which your `style.json` currently uses).*

**Step 2: Replace the file.**
1. Rename your new file to `tiles.mbtiles`.
2. Delete the old `/assets/map/tiles.mbtiles`.
3. Place the new file in `/assets/map/`.
4. the Flutter app automatically detects changes via file size comparison (`assetSize != localSize`) and will overwrite the local device cache upon next launch.

### ➕ Adding Multiple Territories

If you want the map to work offline for *multiple distinct regions* (e.g., Jakarta AND Tokyo) without downloading the entire planet (which is ~100GB+), you must **merge** them into a single `mbtiles` file.

**Tools for Merging:**
*   **[tippecanoe](https://github.com/felt/tippecanoe):** Contains a utility tool called `tile-join` specifically designed for this purpose.
    ```bash
    tile-join -o combined_tiles.mbtiles region1.mbtiles region2.mbtiles
    ```

Once combined, rename `combined_tiles.mbtiles` to `tiles.mbtiles` and place it in the `assets/map/` directory as described above.

### 🗑️ Deleting Territories

If you want to drastically reduce the app bundle size by removing the offline map entirely (or reverting to a smaller region):

1. **Delete File:** Delete the `assets/map/tiles.mbtiles` file completely.
2. **Update Code:** If you delete the file completely, update `pubspec.yaml` to remove it from the `assets` list to prevent a build error. Additionally, update the initialization logic in `map_screen.dart` to prevent it from attempting to load the missing asset. 

**Note on App Size:** Offline vector tiles are very efficient. An entire mid-sized city usually takes fewer than 10-30 MBs depending on zoom density limit. Be cautious about generating tiles beyond zoom level 14 or 15, as exponential growth in tile count creates massive MBTiles files.

---

## 🕵️ Troubleshooting

*   **Map displays grid lines but no data:** The `mbtiles` file does not contain data for the current coordinates/current zoom level. Ensure your initial camera position is within the actual territory boundary.
*   **"Map cannot load" banner:** This means the local `mbtiles` file successfully copied, but it has 0 bytes. Ensure the asset is valid.
*   **Text/Icons missing:** The `LocalAssetServer` failed to start or `style.json` is missing the `127.0.0.1:8080` prefix. Ensure your port is not colliding.
