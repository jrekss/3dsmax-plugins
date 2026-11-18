/*
================================================================================
    FloorGenerator v2.1 (MaxScript Edition)
    Reconstructed from FloorGenerator_max2027_64bit.dlm
================================================================================
    HOW TO USE:
    1. In 3ds Max: Scripting -> Run Script... -> select "FloorGenerator_v2.ms"
       (or drag-and-drop into viewport).
    2. It registers the "FloorGenerator v2.1" modifier in the Modifier List with
       the exact 1:1 multi-rollout UI (collapsible tabs, Border rollout, and
       compact [L] lock buttons).
================================================================================
*/

global FGv2_Engine
try (if FGv2_Floater != undefined do (closeRolloutFloater FGv2_Floater; FGv2_Floater = undefined)) catch ()

struct FGv2_BorderCtx
(
    active = false,
    hasValidFrame = false,
    isRectRoom = true,
    roomMinX = 0.0,
    roomMinY = 0.0,
    roomMaxX = 0.0,
    roomMaxY = 0.0,
    roomTris = #(),
    xOutMin = 0.0,
    yOutMin = 0.0,
    xOutMax = 0.0,
    yOutMax = 0.0,
    xInMin = 0.0,
    yInMin = 0.0,
    xInMax = 0.0,
    yInMax = 0.0,
    inFieldMinX = 0.0,
    inFieldMinY = 0.0,
    inFieldMaxX = 0.0,
    inFieldMaxY = 0.0,
    hasInnerField = false,
    outerStrips = #(),
    ringStrips = #(),
    miterStrips = #(),
    dirPreTM = undefined,
    dirPostTM = undefined
)

struct FGv2_Config
(
    FloorPattern = 1,
    HerringboneParallels = 1,
    ChevronAngle = 45.0,
    BasketWeaveSubBoards = 3,
    OctagonInsertSize = 200.0,

    Length = 1000.0,
    Length_L = true,
    Length_R = 1000.0,
    Length_S = 0.5,

    Width = 70.0,
    Width_L = true,
    Width_R = 70.0,
    Width_S = 0.5,

    GroutLength = 0.2,
    GroutWidth = 0.2,
    Grout_L = true,

    MinRowOffset = 20.0,
    MaxRowOffset = 20.0,
    RowOffset_L = true,

    DoExtrude = true,
    Extrude = 1.0,
    DoBevel = true,
    Bevel = 0.5,
    BevelL = true,
    Outline = 0.5,

    DoGrout = false,
    GroutDepth = 0.5,
    GroutMatID = 3,

    DoBorder = false,
    BorderWidth = 100.0,
    BorderOffset = 200.0,
    BorderPattern = 1,
    BorderTileSize = 600.0,
    BorderCutMode = 1,
    BorderMatID = 4,
    BorderOffBot = 0.0,
    BorderOffTop = 0.0,
    BorderOffLeft = 0.0,
    BorderOffRight = 0.0,

    MaxRotation = 0.0,
    Rotation_R = 0.0,
    RotationSpread = 0.5,

    Offset_X = 0.0,
    Offset_X_R = 0.0,
    Offset_X_S = 0.5,
    Offset_Y = 0.0,
    Offset_Y_R = 0.0,
    Offset_Y_S = 0.5,
    Offset_L = true,

    Tilt = 0.0,
    Tilt_R = 0.0,
    Tilt_S = 0.5,
    MaxOverlap = 0.0,

    Scale = 100.0,
    Direction = 0.0,
    Seed = 12345,
    ObjOffsetX = 0.0,
    ObjOffsetY = 0.0,
    DoWeld = false,
    Weld = 0.05,

    UVChannel = 1,
    FlipU = true,
    FlipV = true,
    RandomOffsetU = true,
    RandomOffsetV = true,

    WarnMaxBoard = 10000,
    LiveUpdate = true
)

