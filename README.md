# fylr-plugin-ubhd-3d-viewer

Dieses Plugin bindet den UBHD-3D-Viewer in FYLR ein und zeigt 3D-Modelle in der Asset-Detailansicht an.

Der FYLR-spezifische Host-Code liegt in `src/webfrontend/UBHD3DViewerPlugin.coffee`. Die eigentliche Viewer-App kommt aus dem Git-Submodul `lib/ubhd-3d-viewer` und wird beim Build als statisches `viewer-dist/` in das Plugin kopiert.

## Build

Voraussetzungen:

- Node.js und npm
- initialisiertes Submodul `lib/ubhd-3d-viewer`

```bash
git submodule update --init --recursive
make build
```

`make build` kompiliert den FYLR-Host, baut den eingebetteten Viewer und legt das Plugin unter `build/fylr-plugin-ubhd-3d-viewer/` ab.

Für ein installierbares Paket:

```bash
make zip
```

Das ZIP liegt danach unter `build/fylr-plugin-ubhd-3d-viewer.zip`.
