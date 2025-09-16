> This Plugin / Repo is being maintained by a community of developers.
There is no warranty given or bug fixing guarantee; especially not by
Programmfabrik GmbH. Please use the github issue tracking to report bugs
and self organize bug fixing. Feel free to directly contact the committing
developers.

# fylr-plugin-ubhd-3d-viewer
3D viewer plugin (Heidelberg University Library)

**At the moment, this plugin is only a prototype!!!**

The plugin works roughly as follows (If one of these conditions is met, the following are no longer checked):

 * If a **Nexus file (.nxs or .nxz)** is found among the file variants of an asset, the **3DHOP viewer** is invoked with this file.
 * If a **ply model (.ply)** is found among the file variants of an asset and the version name (explicitly named so by the user) is "ply", the **3DHOP viewer** is invoked with this file. The check for the version name is done so that very large ply models are not automatically passed to the viewer, which may cause the user's browser to freeze.
 * If a zip file with directory access (.unpack.zip) is found among the file variants and the version name (explicitly named so by the user) is "gltf", the **three.js based viewer** is invoked with this file. **Attention: Within the zip file, the gltf file must be named model.gltf.**
 * If a **glb (binary variant of gltf) model** is found among the file variants of an asset, the **three.js based viewer** is invoked with this file.
 * If a zip file with directory access (.unpack.zip) is found among the file variants and the version name (explicitly named so by the user) is "rti", the **Relight rti viewer** is invoked with this file, which should be in the relight format (with info.json, https://vcg.isti.cnr.it/relight/#format)

## Viewer based on [3D Heritage Online Presenter (3DHOP)](https://3dhop.net/)

Prerequisites:
The plugin expects assets in the **Nexus (.nxs)** format (http://vcg.isti.cnr.it/nexus/). The nexus files could be compressed (.nxz). The Nexus file does not have to be the preferred version of an asset. For example, it is possible to store an additional file version in Nexus format for an asset in ply format.

Alternatively, the plugin is able to display **ply** files. To make sure that the files don't contain too many faces (causes the browser to crash when 3DHOP displays them), the plugin expects the asset version name "preview_version". It is up to the user to import only suitable ply files.

## Viewer based on [three.js](https://threejs.org/)

Prerequisites:
The plugin expects assets in the **binary form of the glTF format (.glb)** (https://wiki.fileformat.com/3d/glb/). This format combines all files of a glTF object into one file.

Alternatively it is possible to put a **glTF file (.gltf)** (https://en.wikipedia.org/wiki/GlTF) together with other files (texture etc.) into a zip file. To indicate that a zip archive contains a 3D object in GLTF format, the corresponding asset version must have the name "gltf".

## Viewer based on [Relight](https://vcg.isti.cnr.it/relight/)

Prerequisites:
zip file in Relight format (see https://vcg.isti.cnr.it/relight/#format)

## TODOs
### Common
 * [x] adaption to fylr
 * [ ] suitable recips plugins for generating glb or Nexus format (and 2D preview)

### three.js based viewer
 * [x] add controls
 * [ ] add hints for mouse controls
 * [x] respect default values for camera settings, lighting etc. in gltf/glb files
 * [ ] respect default values for camera settings, lightning etc. stored in easydb/fylr

### RTI
 * [x] add RTI viewer