struct FGv2_EngineStruct
(
    -- 1. Exact Spread distribution from FUN_1800087f0
    fn spreadRand minVal maxVal spread =
    (
        if abs (maxVal - minVal) <= 1e-6 do return minVal
        local r = random 0.0 1.0
        local t = 0.0
        if r <= 1e-5 then
            t = 0.0
        else if r >= 0.99999 then
            t = 1.0
        else
        (
            local invR = 1.0 - r
            if invR <= spread then
                t = ((spread - 1.0) * invR) / r + 1.0
            else
                t = (r * spread) / invR
        )
        minVal + (maxVal - minVal) * t
    ),

    fn randSign =
    (
        if (random 0 1) == 1 then -1.0 else 1.0
    ),

    -- 2. Collision-limited max rotation angle (in degrees) from FUN_1800088b0
    fn calcCollisionAngleDeg a b availGap =
    (
        if a <= 1e-5 or b <= 1e-5 do return 0.0
        local d = sqrt (0.25 * a * a + 0.25 * b * b)
        local halfSpan = (a + availGap) * 0.5
        local ang = 180.0
        if halfSpan <= d and d > 1e-6 do
        (
            local ratio = amin 1.0 (amax -1.0 (halfSpan / d))
            ang = 90.0 - (atan (a / b)) - (acos ratio)
        )
        amax 0.0 ang
    ),

    -- FUN_180008990: Per-board rotation in degrees
    fn sampleBoardRotationDeg maxRotPct minRotPct rotSpread boardL boardW availGapW availGapL offX offY =
    (
        if maxRotPct <= 1e-4 and minRotPct <= 1e-4 do return 0.0
        local frac = (this.spreadRand (minRotPct * 0.01) (maxRotPct * 0.01) (1.0 - rotSpread))
        local effGapW = availGapW - 2.0 * (abs offX)
        local effGapL = availGapL - 2.0 * (abs offY)
        local a1 = (this.calcCollisionAngleDeg boardW boardL effGapW) * frac
        local a2 = (this.calcCollisionAngleDeg boardL boardW effGapL) * frac
        local lim = amin a1 a2
        lim * (this.randSign())
    ),

    -- 3. 2D Sutherland-Hodgman Polygon Clipping
    fn clipPolyByEdge poly pA pB =
    (
        local cnt = poly.count
        if cnt < 3 do return #()
        local out = #()
        local dx = pB.x - pA.x
        local dy = pB.y - pA.y
        local prevPt = poly[cnt]
        local prevVal = dx * (prevPt.y - pA.y) - dy * (prevPt.x - pA.x)
        local prevIn = (prevVal >= -1e-4)

        for i = 1 to cnt do
        (
            local curPt = poly[i]
            local curVal = dx * (curPt.y - pA.y) - dy * (curPt.x - pA.x)
            local curIn = (curVal >= -1e-4)
            if curIn then
            (
                if not prevIn do
                (
                    local denom = prevVal - curVal
                    local t = if abs denom > 1e-9 then (prevVal / denom) else 0.5
                    append out (prevPt + (curPt - prevPt) * t)
                )
                append out curPt
            )
            else if prevIn do
            (
                local denom = prevVal - curVal
                local t = if abs denom > 1e-9 then (prevVal / denom) else 0.5
                append out (prevPt + (curPt - prevPt) * t)
            )
            prevPt = curPt
            prevVal = curVal
            prevIn = curIn
        )
        out
    ),

    fn cleanPoly2D poly =
    (
        if poly.count < 3 do return #()
        local cleaned = #()
        local prev = poly[poly.count]
        for i = 1 to poly.count do
        (
            local p = poly[i]
            local dx = p.x - prev.x
            local dy = p.y - prev.y
            if (dx * dx + dy * dy) > 1e-6 do
            (
                append cleaned p
                prev = p
            )
        )
        if cleaned.count < 3 do return #()
        local area2 = 0.0
        local p0 = cleaned[1]
        for i = 2 to (cleaned.count - 1) do
        (
            local v1 = cleaned[i] - p0
            local v2 = cleaned[i + 1] - p0
            area2 += (v1.x * v2.y - v1.y * v2.x)
        )
        if area2 <= 1e-5 do return #()
        cleaned
    ),

    fn clipPolyToRect poly minX minY maxX maxY =
    (
        local bMinX = 1e30, bMinY = 1e30, bMaxX = -1e30, bMaxY = -1e30
        for p in poly do
        (
            if p.x < bMinX do bMinX = p.x
            if p.y < bMinY do bMinY = p.y
            if p.x > bMaxX do bMaxX = p.x
            if p.y > bMaxY do bMaxY = p.y
        )
        if bMaxX <= minX + 1e-4 or bMinX >= maxX - 1e-4 or bMaxY <= minY + 1e-4 or bMinY >= maxY - 1e-4 do
            return #()
        if bMinX >= minX - 1e-4 and bMaxX <= maxX + 1e-4 and bMinY >= minY - 1e-4 and bMaxY <= maxY + 1e-4 do
            return poly

        local r1 = [minX, minY, 0.0]
        local r2 = [maxX, minY, 0.0]
        local r3 = [maxX, maxY, 0.0]
        local r4 = [minX, maxY, 0.0]
        local c = this.clipPolyByEdge poly r1 r2
        if c.count < 3 do return #()
        c = this.clipPolyByEdge c r2 r3
        if c.count < 3 do return #()
        c = this.clipPolyByEdge c r3 r4
        if c.count < 3 do return #()
        c = this.clipPolyByEdge c r4 r1
        this.cleanPoly2D c
    ),

    fn clipPolyToTri poly t1 t2 t3 =
    (
        local c = this.clipPolyByEdge poly t1 t2
        if c.count < 3 do return #()
        c = this.clipPolyByEdge c t2 t3
        if c.count < 3 do return #()
        c = this.clipPolyByEdge c t3 t1
        this.cleanPoly2D c
    ),

    fn clipPolyToConvex2D poly conv =
    (
        local c = poly
        local n = conv.count
        for i = 1 to n while c.count >= 3 do
        (
            local pNext = conv[if i == n then 1 else i + 1]
            c = this.clipPolyByEdge c conv[i] pNext
        )
        if c.count >= 3 then (this.cleanPoly2D c) else #()
    ),

    -- 3b. Polygon area & merge board pieces cut by triangulation lines
    fn polyArea2D poly =
    (
        if poly.count < 3 do return 0.0
        local a = 0.0
        local p0 = poly[1]
        for i = 2 to (poly.count - 1) do
        (
            local v1 = poly[i] - p0
            local v2 = poly[i + 1] - p0
            a += (v1.x * v2.y - v1.y * v2.x)
        )
        0.5 * (abs a)
    ),

    fn mergeClippedPieces pieces =
    (
        if pieces.count <= 1 do return pieces

        local halfEdges = #()
        local eps2 = 1e-4

        for poly in pieces do
        (
            local cnt = poly.count
            for i = 1 to cnt do
            (
                local pA = poly[i]
                local pB = poly[if i == cnt then 1 else i + 1]
                local midX = (pA.x + pB.x) * 0.5
                local midY = (pA.y + pB.y) * 0.5

                local twinIdx = 0
                for j = 1 to halfEdges.count while twinIdx == 0 do
                (
                    local he = halfEdges[j]
                    if he[3] and (abs (midX - he[4]) < 1e-2) and (abs (midY - he[5]) < 1e-2) do
                    (
                        local eA = he[1]
                        local eB = he[2]
                        local d1 = (pA.x - eB.x)^2 + (pA.y - eB.y)^2
                        local d2 = (pB.x - eA.x)^2 + (pB.y - eA.y)^2
                        if d1 < eps2 and d2 < eps2 do twinIdx = j
                    )
                )

                if twinIdx > 0 then
                    halfEdges[twinIdx][3] = false
                else
                    append halfEdges #(pA, pB, true, midX, midY)
            )
        )

        local activeEdges = for e in halfEdges where e[3] collect #(e[1], e[2], false)
        local mergedPolys = #()

        for i = 1 to activeEdges.count do
        (
            if not activeEdges[i][3] do
            (
                activeEdges[i][3] = true
                local loop = #(activeEdges[i][1])
                local curEnd = activeEdges[i][2]
                local closed = false

                while not closed do
                (
                    if ((curEnd.x - loop[1].x)^2 + (curEnd.y - loop[1].y)^2) < eps2 then
                        closed = true
                    else
                    (
                        append loop curEnd
                        local foundNext = false
                        for j = 1 to activeEdges.count while not foundNext do
                        (
                            if not activeEdges[j][3] do
                            (
                                local st = activeEdges[j][1]
                                if ((curEnd.x - st.x)^2 + (curEnd.y - st.y)^2) < eps2 do
                                (
                                    activeEdges[j][3] = true
                                    curEnd = activeEdges[j][2]
                                    foundNext = true
                                )
                            )
                        )
                        if not foundNext do closed = true
                    )
                )

                if loop.count >= 3 do
                (
                    local simplified = #()
                    local n = loop.count
                    for k = 1 to n do
                    (
                        local pPrev = loop[if k == 1 then n else k - 1]
                        local pCur  = loop[k]
                        local pNext = loop[if k == n then 1 else k + 1]
                        local v1 = normalize (pCur - pPrev)
                        local v2 = normalize (pNext - pCur)
                        if (abs (v1.x * v2.y - v1.y * v2.x)) > 1e-3 do
                            append simplified pCur
                    )
                    local cleaned = this.cleanPoly2D simplified
                    if cleaned.count >= 3 do append mergedPolys cleaned
                )
            )
        )
        if mergedPolys.count == 0 do return pieces
        mergedPolys
    ),

    -- 3c. Convexity check & Ear-Clipping Triangulation for non-convex clipped boards
    fn isConvexPoly2D poly =
    (
        local n = poly.count
        if n <= 3 do return true
        for i = 1 to n do
        (
            local pPrev = poly[if i == 1 then n else i - 1]
            local pCur  = poly[i]
            local pNext = poly[if i == n then 1 else i + 1]
            local crossZ = (pCur.x - pPrev.x) * (pNext.y - pCur.y) - (pCur.y - pPrev.y) * (pNext.x - pCur.x)
            if crossZ < -1e-4 do return false
        )
        true
    ),

    fn pointInTri2D pt a b c =
    (
        local c1 = (b.x - a.x) * (pt.y - a.y) - (b.y - a.y) * (pt.x - a.x)
        if c1 < -1e-5 do return false
        local c2 = (c.x - b.x) * (pt.y - b.y) - (c.y - b.y) * (pt.x - b.x)
        if c2 < -1e-5 do return false
        local c3 = (a.x - c.x) * (pt.y - c.y) - (a.y - c.y) * (pt.x - c.x)
        if c3 < -1e-5 do return false
        true
    ),

    fn triangulatePoly2D poly =
    (
        local n = poly.count
        if n < 3 do return #()
        if n == 3 do return #([1, 2, 3])
        if (this.isConvexPoly2D poly) do
        (
            local fan = #()
            for i = 2 to (n - 1) do append fan [1, i, i + 1]
            return fan
        )

        local idxList = for i = 1 to n collect i
        local tris = #()
        local guard = n * 3

        while idxList.count > 3 and guard > 0 do
        (
            guard -= 1
            local cnt = idxList.count
            local earFound = false

            for k = 1 to cnt while not earFound do
            (
                local iPrev = idxList[if k == 1 then cnt else k - 1]
                local iCur  = idxList[k]
                local iNext = idxList[if k == cnt then 1 else k + 1]

                local a = poly[iPrev]
                local b = poly[iCur]
                local c = poly[iNext]

                local crossZ = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                if crossZ > 1e-5 do
                (
                    local hasInside = false
                    for m = 1 to cnt while not hasInside do
                    (
                        local idxTest = idxList[m]
                        if idxTest != iPrev and idxTest != iCur and idxTest != iNext do
                        (
                            if (this.pointInTri2D poly[idxTest] a b c) do hasInside = true
                        )
                    )
                    if not hasInside do
                    (
                        append tris [iPrev, iCur, iNext]
                        deleteItem idxList k
                        earFound = true
                    )
                )
            )

            if not earFound do
            (
                -- Fallback if degenerate ear
                append tris [idxList[1], idxList[2], idxList[3]]
                deleteItem idxList 2
            )
        )

        if idxList.count == 3 do
            append tris [idxList[1], idxList[2], idxList[3]]

        tris
    ),

    -- 4. Emit a single 3D board (Extrude + Bevel/Outline + Tilt + UVW)
    fn emitBoardPrism poly boardCenter totalRotDeg uvSpanL uvSpanW flipU flipV offU offV \
        doExtrude extrudeH doBevel bevelH outlineW tiltDirDeg tiltAmount dirPostTM \
        boardMatID outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis =
    (
        local m = poly.count
        if m < 3 do return false

        local pMinX = 1e30, pMinY = 1e30, pMaxX = -1e30, pMaxY = -1e30
        for p in poly do
        (
            if p.x < pMinX do pMinX = p.x
            if p.y < pMinY do pMinY = p.y
            if p.x > pMaxX do pMaxX = p.x
            if p.y > pMaxY do pMaxY = p.y
        )
        local minSpan = amin (pMaxX - pMinX) (pMaxY - pMinY)
        local maxOutlineRatio = if m == 3 then 0.28 else 0.45
        local effOutline = if doBevel then (amin outlineW (minSpan * maxOutlineRatio)) else 0.0
        local effExtrude = if doExtrude then extrudeH else 0.0
        local effBevel   = if doBevel then bevelH else 0.0

        local miters = #()
        miters.count = m
        if doBevel and abs effOutline > 1e-5 then
        (
            local edgeNormals = #()
            edgeNormals.count = m
            for i = 1 to m do
            (
                local ip1 = if i == m then 1 else (i + 1)
                local d = poly[ip1] - poly[i]
                local len = sqrt (d.x * d.x + d.y * d.y)
                if len > 1e-6 then
                    edgeNormals[i] = [d.y / len, -d.x / len, 0.0]
                else
                    edgeNormals[i] = [0.0, 0.0, 0.0]
            )
            for i = 1 to m do
            (
                local im1 = if i == 1 then m else (i - 1)
                local nPrev = edgeNormals[im1]
                local nCur  = edgeNormals[i]
                local denom = 1.0 + (nPrev.x * nCur.x + nPrev.y * nCur.y)
                local bisX = 0.0
                local bisY = 0.0
                if denom > 0.15 then
                (
                    bisX = -(nPrev.x + nCur.x) / denom
                    bisY = -(nPrev.y + nCur.y) / denom
                )
                else
                (
                    bisX = -(nPrev.x + nCur.x)
                    bisY = -(nPrev.y + nCur.y)
                )
                local bLen2 = bisX * bisX + bisY * bisY
                if bLen2 > 6.25 do
                (
                    local sc = 2.5 / (sqrt bLen2)
                    bisX *= sc
                    bisY *= sc
                )
                miters[i] = [bisX * effOutline, bisY * effOutline, 0.0]
            )
        )
        else
        (
            for i = 1 to m do miters[i] = [0.0, 0.0, 0.0]
        )

        local ringStartIndices = #()
        local bVertStart = outVerts.count + 1

        -- Ring 1 (z = 0)
        local r1Start = outVerts.count + 1
        append ringStartIndices r1Start
        for i = 1 to m do
        (
            local p = poly[i]
            append outVerts [p.x, p.y, 0.0]
        )

        local topRingStart = r1Start
        if doExtrude and abs effExtrude > 1e-5 do
        (
            local r2Start = outVerts.count + 1
            append ringStartIndices r2Start
            for i = 1 to m do
            (
                local p = poly[i]
                append outVerts [p.x, p.y, effExtrude]
            )
            topRingStart = r2Start
        )

        local topCapPoly = #()
        topCapPoly.count = m
        if doBevel and (abs effBevel > 1e-5 or abs effOutline > 1e-5) then
        (
            local r3Start = outVerts.count + 1
            append ringStartIndices r3Start
            local zTop = effExtrude + effBevel
            for i = 1 to m do
            (
                local p = poly[i]
                local mt = miters[i]
                local tp = [p.x + mt.x, p.y + mt.y, zTop]
                append outVerts tp
                topCapPoly[i] = tp
            )
            topRingStart = r3Start
        )
        else
        (
            topCapPoly = poly
        )

        local bVertEnd = outVerts.count

        -- Side quads
        for r = 1 to (ringStartIndices.count - 1) do
        (
            local bot0 = ringStartIndices[r]
            local top0 = ringStartIndices[r + 1]
            local smG  = if r == 1 then 2 else 4
            for i = 0 to (m - 1) do
            (
                local inext = mod (i + 1) m
                local v00 = bot0 + i
                local v10 = bot0 + inext
                local v11 = top0 + inext
                local v01 = top0 + i

                append outFaces [v00, v10, v11]
                append outMatIDs (boardMatID as integer)
                append outSmGroups smG
                append outEdgeVis #(true, true, false)

                append outFaces [v00, v11, v01]
                append outMatIDs (boardMatID as integer)
                append outSmGroups smG
                append outEdgeVis #(false, true, true)
            )
        )

        -- Top cap faces (supports both convex & concave polygons)
        local capTris = this.triangulatePoly2D topCapPoly
        for t in capTris do
        (
            local i1 = t.x as integer
            local i2 = t.y as integer
            local i3 = t.z as integer
            local v1 = topRingStart + i1 - 1
            local v2 = topRingStart + i2 - 1
            local v3 = topRingStart + i3 - 1
            append outFaces [v1, v2, v3]
            append outMatIDs (boardMatID as integer)
            append outSmGroups 1
            local e1Vis = ((mod i1 m) + 1 == i2)
            local e2Vis = ((mod i2 m) + 1 == i3)
            local e3Vis = ((mod i3 m) + 1 == i1)
            append outEdgeVis #(e1Vis, e2Vis, e3Vis)
        )

        local cosR = cos (-totalRotDeg)
        local sinR = sin (-totalRotDeg)

        local hasTilt = (tiltAmount > 1e-5)
        local cosT = 1.0, sinT = 0.0, tiltMinX = 0.0, tiltSpanX = 1.0
        if hasTilt do
        (
            cosT = cos tiltDirDeg
            sinT = sin tiltDirDeg
            tiltMinX = 1e30
            local tiltMaxX = -1e30
            for i = 1 to m do
            (
                local dx = poly[i].x - boardCenter.x
                local dy = poly[i].y - boardCenter.y
                local rx = dx * cosT - dy * sinT
                if rx < tiltMinX do tiltMinX = rx
                if rx > tiltMaxX do tiltMaxX = rx
            )
            tiltSpanX = amax 1e-4 (tiltMaxX - tiltMinX)
        )

        local invSpanL = if uvSpanL > 1e-5 then (1.0 / uvSpanL) else 1.0
        local invSpanW = if uvSpanW > 1e-5 then (1.0 / uvSpanW) else 1.0
        local minZAfterTilt = 0.0

        for vi = bVertStart to bVertEnd do
        (
            local pt = outVerts[vi]
            local lx = pt.x - boardCenter.x
            local ly = pt.y - boardCenter.y
            local lz = pt.z - boardCenter.z

            local locX = lx * cosR - ly * sinR
            local locY = lx * sinR + ly * cosR

            local u = locX * invSpanL + 0.5
            local v = locY * invSpanW + 0.5
            if flipU do u = 1.0 - u
            if flipV do v = 1.0 - v
            u += offU
            v += offV
            outTVerts[vi] = [u, v, lz]

            if hasTilt and lz > 1e-5 do
            (
                local tx = lx * cosT - ly * sinT
                lz += ((tx - tiltMinX) / tiltSpanX) * tiltAmount
            )

            local worldPt = [lx + boardCenter.x, ly + boardCenter.y, lz + boardCenter.z]
            if dirPostTM != undefined do
                worldPt = worldPt * dirPostTM

            if worldPt.z < minZAfterTilt do minZAfterTilt = worldPt.z
            outVerts[vi] = worldPt
        )

        if minZAfterTilt < 0.0 do
        (
            for vi = bVertStart to bVertEnd do
                outVerts[vi].z -= minZAfterTilt
        )
        true
    ),

    -- 5. Rotate 2D board polygon & Process single board
    fn rotatePoly2D poly center rotDeg =
    (
        if abs rotDeg <= 1e-5 do return poly
        local c = cos rotDeg
        local s = sin rotDeg
        local out = #()
        out.count = poly.count
        for i = 1 to poly.count do
        (
            local dx = poly[i].x - center.x
            local dy = poly[i].y - center.y
            out[i] = [center.x + dx * c - dy * s, center.y + dx * s + dy * c, 0.0]
        )
        out
    ),

    fn transformPoly2D poly tm =
    (
        if tm == undefined do return poly
        local out = #()
        out.count = poly.count
        for i = 1 to poly.count do
        (
            local pt = [poly[i].x, poly[i].y, 0.0] * tm
            out[i] = [pt.x, pt.y, 0.0]
        )
        out
    ),

    fn clipPolyToFootprint2D poly bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris =
    (
        if poly.count < 3 do return #()
        if isRectangularFootprint do
        (
            local clipped = this.clipPolyToRect poly bbMinX bbMinY bbMaxX bbMaxY
            if clipped.count >= 3 then return #(clipped) else return #()
        )

        local pMinX = 1e30, pMinY = 1e30, pMaxX = -1e30, pMaxY = -1e30
        for p in poly do
        (
            if p.x < pMinX do pMinX = p.x
            if p.y < pMinY do pMinY = p.y
            if p.x > pMaxX do pMaxX = p.x
            if p.y > pMaxY do pMaxY = p.y
        )
        if pMaxX <= bbMinX or pMinX >= bbMaxX or pMaxY <= bbMinY or pMinY >= bbMaxY do return #()

        local pieces = #()
        local clippedArea = 0.0
        for tri in baseTris do
        (
            if pMaxX > tri[4] and pMinX < tri[6] and pMaxY > tri[5] and pMinY < tri[7] do
            (
                local clipped = this.clipPolyToTri poly tri[1] tri[2] tri[3]
                if clipped.count >= 3 do
                (
                    append pieces clipped
                    clippedArea += this.polyArea2D clipped
                )
            )
        )
        if pieces.count == 0 do return #()

        local fullArea = this.polyArea2D poly
        if abs (clippedArea - fullArea) <= (1e-4 * fullArea) then return #(poly)
        else if pieces.count > 1 then
        (
            local merged = this.mergeClippedPieces pieces
            if merged.count > 0 do return merged
        )
        pieces
    ),

    fn clipPolyAgainstRectListAndEmit polyRoom rects bctx \
        boardCenter totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
        cfg extrudeH bevelH outlineW bTiltDir bTiltAmt dirPostTM matID \
        outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis =
    (
        if rects.count == 0 do return false
        local collected = #()
        for r in rects do
        (
            local sub = this.clipPolyToRect polyRoom r[1] r[2] r[3] r[4]
            if sub.count >= 3 do
            (
                local roomClipped = this.clipPolyToFootprint2D sub bctx.roomMinX bctx.roomMinY bctx.roomMaxX bctx.roomMaxY bctx.isRectRoom bctx.roomTris
                for rp in roomClipped do append collected rp
            )
        )
        if collected.count == 0 do return false
        if collected.count > 1 do
            collected = this.mergeClippedPieces collected

        for fpRoom in collected do
        (
            local fpTile = if bctx.dirPreTM != undefined then (this.transformPoly2D fpRoom bctx.dirPreTM) else fpRoom
            this.emitBoardPrism fpTile boardCenter totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                cfg.DoExtrude extrudeH cfg.DoBevel bevelH outlineW bTiltDir bTiltAmt dirPostTM \
                matID outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
        )
        true
    ),

    fn clipPolyAgainstBorderRingAndEmit polyRoom bctx \
        boardCenter totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
        cfg extrudeH bevelH outlineW bTiltDir bTiltAmt dirPostTM bMatID \
        outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis =
    (
        if cfg.BorderCutMode == 1 then
        (
            for trap in bctx.miterStrips do
            (
                local sub = this.clipPolyToConvex2D polyRoom trap
                if sub.count >= 3 do
                (
                    local roomClipped = this.clipPolyToFootprint2D sub bctx.roomMinX bctx.roomMinY bctx.roomMaxX bctx.roomMaxY bctx.isRectRoom bctx.roomTris
                    for fpRoom in roomClipped do
                    (
                        local fpTile = if bctx.dirPreTM != undefined then (this.transformPoly2D fpRoom bctx.dirPreTM) else fpRoom
                        this.emitBoardPrism fpTile boardCenter totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                            cfg.DoExtrude extrudeH cfg.DoBevel bevelH outlineW bTiltDir bTiltAmt dirPostTM \
                            bMatID outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
                    )
                )
            )
            true
        )
        else
        (
            this.clipPolyAgainstRectListAndEmit polyRoom bctx.ringStrips bctx \
                boardCenter totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                cfg extrudeH bevelH outlineW bTiltDir bTiltAmt dirPostTM bMatID \
                outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
        )
    ),

    fn processBoardPoly rawPoly baseRotDeg curBoardL curBoardW \
        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
        cfg sc maxL maxW uvSpanL uvSpanW availGapW availGapL \
        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:undefined fixedMatID:0 ringOnly:false =
    (
        boardIdx += 1
        local dxOff = (this.spreadRand clampOffXMin clampOffXMax (1.0 - offXSpr)) * (this.randSign())
        local dyOff = (this.spreadRand clampOffYMin clampOffYMax (1.0 - offYSpr)) * (this.randSign())

        local shifted = #()
        shifted.count = rawPoly.count
        local cx = 0.0, cy = 0.0
        for i = 1 to rawPoly.count do
        (
            local px = rawPoly[i].x - dxOff
            local py = rawPoly[i].y - dyOff
            shifted[i] = [px, py, 0.0]
            cx += px
            cy += py
        )
        cx /= (rawPoly.count as float)
        cy /= (rawPoly.count as float)
        local center = [cx, cy, 0.0]

        local randRotDeg = this.sampleBoardRotationDeg cfg.MaxRotation cfg.Rotation_R cfg.RotationSpread \
            curBoardL curBoardW availGapW availGapL dxOff dyOff
        local polyRot = this.rotatePoly2D shifted center randRotDeg
        local totalRotDeg = baseRotDeg + randRotDeg

        local bFlipU = if cfg.FlipU then ((random 0 1) == 1) else false
        local bFlipV = if cfg.FlipV then ((random 0 1) == 1) else false
        local bOffU  = if cfg.RandomOffsetU then (random -0.5 0.5) else 0.0
        local bOffV  = if cfg.RandomOffsetV then (random -0.5 0.5) else 0.0

        local bTiltDir = 0.0
        local bTiltAmt = 0.0
        if maxTilt > 1e-5 or minTilt > 1e-5 do
        (
            bTiltDir = random 0.0 360.0
            bTiltAmt = this.spreadRand minTilt maxTilt (1.0 - tiltSpr)
        )

        local matID = if fixedMatID > 0 then (fixedMatID as integer) else (((mod (boardIdx - 1) 65535) + 1) as integer)

        if bctx != undefined and bctx.active and bctx.hasValidFrame do
        (
            local polyRoom = if bctx.dirPostTM != undefined then (this.transformPoly2D polyRot bctx.dirPostTM) else polyRot
            local bMatID = amax 1 (cfg.BorderMatID as integer)

            if ringOnly do
            (
                this.clipPolyAgainstBorderRingAndEmit polyRoom bctx \
                    center totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                    cfg extrudeH bevelH outlineW bTiltDir bTiltAmt dirPostTM bMatID \
                    outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
                return true
            )

            if bctx.hasInnerField do
            (
                local inSub = this.clipPolyToRect polyRoom bctx.inFieldMinX bctx.inFieldMinY bctx.inFieldMaxX bctx.inFieldMaxY
                if inSub.count >= 3 do
                (
                    local finalPolys = this.clipPolyToFootprint2D inSub bctx.roomMinX bctx.roomMinY bctx.roomMaxX bctx.roomMaxY bctx.isRectRoom bctx.roomTris
                    for fpRoom in finalPolys do
                    (
                        local fpTile = if bctx.dirPreTM != undefined then (this.transformPoly2D fpRoom bctx.dirPreTM) else fpRoom
                        this.emitBoardPrism fpTile center totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                            cfg.DoExtrude extrudeH cfg.DoBevel bevelH outlineW bTiltDir bTiltAmt dirPostTM \
                            matID outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
                    )
                )
            )

            this.clipPolyAgainstRectListAndEmit polyRoom bctx.outerStrips bctx \
                center totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                cfg extrudeH bevelH outlineW bTiltDir bTiltAmt dirPostTM matID \
                outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis

            if cfg.BorderPattern == 1 do
            (
                this.clipPolyAgainstBorderRingAndEmit polyRoom bctx \
                    center totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                    cfg extrudeH bevelH outlineW bTiltDir bTiltAmt dirPostTM bMatID \
                    outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
            )
            return true
        )

        local finalPolys = this.clipPolyToFootprint2D polyRot bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris
        for fp in finalPolys do
        (
            this.emitBoardPrism fp center totalRotDeg uvSpanL uvSpanW bFlipU bFlipV bOffU bOffV \
                cfg.DoExtrude extrudeH cfg.DoBevel bevelH outlineW bTiltDir bTiltAmt dirPostTM \
                matID outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis
        )
    ),

    fn buildTrisFromMesh ioMesh verts2D =
    (
        local tris = #()
        local areaSum = 0.0
        for f = 1 to ioMesh.numFaces do
        (
            local fv = getFace ioMesh f
            local p1 = verts2D[fv.x]
            local p2 = verts2D[fv.y]
            local p3 = verts2D[fv.z]
            local a2 = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
            if abs a2 > 1e-5 do
            (
                areaSum += 0.5 * (abs a2)
                local tMinX = amin p1.x (amin p2.x p3.x)
                local tMinY = amin p1.y (amin p2.y p3.y)
                local tMaxX = amax p1.x (amax p2.x p3.x)
                local tMaxY = amax p1.y (amax p2.y p3.y)
                if a2 > 0.0 then
                    append tris #(p1, p2, p3, tMinX, tMinY, tMaxX, tMaxY)
                else
                    append tris #(p1, p3, p2, tMinX, tMinY, tMaxX, tMaxY)
            )
        )
        #(tris, areaSum)
    ),

    -- 6. Main Floor Mesh Builder (FUN_180007010 ModifyObject)
    fn buildFloorOnTriMesh ioMesh cfg allowDialogs:true =
    (
        if ioMesh == undefined or ioMesh.numFaces == 0 do return false

        -- 1. Coplanarity check
        local n0 = normalize (getFaceNormal ioMesh 1)
        local isCoplanar = true
        for f = 2 to ioMesh.numFaces while isCoplanar do
        (
            local nf = normalize (getFaceNormal ioMesh f)
            if (dot n0 nf) < 0.95 do isCoplanar = false
        )
        if (not isCoplanar) and allowDialogs do
        (
            local msg = "Invalid input mesh detected.\nFloorGenerator requires a coplanar base object, continue?"
            if not (queryBox msg title:"Input Mesh Warning") do return false
        )

        -- 2. Seed PRNG
        seed (amax 0 cfg.Seed)

        -- 3. Orthonormal basis
        local fromPlaneTM = matrix3 1
        if abs (n0.z - 1.0) < 1e-4 then
            fromPlaneTM = matrix3 [1,0,0] [0,1,0] [0,0,1] [0,0,0]
        else if abs (n0.z + 1.0) < 1e-4 then
            fromPlaneTM = matrix3 [1,0,0] [0,-1,0] [0,0,-1] [0,0,0]
        else
        (
            local axX = normalize (cross [0,0,1] n0)
            local axY = normalize (cross n0 axX)
            fromPlaneTM = matrix3 axX axY n0 [0,0,0]
        )
        local toPlaneTM = inverse fromPlaneTM

        local f1Verts = getFace ioMesh 1
        local faceCenter0 = ((getVert ioMesh f1Verts.x) + (getVert ioMesh f1Verts.y) + (getVert ioMesh f1Verts.z)) / 3.0
        local planeHeight = dot n0 faceCenter0
        local planeOffset = n0 * planeHeight

        -- Direction rotation around Z
        local dirDeg = cfg.Direction
        local dirPreTM  = if abs dirDeg > 1e-4 then (rotateZMatrix (-dirDeg)) else undefined
        local dirPostTM = if abs dirDeg > 1e-4 then (rotateZMatrix dirDeg) else undefined

        -- Transform base mesh vertices to 2D plane (z = 0)
        local numBaseVerts = ioMesh.numVerts
        local roomVerts2D = #()
        roomVerts2D.count = numBaseVerts
        local baseVerts2D = #()
        baseVerts2D.count = numBaseVerts
        local roomMinX = 1e30, roomMinY = 1e30, roomMaxX = -1e30, roomMaxY = -1e30
        local bbMinX = 1e30, bbMinY = 1e30, bbMaxX = -1e30, bbMaxY = -1e30

        for v = 1 to numBaseVerts do
        (
            local pRoom = (getVert ioMesh v) * toPlaneTM
            pRoom.z = 0.0
            roomVerts2D[v] = pRoom
            if pRoom.x < roomMinX do roomMinX = pRoom.x
            if pRoom.y < roomMinY do roomMinY = pRoom.y
            if pRoom.x > roomMaxX do roomMaxX = pRoom.x
            if pRoom.y > roomMaxY do roomMaxY = pRoom.y

            local p = if dirPreTM != undefined then (pRoom * dirPreTM) else pRoom
            baseVerts2D[v] = p
            if p.x < bbMinX do bbMinX = p.x
            if p.y < bbMinY do bbMinY = p.y
            if p.x > bbMaxX do bbMaxX = p.x
            if p.y > bbMaxY do bbMaxY = p.y
        )

        local bbSpanX = bbMaxX - bbMinX
        local bbSpanY = bbMaxY - bbMinY
        local roomSpanX = roomMaxX - roomMinX
        local roomSpanY = roomMaxY - roomMinY
        if bbSpanX <= 1e-4 or bbSpanY <= 1e-4 or roomSpanX <= 1e-4 or roomSpanY <= 1e-4 do return false

        local btBase = this.buildTrisFromMesh ioMesh baseVerts2D
        local baseTris = btBase[1]
        local totalTriArea = btBase[2]
        local bboxArea = bbSpanX * bbSpanY
        local isRectangularFootprint = (abs (totalTriArea - bboxArea) <= (1e-4 * bboxArea))

        local btRoom = if dirPreTM != undefined then (this.buildTrisFromMesh ioMesh roomVerts2D) else btBase
        local roomTris = btRoom[1]
        local roomArea = btRoom[2]
        local roomBboxArea = roomSpanX * roomSpanY
        local isRectRoom = (abs (roomArea - roomBboxArea) <= (1e-4 * roomBboxArea))

        -- 4. Resolve scaled parameters & check WarnMaxBoard
        local sc = amax 0.0001 (cfg.Scale * 0.01)
        local maxL = (amax 0.1 cfg.Length) * sc
        local minL = if cfg.Length_L then maxL else ((amax 0.1 cfg.Length_R) * sc)
        local maxW = (amax 0.1 cfg.Width) * sc
        local minW = if cfg.Width_L then maxW else ((amax 0.1 cfg.Width_R) * sc)

        local gapL = (amax 0.0 cfg.GroutLength) * sc
        local gapW = if cfg.Grout_L then gapL else ((amax 0.0 cfg.GroutWidth) * sc)

        local uvSpanL = maxL
        local uvSpanW = maxW
        if cfg.FloorPattern == 4 then
        (
            local sub = amax 1 cfg.BasketWeaveSubBoards
            uvSpanL = maxL
            uvSpanW = if sub > 1 then (maxL / sub - gapL * 0.5) else maxL
        )
        else if cfg.FloorPattern == 5 then
        (
            uvSpanL = maxL * 2.0
            uvSpanW = maxL * 2.0
        )
        else if cfg.FloorPattern == 6 then
        (
            uvSpanL = maxL
            uvSpanW = maxL * 0.8660254
        )
        else if cfg.FloorPattern == 7 do
        (
            uvSpanL = maxL
            uvSpanW = if cfg.Width_L then maxL else maxW
        )

        local estBoardArea = if cfg.FloorPattern == 6 then (amax 1e-4 (0.5 * uvSpanL * uvSpanW)) else (amax 1e-4 (uvSpanL * uvSpanW))
        local estBoardCount = bboxArea / estBoardArea
        local maxAllowedBoards = amax 100 cfg.WarnMaxBoard

        -- Guard: prevent 3ds Max freeze on excessive boards
        if estBoardCount > maxAllowedBoards do
        (
            if allowDialogs then
            (
                local warnMsg = "More boards created than specified in Max Boards (" + (maxAllowedBoards as integer) as string + ").\nEither raise the maximum, or make the boards larger.\nOK to continue, or Cancel creating floor?"
                if not (queryBox warnMsg title:"Pattern Creation Warning") do return false
            )
            else
            (
                return false
            )
        )

        local offXMax = cfg.Offset_X * sc
        local offXMin = cfg.Offset_X_R * sc
        local offXSpr = cfg.Offset_X_S
        local offYMax = if cfg.Offset_L then offXMax else (cfg.Offset_Y * sc)
        local offYMin = if cfg.Offset_L then offXMin else (cfg.Offset_Y_R * sc)
        local offYSpr = if cfg.Offset_L then offXSpr else cfg.Offset_Y_S

        local availGapL = cfg.MaxOverlap * sc + gapL
        local availGapW = cfg.MaxOverlap * sc + gapW
        local halfAvailL = availGapL * 0.5
        local halfAvailW = availGapW * 0.5

        local clampOffXMin = amin offXMin halfAvailL
        local clampOffXMax = amin offXMax halfAvailL
        local clampOffYMin = amin offYMin halfAvailW
        local clampOffYMax = amin offYMax halfAvailW

        local maxTilt = cfg.Tilt * sc
        local minTilt = cfg.Tilt_R * sc
        local tiltSpr = cfg.Tilt_S

        local extrudeH = cfg.Extrude * sc
        local bevelH   = cfg.Bevel * sc
        local outlineW = (if cfg.BevelL then cfg.Bevel else cfg.Outline) * sc

        local outVerts    = #()
        local outFaces    = #()
        local outTVerts   = #()
        local outMatIDs   = #()
        local outSmGroups = #()
        local outEdgeVis  = #()
        local boardIdx    = 0

        local bctx = FGv2_BorderCtx \
            active:cfg.DoBorder \
            isRectRoom:isRectRoom \
            roomMinX:roomMinX roomMinY:roomMinY roomMaxX:roomMaxX roomMaxY:roomMaxY \
            roomTris:roomTris dirPreTM:dirPreTM dirPostTM:dirPostTM

        if bctx.active do
        (
            local bOff = cfg.BorderOffset * sc
            local bW = amax (0.1 * sc) (cfg.BorderWidth * sc)
            local x0 = roomMinX + bOff + cfg.BorderOffLeft * sc
            local x1 = roomMaxX - bOff + cfg.BorderOffRight * sc
            local y0 = roomMinY + bOff + cfg.BorderOffBot * sc
            local y1 = roomMaxY - bOff + cfg.BorderOffTop * sc

            bctx.xOutMin = amin x0 x1
            bctx.xOutMax = amax x0 x1
            bctx.yOutMin = amin y0 y1
            bctx.yOutMax = amax y0 y1
            local frameW = bctx.xOutMax - bctx.xOutMin
            local frameH = bctx.yOutMax - bctx.yOutMin
            bctx.hasValidFrame = (frameW > 1e-3 and frameH > 1e-3)

            if bctx.hasValidFrame do
            (
                local effW = amin bW (0.49 * (amin frameW frameH))
                bctx.xInMin = bctx.xOutMin + effW
                bctx.xInMax = bctx.xOutMax - effW
                bctx.yInMin = bctx.yOutMin + effW
                bctx.yInMax = bctx.yOutMax - effW

                bctx.inFieldMinX = bctx.xInMin + gapL
                bctx.inFieldMaxX = bctx.xInMax - gapL
                bctx.inFieldMinY = bctx.yInMin + gapW
                bctx.inFieldMaxY = bctx.yInMax - gapW
                bctx.hasInnerField = (bctx.inFieldMaxX > bctx.inFieldMinX + 1e-3) and (bctx.inFieldMaxY > bctx.inFieldMinY + 1e-3)

                local blkMinX = bctx.xOutMin - gapL
                local blkMaxX = bctx.xOutMax + gapL
                local blkMinY = bctx.yOutMin - gapW
                local blkMaxY = bctx.yOutMax + gapW

                local cxMin = amax roomMinX blkMinX
                local cxMax = amin roomMaxX blkMaxX
                if (amin roomMaxX blkMinX) > roomMinX + 1e-4 do append bctx.outerStrips #(roomMinX, roomMinY, amin roomMaxX blkMinX, roomMaxY)
                if roomMaxX > (amax roomMinX blkMaxX) + 1e-4 do append bctx.outerStrips #(amax roomMinX blkMaxX, roomMinY, roomMaxX, roomMaxY)
                if cxMax > cxMin + 1e-4 do
                (
                    if (amin roomMaxY blkMinY) > roomMinY + 1e-4 do append bctx.outerStrips #(cxMin, roomMinY, cxMax, amin roomMaxY blkMinY)
                    if roomMaxY > (amax roomMinY blkMaxY) + 1e-4 do append bctx.outerStrips #(cxMin, amax roomMinY blkMaxY, cxMax, roomMaxY)
                )

                if bctx.xOutMax > bctx.xOutMin + 1e-4 and bctx.yInMin > bctx.yOutMin + 1e-4 do append bctx.ringStrips #(bctx.xOutMin, bctx.yOutMin, bctx.xOutMax, bctx.yInMin)
                if bctx.xOutMax > bctx.xOutMin + 1e-4 and bctx.yOutMax > bctx.yInMax + 1e-4 do append bctx.ringStrips #(bctx.xOutMin, bctx.yInMax, bctx.xOutMax, bctx.yOutMax)
                if bctx.xInMin > bctx.xOutMin + 1e-4 and bctx.yInMax > bctx.yInMin + 1e-4 do append bctx.ringStrips #(bctx.xOutMin, bctx.yInMin, bctx.xInMin, bctx.yInMax)
                if bctx.xOutMax > bctx.xInMax + 1e-4 and bctx.yInMax > bctx.yInMin + 1e-4 do append bctx.ringStrips #(bctx.xInMax, bctx.yInMin, bctx.xOutMax, bctx.yInMax)

                local inW = bctx.xInMax - bctx.xInMin
                local inH = bctx.yInMax - bctx.yInMin
                local maxD45 = 0.45 * (amin inW inH)
                local d45 = amin maxD45 (0.70710678 * gapL)
                bctx.miterStrips = #(
                    #([bctx.xOutMin + d45, bctx.yOutMin, 0.0], [bctx.xOutMax - d45, bctx.yOutMin, 0.0], [bctx.xInMax - d45, bctx.yInMin, 0.0], [bctx.xInMin + d45, bctx.yInMin, 0.0]),
                    #([bctx.xInMin + d45, bctx.yInMax, 0.0], [bctx.xInMax - d45, bctx.yInMax, 0.0], [bctx.xOutMax - d45, bctx.yOutMax, 0.0], [bctx.xOutMin + d45, bctx.yOutMax, 0.0]),
                    #([bctx.xOutMin, bctx.yOutMin + d45, 0.0], [bctx.xInMin, bctx.yInMin + d45, 0.0], [bctx.xInMin, bctx.yInMax - d45, 0.0], [bctx.xOutMin, bctx.yOutMax - d45, 0.0]),
                    #([bctx.xInMax, bctx.yInMin + d45, 0.0], [bctx.xOutMax, bctx.yOutMin + d45, 0.0], [bctx.xOutMax, bctx.yOutMax - d45, 0.0], [bctx.xInMax, bctx.yInMax - d45, 0.0])
                )
            )
        )

        -- 5. Generate Pattern Boards
        local pat = cfg.FloorPattern
        local offObjX = cfg.ObjOffsetX * sc
        local offObjY = cfg.ObjOffsetY * sc

        if pat == 1 then -- STANDARD
        (
            local minRowOff = cfg.MinRowOffset * 0.01
            local maxRowOff = if cfg.RowOffset_L then minRowOff else (cfg.MaxRowOffset * 0.01)
            local avgRowOff = (minRowOff + maxRowOff) * 0.5
            local stepLMax  = maxL + gapL

            local yCursor = -maxW - gapW - (mod offObjY (maxW + gapW))
            local yLimit  = bbSpanY + maxW + gapW
            local rowIdx  = 0

            while yCursor < yLimit do
            (
                local curW = this.spreadRand minW maxW cfg.Width_S
                local randOff = if cfg.RowOffset_L then 0.0 else ((random minRowOff maxRowOff) - avgRowOff)
                local rowShift = mod ((rowIdx * avgRowOff + randOff) * (-stepLMax)) stepLMax
                local xCursor = rowShift - (mod offObjX stepLMax) - stepLMax
                local xLimit  = bbSpanX + stepLMax

                while xCursor < xLimit do
                (
                    local curL = this.spreadRand minL maxL cfg.Length_S
                    local x0 = bbMinX + xCursor
                    local y0 = bbMinY + yCursor
                    local quad = #(
                        [x0,        y0,        0.0],
                        [x0 + curL, y0,        0.0],
                        [x0 + curL, y0 + curW, 0.0],
                        [x0,        y0 + curW, 0.0]
                    )
                    this.processBoardPoly quad 0.0 curL curW \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc maxL maxW uvSpanL uvSpanW availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx

                    xCursor += curL + gapL
                )
                rowIdx += 1
                yCursor += curW + gapW
            )
        )
        else if pat == 2 then -- HERRINGBONE
        (
            local k45 = 0.70710678
            local dxL = maxL * k45
            local dxW = maxW * k45
            local dGap = gapL * k45
            local nPar = amax 1 cfg.HerringboneParallels
            local parStep = dxW + dGap
            local colStepX = dxL + dGap
            local rowStepY = ((maxW + gapL) * (nPar as float)) / k45

            local yCursor = -maxW - gapL - dxL - (mod offObjY rowStepY)
            local yLimit  = bbSpanY + maxW + (nPar as float) * parStep + dxL + gapL
            local xStart  = -(mod offObjX (2.0 * colStepX)) - (maxL + gapL)
            local xLimit  = bbSpanX + (nPar as float) * parStep + dxL

            while yCursor < yLimit do
            (
                local colIdx = 0
                local xCursor = xStart
                while xCursor < xLimit do
                (
                    local isOdd = ((mod colIdx 2) != 0)
                    local dirSign = if isOdd then -1.0 else 1.0
                    for pIdx = 0 to (nPar - 1) do
                    (
                        local hbX = bbMinX + xCursor - (pIdx as float) * parStep
                        local hbY = bbMinY + yCursor + (pIdx as float) * dirSign * parStep
                        local quad = undefined
                        local baseAng = 45.0
                        if not isOdd then
                        (
                            quad = #(
                                [hbX,             hbY + dxW,       0.0],
                                [hbX + dxW,       hbY,             0.0],
                                [hbX + dxL + dxW, hbY + dxL,       0.0],
                                [hbX + dxL,       hbY + dxL + dxW, 0.0]
                            )
                            baseAng = 45.0
                        )
                        else
                        (
                            local hbYOdd = hbY - dGap
                            quad = #(
                                [hbX + dxW,       hbYOdd + dxL,       0.0],
                                [hbX,             hbYOdd + dxL - dxW, 0.0],
                                [hbX + dxL,       hbYOdd - dxW,       0.0],
                                [hbX + dxL + dxW, hbYOdd,             0.0]
                            )
                            baseAng = -45.0
                        )
                        this.processBoardPoly quad baseAng maxL maxW \
                            bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                            cfg sc maxL maxW uvSpanL uvSpanW availGapW availGapL \
                            clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                            minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                            &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx
                    )
                    colIdx += 1
                    xCursor += colStepX
                )
                yCursor += rowStepY
            )
        )
        else if pat == 3 then -- CHEVRON
        (
            local ang = amax 1.0 (amin 85.0 cfg.ChevronAngle)
            local cosA = cos ang
            local sinA = sin ang
            local dx = maxL * cosA
            local dy = maxL * sinA
            local hY = maxW / cosA
            local stepX = dx + gapL
            local stepY = hY + (gapW / cosA)

            local yCursor = -hY - dy - gapW - (mod offObjY stepY)
            local yLimit  = bbSpanY + hY + dy + gapW
            local xStart  = -(mod offObjX (2.0 * stepX)) - stepX
            local xLimit  = bbSpanX + stepX

            while yCursor < yLimit do
            (
                local colIdx = 0
                local xCursor = xStart
                while xCursor < xLimit do
                (
                    local isRight = ((mod colIdx 2) != 0)
                    local x0 = bbMinX + xCursor
                    local y0 = bbMinY + yCursor
                    local quad = undefined
                    local baseAng = ang
                    if not isRight then
                    (
                        quad = #(
                            [x0,      y0 + dy,      0.0],
                            [x0 + dx, y0,           0.0],
                            [x0 + dx, y0 + hY,      0.0],
                            [x0,      y0 + dy + hY, 0.0]
                        )
                        baseAng = -ang
                    )
                    else
                    (
                        quad = #(
                            [x0,      y0,           0.0],
                            [x0 + dx, y0 + dy,      0.0],
                            [x0 + dx, y0 + dy + hY, 0.0],
                            [x0,      y0 + hY,      0.0]
                        )
                        baseAng = ang
                    )
                    this.processBoardPoly quad baseAng maxL maxW \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc maxL maxW uvSpanL uvSpanW availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx

                    colIdx += 1
                    xCursor += stepX
                )
                yCursor += stepY
            )
        )
        else if pat == 4 then -- BASKET WEAVE
        (
            local nSub = amax 1 cfg.BasketWeaveSubBoards
            local subW = (maxL - (nSub - 1) * gapL) / (nSub as float)
            local subStep = subW + gapL
            local blockStep = maxL + gapL

            local yCursor = -blockStep - (mod offObjY (2.0 * blockStep))
            local yLimit  = bbSpanY + blockStep
            local xStart  = -blockStep - (mod offObjX (2.0 * blockStep))
            local xLimit  = bbSpanX + blockStep
            local rowIdx  = 0

            while yCursor < yLimit do
            (
                local colIdx = 0
                local xCursor = xStart
                while xCursor < xLimit do
                (
                    local isVert = ((mod (rowIdx + colIdx) 2) != 0)
                    for sIdx = 0 to (nSub - 1) do
                    (
                        local sOff = (sIdx as float) * subStep
                        local x0 = bbMinX + xCursor
                        local y0 = bbMinY + yCursor
                        local quad = undefined
                        local baseAng = 0.0
                        if not isVert then
                        (
                            quad = #(
                                [x0,        y0 + sOff,        0.0],
                                [x0 + maxL, y0 + sOff,        0.0],
                                [x0 + maxL, y0 + sOff + subW, 0.0],
                                [x0,        y0 + sOff + subW, 0.0]
                            )
                            baseAng = 0.0
                        )
                        else
                        (
                            quad = #(
                                [x0 + sOff,        y0,        0.0],
                                [x0 + sOff + subW, y0,        0.0],
                                [x0 + sOff + subW, y0 + maxL, 0.0],
                                [x0 + sOff,        y0 + maxL, 0.0]
                            )
                            baseAng = 90.0
                        )
                        this.processBoardPoly quad baseAng maxL subW \
                            bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                            cfg sc maxL subW uvSpanL uvSpanW availGapW availGapL \
                            clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                            minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                            &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx
                    )
                    colIdx += 1
                    xCursor += blockStep
                )
                rowIdx += 1
                yCursor += blockStep
            )
        )
        else if pat == 5 then -- HEXAGON
        (
            local rad = maxL
            local dx  = rad * 0.8660254
            local dy  = rad * 0.5
            local stepX = 2.0 * dx + gapL
            local stepY = 1.5 * rad + gapL * 0.8660254

            local yCursor = -rad - gapL - (mod offObjY (2.0 * stepY))
            local yLimit  = bbSpanY + rad + gapL
            local xStart  = -dx - gapL - (mod offObjX stepX)
            local xLimit  = bbSpanX + dx + gapL
            local rowIdx  = 0

            while yCursor < yLimit do
            (
                local isOdd = ((mod rowIdx 2) != 0)
                local xCursor = if isOdd then (xStart - (dx + gapL * 0.5)) else xStart
                while xCursor < xLimit do
                (
                    local cx = bbMinX + xCursor
                    local cy = bbMinY + yCursor
                    local hexPoly = #(
                        [cx - dx, cy + dy,  0.0],
                        [cx - dx, cy - dy,  0.0],
                        [cx,      cy - rad, 0.0],
                        [cx + dx, cy - dy,  0.0],
                        [cx + dx, cy + dy,  0.0],
                        [cx,      cy + rad, 0.0]
                    )
                    this.processBoardPoly hexPoly 0.0 (rad * 2.0) (rad * 2.0) \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc (rad * 2.0) (rad * 2.0) uvSpanL uvSpanW availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx

                    xCursor += stepX
                )
                rowIdx += 1
                yCursor += stepY
            )
        )
        else if pat == 6 then -- TRIANGLE
        (
            local side = maxL
            local halfSide = side * 0.5
            local triH = side * 0.8660254
            -- True equilateral lattice inset by gapL/2 on all 3 sides so 0, +60, and -60 deg grout lines are all straight:
            -- Grid side L_grid = side + sqrt(3)*gapL, row height S_y = triH + 1.5*gapL, down-triangle Y shift = +0.5*gapL
            local stepX = side + gapL * 1.7320508
            local halfStepX = stepX * 0.5
            local stepY = triH + gapL * 1.5
            local downShiftY = gapL * 0.5

            local yCursor = -triH - gapL * 2.0 - (mod offObjY (2.0 * stepY))
            local yLimit  = bbSpanY + triH + gapL * 2.0
            local xStart  = -stepX - (mod offObjX stepX)
            local xLimit  = bbSpanX + stepX
            local rowIdx  = 0

            while yCursor < yLimit do
            (
                local isOddRow = ((mod rowIdx 2) != 0)
                local xCursor = if isOddRow then (xStart + halfStepX) else xStart
                local yUp = bbMinY + yCursor
                local yDn = yUp + downShiftY

                while xCursor < xLimit do
                (
                    -- 1. Up-pointing triangle (base at yUp, apex at yUp + triH)
                    local cxUp = bbMinX + xCursor
                    local triUp = #(
                        [cxUp - halfSide, yUp,        0.0],
                        [cxUp + halfSide, yUp,        0.0],
                        [cxUp,            yUp + triH, 0.0]
                    )
                    this.processBoardPoly triUp 0.0 side triH \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc side triH uvSpanL uvSpanW availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx

                    -- 2. Down-pointing triangle (shifted up by 0.5*gapL so all 60-deg edges align across rows)
                    local cxDn = cxUp + halfStepX
                    local triDn = #(
                        [cxDn,            yDn,        0.0],
                        [cxDn + halfSide, yDn + triH, 0.0],
                        [cxDn - halfSide, yDn + triH, 0.0]
                    )
                    this.processBoardPoly triDn 180.0 side triH \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc side triH uvSpanL uvSpanW availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx

                    xCursor += stepX
                )
                rowIdx += 1
                yCursor += stepY
            )
        )
        else if pat == 7 do -- OCTAGON (Main Octagon Tile [MatID=1] + Rotated Diamond Insert [MatID=2])
        (
            local tileL = maxL
            local tileW = if cfg.Width_L then maxL else maxW
            local minTileDim = amin tileL tileW
            local k45 = 0.70710678
            -- Clamp Insert Size so the 45-deg chamfer never exceeds 45% of the main tile side (preventing overlap/ugly geometry)
            local maxChamfer = minTileDim * 0.45
            local maxAllowedInsDiag = amax 0.0 (maxChamfer - 1.41421356 * gapL + 0.5 * (gapL + gapW))
            local maxAllowedInsSide = maxAllowedInsDiag / k45
            local insSide = amax 0.0 (amin ((amax 0.0 cfg.OctagonInsertSize) * sc) maxAllowedInsSide)
            local insHalfDiag = insSide * k45

            local stepX = tileL + gapL
            local stepY = tileW + gapW

            -- Exact 45-deg chamfer leg on main tile so perpendicular gap to diamond insert equals gapL
            local rawChamfer = if insSide > 1e-4 then (insHalfDiag + 1.41421356 * gapL - 0.5 * (gapL + gapW)) else 0.0
            local c = amax 0.0 (amin maxChamfer rawChamfer)

            local yCursor = -stepY - (mod offObjY stepY)
            local yLimit  = bbSpanY + stepY
            local xStart  = -stepX - (mod offObjX stepX)
            local xLimit  = bbSpanX + stepX

            while yCursor < yLimit do
            (
                local xCursor = xStart
                local y0 = bbMinY + yCursor
                while xCursor < xLimit do
                (
                    local x0 = bbMinX + xCursor

                    -- 1. Main Octagon Tile (MatID = 1)
                    local octPoly = if c > 1e-4 then
                    #(
                        [x0 + c,         y0,             0.0],
                        [x0 + tileL - c, y0,             0.0],
                        [x0 + tileL,     y0 + c,         0.0],
                        [x0 + tileL,     y0 + tileW - c, 0.0],
                        [x0 + tileL - c, y0 + tileW,     0.0],
                        [x0 + c,         y0 + tileW,     0.0],
                        [x0,             y0 + tileW - c, 0.0],
                        [x0,             y0 + c,         0.0]
                    )
                    else
                    #(
                        [x0,         y0,         0.0],
                        [x0 + tileL, y0,         0.0],
                        [x0 + tileL, y0 + tileW, 0.0],
                        [x0,         y0 + tileW, 0.0]
                    )

                    this.processBoardPoly octPoly 0.0 tileL tileW \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc tileL tileW tileL tileW availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx fixedMatID:1

                    -- 2. Diamond Insert at top-right corner intersection (MatID = 2)
                    if insHalfDiag > 1e-4 do
                    (
                        local nx = x0 + tileL + 0.5 * gapL
                        local ny = y0 + tileW + 0.5 * gapW
                        local diaPoly = #(
                            [nx,               ny - insHalfDiag, 0.0],
                            [nx + insHalfDiag, ny,               0.0],
                            [nx,               ny + insHalfDiag, 0.0],
                            [nx - insHalfDiag, ny,               0.0]
                        )
                        this.processBoardPoly diaPoly 45.0 insSide insSide \
                            bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                            cfg sc insSide insSide insSide insSide availGapW availGapL \
                            clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                            minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                            &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis bctx:bctx fixedMatID:2
                    )

                    xCursor += stepX
                )
                yCursor += stepY
            )
        )

        -- 5a. Border Standard Tile ring pass (tiles of BorderTileSize inside the border frame only)
        if bctx.active and bctx.hasValidFrame and cfg.BorderPattern == 2 do
        (
            local bTile = (amax 0.1 cfg.BorderTileSize) * sc
            local stepX = bTile + gapL
            local stepY = bTile + gapW
            local yCursor = -stepY - (mod offObjY stepY)
            local yLimit  = bbSpanY + stepY
            local xStart  = -stepX - (mod offObjX stepX)
            local xLimit  = bbSpanX + stepX
            local bMatID  = amax 1 (cfg.BorderMatID as integer)

            while yCursor < yLimit do
            (
                local xCursor = xStart
                local y0 = bbMinY + yCursor
                while xCursor < xLimit do
                (
                    local x0 = bbMinX + xCursor
                    local quad = #(
                        [x0,         y0,         0.0],
                        [x0 + bTile, y0,         0.0],
                        [x0 + bTile, y0 + bTile, 0.0],
                        [x0,         y0 + bTile, 0.0]
                    )
                    this.processBoardPoly quad 0.0 bTile bTile \
                        bbMinX bbMinY bbMaxX bbMaxY isRectangularFootprint baseTris \
                        cfg sc bTile bTile bTile bTile availGapW availGapL \
                        clampOffXMin clampOffXMax offXSpr clampOffYMin clampOffYMax offYSpr \
                        minTilt maxTilt tiltSpr extrudeH bevelH outlineW dirPostTM \
                        &boardIdx outVerts outFaces outTVerts outMatIDs outSmGroups outEdgeVis \
                        bctx:bctx fixedMatID:bMatID ringOnly:true
                    xCursor += stepX
                )
                yCursor += stepY
            )
        )

        if outFaces.count == 0 do return false

        -- 5b. Ultra-Lightweight Grout Mesh (Single Base Footprint Layer)
        if cfg.DoGrout and (gapL > 1e-5 or gapW > 1e-5) do
        (
            local effExtrude = if cfg.DoExtrude then extrudeH else 0.0
            local effBevel   = if cfg.DoBevel then bevelH else 0.0
            local zBoardTop  = effExtrude + effBevel
            local gDepth     = amax 0.0 (cfg.GroutDepth * sc)
            local zGroutTop  = amax 0.0 (zBoardTop - gDepth)
            local gMatID     = amax 1 (cfg.GroutMatID as integer)
            local invSpanX   = if bbSpanX > 1e-5 then (1.0 / bbSpanX) else 1.0
            local invSpanY   = if bbSpanY > 1e-5 then (1.0 / bbSpanY) else 1.0

            -- Add top grout surface vertices mapped 1:1 from baseVerts2D
            local gTopStart = outVerts.count
            for v = 1 to numBaseVerts do
            (
                local p2d = baseVerts2D[v]
                local u = (p2d.x - bbMinX) * invSpanX
                local vCoord = (p2d.y - bbMinY) * invSpanY
                local wp = [p2d.x, p2d.y, zGroutTop]
                if dirPostTM != undefined do wp = wp * dirPostTM
                append outVerts wp
                append outTVerts [u, vCoord, zGroutTop]
            )

            -- Emit original base footprint triangles at zGroutTop (+2 faces for a rectangular room!)
            for f = 1 to ioMesh.numFaces do
            (
                local fv = getFace ioMesh f
                local p1 = baseVerts2D[fv.x]
                local p2 = baseVerts2D[fv.y]
                local p3 = baseVerts2D[fv.z]
                local a2 = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
                if abs a2 > 1e-5 do
                (
                    local v1 = gTopStart + (fv.x as integer)
                    local v2 = gTopStart + (fv.y as integer)
                    local v3 = gTopStart + (fv.z as integer)
                    local ev1 = getEdgeVis ioMesh f 1
                    local ev2 = getEdgeVis ioMesh f 2
                    local ev3 = getEdgeVis ioMesh f 3
                    if a2 > 0.0 then
                    (
                        append outFaces [v1, v2, v3]
                        append outEdgeVis #(ev1, ev2, ev3)
                    )
                    else
                    (
                        append outFaces [v1, v3, v2]
                        append outEdgeVis #(ev3, ev2, ev1)
                    )
                    append outMatIDs gMatID
                    append outSmGroups 8
                )
            )
        )

        -- 6. Transform back
        fromPlaneTM.row4 = planeOffset
        for i = 1 to outVerts.count do
            outVerts[i] = outVerts[i] * fromPlaneTM

        -- 7. Populate TriMesh
        setMesh ioMesh verts:outVerts faces:outFaces

        for f = 1 to outFaces.count do
        (
            setFaceMatID ioMesh f outMatIDs[f]
            setFaceSmoothGroup ioMesh f outSmGroups[f]
            local ev = outEdgeVis[f]
            setEdgeVis ioMesh f 1 ev[1]
            setEdgeVis ioMesh f 2 ev[2]
            setEdgeVis ioMesh f 3 ev[3]
        )

        -- 8. UVW Channel
        local uvCh = amax 1 (amin 99 cfg.UVChannel)
        if (meshop.getNumMaps ioMesh) < (uvCh + 1) do
            meshop.setNumMaps ioMesh (uvCh + 1) keep:false
        meshop.setMapSupport ioMesh uvCh true
        meshop.setNumMapVerts ioMesh uvCh outTVerts.count keep:false
        meshop.setNumMapFaces ioMesh uvCh outFaces.count keep:false
        for v = 1 to outTVerts.count do
            meshop.setMapVert ioMesh uvCh v outTVerts[v]
        for f = 1 to outFaces.count do
            meshop.setMapFace ioMesh uvCh f outFaces[f]

        -- 9. Optional Weld
        if cfg.DoWeld and cfg.Weld > 0.0 do
            meshop.weldVertsByThreshold ioMesh #{1..ioMesh.numVerts} (cfg.Weld * sc)

        update ioMesh
        true
    ),

    -- 7. Preset INI Handling
    fn readIniFloat f s k def =
    (
        local v = getINISetting f s k
        if v != "" then (v as float) else def
    ),

    fn readIniInt f s k def =
    (
        local v = getINISetting f s k
        if v != "" then (v as integer) else def
    ),

    fn readIniBool f s k def =
    (
        local v = getINISetting f s k
        if v != "" then ((v as integer) != 0) else def
    ),

    fn savePresetIni cfg filePath =
    (
        if filePath == undefined or filePath == "" do return false
        local sec = "Params"
        local patCode = case cfg.FloorPattern of
        (
            1: 2
            2: 4
            3: 8
            4: 16
            5: 32
            6: 64
            7: 128
            default: 2
        )
        setINISetting filePath sec "FloorPattern" (patCode as string)
        setINISetting filePath sec "HerringboneParallels" (cfg.HerringboneParallels as string)
        setINISetting filePath sec "ChevronAngle" ((degToRad cfg.ChevronAngle) as string)
        setINISetting filePath sec "BasketWeaveSubBoards" (cfg.BasketWeaveSubBoards as string)
        setINISetting filePath sec "OctagonInsertSize" (cfg.OctagonInsertSize as string)

        setINISetting filePath sec "Length" (cfg.Length as string)
        setINISetting filePath sec "Length_L" (if cfg.Length_L then "1" else "0")
        setINISetting filePath sec "Length_R" (cfg.Length_R as string)
        setINISetting filePath sec "Length_S" (cfg.Length_S as string)

        setINISetting filePath sec "Width" (cfg.Width as string)
        setINISetting filePath sec "Width_L" (if cfg.Width_L then "1" else "0")
        setINISetting filePath sec "Width_R" (cfg.Width_R as string)
        setINISetting filePath sec "Width_S" (cfg.Width_S as string)

        setINISetting filePath sec "GroutLength" (cfg.GroutLength as string)
        setINISetting filePath sec "GroutWidth" (cfg.GroutWidth as string)
        setINISetting filePath sec "Grout_L" (if cfg.Grout_L then "1" else "0")

        setINISetting filePath sec "MinRowOffset" ((cfg.MinRowOffset * 0.01) as string)
        setINISetting filePath sec "MaxRowOffset" ((cfg.MaxRowOffset * 0.01) as string)
        setINISetting filePath sec "RowOffset_L" (if cfg.RowOffset_L then "1" else "0")

        setINISetting filePath sec "DoExtrude" (if cfg.DoExtrude then "1" else "0")
        setINISetting filePath sec "Extrude" (cfg.Extrude as string)
        setINISetting filePath sec "DoBevel" (if cfg.DoBevel then "1" else "0")
        setINISetting filePath sec "Bevel" (cfg.Bevel as string)
        setINISetting filePath sec "BevelL" (if cfg.BevelL then "1" else "0")
        setINISetting filePath sec "Outline" (cfg.Outline as string)
        setINISetting filePath sec "DoGrout" (if cfg.DoGrout then "1" else "0")
        setINISetting filePath sec "GroutDepth" (cfg.GroutDepth as string)
        setINISetting filePath sec "GroutMatID" (cfg.GroutMatID as string)

        setINISetting filePath sec "DoBorder" (if cfg.DoBorder then "1" else "0")
        setINISetting filePath sec "BorderWidth" (cfg.BorderWidth as string)
        setINISetting filePath sec "BorderOffset" (cfg.BorderOffset as string)
        setINISetting filePath sec "BorderPattern" (cfg.BorderPattern as string)
        setINISetting filePath sec "BorderTileSize" (cfg.BorderTileSize as string)
        setINISetting filePath sec "BorderCutMode" (cfg.BorderCutMode as string)
        setINISetting filePath sec "BorderMatID" (cfg.BorderMatID as string)
        setINISetting filePath sec "BorderOffBot" (cfg.BorderOffBot as string)
        setINISetting filePath sec "BorderOffTop" (cfg.BorderOffTop as string)
        setINISetting filePath sec "BorderOffLeft" (cfg.BorderOffLeft as string)
        setINISetting filePath sec "BorderOffRight" (cfg.BorderOffRight as string)

        setINISetting filePath sec "MaxRotation" ((cfg.MaxRotation * 0.01) as string)
        setINISetting filePath sec "Rotation_R" ((cfg.Rotation_R * 0.01) as string)
        setINISetting filePath sec "RotationSpread" (cfg.RotationSpread as string)

        setINISetting filePath sec "Offset_X" (cfg.Offset_X as string)
        setINISetting filePath sec "Offset_X_R" (cfg.Offset_X_R as string)
        setINISetting filePath sec "Offset_X_S" (cfg.Offset_X_S as string)
        setINISetting filePath sec "Offset_Y" (cfg.Offset_Y as string)
        setINISetting filePath sec "Offset_Y_R" (cfg.Offset_Y_R as string)
        setINISetting filePath sec "Offset_Y_S" (cfg.Offset_Y_S as string)
        setINISetting filePath sec "Offset_L" (if cfg.Offset_L then "1" else "0")

        setINISetting filePath sec "Tilt" (cfg.Tilt as string)
        setINISetting filePath sec "Tilt_R" (cfg.Tilt_R as string)
        setINISetting filePath sec "Tilt_S" (cfg.Tilt_S as string)
        setINISetting filePath sec "MaxOverlap" (cfg.MaxOverlap as string)

        setINISetting filePath sec "Scale" ((cfg.Scale * 0.01) as string)
        setINISetting filePath sec "Direction" ((degToRad cfg.Direction) as string)
        setINISetting filePath sec "Seed" (cfg.Seed as string)
        setINISetting filePath sec "ObjOffsetX" (cfg.ObjOffsetX as string)
        setINISetting filePath sec "ObjOffsetY" (cfg.ObjOffsetY as string)
        setINISetting filePath sec "DoWeld" (if cfg.DoWeld then "1" else "0")
        setINISetting filePath sec "Weld" (cfg.Weld as string)

        setINISetting filePath sec "UVChannel" (cfg.UVChannel as string)
        setINISetting filePath sec "FlipU" (if cfg.FlipU then "1" else "0")
        setINISetting filePath sec "FlipV" (if cfg.FlipV then "1" else "0")
        setINISetting filePath sec "RandomOffsetU" (if cfg.RandomOffsetU then "1" else "0")
        setINISetting filePath sec "RandomOffsetV" (if cfg.RandomOffsetV then "1" else "0")
        setINISetting filePath sec "WarnMaxBoard" (cfg.WarnMaxBoard as string)
        true
    ),

    fn loadPresetIni cfg filePath =
    (
        if filePath == undefined or not (doesFileExist filePath) do return false
        local sec = "Params"

        local patRaw = this.readIniInt filePath sec "FloorPattern" 2
        cfg.FloorPattern = case patRaw of
        (
            2: 1
            4: 2
            8: 3
            16: 4
            32: 5
            64: 6
            128: 7
            default: (amax 1 (amin 7 patRaw))
        )
        cfg.HerringboneParallels = this.readIniInt filePath sec "HerringboneParallels" cfg.HerringboneParallels
        local chv = this.readIniFloat filePath sec "ChevronAngle" 0.785398
        cfg.ChevronAngle = if chv <= 3.15 then (radToDeg chv) else chv
        cfg.BasketWeaveSubBoards = this.readIniInt filePath sec "BasketWeaveSubBoards" cfg.BasketWeaveSubBoards
        cfg.OctagonInsertSize = this.readIniFloat filePath sec "OctagonInsertSize" cfg.OctagonInsertSize

        cfg.Length    = this.readIniFloat filePath sec "Length" cfg.Length
        cfg.Length_L  = this.readIniBool filePath sec "Length_L" cfg.Length_L
        cfg.Length_R  = this.readIniFloat filePath sec "Length_R" cfg.Length_R
        cfg.Length_S  = this.readIniFloat filePath sec "Length_S" cfg.Length_S

        cfg.Width     = this.readIniFloat filePath sec "Width" cfg.Width
        cfg.Width_L   = this.readIniBool filePath sec "Width_L" cfg.Width_L
        cfg.Width_R   = this.readIniFloat filePath sec "Width_R" cfg.Width_R
        cfg.Width_S   = this.readIniFloat filePath sec "Width_S" cfg.Width_S

        cfg.GroutLength = this.readIniFloat filePath sec "GroutLength" cfg.GroutLength
        cfg.GroutWidth  = this.readIniFloat filePath sec "GroutWidth" cfg.GroutWidth
        cfg.Grout_L     = this.readIniBool filePath sec "Grout_L" cfg.Grout_L

        cfg.MinRowOffset = (this.readIniFloat filePath sec "MinRowOffset" (cfg.MinRowOffset * 0.01)) * 100.0
        cfg.MaxRowOffset = (this.readIniFloat filePath sec "MaxRowOffset" (cfg.MaxRowOffset * 0.01)) * 100.0
        cfg.RowOffset_L  = this.readIniBool filePath sec "RowOffset_L" cfg.RowOffset_L

        cfg.DoExtrude = this.readIniBool filePath sec "DoExtrude" cfg.DoExtrude
        cfg.Extrude   = this.readIniFloat filePath sec "Extrude" cfg.Extrude
        cfg.DoBevel   = this.readIniBool filePath sec "DoBevel" cfg.DoBevel
        cfg.Bevel     = this.readIniFloat filePath sec "Bevel" cfg.Bevel
        cfg.BevelL    = this.readIniBool filePath sec "BevelL" cfg.BevelL
        cfg.Outline   = this.readIniFloat filePath sec "Outline" cfg.Outline
        cfg.DoGrout    = this.readIniBool filePath sec "DoGrout" cfg.DoGrout
        cfg.GroutDepth = this.readIniFloat filePath sec "GroutDepth" cfg.GroutDepth
        cfg.GroutMatID = this.readIniInt filePath sec "GroutMatID" cfg.GroutMatID

        cfg.DoBorder       = this.readIniBool filePath sec "DoBorder" cfg.DoBorder
        cfg.BorderWidth    = this.readIniFloat filePath sec "BorderWidth" cfg.BorderWidth
        cfg.BorderOffset   = this.readIniFloat filePath sec "BorderOffset" cfg.BorderOffset
        cfg.BorderPattern  = amax 1 (amin 2 (this.readIniInt filePath sec "BorderPattern" cfg.BorderPattern))
        cfg.BorderTileSize = this.readIniFloat filePath sec "BorderTileSize" cfg.BorderTileSize
        cfg.BorderCutMode  = amax 1 (amin 2 (this.readIniInt filePath sec "BorderCutMode" cfg.BorderCutMode))
        cfg.BorderMatID    = this.readIniInt filePath sec "BorderMatID" cfg.BorderMatID
        cfg.BorderOffBot   = this.readIniFloat filePath sec "BorderOffBot" cfg.BorderOffBot
        cfg.BorderOffTop   = this.readIniFloat filePath sec "BorderOffTop" cfg.BorderOffTop
        cfg.BorderOffLeft  = this.readIniFloat filePath sec "BorderOffLeft" cfg.BorderOffLeft
        cfg.BorderOffRight = this.readIniFloat filePath sec "BorderOffRight" cfg.BorderOffRight

        cfg.MaxRotation    = (this.readIniFloat filePath sec "MaxRotation" (cfg.MaxRotation * 0.01)) * 100.0
        cfg.Rotation_R     = (this.readIniFloat filePath sec "Rotation_R" (cfg.Rotation_R * 0.01)) * 100.0
        cfg.RotationSpread = this.readIniFloat filePath sec "RotationSpread" cfg.RotationSpread

        cfg.Offset_X   = this.readIniFloat filePath sec "Offset_X" cfg.Offset_X
        cfg.Offset_X_R = this.readIniFloat filePath sec "Offset_X_R" cfg.Offset_X_R
        cfg.Offset_X_S = this.readIniFloat filePath sec "Offset_X_S" cfg.Offset_X_S
        cfg.Offset_Y   = this.readIniFloat filePath sec "Offset_Y" cfg.Offset_Y
        cfg.Offset_Y_R = this.readIniFloat filePath sec "Offset_Y_R" cfg.Offset_Y_R
        cfg.Offset_Y_S = this.readIniFloat filePath sec "Offset_Y_S" cfg.Offset_Y_S
        cfg.Offset_L   = this.readIniBool filePath sec "Offset_L" cfg.Offset_L

        cfg.Tilt       = this.readIniFloat filePath sec "Tilt" cfg.Tilt
        cfg.Tilt_R     = this.readIniFloat filePath sec "Tilt_R" cfg.Tilt_R
        cfg.Tilt_S     = this.readIniFloat filePath sec "Tilt_S" cfg.Tilt_S
        cfg.MaxOverlap = this.readIniFloat filePath sec "MaxOverlap" cfg.MaxOverlap

        cfg.Scale      = (this.readIniFloat filePath sec "Scale" (cfg.Scale * 0.01)) * 100.0
        cfg.Direction  = radToDeg (this.readIniFloat filePath sec "Direction" (degToRad cfg.Direction))
        cfg.Seed       = this.readIniInt filePath sec "Seed" cfg.Seed
        cfg.ObjOffsetX = this.readIniFloat filePath sec "ObjOffsetX" cfg.ObjOffsetX
        cfg.ObjOffsetY = this.readIniFloat filePath sec "ObjOffsetY" cfg.ObjOffsetY
        cfg.DoWeld     = this.readIniBool filePath sec "DoWeld" cfg.DoWeld
        cfg.Weld       = this.readIniFloat filePath sec "Weld" cfg.Weld

        cfg.UVChannel     = this.readIniInt filePath sec "UVChannel" cfg.UVChannel
        cfg.FlipU         = this.readIniBool filePath sec "FlipU" cfg.FlipU
        cfg.FlipV         = this.readIniBool filePath sec "FlipV" cfg.FlipV
        cfg.RandomOffsetU = this.readIniBool filePath sec "RandomOffsetU" cfg.RandomOffsetU
        cfg.RandomOffsetV = this.readIniBool filePath sec "RandomOffsetV" cfg.RandomOffsetV
        cfg.WarnMaxBoard  = this.readIniInt filePath sec "WarnMaxBoard" cfg.WarnMaxBoard
        true
    )
)

