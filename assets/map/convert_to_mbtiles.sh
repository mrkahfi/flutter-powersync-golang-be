#!/usr/bin/env bash
# Converts BBBike Shapefile layers to a single MBTiles file for offline use in Flutter.
# Run from the project root: bash assets/map/convert_to_mbtiles.sh

set -e

SHP_DIR="assets/map/solo-shp/shape"
TMP_DIR="assets/map/tmp_geojson"
OUT_MBTILES="assets/map/tiles.mbtiles"

echo "🗂  Creating temp GeoJSON directory..."
mkdir -p "$TMP_DIR"

# Convert each shapefile to GeoJSON
for LAYER in roads buildings waterways landuse natural railways places points; do
  SHP="$SHP_DIR/$LAYER.shp"
  if [ -f "$SHP" ]; then
    echo "🔄  Converting $LAYER → GeoJSON..."
    ogr2ogr \
      -f GeoJSON \
      -t_srs EPSG:4326 \
      "$TMP_DIR/$LAYER.geojson" \
      "$SHP"
  else
    echo "⚠️  Skipping $LAYER (not found)"
  fi
done

echo "🧱  Building MBTiles with Tippecanoe..."
tippecanoe \
  --output="$OUT_MBTILES" \
  --force \
  --maximum-zoom=16 \
  --minimum-zoom=10 \
  --no-tile-compression \
  --drop-densest-as-needed \
  -L roads:"$TMP_DIR/roads.geojson" \
  -L buildings:"$TMP_DIR/buildings.geojson" \
  -L waterways:"$TMP_DIR/waterways.geojson" \
  -L landuse:"$TMP_DIR/landuse.geojson" \
  -L natural:"$TMP_DIR/natural.geojson" \
  -L railways:"$TMP_DIR/railways.geojson" \
  -L places:"$TMP_DIR/places.geojson" \
  -L points:"$TMP_DIR/points.geojson"

echo "🧹  Cleaning up temp files..."
rm -rf "$TMP_DIR"

echo "✅  Done! Output: $OUT_MBTILES"
sqlite3 "$OUT_MBTILES" "SELECT name, value FROM metadata;" 2>/dev/null || true
