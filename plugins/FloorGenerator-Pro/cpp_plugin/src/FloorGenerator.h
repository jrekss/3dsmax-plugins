#pragma once

#include "Max.h"
#include "resource.h"
#include "istdplug.h"
#include "iparamb2.h"
#include "iparamm2.h"
#include "meshadj.h"
#include "MeshDelta.h"
#include "modstack.h"
#include "objmode.h"
#include "utilapi.h"

#include <vector>
#include <cmath>
#include <algorithm>
#include <cstdint>

extern HINSTANCE hInstance;
TCHAR* GetString(int id);

#define FLOORGEN_CLASS_ID Class_ID(0x46477632, 0x20270021)

enum RolloutMapIDs
{
    MAP_PATTERN = 0,
    MAP_BOARDSIZE,
    MAP_BORDER,
    MAP_VARIATION,
    MAP_GENERAL,
    MAP_UV,
    MAP_WARNINGS,
    MAP_UPDATE,
    MAP_PRESETS,
    MAP_CREDITS
};

enum ParamIDs
{
    // Pattern
    pb_floor_pattern = 0,
    pb_hb_parallels,
    pb_chevron_angle,
    pb_bw_subboards,
    pb_oct_insertsize,

    // Board Size
    pb_length,
    pb_length_l,
    pb_length_r,
    pb_length_s,
    pb_width,
    pb_width_l,
    pb_width_r,
    pb_width_s,
    pb_grout_len,
    pb_grout_wid,
    pb_grout_l,
    pb_min_row_off,
    pb_max_row_off,
    pb_row_off_l,
    pb_do_extrude,
    pb_extrude,
    pb_do_bevel,
    pb_bevel,
    pb_bevel_l,
    pb_outline,
    pb_do_grout,
    pb_grout_depth,
    pb_grout_matid,

    // Variation
    pb_max_rot,
    pb_min_rot,
    pb_rot_spread,
    pb_off_x,
    pb_off_x_r,
    pb_off_x_s,
    pb_off_y,
    pb_off_y_r,
    pb_off_y_s,
    pb_off_l,
    pb_tilt,
    pb_tilt_r,
    pb_tilt_s,
    pb_max_overlap,

    // General
    pb_scale,
    pb_direction,
    pb_seed,
    pb_obj_off_x,
    pb_obj_off_y,
    pb_do_weld,
    pb_weld,

    // UV
    pb_uv_channel,
    pb_flip_u,
    pb_flip_v,
    pb_rand_off_u,
    pb_rand_off_v,

    // Warnings & Update
    pb_warn_max,
    pb_live_update,

    // Border
    pb_do_border,
    pb_border_width,
    pb_border_offset,
    pb_border_cut_mode,
    pb_border_matid,
    pb_border_off_bot,
    pb_border_off_top,
    pb_border_off_left,
    pb_border_off_right,
    pb_border_pattern,
    pb_border_tilesize
};

class FloorGeneratorMod : public Modifier
{
public:
    IParamBlock2* pblock = nullptr;
    Mesh cachedMesh;
    bool hasCachedMesh = false;
    bool forceRefresh = false;

    // Sub-Object border line editing state (0:Bottom, 1:Top, 2:Left, 3:Right)
    bool borderLineSel[4] = { false, false, false, false };
    bool hasCachedPlane = false;
    Matrix3 lastFromPlaneTM;
    Matrix3 lastToPlaneTM;
    double lastRoomMinX = 0.0;
    double lastRoomMinY = 0.0;
    double lastRoomMaxX = 0.0;
    double lastRoomMaxY = 0.0;
    float lastZTop = 0.0f;

    static IObjParam* ip;
    static MoveModBoxCMode* moveMode;

    FloorGeneratorMod();
    ~FloorGeneratorMod() override = default;

    // Animatable
    void DeleteThis() override { delete this; }
    void GetClassName(MSTR& s, bool localized) const override { s = _T("FloorGenerator v2.1"); }
    Class_ID ClassID() override { return FLOORGEN_CLASS_ID; }
    SClass_ID SuperClassID() override { return OSM_CLASS_ID; }

