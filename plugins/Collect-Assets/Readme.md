# Collect Assets v3.0

- Based on script by @Morozov Anton.
- This script collects textures and other files used in the scene in one folder.
- **Adapted for 3ds Max 2027** by Sisyphus.

## Supported Renderers (Updated for 2027):

### V-Ray 7.x
- VRayHDRI, VRayProxy, VRayBmpFilter, VRayVolumeGrid
- VRayBitmap, VRayColor, VRayMultiSubTex, VRayNormalMap
- VRayCompTex, VRayDirt, VRayEdgesTex, VRayNoiseTex, VRaySky

### Corona 12.x
- CoronaProxy, CProxy, coronaBitmap, CoronaCam
- CoronaNormal, CoronaColor, CoronaMultiMap, CoronaLayered
- CoronaMix, CoronaAO, CoronaRoundEdges, CoronaWire

### Redshift 2026.x
- Redshift_Bitmap, Redshift_Camera_Map, Redshift_Environment, Redshift_Normal_Map
- RS_Bitmap, RS_Camera_Map, RS_Environment, RS_Normal_Map, RS_Sprite
- RS_Material, RS_Standard_Material, RS_Color_Correction, RS_Ramp, RS_Noise
- RS_Mix, RS_Bump_Map, RS_Displacement, RS_Ambient_Occlusion, RS_Curvature, RS_Switch

### Arnold 5.9.0 (Arnold 7.5.0.0)
- ai_image, ai_normal_map, ai_bump2d, ai_color_correct, ai_range
- ai_noise, ai_cell_noise, ai_checker, ai_flakes, ai_shadow_matte
- ai_ambient_occlusion, ai_curvature, ai_round_corners, ai_switch

### Octane 2024.x
- OctaneProxy, IES_Texture, Alpha_image, Greyscale_image, RGB_image
- OctaneTexture, OctaneMaterial, OctaneMix, OctaneColorCorrect
- OctaneNoise, OctaneBump, OctaneDisplacement

### FStorm
- FStormBitmap, FStormProxy, FStormNormal, FStormColor

### FinalRender
- fR_Proxy, fR_Scatter, fR_Material, fR_Bitmap

### Maxwell
- MaxwellBitmap, MaxwellMaterial

### Volumetric & Simulation
- VDB_Object, VDB_Volume, PhoenixFD_Simulator, tyFlow

### Standard 3ds Max
- bitmaptex, camera_map_per_pixel, AlembicObject, point_Cache
- BitmapHDR, Plant, Forest_Pro, Displace, BipSlave_Control
- proxyGeometry, VolumeGeometry

## New Features in v3.0:

1. **Updated for 3ds Max 2027** - Full compatibility with .NET 10 and new API
2. **Extended Renderer Support** - Added 50+ new material/texture classes
3. **New Image Formats** - Added .webp and .avif support
4. **Improved Error Handling** - Better error messages and recovery
5. **Updated Light Detection** - Enhanced IES light profile detection
6. **Backward Compatibility** - Works with scenes from older Max versions

## Installation:

### Inside 3ds Max 2027

- Scripting -> Run script
- Select `installCA.ms` file
- Find it in Customize -> Customize user interface -> Toolbars
- Inside Category: `ModX`.

### Manual Installation

1. Copy `Collect_asset` folder to `%USERSCRIPTS%\Collect_asset\`
2. Copy icons from `Icons` and `IconsDark` to `%UI_ln%\Icons\` and `%UI_ln%\IconsDark\`
3. Run `collect_asset_3.0.ms` from Scripting -> Run script

## Building from source

If you don't want to download built plugin from mirrors above, then you can build the plugin yourself.

- Make sure 7-Zip is installed in your Windows PC. Download [7-Zip](https://www.7-zip.org/) from here
- Clone the repository with [GitHub Desktop](https://desktop.github.com) or using git clone on WSL 2
```bat
:: ONLY RUN THIS IF YOU USE GIT AND HAVE IT INSTALLED
git clone --depth=1 https://github.com/jrekss/Collect-Assets
```
- Run `build.bat`
- Don't use git in command-line or powershell to clone repo. Some users reported that it's corrupting contents.
- After a second, you will see a **.mzp** file with plugin name in the same folder.

## Changelog:

### v3.0 (2027-06-01)
- Adapted for 3ds Max 2027
- Added support for .NET 10
- Added 50+ new renderer classes (V-Ray 7, Corona 12, Redshift 2026, Arnold 5.9, Octane 2024)
- Added new image formats (.webp, .avif)
- Improved error handling and logging
- Updated light profile detection
- Fixed compatibility issues with new Max API

### v1.2 (Original)
- Original script by Morozov Anton
- Support for V-Ray, Corona, Octane, Redshift, FStorm, FinalRender