FGv2_Engine = FGv2_EngineStruct()


-- =============================================================================
-- PART A: 3ds Max Modifier Plugin ("FloorGenerator v2")
--         1:1 Original Multi-Rollout UI with Collapsible Tabs & [L] Buttons
-- =============================================================================
plugin simpleMeshMod FloorGenerator_v2
    name:"FloorGenerator v2.1"
    classID:#(0x46477632, 0x20270002)
    version:3
(
    local cachedMesh = undefined
    local forceRefresh = false
    local lockHighlightCol = color 105 162 225

    parameters pPattern rollout:rolFG_Pattern
    (
        FloorPattern         type:#integer    default:1     animatable:false ui:ddPattern
        HerringboneParallels type:#integer    default:1     animatable:true  ui:spnParallels
        ChevronAngle         type:#float      default:45.0  animatable:true  ui:spnChevronAngle
        BasketWeaveSubBoards type:#integer    default:3     animatable:true  ui:spnSubBoards
        OctagonInsertSize    type:#worldUnits default:200.0 animatable:true  ui:spnInsertSize

        on FloorPattern set val do this.refreshAllRollouts()
    )

    parameters pBoardSize rollout:rolFG_BoardSize
    (
        Length               type:#worldUnits default:1000.0 animatable:true  ui:spnLength
        Length_L             type:#boolean    default:true   animatable:false ui:btnLockLength
        Length_R             type:#worldUnits default:1000.0 animatable:true  ui:spnLengthR
        Length_S             type:#float      default:0.5    animatable:true  ui:spnLengthS

        Width                type:#worldUnits default:70.0   animatable:true  ui:spnWidth
        Width_L              type:#boolean    default:true   animatable:false ui:btnLockWidth
        Width_R              type:#worldUnits default:70.0   animatable:true  ui:spnWidthR
        Width_S              type:#float      default:0.5    animatable:true  ui:spnWidthS

        GroutLength          type:#worldUnits default:0.2    animatable:true  ui:spnGroutL
        GroutWidth           type:#worldUnits default:0.2    animatable:true  ui:spnGroutW
        Grout_L              type:#boolean    default:true   animatable:false ui:btnLockGrout

        MinRowOffset         type:#float      default:20.0   animatable:true  ui:spnMinRowOff
        MaxRowOffset         type:#float      default:20.0   animatable:true  ui:spnMaxRowOff
        RowOffset_L          type:#boolean    default:true   animatable:false ui:btnLockRowOff

        DoExtrude            type:#boolean    default:true   animatable:false ui:chkDoExtrude
        Extrude              type:#worldUnits default:1.0    animatable:true  ui:spnExtrude
        DoBevel              type:#boolean    default:true   animatable:false ui:chkDoBevel
        Bevel                type:#worldUnits default:0.5    animatable:true  ui:spnBevel
        BevelL               type:#boolean    default:true   animatable:false ui:btnLockOutline
        Outline              type:#worldUnits default:0.5    animatable:true  ui:spnOutline

        DoGrout              type:#boolean    default:false  animatable:false ui:chkDoGrout
        GroutDepth           type:#worldUnits default:0.5    animatable:true  ui:spnGroutDepth
        GroutMatID           type:#integer    default:3      animatable:false ui:spnGroutMatID

        on Length set val do
        (
            if Length_L do Length_R = val
            if FloorPattern == 7 do
            (
                local minDim = if Width_L then val else (amin val Width)
                local maxIns = amax 0.0 ((minDim * 0.45 - 1.41421356 * GroutLength + 0.5 * (GroutLength + GroutWidth)) * 1.41421356)
                if OctagonInsertSize > maxIns do OctagonInsertSize = maxIns
                this.refreshAllRollouts()
            )
        )
        on Width set val do
        (
            if Width_L do Width_R = val
            if FloorPattern == 7 and (not Width_L) do
            (
                local minDim = amin Length val
                local maxIns = amax 0.0 ((minDim * 0.45 - 1.41421356 * GroutLength + 0.5 * (GroutLength + GroutWidth)) * 1.41421356)
                if OctagonInsertSize > maxIns do OctagonInsertSize = maxIns
                this.refreshAllRollouts()
            )
        )
        on GroutLength set val do (if Grout_L do GroutWidth = val)
        on MinRowOffset set val do (if RowOffset_L do MaxRowOffset = val)
        on Bevel set val do (if BevelL do Outline = val)
    )

    parameters pBorder rollout:rolFG_Border
    (
        DoBorder       type:#boolean    default:false animatable:false ui:chkDoBorder
        BorderWidth    type:#worldUnits default:100.0 animatable:true  ui:spnBorderWidth
        BorderOffset   type:#worldUnits default:200.0 animatable:true  ui:spnBorderOffset
        BorderPattern  type:#integer    default:1     animatable:false ui:ddBorderPat
        BorderTileSize type:#worldUnits default:600.0 animatable:true  ui:spnBorderTileSize
        BorderCutMode  type:#integer    default:1     animatable:false ui:ddBorderCut
        BorderMatID    type:#integer    default:4     animatable:false ui:spnBorderMatID
        BorderOffBot   type:#worldUnits default:0.0   animatable:true  ui:spnBorderOffBot
        BorderOffTop   type:#worldUnits default:0.0   animatable:true  ui:spnBorderOffTop
        BorderOffLeft  type:#worldUnits default:0.0   animatable:true  ui:spnBorderOffLeft
        BorderOffRight type:#worldUnits default:0.0   animatable:true  ui:spnBorderOffRight

        on DoBorder set val do this.refreshAllRollouts()
        on BorderPattern set val do this.refreshAllRollouts()
        on BorderCutMode set val do this.refreshAllRollouts()
    )

    parameters pVariation rollout:rolFG_Variation
    (
        MaxRotation          type:#float      default:0.0 animatable:true  ui:spnMaxRot
        Rotation_R           type:#float      default:0.0 animatable:true  ui:spnMinRot
        RotationSpread       type:#float      default:0.5 animatable:true  ui:spnRotS

        Offset_X             type:#worldUnits default:0.0 animatable:true  ui:spnOffX
        Offset_X_R           type:#worldUnits default:0.0 animatable:true  ui:spnOffXR
        Offset_X_S           type:#float      default:0.5 animatable:true  ui:spnOffXS
        Offset_Y             type:#worldUnits default:0.0 animatable:true  ui:spnOffY
        Offset_Y_R           type:#worldUnits default:0.0 animatable:true  ui:spnOffYR
        Offset_Y_S           type:#float      default:0.5 animatable:true  ui:spnOffYS
        Offset_L             type:#boolean    default:true animatable:false ui:btnLockOffset

        Tilt                 type:#worldUnits default:0.0 animatable:true  ui:spnTilt
        Tilt_R               type:#worldUnits default:0.0 animatable:true  ui:spnTiltR
        Tilt_S               type:#float      default:0.5 animatable:true  ui:spnTiltS
        MaxOverlap           type:#worldUnits default:0.0 animatable:true  ui:spnOverlap

        on Offset_X set val do (if Offset_L do Offset_Y = val)
        on Offset_X_R set val do (if Offset_L do Offset_Y_R = val)
        on Offset_X_S set val do (if Offset_L do Offset_Y_S = val)
    )

    parameters pGeneral rollout:rolFG_General
    (
        Scale                type:#float      default:100.0 animatable:true  ui:spnScale
        Direction            type:#float      default:0.0   animatable:true  ui:spnDirection
        Seed                 type:#integer    default:12345 animatable:true  ui:spnSeed
        ObjOffsetX           type:#worldUnits default:0.0   animatable:true  ui:spnObjOffX
        ObjOffsetY           type:#worldUnits default:0.0   animatable:true  ui:spnObjOffY
        DoWeld               type:#boolean    default:false animatable:false ui:chkDoWeld
        Weld                 type:#worldUnits default:0.05  animatable:true  ui:spnWeld
    )

    parameters pUV rollout:rolFG_UV
    (
        UVChannel            type:#integer    default:1    animatable:false ui:spnUVChan
        FlipU                type:#boolean    default:true animatable:false ui:chkFlipU
        FlipV                type:#boolean    default:true animatable:false ui:chkFlipV
        RandomOffsetU        type:#boolean    default:true animatable:false ui:chkRandOffU
        RandomOffsetV        type:#boolean    default:true animatable:false ui:chkRandOffV
    )

    parameters pWarnings rollout:rolFG_Warnings
    (
        WarnMaxBoard         type:#integer    default:10000 animatable:false ui:spnWarnMax
    )

    parameters pUpdate rollout:rolFG_Update
    (
        LiveUpdate           type:#boolean    default:true  animatable:false
    )

    parameters pPresets rollout:rolFG_Presets
    (
    )

    parameters pCredits rollout:rolFG_Credits
    (
    )

    fn makeConfig =
    (
        FGv2_Config \
            FloorPattern:FloorPattern HerringboneParallels:HerringboneParallels \
            ChevronAngle:ChevronAngle BasketWeaveSubBoards:BasketWeaveSubBoards OctagonInsertSize:OctagonInsertSize \
            Length:Length Length_L:Length_L Length_R:Length_R Length_S:Length_S \
            Width:Width Width_L:Width_L Width_R:Width_R Width_S:Width_S \
            GroutLength:GroutLength GroutWidth:GroutWidth Grout_L:Grout_L \
            MinRowOffset:MinRowOffset MaxRowOffset:MaxRowOffset RowOffset_L:RowOffset_L \
            DoExtrude:DoExtrude Extrude:Extrude DoBevel:DoBevel Bevel:Bevel BevelL:BevelL Outline:Outline \
            DoGrout:DoGrout GroutDepth:GroutDepth GroutMatID:GroutMatID \
            DoBorder:DoBorder BorderWidth:BorderWidth BorderOffset:BorderOffset \
            BorderPattern:BorderPattern BorderTileSize:BorderTileSize BorderCutMode:BorderCutMode BorderMatID:BorderMatID \
            BorderOffBot:BorderOffBot BorderOffTop:BorderOffTop BorderOffLeft:BorderOffLeft BorderOffRight:BorderOffRight \
            MaxRotation:MaxRotation Rotation_R:Rotation_R RotationSpread:RotationSpread \
            Offset_X:Offset_X Offset_X_R:Offset_X_R Offset_X_S:Offset_X_S \
            Offset_Y:Offset_Y Offset_Y_R:Offset_Y_R Offset_Y_S:Offset_Y_S Offset_L:Offset_L \
            Tilt:Tilt Tilt_R:Tilt_R Tilt_S:Tilt_S MaxOverlap:MaxOverlap \
            Scale:Scale Direction:Direction Seed:Seed ObjOffsetX:ObjOffsetX ObjOffsetY:ObjOffsetY \
            DoWeld:DoWeld Weld:Weld \
            UVChannel:UVChannel FlipU:FlipU FlipV:FlipV RandomOffsetU:RandomOffsetU RandomOffsetV:RandomOffsetV \
            WarnMaxBoard:WarnMaxBoard LiveUpdate:LiveUpdate
    )

    fn refreshAllRollouts =
    (
        if this.rolFG_Pattern != undefined and this.rolFG_Pattern.open do
        (
            local hasSubParam = (FloorPattern == 2 or FloorPattern == 3 or FloorPattern == 4 or FloorPattern == 7)
            this.rolFG_Pattern.spnParallels.visible    = (FloorPattern == 2)
            this.rolFG_Pattern.spnChevronAngle.visible = (FloorPattern == 3)
            this.rolFG_Pattern.spnSubBoards.visible    = (FloorPattern == 4)
            this.rolFG_Pattern.spnInsertSize.visible   = (FloorPattern == 7)

            if FloorPattern == 7 do
            (
                local minDim = if Width_L then Length else (amin Length Width)
                local maxIns = amax 0.0 ((minDim * 0.45 - 1.41421356 * GroutLength + 0.5 * (GroutLength + GroutWidth)) * 1.41421356)
                this.rolFG_Pattern.spnInsertSize.range = [0.0, amax 0.1 maxIns, amin OctagonInsertSize maxIns]
                if OctagonInsertSize > maxIns do OctagonInsertSize = maxIns
            )

            -- Dynamically resize Floor Pattern rollout so there is no empty space when no sub-parameter is shown
            local targetH = if hasSubParam then 46 else 26
            if this.rolFG_Pattern.height != targetH do
                this.rolFG_Pattern.height = targetH
        )
        if this.rolFG_BoardSize != undefined and this.rolFG_BoardSize.open do
        (
            local isStd = (FloorPattern == 1)
            local isOct = (FloorPattern == 7)
            local hasWidth = (FloorPattern == 1 or FloorPattern == 2 or FloorPattern == 3 or (isOct and not Width_L))
            this.rolFG_BoardSize.btnLockLength.state = Length_L
            this.rolFG_BoardSize.btnLockWidth.state  = Width_L
            this.rolFG_BoardSize.btnLockGrout.state  = Grout_L
            this.rolFG_BoardSize.btnLockRowOff.state = RowOffset_L
            this.rolFG_BoardSize.btnLockOutline.state = BevelL

            this.rolFG_BoardSize.spnLengthR.enabled = isStd and (not Length_L)
            this.rolFG_BoardSize.spnLengthS.enabled = isStd and (not Length_L)
            this.rolFG_BoardSize.btnLockLength.enabled = isStd

            this.rolFG_BoardSize.spnWidth.enabled   = hasWidth
            this.rolFG_BoardSize.spnWidthR.enabled  = isStd and (not Width_L)
            this.rolFG_BoardSize.spnWidthS.enabled  = isStd and (not Width_L)
            this.rolFG_BoardSize.btnLockWidth.enabled = (isStd or isOct)

            this.rolFG_BoardSize.spnGroutW.enabled  = (FloorPattern == 1 or FloorPattern == 3 or isOct) and (not Grout_L)
            this.rolFG_BoardSize.btnLockGrout.enabled = (FloorPattern == 1 or FloorPattern == 3 or isOct)

            this.rolFG_BoardSize.spnMinRowOff.enabled = isStd
            this.rolFG_BoardSize.spnMaxRowOff.enabled = isStd and (not RowOffset_L)
            this.rolFG_BoardSize.btnLockRowOff.enabled = isStd

            this.rolFG_BoardSize.spnExtrude.enabled = DoExtrude
            this.rolFG_BoardSize.spnBevel.enabled   = DoBevel
            this.rolFG_BoardSize.spnOutline.enabled = DoBevel and (not BevelL)
            this.rolFG_BoardSize.btnLockOutline.enabled = DoBevel
            this.rolFG_BoardSize.spnGroutDepth.enabled  = DoGrout
            this.rolFG_BoardSize.spnGroutMatID.enabled  = DoGrout
        )
        if this.rolFG_Border != undefined and this.rolFG_Border.open do
        (
            local bOn = DoBorder
            local bPat = amin 2 (amax 1 (BorderPattern as integer))
            this.rolFG_Border.spnBorderWidth.enabled    = bOn
            this.rolFG_Border.spnBorderOffset.enabled   = bOn
            this.rolFG_Border.lblBorderPat.enabled      = bOn
            this.rolFG_Border.ddBorderPat.enabled       = bOn
            this.rolFG_Border.ddBorderPat.selection     = bPat
            this.rolFG_Border.spnBorderTileSize.enabled = bOn and (bPat == 2)
            this.rolFG_Border.lblBorderCut.enabled      = bOn
            this.rolFG_Border.ddBorderCut.enabled       = bOn
            this.rolFG_Border.ddBorderCut.selection     = amin 2 (amax 1 (BorderCutMode as integer))
            this.rolFG_Border.spnBorderMatID.enabled    = bOn
            this.rolFG_Border.spnBorderOffBot.enabled   = bOn
            this.rolFG_Border.spnBorderOffTop.enabled   = bOn
            this.rolFG_Border.spnBorderOffLeft.enabled  = bOn
            this.rolFG_Border.spnBorderOffRight.enabled = bOn
            this.rolFG_Border.btnBorderReset.enabled    = bOn
        )
        if this.rolFG_Variation != undefined and this.rolFG_Variation.open do
        (
            this.rolFG_Variation.btnLockOffset.state = Offset_L
            this.rolFG_Variation.spnOffY.enabled  = not Offset_L
            this.rolFG_Variation.spnOffYR.enabled = not Offset_L
            this.rolFG_Variation.spnOffYS.enabled = not Offset_L
        )
        if this.rolFG_General != undefined and this.rolFG_General.open do
        (
            this.rolFG_General.spnWeld.enabled = DoWeld
        )
        if this.rolFG_Update != undefined and this.rolFG_Update.open do
        (
            this.rolFG_Update.rbUpdate.state = if LiveUpdate then 1 else 2
            this.rolFG_Update.btnManualUpdate.enabled = not LiveUpdate
        )
    )

    fn applyConfig cfg =
    (
        Length_L = cfg.Length_L
        Width_L = cfg.Width_L
        Grout_L = cfg.Grout_L
        RowOffset_L = cfg.RowOffset_L
        BevelL = cfg.BevelL
        Offset_L = cfg.Offset_L

        FloorPattern = cfg.FloorPattern
        HerringboneParallels = cfg.HerringboneParallels
        ChevronAngle = cfg.ChevronAngle
        BasketWeaveSubBoards = cfg.BasketWeaveSubBoards
        OctagonInsertSize = cfg.OctagonInsertSize
        Length = cfg.Length
        Length_R = cfg.Length_R
        Length_S = cfg.Length_S
        Width = cfg.Width
        Width_R = cfg.Width_R
        Width_S = cfg.Width_S
        GroutLength = cfg.GroutLength
        GroutWidth = cfg.GroutWidth
        MinRowOffset = cfg.MinRowOffset
        MaxRowOffset = cfg.MaxRowOffset
        DoExtrude = cfg.DoExtrude
        Extrude = cfg.Extrude
        DoBevel = cfg.DoBevel
        Bevel = cfg.Bevel
        Outline = cfg.Outline
        DoGrout = cfg.DoGrout
        GroutDepth = cfg.GroutDepth
        GroutMatID = cfg.GroutMatID
        DoBorder = cfg.DoBorder
        BorderWidth = cfg.BorderWidth
        BorderOffset = cfg.BorderOffset
        BorderPattern = cfg.BorderPattern
        BorderTileSize = cfg.BorderTileSize
        BorderCutMode = cfg.BorderCutMode
        BorderMatID = cfg.BorderMatID
        BorderOffBot = cfg.BorderOffBot
        BorderOffTop = cfg.BorderOffTop
        BorderOffLeft = cfg.BorderOffLeft
        BorderOffRight = cfg.BorderOffRight
        MaxRotation = cfg.MaxRotation
        Rotation_R = cfg.Rotation_R
        RotationSpread = cfg.RotationSpread
        Offset_X = cfg.Offset_X
        Offset_X_R = cfg.Offset_X_R
        Offset_X_S = cfg.Offset_X_S
        Offset_Y = cfg.Offset_Y
        Offset_Y_R = cfg.Offset_Y_R
        Offset_Y_S = cfg.Offset_Y_S
        Tilt = cfg.Tilt
        Tilt_R = cfg.Tilt_R
        Tilt_S = cfg.Tilt_S
        MaxOverlap = cfg.MaxOverlap
        Scale = cfg.Scale
        Direction = cfg.Direction
        Seed = cfg.Seed
        ObjOffsetX = cfg.ObjOffsetX
        ObjOffsetY = cfg.ObjOffsetY
        DoWeld = cfg.DoWeld
        Weld = cfg.Weld
        UVChannel = cfg.UVChannel
        FlipU = cfg.FlipU
        FlipV = cfg.FlipV
        RandomOffsetU = cfg.RandomOffsetU
        RandomOffsetV = cfg.RandomOffsetV
        WarnMaxBoard = cfg.WarnMaxBoard
        cachedMesh = undefined
        this.refreshAllRollouts()
    )

    -- 1. Rollout: Floor Pattern
    rollout rolFG_Pattern "Floor Pattern" width:162 height:26
    (
        label lblPat "Floor Pattern" align:#left offset:[-5, 1] across:2
        dropdownList ddPattern "" items:#("Standard", "Herringbone", "Chevron", "Basket Weave", "Hexagon", "Triangle", "Octagon") selection:1 width:82 align:#right offset:[6, -2]
        spinner spnParallels "Parallel Boards " range:[1,100,1] type:#integer fieldwidth:56 pos:[85, 25] visible:false
        spinner spnChevronAngle "Angle " range:[1.0,85.0,45.0] type:#float scale:0.5 fieldwidth:56 pos:[85, 25] visible:false
        spinner spnSubBoards "Sub Boards " range:[1,100,3] type:#integer fieldwidth:56 pos:[85, 25] visible:false
        spinner spnInsertSize "Insert Size " range:[0.0,1e6,200.0] type:#worldUnits fieldwidth:56 pos:[85, 25] visible:false

        on rolFG_Pattern open do this.refreshAllRollouts()
        on ddPattern selected idx do this.refreshAllRollouts()
    )

    -- 2. Rollout: Board Size
    rollout rolFG_BoardSize "Board Size" width:162
    (
        spinner spnLength  "Max Length " range:[0.1,1e6,1000.0] type:#worldUnits fieldwidth:56 align:#right offset:[-12, -2]
        spinner spnLengthR "Min Length " range:[0.1,1e6,1000.0] type:#worldUnits fieldwidth:56 align:#right offset:[-12, -4]
        checkbutton btnLockLength "L" width:13 height:16 align:#right offset:[4, -29] highlightColor:lockHighlightCol toolTip:"Lock Min/Max Length"
        spinner spnLengthS "Spread "     range:[0.0,1.0,0.5]    type:#float scale:0.01 fieldwidth:56 align:#right offset:[-12, 5]

        spinner spnWidth   "Max Width "  range:[0.1,1e6,70.0]   type:#worldUnits fieldwidth:56 align:#right offset:[-12, 3]
        spinner spnWidthR  "Min Width "  range:[0.1,1e6,70.0]   type:#worldUnits fieldwidth:56 align:#right offset:[-12, -4]
        checkbutton btnLockWidth "L" width:13 height:16 align:#right offset:[4, -29] highlightColor:lockHighlightCol toolTip:"Lock Min/Max Width"
        spinner spnWidthS  "Spread "     range:[0.0,1.0,0.5]    type:#float scale:0.01 fieldwidth:56 align:#right offset:[-12, 5]

        spinner spnGroutL  "Grout Len "  range:[0.0,1e5,0.2]    type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, 3]
        spinner spnGroutW  "Grout Wid "  range:[0.0,1e5,0.2]    type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -4]
        checkbutton btnLockGrout "L" width:13 height:16 align:#right offset:[4, -29] highlightColor:lockHighlightCol toolTip:"Lock Grout Length/Width"

        spinner spnMinRowOff "Min Offset % " range:[0.0,100.0,20.0] type:#float fieldwidth:56 align:#right offset:[-12, 12]
        spinner spnMaxRowOff "Max Offset % " range:[0.0,100.0,20.0] type:#float fieldwidth:56 align:#right offset:[-12, -4]
        checkbutton btnLockRowOff "L" width:13 height:16 align:#right offset:[4, -29] highlightColor:lockHighlightCol toolTip:"Lock Min/Max Row Offset %"

        checkbox chkDoExtrude "Extrude" align:#left offset:[-5, 12] checked:true
        spinner spnExtrude "H " range:[0.0,1e5,1.0] type:#worldUnits scale:0.1 fieldwidth:56 align:#right offset:[-12, -20]

        checkbox chkDoBevel "Bevel" align:#left offset:[-5, -4] checked:true
        spinner spnBevel "H " range:[0.0,1e5,0.5] type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -20]

        spinner spnOutline "Outline " range:[0.0,1e5,0.5] type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -4]
        checkbutton btnLockOutline "L" width:13 height:16 align:#right offset:[4, -29] highlightColor:lockHighlightCol toolTip:"Lock Bevel Height / Outline"

        checkbox chkDoGrout "Grout" align:#left offset:[-5, 6] checked:false toolTip:"Generate ultra-lightweight 3D Grout base mesh under gaps"
        spinner spnGroutDepth "Depth " range:[0.0,1e5,0.5] type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -20]
        spinner spnGroutMatID "Grout ID " range:[1,65535,3] type:#integer fieldwidth:56 align:#right offset:[-12, -4]
        label lblPadBS "" height:1 align:#left offset:[0, 2]

        on rolFG_BoardSize open do this.refreshAllRollouts()
        on chkDoExtrude changed state do this.refreshAllRollouts()
        on chkDoBevel changed state do this.refreshAllRollouts()
        on chkDoGrout changed state do this.refreshAllRollouts()

        on btnLockLength changed state do
        (
            Length_L = state
            if state do Length_R = Length
            this.refreshAllRollouts()
        )
        on btnLockWidth changed state do
        (
            Width_L = state
            if state do Width_R = Width
            this.refreshAllRollouts()
        )
        on btnLockGrout changed state do
        (
            Grout_L = state
            if state do GroutWidth = GroutLength
            this.refreshAllRollouts()
        )
        on btnLockRowOff changed state do
        (
            RowOffset_L = state
            if state do MaxRowOffset = MinRowOffset
            this.refreshAllRollouts()
        )
        on btnLockOutline changed state do
        (
            BevelL = state
            if state do Outline = Bevel
            this.refreshAllRollouts()
        )
    )

    -- 2b. Rollout: Border
    rollout rolFG_Border "Border" width:162 rolledUp:true
    (
        checkbox chkDoBorder "Border" align:#left offset:[-5, -2] checked:false toolTip:"Add rectangular perimeter frame border around main tile field"
        spinner spnBorderWidth  "Width "  range:[0.1,1e6,100.0] type:#worldUnits fieldwidth:56 align:#right offset:[-12, 0]
        spinner spnBorderOffset "Offset " range:[0.0,1e6,200.0] type:#worldUnits fieldwidth:56 align:#right offset:[-12, -2]
        label lblBorderPat "Pattern" align:#left offset:[-5, 3] across:2
        dropdownList ddBorderPat "" items:#("Same Pattern", "Standard Tile") selection:1 width:82 align:#right offset:[6, 0]
        spinner spnBorderTileSize "Tile Size " range:[0.1,1e6,600.0] type:#worldUnits fieldwidth:56 align:#right offset:[-12, 1]
        label lblBorderCut "Corners" align:#left offset:[-5, 3] across:2
        dropdownList ddBorderCut "" items:#("Miter 45", "Tile Seams") selection:1 width:82 align:#right offset:[6, 0]
        spinner spnBorderMatID "Border ID " range:[1,65535,4] type:#integer fieldwidth:56 align:#right offset:[-12, 2]

        group "Line Offsets (Sides)"
        (
            spinner spnBorderOffBot   "Bottom " range:[-1e6,1e6,0.0] type:#worldUnits fieldwidth:52 align:#right offset:[-4, -2]
            spinner spnBorderOffTop   "Top "    range:[-1e6,1e6,0.0] type:#worldUnits fieldwidth:52 align:#right offset:[-4, -2]
            spinner spnBorderOffLeft  "Left "   range:[-1e6,1e6,0.0] type:#worldUnits fieldwidth:52 align:#right offset:[-4, -2]
            spinner spnBorderOffRight "Right "  range:[-1e6,1e6,0.0] type:#worldUnits fieldwidth:52 align:#right offset:[-4, -2]
            button btnBorderReset "Reset Lines" width:126 height:18 align:#center offset:[0, 2]
        )

        on rolFG_Border open do this.refreshAllRollouts()
        on chkDoBorder changed state do this.refreshAllRollouts()
        on ddBorderPat selected idx do this.refreshAllRollouts()
        on ddBorderCut selected idx do this.refreshAllRollouts()
        on btnBorderReset pressed do
        (
            undo "Reset Border Lines" on
            (
                BorderOffBot = 0.0
                BorderOffTop = 0.0
                BorderOffLeft = 0.0
                BorderOffRight = 0.0
            )
            this.refreshAllRollouts()
        )
    )

    -- 3. Rollout: Variation Per Board
    rollout rolFG_Variation "Variation Per Board" width:162
    (
        spinner spnMaxRot "Max Rotation " range:[0.0,100.0,0.0] type:#float fieldwidth:56 align:#right offset:[-12, -2]
        spinner spnMinRot "Min Rotation " range:[0.0,100.0,0.0] type:#float fieldwidth:56 align:#right offset:[-12, -4]
        spinner spnRotS   "Spread "       range:[0.0,1.0,0.5]   type:#float scale:0.01 fieldwidth:56 align:#right offset:[-12, -4]

        spinner spnOffX   "Max Offset X " range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, 3]
        spinner spnOffXR  "Min Offset X " range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -4]
        spinner spnOffXS  "Spread "       range:[0.0,1.0,0.5]   type:#float scale:0.01 fieldwidth:56 align:#right offset:[-12, -4]

        checkbutton btnLockOffset "L" width:13 height:16 align:#right offset:[4, -5] highlightColor:lockHighlightCol toolTip:"Lock Offset X / Offset Y"

        spinner spnOffY   "Max Offset Y " range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -5]
        spinner spnOffYR  "Min Offset Y " range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -4]
        spinner spnOffYS  "Spread "       range:[0.0,1.0,0.5]   type:#float scale:0.01 fieldwidth:56 align:#right offset:[-12, -4]

        spinner spnTilt   "Max Tilt "     range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, 3]
        spinner spnTiltR  "Min Tilt "     range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, -4]
        spinner spnTiltS  "Spread "       range:[0.0,1.0,0.5]   type:#float scale:0.01 fieldwidth:56 align:#right offset:[-12, -4]

        spinner spnOverlap "Max Overlap " range:[0.0,1e5,0.0]   type:#worldUnits scale:0.05 fieldwidth:56 align:#right offset:[-12, 3]

        on rolFG_Variation open do this.refreshAllRollouts()
        on btnLockOffset changed state do
        (
            Offset_L = state
            if state do (Offset_Y = Offset_X; Offset_Y_R = Offset_X_R; Offset_Y_S = Offset_X_S)
            this.refreshAllRollouts()
        )
    )

    -- 4. Rollout: General
    rollout rolFG_General "General" width:162
    (
        spinner spnScale     "Scale % "   range:[0.1,100000.0,100.0] type:#float fieldwidth:56 align:#right offset:[-12, -2]
        spinner spnDirection "Direction " range:[-360.0,360.0,0.0]   type:#float fieldwidth:56 align:#right offset:[-12, -4]
        spinner spnSeed      "Seed "      range:[0,2000000000,12345] type:#integer fieldwidth:56 align:#right offset:[-12, -4]
        spinner spnObjOffX   "Offset X "  range:[-1e6,1e6,0.0]       type:#worldUnits fieldwidth:56 align:#right offset:[-12, -2]
        spinner spnObjOffY   "Offset Y "  range:[-1e6,1e6,0.0]       type:#worldUnits fieldwidth:56 align:#right offset:[-12, -4]
        checkbox chkDoWeld   "Weld"       align:#left offset:[-2, -2] checked:false
        spinner spnWeld      "Thr. "      range:[0.0,100.0,0.05]     type:#worldUnits scale:0.01 fieldwidth:56 align:#right offset:[-12, -20]

        on rolFG_General open do this.refreshAllRollouts()
        on chkDoWeld changed state do this.refreshAllRollouts()
    )

    -- 5. Rollout: UV Settings
    rollout rolFG_UV "UV Settings" width:162
    (
        spinner spnUVChan "UV Channel " range:[1,99,1] type:#integer fieldwidth:56 align:#right offset:[-12, -2]
        checkbox chkFlipU    "Random Flip Mapping U" align:#left offset:[2, 1]  checked:true
        checkbox chkFlipV    "Random Flip Mapping V" align:#left offset:[2, -3] checked:true
        checkbox chkRandOffU "Random Offset U"       align:#left offset:[2, -3] checked:true
        checkbox chkRandOffV "Random Offset V"       align:#left offset:[2, -3] checked:true
    )

    -- 6. Rollout: Warnings
    rollout rolFG_Warnings "Warnings" width:162
    (
        spinner spnWarnMax "Max Boards " range:[100,1000000,10000] type:#integer fieldwidth:56 align:#right offset:[-12, -2]
    )

    -- 7. Rollout: Update
    rollout rolFG_Update "Update" width:162
    (
        radiobuttons rbUpdate "" labels:#("Always", "Manually") columns:1 default:1 align:#center offset:[-6, -2]
        button btnManualUpdate "Update" width:116 height:18 align:#center offset:[0, -1]

        on rolFG_Update open do this.refreshAllRollouts()
        on rbUpdate changed state do
        (
            LiveUpdate = (state == 1)
            btnManualUpdate.enabled = (state == 2)
            if LiveUpdate do
            (
                forceRefresh = true
                cachedMesh = undefined
                Seed = Seed
            )
        )
        on btnManualUpdate pressed do
        (
            forceRefresh = true
            cachedMesh = undefined
            Seed = Seed
        )
    )

    -- 8. Rollout: Save/Load Presets
    rollout rolFG_Presets "Save/Load Presets" width:162
    (
        button btnSaveIni "Save" width:64 height:18 across:2 align:#left offset:[-2, -2]
        button btnLoadIni "Load" width:64 height:18 align:#right offset:[2, -2]

        on btnSaveIni pressed do
        (
            local f = getSaveFileName caption:"Save FloorGenerator Preset" types:"Ini(*.ini)|*.ini|All(*.*)|*.*|"
            if f != undefined do FGv2_Engine.savePresetIni (this.makeConfig()) f
        )

        on btnLoadIni pressed do
        (
            local f = getOpenFileName caption:"Load FloorGenerator Preset" types:"Ini(*.ini)|*.ini|All(*.*)|*.*|"
            if f != undefined do
            (
                local c = this.makeConfig()
                if (FGv2_Engine.loadPresetIni c f) do this.applyConfig c
            )
        )
    )

    -- 9. Rollout: Credits
    rollout rolFG_Credits "Credits" width:162
    (
        label lblCredits1 "FloorGenerator V2.1" align:#center offset:[0, -2]
        label lblCredits2 "Created by" align:#center offset:[0, -4]
        hyperLink hlCredits "CG-Source.com" address:"https://www.cg-source.com" color:(color 45 95 225) hoverColor:(color 90 145 255) visitedColor:(color 45 95 225) align:#center offset:[0, -4]
        label lblCredits3 "The source for" align:#center offset:[0, -4]
        label lblCredits4 "HighQuality texures" align:#center offset:[0, -4]
    )

    on modifyMesh do
    (
        if (not LiveUpdate) and (not forceRefresh) and cachedMesh != undefined then
        (
            mesh = copy cachedMesh
        )
        else
        (
            forceRefresh = false
            local workMesh = copy mesh
            local cfg = makeConfig()
            if (FGv2_Engine.buildFloorOnTriMesh workMesh cfg allowDialogs:false) then
            (
                cachedMesh = copy workMesh
                mesh = workMesh
            )
            else if cachedMesh != undefined do
            (
                mesh = copy cachedMesh
            )
        )
    )
)

format "[FloorGenerator v2.1] Loaded! Modifier 'FloorGenerator v2.1' registered in Modifier List.\n"