    int NumSubs() override { return 1; }
    Animatable* SubAnim(int i) override { return (i == 0) ? pblock : nullptr; }
    MSTR SubAnimName(int i, bool localized) override { return (i == 0) ? MSTR(_T("Parameters")) : MSTR(); }

    int NumRefs() override { return 1; }
    RefTargetHandle GetReference(int i) override { return (i == 0) ? pblock : nullptr; }
    void SetReference(int i, RefTargetHandle rtarg) override { if (i == 0) pblock = static_cast<IParamBlock2*>(rtarg); }

    int NumParamBlocks() override { return 1; }
    IParamBlock2* GetParamBlock(int i) override { return (i == 0) ? pblock : nullptr; }
    IParamBlock2* GetParamBlockByID(BlockID id) override { return (pblock && pblock->ID() == id) ? pblock : nullptr; }

    RefResult NotifyRefChanged(const Interval& changeInt, RefTargetHandle hTarget, PartID& partID, RefMessage message, BOOL propagate) override;
    RefTargetHandle Clone(RemapDir& remap) override;

    // BaseObject & Sub-Object Support
    CreateMouseCallBack* GetCreateMouseCallBack() override { return nullptr; }
    void BeginEditParams(IObjParam* ip, ULONG flags, Animatable* prev) override;
    void EndEditParams(IObjParam* ip, ULONG flags, Animatable* next) override;
    const TCHAR* GetObjectName(bool localized) const override { return _T("FloorGenerator v2.1"); }

    int HitTest(TimeValue t, INode* inode, int type, int crossing, int flags, IPoint2* p, ViewExp* vpt, ModContext* mc) override;
    int Display(TimeValue t, INode* inode, ViewExp* vpt, int flags, ModContext* mc) override;
    void GetWorldBoundBox(TimeValue t, INode* inode, ViewExp* vpt, Box3& box, ModContext* mc) override;
    void Move(TimeValue t, Matrix3& partm, Matrix3& tmAxis, Point3& val, BOOL localOrigin = FALSE) override;
    void GetSubObjectCenters(SubObjAxisCallback* cb, TimeValue t, INode* node, ModContext* mc) override;
    void GetSubObjectTMs(SubObjAxisCallback* cb, TimeValue t, INode* node, ModContext* mc) override;
    void ActivateSubobjSel(int level, XFormModes& modes) override;
    void SelectSubComponent(HitRecord* hitRec, BOOL selected, BOOL all, BOOL invert = FALSE) override;
    void ClearSelection(int selLevel) override;
    void SelectAll(int selLevel) override;
    void InvertSelection(int selLevel) override;
    int NumSubObjTypes() override;
    ISubObjType* GetSubObjType(int i) override;

    // Modifier
    ChannelMask ChannelsUsed() override { return GEOM_CHANNEL | TOPO_CHANNEL | SELECT_CHANNEL | TEXMAP_CHANNEL | SUBSEL_TYPE_CHANNEL; }
    ChannelMask ChannelsChanged() override { return GEOM_CHANNEL | TOPO_CHANNEL | TEXMAP_CHANNEL | VERTCOLOR_CHANNEL; }
    Class_ID InputType() override { return triObjectClassID; }
    BOOL ChangeTopology() override { return TRUE; }
    Interval LocalValidity(TimeValue t) override;
    void ModifyObject(TimeValue t, ModContext& mc, ObjectState* os, INode* node) override;

    Matrix3 CompMatrix(TimeValue t, INode* inode, ModContext* mc);
    void ComputeBorderLineSegments(TimeValue t, Point3 outP0[4], Point3 outP1[4], Point3 outMid[4]) const;
    void UpdateUIControls();
    void SavePresetINI(const MCHAR* path, TimeValue t);
    void LoadPresetINI(const MCHAR* path, TimeValue t);
};
