#include "FloorGenerator.h"
#include <commdlg.h>
#include <shellapi.h>
#include <random>
#include <string>

IObjParam* FloorGeneratorMod::ip = nullptr;

namespace
{
    constexpr double kPi = 3.14159265358979323846;
    constexpr double kDegToRad = kPi / 180.0;
    constexpr double kRadToDeg = 180.0 / kPi;

    struct Vec2
    {
        double x = 0.0;
        double y = 0.0;
        Vec2() = default;
        Vec2(double x_, double y_) : x(x_), y(y_) {}
        Vec2 operator+(const Vec2& o) const { return { x + o.x, y + o.y }; }
        Vec2 operator-(const Vec2& o) const { return { x - o.x, y - o.y }; }
        Vec2 operator*(double s) const { return { x * s, y * s }; }
    };

    struct Tri2D
    {
        Vec2 p1, p2, p3;
        double minX, minY, maxX, maxY;
    };

    struct BoardConfig
    {
        int pattern = 1;
        int hbParallels = 1;
        double chevronAngle = 45.0;
        int bwSubBoards = 3;
        double octInsertSize = 200.0;

        double length = 1000.0;
        bool lengthL = true;
        double lengthR = 1000.0;
        double lengthS = 0.5;

        double width = 70.0;
        bool widthL = true;
        double widthR = 70.0;
        double widthS = 0.5;

        double groutLen = 0.2;
        double groutWid = 0.2;
        bool groutL = true;

        double minRowOff = 20.0;
        double maxRowOff = 20.0;
        bool rowOffL = true;

        bool doExtrude = true;
        double extrude = 1.0;
        bool doBevel = true;
        double bevel = 0.5;
        bool bevelL = true;
        double outline = 0.5;

        bool doGrout = false;
        double groutDepth = 0.5;
        int groutMatID = 3;

        double maxRot = 0.0;
        double minRot = 0.0;
        double rotSpread = 0.5;

        double offX = 0.0, offXR = 0.0, offXS = 0.5;
        double offY = 0.0, offYR = 0.0, offYS = 0.5;
        bool offL = true;

        double tilt = 0.0, tiltR = 0.0, tiltS = 0.5;
        double maxOverlap = 0.0;

        double scale = 100.0;
        double direction = 0.0;
        int seed = 12345;
        double objOffX = 0.0;
        double objOffY = 0.0;
        bool doWeld = false;
        double weld = 0.05;

        int uvChannel = 1;
        bool flipU = true;
        bool flipV = true;
        bool randOffU = true;
        bool randOffV = true;

        int warnMaxBoard = 10000;
        bool liveUpdate = true;
    };

    struct MeshBuffers
    {
        std::vector<Point3> verts;
        std::vector<Point3> tverts;
        struct FaceRec
        {
            DWORD v[3];
            MtlID matID;
            DWORD smGroup;
            bool ev[3];
        };
        std::vector<FaceRec> faces;
    };

    class FastRNG
    {
        std::mt19937 gen;
        std::uniform_real_distribution<double> u01{ 0.0, 1.0 };
    public:
        explicit FastRNG(uint32_t seedVal) : gen(seedVal) {}
        double next01() { return u01(gen); }
        double range(double a, double b)
        {
            if (b < a) std::swap(a, b);
            return a + (b - a) * u01(gen);
        }
        int bit() { return (gen() & 1u) ? 1 : 0; }
        double randSign() { return bit() ? -1.0 : 1.0; }

        double spreadRand(double minVal, double maxVal, double spread)
        {
            if (std::abs(maxVal - minVal) <= 1e-6) return minVal;
            double r = next01();
            double t = 0.0;
            if (r <= 1e-5) t = 0.0;
            else if (r >= 0.99999) t = 1.0;
            else
            {
                double invR = 1.0 - r;
                if (invR <= spread)
                    t = ((spread - 1.0) * invR) / r + 1.0;
                else
                    t = (r * spread) / invR;
            }
            return minVal + (maxVal - minVal) * t;
        }
    };

    double calcCollisionAngleDeg(double a, double b, double availGap)
    {
        if (a <= 1e-5 || b <= 1e-5) return 0.0;
        double d = std::sqrt(0.25 * a * a + 0.25 * b * b);
        double halfSpan = (a + availGap) * 0.5;
        double ang = 180.0;
        if (halfSpan <= d && d > 1e-6)
        {
            double ratio = std::clamp(halfSpan / d, -1.0, 1.0);
            ang = 90.0 - std::atan(a / b) * kRadToDeg - std::acos(ratio) * kRadToDeg;
        }
        return (std::max)(0.0, ang);
    }

    double sampleBoardRotationDeg(FastRNG& rng, double maxRotPct, double minRotPct, double rotSpread,
                                  double boardL, double boardW, double availGapW, double availGapL,
                                  double offX, double offY)
    {
        if (maxRotPct <= 1e-4 && minRotPct <= 1e-4) return 0.0;
        double frac = rng.spreadRand(minRotPct * 0.01, maxRotPct * 0.01, 1.0 - rotSpread);
        double effGapW = availGapW - 2.0 * std::abs(offX);
        double effGapL = availGapL - 2.0 * std::abs(offY);
        double a1 = calcCollisionAngleDeg(boardW, boardL, effGapW) * frac;
        double a2 = calcCollisionAngleDeg(boardL, boardW, effGapL) * frac;
        return (std::min)(a1, a2) * rng.randSign();
    }

    std::vector<Vec2> clipPolyByEdge(const std::vector<Vec2>& poly, const Vec2& pA, const Vec2& pB)
    {
        const size_t cnt = poly.size();
        if (cnt < 3) return {};
        std::vector<Vec2> out;
        out.reserve(cnt + 2);
        const double dx = pB.x - pA.x;
        const double dy = pB.y - pA.y;
        Vec2 prevPt = poly[cnt - 1];
        double prevVal = dx * (prevPt.y - pA.y) - dy * (prevPt.x - pA.x);
        bool prevIn = (prevVal >= -1e-4);

        for (size_t i = 0; i < cnt; ++i)
        {
            const Vec2& curPt = poly[i];
            const double curVal = dx * (curPt.y - pA.y) - dy * (curPt.x - pA.x);
            const bool curIn = (curVal >= -1e-4);
            if (curIn)
            {
                if (!prevIn)
                {
                    double denom = prevVal - curVal;
                    double t = (std::abs(denom) > 1e-9) ? (prevVal / denom) : 0.5;
                    out.push_back(prevPt + (curPt - prevPt) * t);
                }
                out.push_back(curPt);
            }
            else if (prevIn)
            {
                double denom = prevVal - curVal;
                double t = (std::abs(denom) > 1e-9) ? (prevVal / denom) : 0.5;
                out.push_back(prevPt + (curPt - prevPt) * t);
            }
            prevPt = curPt;
            prevVal = curVal;
            prevIn = curIn;
        }
        return out;
    }

    std::vector<Vec2> cleanPoly2D(const std::vector<Vec2>& poly)
    {
        if (poly.size() < 3) return {};
        std::vector<Vec2> cleaned;
        cleaned.reserve(poly.size());
        Vec2 prev = poly.back();
        for (const Vec2& p : poly)
        {
            double dx = p.x - prev.x;
            double dy = p.y - prev.y;
            if (dx * dx + dy * dy > 1e-6)
            {
                cleaned.push_back(p);
                prev = p;
            }
        }
        if (cleaned.size() < 3) return {};
        double area2 = 0.0;
        const Vec2& p0 = cleaned[0];
        for (size_t i = 1; i + 1 < cleaned.size(); ++i)
        {
            Vec2 v1 = cleaned[i] - p0;
            Vec2 v2 = cleaned[i + 1] - p0;
            area2 += (v1.x * v2.y - v1.y * v2.x);
        }
        if (area2 <= 1e-5) return {};
        return cleaned;
    }

    std::vector<Vec2> clipPolyToRect(const std::vector<Vec2>& poly, double minX, double minY, double maxX, double maxY)
    {
        double bMinX = 1e30, bMinY = 1e30, bMaxX = -1e30, bMaxY = -1e30;
        for (const Vec2& p : poly)
        {
            bMinX = (std::min)(bMinX, p.x);
            bMinY = (std::min)(bMinY, p.y);
            bMaxX = (std::max)(bMaxX, p.x);
            bMaxY = (std::max)(bMaxY, p.y);
        }
        if (bMaxX <= minX + 1e-4 || bMinX >= maxX - 1e-4 || bMaxY <= minY + 1e-4 || bMinY >= maxY - 1e-4)
            return {};
        if (bMinX >= minX - 1e-4 && bMaxX <= maxX + 1e-4 && bMinY >= minY - 1e-4 && bMaxY <= maxY + 1e-4)
            return poly;

        std::vector<Vec2> c = clipPolyByEdge(poly, { minX, minY }, { maxX, minY });
        if (c.size() < 3) return {};
        c = clipPolyByEdge(c, { maxX, minY }, { maxX, maxY });
        if (c.size() < 3) return {};
        c = clipPolyByEdge(c, { maxX, maxY }, { minX, maxY });
        if (c.size() < 3) return {};
        c = clipPolyByEdge(c, { minX, maxY }, { minX, minY });
        return cleanPoly2D(c);
    }

    std::vector<Vec2> clipPolyToTri(const std::vector<Vec2>& poly, const Tri2D& tri)
    {
        std::vector<Vec2> c = clipPolyByEdge(poly, tri.p1, tri.p2);
        if (c.size() < 3) return {};
        c = clipPolyByEdge(c, tri.p2, tri.p3);
        if (c.size() < 3) return {};
        c = clipPolyByEdge(c, tri.p3, tri.p1);
        return cleanPoly2D(c);
    }

    double polyArea2D(const std::vector<Vec2>& poly)
    {
        if (poly.size() < 3) return 0.0;
        double a = 0.0;
        const Vec2& p0 = poly[0];
        for (size_t i = 1; i + 1 < poly.size(); ++i)
        {
            Vec2 v1 = poly[i] - p0;
            Vec2 v2 = poly[i + 1] - p0;
            a += (v1.x * v2.y - v1.y * v2.x);
        }
        return 0.5 * std::abs(a);
    }

    std::vector<std::vector<Vec2>> mergeClippedPieces(const std::vector<std::vector<Vec2>>& pieces)
    {
        if (pieces.size() <= 1) return pieces;

        struct HalfEdge { Vec2 a, b; double mx, my; bool active; };
        std::vector<HalfEdge> halfEdges;
        constexpr double eps2 = 1e-4;

        for (const auto& poly : pieces)
        {
            const size_t cnt = poly.size();
            for (size_t i = 0; i < cnt; ++i)
            {
                Vec2 pA = poly[i];
                Vec2 pB = poly[(i + 1) % cnt];
                double mx = (pA.x + pB.x) * 0.5;
                double my = (pA.y + pB.y) * 0.5;

                int twinIdx = -1;
                for (int j = 0; j < static_cast<int>(halfEdges.size()); ++j)
                {
                    auto& he = halfEdges[j];
                    if (he.active && std::abs(mx - he.mx) < 1e-2 && std::abs(my - he.my) < 1e-2)
                    {
                        double d1 = (pA.x - he.b.x) * (pA.x - he.b.x) + (pA.y - he.b.y) * (pA.y - he.b.y);
                        double d2 = (pB.x - he.a.x) * (pB.x - he.a.x) + (pB.y - he.a.y) * (pB.y - he.a.y);
                        if (d1 < eps2 && d2 < eps2) { twinIdx = j; break; }
                    }
                }
                if (twinIdx >= 0) halfEdges[twinIdx].active = false;
                else halfEdges.push_back({ pA, pB, mx, my, true });
            }
        }

        std::vector<HalfEdge> activeEdges;
        for (const auto& he : halfEdges)
            if (he.active) activeEdges.push_back({ he.a, he.b, he.mx, he.my, false });

        std::vector<std::vector<Vec2>> merged;
        for (size_t i = 0; i < activeEdges.size(); ++i)
        {
            if (activeEdges[i].active) continue;
            activeEdges[i].active = true;
            std::vector<Vec2> loop;
            loop.push_back(activeEdges[i].a);
            Vec2 curEnd = activeEdges[i].b;
            bool closed = false;

            while (!closed)
            {
                double dClose = (curEnd.x - loop[0].x) * (curEnd.x - loop[0].x) + (curEnd.y - loop[0].y) * (curEnd.y - loop[0].y);
                if (dClose < eps2)
                {
                    closed = true;
                }
                else
                {
                    loop.push_back(curEnd);
                    bool foundNext = false;
                    for (size_t j = 0; j < activeEdges.size(); ++j)
                    {
                        if (!activeEdges[j].active)
                        {
                            double d = (curEnd.x - activeEdges[j].a.x) * (curEnd.x - activeEdges[j].a.x) +
                                       (curEnd.y - activeEdges[j].a.y) * (curEnd.y - activeEdges[j].a.y);
                            if (d < eps2)
                            {
                                activeEdges[j].active = true;
                                curEnd = activeEdges[j].b;
                                foundNext = true;
                                break;
                            }
                        }
                    }
                    if (!foundNext) closed = true;
                }
            }

            if (loop.size() >= 3)
            {
                std::vector<Vec2> simplified;
                const size_t n = loop.size();
                for (size_t k = 0; k < n; ++k)
                {
                    Vec2 pPrev = loop[(k + n - 1) % n];
                    Vec2 pCur = loop[k];
                    Vec2 pNext = loop[(k + 1) % n];
                    Vec2 v1 = pCur - pPrev;
                    Vec2 v2 = pNext - pCur;
                    double l1 = std::hypot(v1.x, v1.y);
                    double l2 = std::hypot(v2.x, v2.y);
                    if (l1 > 1e-8 && l2 > 1e-8)
                    {
                        v1 = v1 * (1.0 / l1);
                        v2 = v2 * (1.0 / l2);
                        if (std::abs(v1.x * v2.y - v1.y * v2.x) > 1e-3)
                            simplified.push_back(pCur);
                    }
                }
                auto cleaned = cleanPoly2D(simplified);
                if (cleaned.size() >= 3) merged.push_back(std::move(cleaned));
            }
        }
        return merged.empty() ? pieces : merged;
    }

    bool isConvexPoly2D(const std::vector<Vec2>& poly)
    {
        const size_t n = poly.size();
        if (n <= 3) return true;
        for (size_t i = 0; i < n; ++i)
        {
            const Vec2& pPrev = poly[(i + n - 1) % n];
            const Vec2& pCur = poly[i];
            const Vec2& pNext = poly[(i + 1) % n];
            double crossZ = (pCur.x - pPrev.x) * (pNext.y - pCur.y) - (pCur.y - pPrev.y) * (pNext.x - pCur.x);
            if (crossZ < -1e-4) return false;
        }
        return true;
    }

    bool pointInTri2D(const Vec2& pt, const Vec2& a, const Vec2& b, const Vec2& c)
    {
        if ((b.x - a.x) * (pt.y - a.y) - (b.y - a.y) * (pt.x - a.x) < -1e-5) return false;
        if ((c.x - b.x) * (pt.y - b.y) - (c.y - b.y) * (pt.x - b.x) < -1e-5) return false;
        if ((a.x - c.x) * (pt.y - c.y) - (a.y - c.y) * (pt.x - c.x) < -1e-5) return false;
        return true;
    }

    std::vector<std::array<int, 3>> triangulatePoly2D(const std::vector<Vec2>& poly)
    {
        const int n = static_cast<int>(poly.size());
        if (n < 3) return {};
        if (n == 3) return { { 0, 1, 2 } };
        if (isConvexPoly2D(poly))
        {
            std::vector<std::array<int, 3>> fan;
            fan.reserve(n - 2);
            for (int i = 1; i < n - 1; ++i) fan.push_back({ 0, i, i + 1 });
            return fan;
        }

        std::vector<int> idxList(n);
        for (int i = 0; i < n; ++i) idxList[i] = i;
        std::vector<std::array<int, 3>> tris;
        int guard = n * 3;

        while (idxList.size() > 3 && guard-- > 0)
        {
            const int cnt = static_cast<int>(idxList.size());
            bool earFound = false;
            for (int k = 0; k < cnt && !earFound; ++k)
            {
                int iPrev = idxList[(k + cnt - 1) % cnt];
                int iCur = idxList[k];
                int iNext = idxList[(k + 1) % cnt];
                const Vec2& a = poly[iPrev];
                const Vec2& b = poly[iCur];
                const Vec2& c = poly[iNext];
                if ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 1e-5)
                {
                    bool hasInside = false;
                    for (int m = 0; m < cnt && !hasInside; ++m)
                    {
                        int idxTest = idxList[m];
                        if (idxTest != iPrev && idxTest != iCur && idxTest != iNext)
                        {
                            if (pointInTri2D(poly[idxTest], a, b, c)) hasInside = true;
                        }
                    }
                    if (!hasInside)
                    {
                        tris.push_back({ iPrev, iCur, iNext });
                        idxList.erase(idxList.begin() + k);
                        earFound = true;
                    }
                }
            }
            if (!earFound)
            {
                tris.push_back({ idxList[0], idxList[1], idxList[2] });
                idxList.erase(idxList.begin() + 1);
            }
        }
        if (idxList.size() == 3) tris.push_back({ idxList[0], idxList[1], idxList[2] });
        return tris;
    }

    void emitBoardPrism(const std::vector<Vec2>& poly, const Vec2& boardCenter, double totalRotDeg,
                        double uvSpanL, double uvSpanW, bool flipU, bool flipV, double offU, double offV,
                        bool doExtrude, double extrudeH, bool doBevel, double bevelH, double outlineW,
                        double tiltDirDeg, double tiltAmount, const Matrix3* dirPostTM,
                        MtlID boardMatID, MeshBuffers& out)
    {
        const int m = static_cast<int>(poly.size());
        if (m < 3) return;

        double pMinX = 1e30, pMinY = 1e30, pMaxX = -1e30, pMaxY = -1e30;
        for (const Vec2& p : poly)
        {
            pMinX = (std::min)(pMinX, p.x);
            pMinY = (std::min)(pMinY, p.y);
            pMaxX = (std::max)(pMaxX, p.x);
            pMaxY = (std::max)(pMaxY, p.y);
        }
        const double minSpan = (std::min)(pMaxX - pMinX, pMaxY - pMinY);
        const double maxOutlineRatio = (m == 3) ? 0.28 : 0.45;
        const double effOutline = doBevel ? (std::min)(outlineW, minSpan * maxOutlineRatio) : 0.0;
        const double effExtrude = doExtrude ? extrudeH : 0.0;
        const double effBevel = doBevel ? bevelH : 0.0;

        std::vector<Vec2> miters(m, { 0.0, 0.0 });
        if (doBevel && std::abs(effOutline) > 1e-5)
        {
            std::vector<Vec2> edgeNormals(m, { 0.0, 0.0 });
            for (int i = 0; i < m; ++i)
            {
                Vec2 d = poly[(i + 1) % m] - poly[i];
                double len = std::hypot(d.x, d.y);
                if (len > 1e-6) edgeNormals[i] = { d.y / len, -d.x / len };
            }
            for (int i = 0; i < m; ++i)
            {
                const Vec2& nPrev = edgeNormals[(i + m - 1) % m];
                const Vec2& nCur = edgeNormals[i];
                double denom = 1.0 + (nPrev.x * nCur.x + nPrev.y * nCur.y);
                double bisX = -(nPrev.x + nCur.x);
                double bisY = -(nPrev.y + nCur.y);
                if (denom > 0.15) { bisX /= denom; bisY /= denom; }
                double bLen2 = bisX * bisX + bisY * bisY;
                if (bLen2 > 6.25)
                {
                    double sc = 2.5 / std::sqrt(bLen2);
                    bisX *= sc;
                    bisY *= sc;
                }
                miters[i] = { bisX * effOutline, bisY * effOutline };
            }
        }

        std::vector<DWORD> ringStarts;
        const size_t bVertStart = out.verts.size();

        DWORD r1Start = static_cast<DWORD>(out.verts.size());
        ringStarts.push_back(r1Start);
        for (int i = 0; i < m; ++i)
        {
            out.verts.emplace_back(static_cast<float>(poly[i].x), static_cast<float>(poly[i].y), 0.0f);
            out.tverts.emplace_back(0.0f, 0.0f, 0.0f);
        }

        DWORD topRingStart = r1Start;
        if (doExtrude && std::abs(effExtrude) > 1e-5)
        {
            DWORD r2Start = static_cast<DWORD>(out.verts.size());
            ringStarts.push_back(r2Start);
            for (int i = 0; i < m; ++i)
            {
                out.verts.emplace_back(static_cast<float>(poly[i].x), static_cast<float>(poly[i].y), static_cast<float>(effExtrude));
                out.tverts.emplace_back(0.0f, 0.0f, 0.0f);
            }
            topRingStart = r2Start;
        }

        std::vector<Vec2> topCapPoly;
        if (doBevel && (std::abs(effBevel) > 1e-5 || std::abs(effOutline) > 1e-5))
        {
            DWORD r3Start = static_cast<DWORD>(out.verts.size());
            ringStarts.push_back(r3Start);
            topCapPoly.resize(m);
            const double zTop = effExtrude + effBevel;
            for (int i = 0; i < m; ++i)
            {
                Vec2 tp{ poly[i].x + miters[i].x, poly[i].y + miters[i].y };
                topCapPoly[i] = tp;
                out.verts.emplace_back(static_cast<float>(tp.x), static_cast<float>(tp.y), static_cast<float>(zTop));
                out.tverts.emplace_back(0.0f, 0.0f, 0.0f);
            }
            topRingStart = r3Start;
        }
        else
        {
            topCapPoly = poly;
        }

        const size_t bVertEnd = out.verts.size();

        // Side quads
        for (size_t r = 0; r + 1 < ringStarts.size(); ++r)
        {
            DWORD bot0 = ringStarts[r];
            DWORD top0 = ringStarts[r + 1];
            DWORD smG = (r == 0) ? 2u : 4u;
            for (int i = 0; i < m; ++i)
            {
                int inext = (i + 1) % m;
                DWORD v00 = bot0 + i;
                DWORD v10 = bot0 + inext;
                DWORD v11 = top0 + inext;
                DWORD v01 = top0 + i;
                out.faces.push_back({ { v00, v10, v11 }, boardMatID, smG, { true, true, false } });
                out.faces.push_back({ { v00, v11, v01 }, boardMatID, smG, { false, true, true } });
            }
        }

        // Top cap
        auto capTris = triangulatePoly2D(topCapPoly);
        for (const auto& t : capTris)
        {
            int i0 = t[0], i1 = t[1], i2 = t[2];
            DWORD v1 = topRingStart + i0;
            DWORD v2 = topRingStart + i1;
            DWORD v3 = topRingStart + i2;
            bool e1Vis = ((i0 + 1) % m == i1);
            bool e2Vis = ((i1 + 1) % m == i2);
            bool e3Vis = ((i2 + 1) % m == i0);
            out.faces.push_back({ { v1, v2, v3 }, boardMatID, 1u, { e1Vis, e2Vis, e3Vis } });
        }

        const double cosR = std::cos(-totalRotDeg * kDegToRad);
        const double sinR = std::sin(-totalRotDeg * kDegToRad);

        const bool hasTilt = (tiltAmount > 1e-5);
        double cosT = 1.0, sinT = 0.0, tiltMinX = 0.0, tiltSpanX = 1.0;
        if (hasTilt)
        {
            cosT = std::cos(tiltDirDeg * kDegToRad);
            sinT = std::sin(tiltDirDeg * kDegToRad);
            tiltMinX = 1e30;
            double tiltMaxX = -1e30;
            for (int i = 0; i < m; ++i)
            {
                double dx = poly[i].x - boardCenter.x;
                double dy = poly[i].y - boardCenter.y;
                double rx = dx * cosT - dy * sinT;
                tiltMinX = (std::min)(tiltMinX, rx);
                tiltMaxX = (std::max)(tiltMaxX, rx);
            }
            tiltSpanX = (std::max)(1e-4, tiltMaxX - tiltMinX);
        }

        const double invSpanL = (uvSpanL > 1e-5) ? (1.0 / uvSpanL) : 1.0;
        const double invSpanW = (uvSpanW > 1e-5) ? (1.0 / uvSpanW) : 1.0;
        float minZAfterTilt = 0.0f;

        for (size_t vi = bVertStart; vi < bVertEnd; ++vi)
        {
            const Point3& pt = out.verts[vi];
            double lx = pt.x - boardCenter.x;
            double ly = pt.y - boardCenter.y;
            double lz = pt.z;

            double locX = lx * cosR - ly * sinR;
            double locY = lx * sinR + ly * cosR;

            double u = locX * invSpanL + 0.5;
            double v = locY * invSpanW + 0.5;
            if (flipU) u = 1.0 - u;
            if (flipV) v = 1.0 - v;
            u += offU;
            v += offV;
            out.tverts[vi] = Point3(static_cast<float>(u), static_cast<float>(v), static_cast<float>(lz));

            if (hasTilt && lz > 1e-5)
            {
                double tx = lx * cosT - ly * sinT;
                lz += ((tx - tiltMinX) / tiltSpanX) * tiltAmount;
            }

            Point3 worldPt(static_cast<float>(lx + boardCenter.x),
                           static_cast<float>(ly + boardCenter.y),
                           static_cast<float>(lz));
            if (dirPostTM) worldPt = worldPt * (*dirPostTM);
            if (worldPt.z < minZAfterTilt) minZAfterTilt = worldPt.z;
            out.verts[vi] = worldPt;
        }

        if (minZAfterTilt < 0.0f)
        {
            for (size_t vi = bVertStart; vi < bVertEnd; ++vi)
                out.verts[vi].z -= minZAfterTilt;
        }
    }

    std::vector<Vec2> rotatePoly2D(const std::vector<Vec2>& poly, const Vec2& center, double rotDeg)
    {
        if (std::abs(rotDeg) <= 1e-5) return poly;
        const double c = std::cos(rotDeg * kDegToRad);
        const double s = std::sin(rotDeg * kDegToRad);
        std::vector<Vec2> out(poly.size());
        for (size_t i = 0; i < poly.size(); ++i)
        {
            double dx = poly[i].x - center.x;
            double dy = poly[i].y - center.y;
            out[i] = { center.x + dx * c - dy * s, center.y + dx * s + dy * c };
        }
        return out;
    }

    void processBoardPoly(FastRNG& rng, const std::vector<Vec2>& rawPoly, double baseRotDeg,
                          double curBoardL, double curBoardW,
                          double bbMinX, double bbMinY, double bbMaxX, double bbMaxY,
                          bool isRectangularFootprint, const std::vector<Tri2D>& baseTris,
                          const BoardConfig& cfg, double uvSpanL, double uvSpanW,
                          double availGapW, double availGapL,
                          double clampOffXMin, double clampOffXMax,
                          double clampOffYMin, double clampOffYMax,
                          double minTilt, double maxTilt,
                          double extrudeH, double bevelH, double outlineW,
                          const Matrix3* dirPostTM,
                          int& boardIdx, MeshBuffers& out, MtlID fixedMatID = 0)
    {
        boardIdx += 1;
        double dxOff = rng.spreadRand(clampOffXMin, clampOffXMax, 1.0 - cfg.offXS) * rng.randSign();
        double dyOff = rng.spreadRand(clampOffYMin, clampOffYMax, 1.0 - cfg.offYS) * rng.randSign();

        std::vector<Vec2> shifted(rawPoly.size());
        double cx = 0.0, cy = 0.0;
        for (size_t i = 0; i < rawPoly.size(); ++i)
        {
            double px = rawPoly[i].x - dxOff;
            double py = rawPoly[i].y - dyOff;
            shifted[i] = { px, py };
            cx += px;
            cy += py;
        }
        cx /= static_cast<double>(rawPoly.size());
        cy /= static_cast<double>(rawPoly.size());
        Vec2 center{ cx, cy };

        double randRotDeg = sampleBoardRotationDeg(rng, cfg.maxRot, cfg.minRot, cfg.rotSpread,
                                                   curBoardL, curBoardW, availGapW, availGapL, dxOff, dyOff);
        auto polyRot = rotatePoly2D(shifted, center, randRotDeg);
        double totalRotDeg = baseRotDeg + randRotDeg;

        bool bFlipU = cfg.flipU ? (rng.bit() == 1) : false;
        bool bFlipV = cfg.flipV ? (rng.bit() == 1) : false;
        double bOffU = cfg.randOffU ? rng.range(-0.5, 0.5) : 0.0;
        double bOffV = cfg.randOffV ? rng.range(-0.5, 0.5) : 0.0;

        double bTiltDir = 0.0, bTiltAmt = 0.0;
        if (maxTilt > 1e-5 || minTilt > 1e-5)
        {
            bTiltDir = rng.range(0.0, 360.0);
            bTiltAmt = rng.spreadRand(minTilt, maxTilt, 1.0 - cfg.tiltS);
        }

        MtlID matID = (fixedMatID > 0) ? fixedMatID : static_cast<MtlID>(((boardIdx - 1) % 65535) + 1);

        if (isRectangularFootprint)
        {
            auto clipped = clipPolyToRect(polyRot, bbMinX, bbMinY, bbMaxX, bbMaxY);
            if (clipped.size() >= 3)
            {
                emitBoardPrism(clipped, center, totalRotDeg, uvSpanL, uvSpanW, bFlipU, bFlipV, bOffU, bOffV,
                               cfg.doExtrude, extrudeH, cfg.doBevel, bevelH, outlineW,
                               bTiltDir, bTiltAmt, dirPostTM, matID, out);
            }
        }
        else
        {
            double pMinX = 1e30, pMinY = 1e30, pMaxX = -1e30, pMaxY = -1e30;
            for (const Vec2& p : polyRot)
            {
                pMinX = (std::min)(pMinX, p.x);
                pMinY = (std::min)(pMinY, p.y);
                pMaxX = (std::max)(pMaxX, p.x);
                pMaxY = (std::max)(pMaxY, p.y);
            }
            if (pMaxX > bbMinX && pMinX < bbMaxX && pMaxY > bbMinY && pMinY < bbMaxY)
            {
                std::vector<std::vector<Vec2>> pieces;
                double clippedArea = 0.0;
                for (const Tri2D& tri : baseTris)
                {
                    if (pMaxX > tri.minX && pMinX < tri.maxX && pMaxY > tri.minY && pMinY < tri.maxY)
                    {
                        auto clipped = clipPolyToTri(polyRot, tri);
                        if (clipped.size() >= 3)
                        {
                            clippedArea += polyArea2D(clipped);
                            pieces.push_back(std::move(clipped));
                        }
                    }
                }
                if (!pieces.empty())
                {
                    double fullArea = polyArea2D(polyRot);
                    std::vector<std::vector<Vec2>> finalPolys;
                    if (std::abs(clippedArea - fullArea) <= 1e-4 * fullArea)
                        finalPolys.push_back(polyRot);
                    else if (pieces.size() > 1)
                        finalPolys = mergeClippedPieces(pieces);
                    else
                        finalPolys = std::move(pieces);

                    for (const auto& fp : finalPolys)
                    {
                        emitBoardPrism(fp, center, totalRotDeg, uvSpanL, uvSpanW, bFlipU, bFlipV, bOffU, bOffV,
                                       cfg.doExtrude, extrudeH, cfg.doBevel, bevelH, outlineW,
                                       bTiltDir, bTiltAmt, dirPostTM, matID, out);
                    }
                }
            }
        }
    }

    bool buildFloorOnMesh(Mesh& ioMesh, const BoardConfig& cfg)
    {
        if (ioMesh.getNumFaces() == 0 || ioMesh.getNumVerts() == 0) return false;

        // 1. Coplanarity check
        Point3 f0v0 = ioMesh.verts[ioMesh.faces[0].v[0]];
        Point3 f0v1 = ioMesh.verts[ioMesh.faces[0].v[1]];
        Point3 f0v2 = ioMesh.verts[ioMesh.faces[0].v[2]];
        Point3 n0 = Normalize(CrossProd(f0v1 - f0v0, f0v2 - f0v0));
        if (n0.LengthSquared() < 1e-8f) n0 = Point3(0.0f, 0.0f, 1.0f);

        // 2. Orthonormal basis
        Matrix3 fromPlaneTM;
        if (std::abs(n0.z - 1.0f) < 1e-4f)
            fromPlaneTM.Set(Point3(1, 0, 0), Point3(0, 1, 0), Point3(0, 0, 1), Point3(0, 0, 0));
        else if (std::abs(n0.z + 1.0f) < 1e-4f)
            fromPlaneTM.Set(Point3(1, 0, 0), Point3(0, -1, 0), Point3(0, 0, -1), Point3(0, 0, 0));
        else
        {
            Point3 axX = Normalize(CrossProd(Point3(0, 0, 1), n0));
            Point3 axY = Normalize(CrossProd(n0, axX));
            fromPlaneTM.Set(axX, axY, n0, Point3(0, 0, 0));
        }
        Matrix3 toPlaneTM = Inverse(fromPlaneTM);

        Point3 faceCenter0 = (f0v0 + f0v1 + f0v2) / 3.0f;
        float planeHeight = DotProd(n0, faceCenter0);
        Point3 planeOffset = n0 * planeHeight;

        const bool hasDir = std::abs(cfg.direction) > 1e-4;
        Matrix3 dirPreTM, dirPostTM;
        if (hasDir)
        {
            dirPreTM.RotateZ(static_cast<float>(-cfg.direction * kDegToRad));
            dirPostTM.RotateZ(static_cast<float>(cfg.direction * kDegToRad));
        }

        const int numBaseVerts = ioMesh.getNumVerts();
        std::vector<Vec2> baseVerts2D(numBaseVerts);
        double bbMinX = 1e30, bbMinY = 1e30, bbMaxX = -1e30, bbMaxY = -1e30;

        for (int v = 0; v < numBaseVerts; ++v)
        {
            Point3 p = ioMesh.verts[v] * toPlaneTM;
            p.z = 0.0f;
            if (hasDir) p = p * dirPreTM;
            baseVerts2D[v] = { p.x, p.y };
            bbMinX = (std::min)(bbMinX, static_cast<double>(p.x));
            bbMinY = (std::min)(bbMinY, static_cast<double>(p.y));
            bbMaxX = (std::max)(bbMaxX, static_cast<double>(p.x));
            bbMaxY = (std::max)(bbMaxY, static_cast<double>(p.y));
        }

        double bbSpanX = bbMaxX - bbMinX;
        double bbSpanY = bbMaxY - bbMinY;
        if (bbSpanX <= 1e-4 || bbSpanY <= 1e-4) return false;

        std::vector<Tri2D> baseTris;
        baseTris.reserve(ioMesh.getNumFaces());
        double totalTriArea = 0.0;
        for (int f = 0; f < ioMesh.getNumFaces(); ++f)
        {
            const Face& fc = ioMesh.faces[f];
            const Vec2& p1 = baseVerts2D[fc.v[0]];
            const Vec2& p2 = baseVerts2D[fc.v[1]];
            const Vec2& p3 = baseVerts2D[fc.v[2]];
            double a2 = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x);
            if (std::abs(a2) > 1e-5)
            {
                totalTriArea += 0.5 * std::abs(a2);
                double tMinX = (std::min)({ p1.x, p2.x, p3.x });
                double tMinY = (std::min)({ p1.y, p2.y, p3.y });
                double tMaxX = (std::max)({ p1.x, p2.x, p3.x });
                double tMaxY = (std::max)({ p1.y, p2.y, p3.y });
                if (a2 > 0.0) baseTris.push_back({ p1, p2, p3, tMinX, tMinY, tMaxX, tMaxY });
                else baseTris.push_back({ p1, p3, p2, tMinX, tMinY, tMaxX, tMaxY });
            }
        }

        double bboxArea = bbSpanX * bbSpanY;
        bool isRectangularFootprint = (std::abs(totalTriArea - bboxArea) <= 1e-4 * bboxArea);

        double sc = (std::max)(0.0001, cfg.scale * 0.01);
        double maxL = (std::max)(0.1, cfg.length) * sc;
        double minL = cfg.lengthL ? maxL : ((std::max)(0.1, cfg.lengthR) * sc);
        double maxW = (std::max)(0.1, cfg.width) * sc;
        double minW = cfg.widthL ? maxW : ((std::max)(0.1, cfg.widthR) * sc);
        double gapL = (std::max)(0.0, cfg.groutLen) * sc;
        double gapW = cfg.groutL ? gapL : ((std::max)(0.0, cfg.groutWid) * sc);

        double uvSpanL = maxL, uvSpanW = maxW;
        if (cfg.pattern == 4)
        {
            int sub = (std::max)(1, cfg.bwSubBoards);
            uvSpanL = maxL;
            uvSpanW = (sub > 1) ? (maxL / sub - gapL * 0.5) : maxL;
        }
        else if (cfg.pattern == 5) { uvSpanL = maxL * 2.0; uvSpanW = maxL * 2.0; }
        else if (cfg.pattern == 6) { uvSpanL = maxL; uvSpanW = maxL * 0.8660254; }
        else if (cfg.pattern == 7) { uvSpanL = maxL; uvSpanW = cfg.widthL ? maxL : maxW; }

        double estBoardArea = (cfg.pattern == 6) ? (std::max)(1e-4, 0.5 * uvSpanL * uvSpanW) : (std::max)(1e-4, uvSpanL * uvSpanW);
        double estBoardCount = bboxArea / estBoardArea;
        if (estBoardCount > static_cast<double>((std::max)(100, cfg.warnMaxBoard)))
            return false;

        double offXMax = cfg.offX * sc, offXMin = cfg.offXR * sc;
        double offYMax = cfg.offL ? offXMax : (cfg.offY * sc);
        double offYMin = cfg.offL ? offXMin : (cfg.offYR * sc);

        double availGapL = cfg.maxOverlap * sc + gapL;
        double availGapW = cfg.maxOverlap * sc + gapW;
        double halfAvailL = availGapL * 0.5;
        double halfAvailW = availGapW * 0.5;

        double clampOffXMin = (std::min)(offXMin, halfAvailL);
        double clampOffXMax = (std::min)(offXMax, halfAvailL);
        double clampOffYMin = (std::min)(offYMin, halfAvailW);
        double clampOffYMax = (std::min)(offYMax, halfAvailW);

        double maxTilt = cfg.tilt * sc, minTilt = cfg.tiltR * sc;
        double extrudeH = cfg.extrude * sc, bevelH = cfg.bevel * sc;
        double outlineW = (cfg.bevelL ? cfg.bevel : cfg.outline) * sc;

        FastRNG rng(static_cast<uint32_t>((std::max)(0, cfg.seed)));
        MeshBuffers out;
        int boardIdx = 0;
        const Matrix3* postPtr = hasDir ? &dirPostTM : nullptr;

        double offObjX = cfg.objOffX * sc;
        double offObjY = cfg.objOffY * sc;
        int pat = cfg.pattern;

        auto modPos = [](double a, double b) -> double {
            if (std::abs(b) < 1e-9) return 0.0;
            return std::fmod(a, b);
        };

        if (pat == 1) // STANDARD
        {
            double minRowOff = cfg.minRowOff * 0.01;
            double maxRowOff = cfg.rowOffL ? minRowOff : (cfg.maxRowOff * 0.01);
            double avgRowOff = (minRowOff + maxRowOff) * 0.5;
            double stepLMax = maxL + gapL;

            double yCursor = -maxW - gapW - modPos(offObjY, maxW + gapW);
            double yLimit = bbSpanY + maxW + gapW;
            int rowIdx = 0;

            while (yCursor < yLimit)
            {
                double curW = rng.spreadRand(minW, maxW, cfg.widthS);
                double randOff = cfg.rowOffL ? 0.0 : (rng.range(minRowOff, maxRowOff) - avgRowOff);
                double rowShift = modPos((rowIdx * avgRowOff + randOff) * (-stepLMax), stepLMax);
                double xCursor = rowShift - modPos(offObjX, stepLMax) - stepLMax;
                double xLimit = bbSpanX + stepLMax;

                while (xCursor < xLimit)
                {
                    double curL = rng.spreadRand(minL, maxL, cfg.lengthS);
                    double x0 = bbMinX + xCursor;
                    double y0 = bbMinY + yCursor;
                    std::vector<Vec2> quad = { { x0, y0 }, { x0 + curL, y0 }, { x0 + curL, y0 + curW }, { x0, y0 + curW } };
                    processBoardPoly(rng, quad, 0.0, curL, curW, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                     isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                     availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                     minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);
                    xCursor += curL + gapL;
                }
                rowIdx += 1;
                yCursor += curW + gapW;
            }
        }
        else if (pat == 2) // HERRINGBONE
        {
            constexpr double k45 = 0.7071067811865475;
            double dxL = maxL * k45, dxW = maxW * k45, dGap = gapL * k45;
            int nPar = (std::max)(1, cfg.hbParallels);
            double parStep = dxW + dGap;
            double colStepX = dxL + dGap;
            double rowStepY = ((maxW + gapL) * nPar) / k45;

            double yCursor = -maxW - gapL - dxL - modPos(offObjY, rowStepY);
            double yLimit = bbSpanY + maxW + nPar * parStep + dxL + gapL;
            double xStart = -modPos(offObjX, 2.0 * colStepX) - (maxL + gapL);
            double xLimit = bbSpanX + nPar * parStep + dxL;

            while (yCursor < yLimit)
            {
                int colIdx = 0;
                double xCursor = xStart;
                while (xCursor < xLimit)
                {
                    bool isOdd = (colIdx % 2) != 0;
                    double dirSign = isOdd ? -1.0 : 1.0;
                    for (int pIdx = 0; pIdx < nPar; ++pIdx)
                    {
                        double hbX = bbMinX + xCursor - pIdx * parStep;
                        double hbY = bbMinY + yCursor + pIdx * dirSign * parStep;
                        std::vector<Vec2> quad;
                        double baseAng = 45.0;
                        if (!isOdd)
                        {
                            quad = { { hbX, hbY + dxW }, { hbX + dxW, hbY }, { hbX + dxL + dxW, hbY + dxL }, { hbX + dxL, hbY + dxL + dxW } };
                            baseAng = 45.0;
                        }
                        else
                        {
                            double hbYOdd = hbY - dGap;
                            quad = { { hbX + dxW, hbYOdd + dxL }, { hbX, hbYOdd + dxL - dxW }, { hbX + dxL, hbYOdd - dxW }, { hbX + dxL + dxW, hbYOdd } };
                            baseAng = -45.0;
                        }
                        processBoardPoly(rng, quad, baseAng, maxL, maxW, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                         isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                         availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                         minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);
                    }
                    colIdx += 1;
                    xCursor += colStepX;
                }
                yCursor += rowStepY;
            }
        }
        else if (pat == 3) // CHEVRON
        {
            double ang = std::clamp(cfg.chevronAngle, 1.0, 85.0);
            double cosA = std::cos(ang * kDegToRad);
            double sinA = std::sin(ang * kDegToRad);
            double dx = maxL * cosA, dy = maxL * sinA;
            double hY = maxW / cosA;
            double stepX = dx + gapL;
            double stepY = hY + (gapW / cosA);

            double yCursor = -hY - dy - gapW - modPos(offObjY, stepY);
            double yLimit = bbSpanY + hY + dy + gapW;
            double xStart = -modPos(offObjX, 2.0 * stepX) - stepX;
            double xLimit = bbSpanX + stepX;

            while (yCursor < yLimit)
            {
                int colIdx = 0;
                double xCursor = xStart;
                while (xCursor < xLimit)
                {
                    bool isRight = (colIdx % 2) != 0;
                    double x0 = bbMinX + xCursor, y0 = bbMinY + yCursor;
                    std::vector<Vec2> quad;
                    double baseAng = ang;
                    if (!isRight)
                    {
                        quad = { { x0, y0 + dy }, { x0 + dx, y0 }, { x0 + dx, y0 + hY }, { x0, y0 + dy + hY } };
                        baseAng = -ang;
                    }
                    else
                    {
                        quad = { { x0, y0 }, { x0 + dx, y0 + dy }, { x0 + dx, y0 + dy + hY }, { x0, y0 + hY } };
                        baseAng = ang;
                    }
                    processBoardPoly(rng, quad, baseAng, maxL, maxW, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                     isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                     availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                     minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);
                    colIdx += 1;
                    xCursor += stepX;
                }
                yCursor += stepY;
            }
        }
        else if (pat == 4) // BASKET WEAVE
        {
            int nSub = (std::max)(1, cfg.bwSubBoards);
            double subW = (maxL - (nSub - 1) * gapL) / static_cast<double>(nSub);
            double subStep = subW + gapL;
            double blockStep = maxL + gapL;

            double yCursor = -blockStep - modPos(offObjY, 2.0 * blockStep);
            double yLimit = bbSpanY + blockStep;
            double xStart = -blockStep - modPos(offObjX, 2.0 * blockStep);
            double xLimit = bbSpanX + blockStep;
            int rowIdx = 0;

            while (yCursor < yLimit)
            {
                int colIdx = 0;
                double xCursor = xStart;
                while (xCursor < xLimit)
                {
                    bool isVert = ((rowIdx + colIdx) % 2) != 0;
                    for (int sIdx = 0; sIdx < nSub; ++sIdx)
                    {
                        double sOff = sIdx * subStep;
                        double x0 = bbMinX + xCursor, y0 = bbMinY + yCursor;
                        std::vector<Vec2> quad;
                        double baseAng = 0.0;
                        if (!isVert)
                        {
                            quad = { { x0, y0 + sOff }, { x0 + maxL, y0 + sOff }, { x0 + maxL, y0 + sOff + subW }, { x0, y0 + sOff + subW } };
                            baseAng = 0.0;
                        }
                        else
                        {
                            quad = { { x0 + sOff, y0 }, { x0 + sOff + subW, y0 }, { x0 + sOff + subW, y0 + maxL }, { x0 + sOff, y0 + maxL } };
                            baseAng = 90.0;
                        }
                        processBoardPoly(rng, quad, baseAng, maxL, subW, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                         isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                         availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                         minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);
                    }
                    colIdx += 1;
                    xCursor += blockStep;
                }
                rowIdx += 1;
                yCursor += blockStep;
            }
        }
        else if (pat == 5) // HEXAGON
        {
            double rad = maxL;
            double dx = rad * 0.8660254;
            double dy = rad * 0.5;
            double stepX = 2.0 * dx + gapL;
            double stepY = 1.5 * rad + gapL * 0.8660254;

            double yCursor = -rad - gapL - modPos(offObjY, 2.0 * stepY);
            double yLimit = bbSpanY + rad + gapL;
            double xStart = -dx - gapL - modPos(offObjX, stepX);
            double xLimit = bbSpanX + dx + gapL;
            int rowIdx = 0;

            while (yCursor < yLimit)
            {
                bool isOdd = (rowIdx % 2) != 0;
                double xCursor = isOdd ? (xStart - (dx + gapL * 0.5)) : xStart;
                while (xCursor < xLimit)
                {
                    double cx = bbMinX + xCursor, cy = bbMinY + yCursor;
                    std::vector<Vec2> hexPoly = {
                        { cx - dx, cy + dy }, { cx - dx, cy - dy }, { cx, cy - rad },
                        { cx + dx, cy - dy }, { cx + dx, cy + dy }, { cx, cy + rad }
                    };
                    processBoardPoly(rng, hexPoly, 0.0, rad * 2.0, rad * 2.0, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                     isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                     availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                     minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);
                    xCursor += stepX;
                }
                rowIdx += 1;
                yCursor += stepY;
            }
        }
        else if (pat == 6) // TRIANGLE
        {
            double side = maxL;
            double halfSide = side * 0.5;
            double triH = side * 0.8660254;
            double stepX = side + gapL * 1.7320508;
            double halfStepX = stepX * 0.5;
            double stepY = triH + gapL * 1.5;
            double downShiftY = gapL * 0.5;

            double yCursor = -triH - gapL * 2.0 - modPos(offObjY, 2.0 * stepY);
            double yLimit = bbSpanY + triH + gapL * 2.0;
            double xStart = -stepX - modPos(offObjX, stepX);
            double xLimit = bbSpanX + stepX;
            int rowIdx = 0;

            while (yCursor < yLimit)
            {
                bool isOddRow = (rowIdx % 2) != 0;
                double xCursor = isOddRow ? (xStart + halfStepX) : xStart;
                double yUp = bbMinY + yCursor;
                double yDn = yUp + downShiftY;

                while (xCursor < xLimit)
                {
                    double cxUp = bbMinX + xCursor;
                    std::vector<Vec2> triUp = { { cxUp - halfSide, yUp }, { cxUp + halfSide, yUp }, { cxUp, yUp + triH } };
                    processBoardPoly(rng, triUp, 0.0, side, triH, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                     isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                     availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                     minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);

                    double cxDn = cxUp + halfStepX;
                    std::vector<Vec2> triDn = { { cxDn, yDn }, { cxDn + halfSide, yDn + triH }, { cxDn - halfSide, yDn + triH } };
                    processBoardPoly(rng, triDn, 180.0, side, triH, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                     isRectangularFootprint, baseTris, cfg, uvSpanL, uvSpanW,
                                     availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                     minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out);

                    xCursor += stepX;
                }
                rowIdx += 1;
                yCursor += stepY;
            }
        }
        else if (pat == 7) // OCTAGON (MatID 1 = Main Octagon, MatID 2 = Diamond Insert)
        {
            double tileL = maxL;
            double tileW = cfg.widthL ? maxL : maxW;
            double minTileDim = (std::min)(tileL, tileW);
            constexpr double k45 = 0.7071067811865475;
            double maxChamfer = minTileDim * 0.45;
            double maxAllowedInsDiag = (std::max)(0.0, maxChamfer - 1.41421356 * gapL + 0.5 * (gapL + gapW));
            double maxAllowedInsSide = maxAllowedInsDiag / k45;
            double insSide = std::clamp(cfg.octInsertSize * sc, 0.0, maxAllowedInsSide);
            double insHalfDiag = insSide * k45;

            double stepX = tileL + gapL;
            double stepY = tileW + gapW;
            double rawChamfer = (insSide > 1e-4) ? (insHalfDiag + 1.41421356 * gapL - 0.5 * (gapL + gapW)) : 0.0;
            double c = std::clamp(rawChamfer, 0.0, maxChamfer);

            double yCursor = -stepY - modPos(offObjY, stepY);
            double yLimit = bbSpanY + stepY;
            double xStart = -stepX - modPos(offObjX, stepX);
            double xLimit = bbSpanX + stepX;

            while (yCursor < yLimit)
            {
                double xCursor = xStart;
                double y0 = bbMinY + yCursor;
                while (xCursor < xLimit)
                {
                    double x0 = bbMinX + xCursor;
                    std::vector<Vec2> octPoly;
                    if (c > 1e-4)
                    {
                        octPoly = {
                            { x0 + c, y0 }, { x0 + tileL - c, y0 },
                            { x0 + tileL, y0 + c }, { x0 + tileL, y0 + tileW - c },
                            { x0 + tileL - c, y0 + tileW }, { x0 + c, y0 + tileW },
                            { x0, y0 + tileW - c }, { x0, y0 + c }
                        };
                    }
                    else
                    {
                        octPoly = { { x0, y0 }, { x0 + tileL, y0 }, { x0 + tileL, y0 + tileW }, { x0, y0 + tileW } };
                    }
                    processBoardPoly(rng, octPoly, 0.0, tileL, tileW, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                     isRectangularFootprint, baseTris, cfg, tileL, tileW,
                                     availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                     minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out, 1);

                    if (insHalfDiag > 1e-4)
                    {
                        double nx = x0 + tileL + 0.5 * gapL;
                        double ny = y0 + tileW + 0.5 * gapW;
                        std::vector<Vec2> diaPoly = {
                            { nx, ny - insHalfDiag }, { nx + insHalfDiag, ny },
                            { nx, ny + insHalfDiag }, { nx - insHalfDiag, ny }
                        };
                        processBoardPoly(rng, diaPoly, 45.0, insSide, insSide, bbMinX, bbMinY, bbMaxX, bbMaxY,
                                         isRectangularFootprint, baseTris, cfg, insSide, insSide,
                                         availGapW, availGapL, clampOffXMin, clampOffXMax, clampOffYMin, clampOffYMax,
                                         minTilt, maxTilt, extrudeH, bevelH, outlineW, postPtr, boardIdx, out, 2);
                    }
                    xCursor += stepX;
                }
                yCursor += stepY;
            }
        }

        if (out.faces.empty()) return false;

        // Ultra-Lightweight Grout Mesh (Single Base Footprint Layer)
        if (cfg.doGrout && (gapL > 1e-5 || gapW > 1e-5))
        {
            const double effExtrude = cfg.doExtrude ? extrudeH : 0.0;
            const double effBevel = cfg.doBevel ? bevelH : 0.0;
            const double zBoardTop = effExtrude + effBevel;
            const double gDepth = (std::max)(0.0, cfg.groutDepth * sc);
            const float zGroutTop = static_cast<float>((std::max)(0.0, zBoardTop - gDepth));
            const MtlID gMatID = static_cast<MtlID>((std::max)(1, cfg.groutMatID));
            const double invSpanX = (bbSpanX > 1e-5) ? (1.0 / bbSpanX) : 1.0;
            const double invSpanY = (bbSpanY > 1e-5) ? (1.0 / bbSpanY) : 1.0;

            const DWORD gTopStart = static_cast<DWORD>(out.verts.size());
            for (int v = 0; v < numBaseVerts; ++v)
            {
                const Vec2& p2d = baseVerts2D[v];
                float u = static_cast<float>((p2d.x - bbMinX) * invSpanX);
                float vCoord = static_cast<float>((p2d.y - bbMinY) * invSpanY);
                Point3 wp(static_cast<float>(p2d.x), static_cast<float>(p2d.y), zGroutTop);
                if (postPtr) wp = wp * (*postPtr);
                out.verts.push_back(wp);
                out.tverts.emplace_back(u, vCoord, zGroutTop);
            }

            const int numBaseFaces = ioMesh.getNumFaces();
            for (int f = 0; f < numBaseFaces; ++f)
            {
                const Face& fc = ioMesh.faces[f];
                const Vec2& p1 = baseVerts2D[fc.v[0]];
                const Vec2& p2 = baseVerts2D[fc.v[1]];
                const Vec2& p3 = baseVerts2D[fc.v[2]];
                double a2 = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x);
                if (std::abs(a2) > 1e-5)
                {
                    DWORD v1 = gTopStart + fc.v[0];
                    DWORD v2 = gTopStart + fc.v[1];
                    DWORD v3 = gTopStart + fc.v[2];
                    bool ev0 = fc.getEdgeVis(0) != 0;
                    bool ev1 = fc.getEdgeVis(1) != 0;
                    bool ev2 = fc.getEdgeVis(2) != 0;
                    if (a2 > 0.0)
                        out.faces.push_back({ { v1, v2, v3 }, gMatID, 8u, { ev0, ev1, ev2 } });
                    else
                        out.faces.push_back({ { v1, v3, v2 }, gMatID, 8u, { ev2, ev1, ev0 } });
                }
            }
        }

        // Transform back to 3D plane
        fromPlaneTM.SetRow(3, planeOffset);
        const int numV = static_cast<int>(out.verts.size());
        const int numF = static_cast<int>(out.faces.size());

        ioMesh.setNumVerts(numV);
        ioMesh.setNumFaces(numF);

        for (int i = 0; i < numV; ++i)
            ioMesh.verts[i] = out.verts[i] * fromPlaneTM;

        for (int f = 0; f < numF; ++f)
        {
            const auto& rec = out.faces[f];
            Face& fc = ioMesh.faces[f];
            fc.setVerts(rec.v[0], rec.v[1], rec.v[2]);
            fc.setMatID(rec.matID);
            fc.setSmGroup(rec.smGroup);
            fc.setEdgeVis(0, rec.ev[0] ? EDGE_VIS : EDGE_INVIS);
            fc.setEdgeVis(1, rec.ev[1] ? EDGE_VIS : EDGE_INVIS);
            fc.setEdgeVis(2, rec.ev[2] ? EDGE_VIS : EDGE_INVIS);
        }

        const int uvCh = std::clamp(cfg.uvChannel, 1, MAX_MESHMAPS - 1);
        if (ioMesh.getNumMaps() <= uvCh)
            ioMesh.setNumMaps(uvCh + 1, FALSE);
        ioMesh.setMapSupport(uvCh, TRUE);
        ioMesh.setNumMapVerts(uvCh, numV, FALSE);
        ioMesh.setNumMapFaces(uvCh, numF, FALSE);

        UVVert* mv = ioMesh.mapVerts(uvCh);
        TVFace* mf = ioMesh.mapFaces(uvCh);
        if (mv && mf)
        {
            for (int i = 0; i < numV; ++i) mv[i] = out.tverts[i];
            for (int f = 0; f < numF; ++f)
            {
                const auto& rec = out.faces[f];
                mf[f].setTVerts(rec.v[0], rec.v[1], rec.v[2]);
            }
        }

        if (cfg.doWeld && cfg.weld > 0.0)
        {
            BitArray allVerts(numV);
            allVerts.SetAll();
            MeshDelta md(ioMesh);
            md.WeldByThreshold(ioMesh, allVerts, static_cast<float>(cfg.weld * sc));
            md.Apply(ioMesh);
        }

        ioMesh.InvalidateGeomCache();
        ioMesh.InvalidateTopologyCache();
        return true;
    }
}

// =============================================================================
// ClassDesc2 & ParamBlockDesc2
// =============================================================================
class FloorGeneratorClassDesc : public ClassDesc2
{
public:
    int IsPublic() override { return TRUE; }
    void* Create(BOOL /*loading*/) override { return new FloorGeneratorMod(); }
    const TCHAR* ClassName() override { return GetString(IDS_CLASS_NAME); }
    const TCHAR* NonLocalizedClassName() override { return _T("FloorGenerator_v2"); }
    SClass_ID SuperClassID() override { return OSM_CLASS_ID; }
    Class_ID ClassID() override { return FLOORGEN_CLASS_ID; }
    const TCHAR* Category() override { return GetString(IDS_CATEGORY); }
    const TCHAR* InternalName() override { return _T("FloorGenerator_v2"); }
    HINSTANCE HInstance() override { return hInstance; }
};

static FloorGeneratorClassDesc floorGenDesc;
ClassDesc2* GetFloorGeneratorDesc() { return &floorGenDesc; }

class FloorGeneratorDlgProc : public ParamMap2UserDlgProc
{
public:
    INT_PTR DlgProc(TimeValue t, IParamMap2* map, HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) override
    {
        auto* mod = static_cast<FloorGeneratorMod*>(map->GetParamBlock()->GetOwner());
        switch (msg)
        {
        case WM_INITDIALOG:
        {
            if (map->GetMapID() == MAP_PATTERN)
            {
                HWND hCombo = GetDlgItem(hWnd, IDC_PAT_COMBO);
                if (hCombo)
                {
                    SendMessage(hCombo, CB_RESETCONTENT, 0, 0);
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Standard"));
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Herringbone"));
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Chevron"));
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Basket Weave"));
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Hexagon"));
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Triangle"));
                    SendMessage(hCombo, CB_ADDSTRING, 0, (LPARAM)_T("Octagon"));
                    int pat = map->GetParamBlock()->GetInt(pb_floor_pattern, t);
                    SendMessage(hCombo, CB_SETCURSEL, (WPARAM)std::clamp(pat - 1, 0, 6), 0);
                }
            }
            if (mod) mod->UpdateUIControls();
            return TRUE;
        }
        case WM_COMMAND:
        {
            int id = LOWORD(wParam);
            int code = HIWORD(wParam);
            IParamBlock2* pb = map->GetParamBlock();
            if (id == IDC_PAT_COMBO && code == CBN_SELCHANGE)
            {
                HWND hCombo = GetDlgItem(hWnd, IDC_PAT_COMBO);
                int sel = (int)SendMessage(hCombo, CB_GETCURSEL, 0, 0);
                pb->SetValue(pb_floor_pattern, t, sel + 1);
                if (mod) mod->UpdateUIControls();
                return TRUE;
            }
            if (id == IDC_UPDATE_BTN && mod)
            {
                mod->forceRefresh = true;
                mod->hasCachedMesh = false;
                mod->NotifyDependents(FOREVER, PART_ALL, REFMSG_CHANGE);
                return TRUE;
            }
            if (id == IDC_PRESET_SAVE && mod)
            {
                TCHAR fileBuf[MAX_PATH] = { 0 };
                OPENFILENAME ofn{};
                ofn.lStructSize = sizeof(ofn);
                ofn.hwndOwner = hWnd;
                ofn.lpstrFilter = _T("Ini (*.ini)\0*.ini\0All (*.*)\0*.*\0");
                ofn.lpstrFile = fileBuf;
                ofn.nMaxFile = MAX_PATH;
                ofn.lpstrDefExt = _T("ini");
                ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
                if (GetSaveFileName(&ofn)) mod->SavePresetINI(fileBuf, t);
                return TRUE;
            }
            if (id == IDC_PRESET_LOAD && mod)
            {
                TCHAR fileBuf[MAX_PATH] = { 0 };
                OPENFILENAME ofn{};
                ofn.lStructSize = sizeof(ofn);
                ofn.hwndOwner = hWnd;
                ofn.lpstrFilter = _T("Ini (*.ini)\0*.ini\0All (*.*)\0*.*\0");
                ofn.lpstrFile = fileBuf;
                ofn.nMaxFile = MAX_PATH;
                ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
                if (GetOpenFileName(&ofn)) mod->LoadPresetINI(fileBuf, t);
                return TRUE;
            }
            if (id == IDC_CREDITS_LINK)
            {
                ShellExecute(nullptr, _T("open"), _T("https://www.cg-source.com"), nullptr, nullptr, SW_SHOWNORMAL);
                return TRUE;
            }
            if (mod) mod->UpdateUIControls();
            break;
        }
        }
        return FALSE;
    }
    void DeleteThis() override {}
};

static FloorGeneratorDlgProc floorGenDlgProc;

static ParamBlockDesc2 floorGenParamBlk(
    0, _T("Parameters"), 0, &floorGenDesc,
    P_AUTO_CONSTRUCT | P_AUTO_UI | P_MULTIMAP, 0,
    // 9 Multi-Map Rollouts
    9,
    MAP_PATTERN,   IDD_PANEL_PATTERN,   IDS_ROL_PATTERN,   0, 0, &floorGenDlgProc,
    MAP_BOARDSIZE, IDD_PANEL_BOARDSIZE, IDS_ROL_BOARDSIZE, 0, 0, &floorGenDlgProc,
    MAP_VARIATION, IDD_PANEL_VARIATION, IDS_ROL_VARIATION, 0, 0, &floorGenDlgProc,
    MAP_GENERAL,   IDD_PANEL_GENERAL,   IDS_ROL_GENERAL,   0, 0, &floorGenDlgProc,
    MAP_UV,        IDD_PANEL_UV,        IDS_ROL_UV,        0, 0, &floorGenDlgProc,
    MAP_WARNINGS,  IDD_PANEL_WARNINGS,  IDS_ROL_WARNINGS,  0, 0, &floorGenDlgProc,
    MAP_UPDATE,    IDD_PANEL_UPDATE,    IDS_ROL_UPDATE,    0, 0, &floorGenDlgProc,
    MAP_PRESETS,   IDD_PANEL_PRESETS,   IDS_ROL_PRESETS,   0, 0, &floorGenDlgProc,
    MAP_CREDITS,   IDD_PANEL_CREDITS,   IDS_ROL_CREDITS,   0, 0, &floorGenDlgProc,

    // Pattern params
    pb_floor_pattern, _T("FloorPattern"), TYPE_INT, 0, IDS_ROL_PATTERN,
        p_default, 1, p_range, 1, 7, p_end,
    pb_hb_parallels, _T("HerringboneParallels"), TYPE_INT, P_ANIMATABLE, IDS_ROL_PATTERN,
        p_default, 1, p_range, 1, 100,
        p_ui, MAP_PATTERN, TYPE_SPINNER, EDITTYPE_INT, IDC_PAT_PARALLELS_EDIT, IDC_PAT_PARALLELS_SPIN, 0.1f, p_end,
    pb_chevron_angle, _T("ChevronAngle"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_PATTERN,
        p_default, 45.0f, p_range, 1.0f, 85.0f,
        p_ui, MAP_PATTERN, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_PAT_CHEVRON_EDIT, IDC_PAT_CHEVRON_SPIN, 0.5f, p_end,
    pb_bw_subboards, _T("BasketWeaveSubBoards"), TYPE_INT, P_ANIMATABLE, IDS_ROL_PATTERN,
        p_default, 3, p_range, 1, 100,
        p_ui, MAP_PATTERN, TYPE_SPINNER, EDITTYPE_INT, IDC_PAT_SUBBOARDS_EDIT, IDC_PAT_SUBBOARDS_SPIN, 0.1f, p_end,
    pb_oct_insertsize, _T("OctagonInsertSize"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_PATTERN,
        p_default, 200.0f, p_range, 0.0f, 1000000.0f,
        p_ui, MAP_PATTERN, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_PAT_INSERTSIZE_EDIT, IDC_PAT_INSERTSIZE_SPIN, SPIN_AUTOSCALE, p_end,

    // Board Size params
    pb_length, _T("Length"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 1000.0f, p_range, 0.1f, 1000000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_LEN_MAX_EDIT, IDC_LEN_MAX_SPIN, SPIN_AUTOSCALE, p_end,
    pb_length_l, _T("Length_L"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_CHECKBUTTON, IDC_LEN_LOCK, p_end,
    pb_length_r, _T("Length_R"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 1000.0f, p_range, 0.1f, 1000000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_LEN_MIN_EDIT, IDC_LEN_MIN_SPIN, SPIN_AUTOSCALE, p_end,
    pb_length_s, _T("Length_S"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.5f, p_range, 0.0f, 1.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_LEN_SPR_EDIT, IDC_LEN_SPR_SPIN, 0.01f, p_end,

    pb_width, _T("Width"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 70.0f, p_range, 0.1f, 1000000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_WID_MAX_EDIT, IDC_WID_MAX_SPIN, SPIN_AUTOSCALE, p_end,
    pb_width_l, _T("Width_L"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_CHECKBUTTON, IDC_WID_LOCK, p_end,
    pb_width_r, _T("Width_R"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 70.0f, p_range, 0.1f, 1000000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_WID_MIN_EDIT, IDC_WID_MIN_SPIN, SPIN_AUTOSCALE, p_end,
    pb_width_s, _T("Width_S"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.5f, p_range, 0.0f, 1.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_WID_SPR_EDIT, IDC_WID_SPR_SPIN, 0.01f, p_end,

    pb_grout_len, _T("GroutLength"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.2f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_GROUT_L_EDIT, IDC_GROUT_L_SPIN, 0.05f, p_end,
    pb_grout_wid, _T("GroutWidth"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.2f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_GROUT_W_EDIT, IDC_GROUT_W_SPIN, 0.05f, p_end,
    pb_grout_l, _T("Grout_L"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_CHECKBUTTON, IDC_GROUT_LOCK, p_end,

    pb_min_row_off, _T("MinRowOffset"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 20.0f, p_range, 0.0f, 100.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_ROW_MIN_EDIT, IDC_ROW_MIN_SPIN, 0.5f, p_end,
    pb_max_row_off, _T("MaxRowOffset"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 20.0f, p_range, 0.0f, 100.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_ROW_MAX_EDIT, IDC_ROW_MAX_SPIN, 0.5f, p_end,
    pb_row_off_l, _T("RowOffset_L"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_CHECKBUTTON, IDC_ROW_LOCK, p_end,

    pb_do_extrude, _T("DoExtrude"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_SINGLECHECKBOX, IDC_DO_EXTRUDE, p_end,
    pb_extrude, _T("Extrude"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 1.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_EXTRUDE_EDIT, IDC_EXTRUDE_SPIN, 0.1f, p_end,
    pb_do_bevel, _T("DoBevel"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_SINGLECHECKBOX, IDC_DO_BEVEL, p_end,
    pb_bevel, _T("Bevel"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.5f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_BEVEL_EDIT, IDC_BEVEL_SPIN, 0.05f, p_end,
    pb_bevel_l, _T("BevelL"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, TRUE, p_ui, MAP_BOARDSIZE, TYPE_CHECKBUTTON, IDC_OUTLINE_LOCK, p_end,
    pb_outline, _T("Outline"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.5f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OUTLINE_EDIT, IDC_OUTLINE_SPIN, 0.05f, p_end,

    pb_do_grout, _T("DoGrout"), TYPE_BOOL, 0, IDS_ROL_BOARDSIZE,
        p_default, FALSE, p_ui, MAP_BOARDSIZE, TYPE_SINGLECHECKBOX, IDC_DO_GROUT, p_end,
    pb_grout_depth, _T("GroutDepth"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_BOARDSIZE,
        p_default, 0.5f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_GROUT_DEPTH_EDIT, IDC_GROUT_DEPTH_SPIN, 0.05f, p_end,
    pb_grout_matid, _T("GroutMatID"), TYPE_INT, 0, IDS_ROL_BOARDSIZE,
        p_default, 3, p_range, 1, 65535,
        p_ui, MAP_BOARDSIZE, TYPE_SPINNER, EDITTYPE_INT, IDC_GROUT_MATID_EDIT, IDC_GROUT_MATID_SPIN, 1.0f, p_end,

    // Variation params
    pb_max_rot, _T("MaxRotation"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_ROT_MAX_EDIT, IDC_ROT_MAX_SPIN, 0.5f, p_end,
    pb_min_rot, _T("Rotation_R"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_ROT_MIN_EDIT, IDC_ROT_MIN_SPIN, 0.5f, p_end,
    pb_rot_spread, _T("RotationSpread"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.5f, p_range, 0.0f, 1.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_ROT_SPR_EDIT, IDC_ROT_SPR_SPIN, 0.01f, p_end,

    pb_off_x, _T("Offset_X"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OFFX_MAX_EDIT, IDC_OFFX_MAX_SPIN, 0.05f, p_end,
    pb_off_x_r, _T("Offset_X_R"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OFFX_MIN_EDIT, IDC_OFFX_MIN_SPIN, 0.05f, p_end,
    pb_off_x_s, _T("Offset_X_S"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.5f, p_range, 0.0f, 1.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_OFFX_SPR_EDIT, IDC_OFFX_SPR_SPIN, 0.01f, p_end,

    pb_off_y, _T("Offset_Y"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OFFY_MAX_EDIT, IDC_OFFY_MAX_SPIN, 0.05f, p_end,
    pb_off_y_r, _T("Offset_Y_R"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OFFY_MIN_EDIT, IDC_OFFY_MIN_SPIN, 0.05f, p_end,
    pb_off_y_s, _T("Offset_Y_S"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.5f, p_range, 0.0f, 1.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_OFFY_SPR_EDIT, IDC_OFFY_SPR_SPIN, 0.01f, p_end,
    pb_off_l, _T("Offset_L"), TYPE_BOOL, 0, IDS_ROL_VARIATION,
        p_default, TRUE, p_ui, MAP_VARIATION, TYPE_CHECKBUTTON, IDC_OFFSET_LOCK, p_end,

    pb_tilt, _T("Tilt"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_TILT_MAX_EDIT, IDC_TILT_MAX_SPIN, 0.05f, p_end,
    pb_tilt_r, _T("Tilt_R"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_TILT_MIN_EDIT, IDC_TILT_MIN_SPIN, 0.05f, p_end,
    pb_tilt_s, _T("Tilt_S"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.5f, p_range, 0.0f, 1.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_TILT_SPR_EDIT, IDC_TILT_SPR_SPIN, 0.01f, p_end,
    pb_max_overlap, _T("MaxOverlap"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_VARIATION,
        p_default, 0.0f, p_range, 0.0f, 100000.0f,
        p_ui, MAP_VARIATION, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OVERLAP_EDIT, IDC_OVERLAP_SPIN, 0.05f, p_end,

    // General params
    pb_scale, _T("Scale"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_GENERAL,
        p_default, 100.0f, p_range, 0.1f, 100000.0f,
        p_ui, MAP_GENERAL, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_SCALE_EDIT, IDC_SCALE_SPIN, 0.5f, p_end,
    pb_direction, _T("Direction"), TYPE_FLOAT, P_ANIMATABLE, IDS_ROL_GENERAL,
        p_default, 0.0f, p_range, -360.0f, 360.0f,
        p_ui, MAP_GENERAL, TYPE_SPINNER, EDITTYPE_FLOAT, IDC_DIR_EDIT, IDC_DIR_SPIN, 0.5f, p_end,
    pb_seed, _T("Seed"), TYPE_INT, P_ANIMATABLE, IDS_ROL_GENERAL,
        p_default, 12345, p_range, 0, 2000000000,
        p_ui, MAP_GENERAL, TYPE_SPINNER, EDITTYPE_INT, IDC_SEED_EDIT, IDC_SEED_SPIN, 1.0f, p_end,
    pb_obj_off_x, _T("ObjOffsetX"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_GENERAL,
        p_default, 0.0f, p_range, -1000000.0f, 1000000.0f,
        p_ui, MAP_GENERAL, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OBJOFFX_EDIT, IDC_OBJOFFX_SPIN, SPIN_AUTOSCALE, p_end,
    pb_obj_off_y, _T("ObjOffsetY"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_GENERAL,
        p_default, 0.0f, p_range, -1000000.0f, 1000000.0f,
        p_ui, MAP_GENERAL, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_OBJOFFY_EDIT, IDC_OBJOFFY_SPIN, SPIN_AUTOSCALE, p_end,
    pb_do_weld, _T("DoWeld"), TYPE_BOOL, 0, IDS_ROL_GENERAL,
        p_default, FALSE, p_ui, MAP_GENERAL, TYPE_SINGLECHECKBOX, IDC_DO_WELD, p_end,
    pb_weld, _T("Weld"), TYPE_WORLD, P_ANIMATABLE, IDS_ROL_GENERAL,
        p_default, 0.05f, p_range, 0.0f, 100.0f,
        p_ui, MAP_GENERAL, TYPE_SPINNER, EDITTYPE_UNIVERSE, IDC_WELD_EDIT, IDC_WELD_SPIN, 0.01f, p_end,

    // UV params
    pb_uv_channel, _T("UVChannel"), TYPE_INT, 0, IDS_ROL_UV,
        p_default, 1, p_range, 1, 99,
        p_ui, MAP_UV, TYPE_SPINNER, EDITTYPE_INT, IDC_UV_CHAN_EDIT, IDC_UV_CHAN_SPIN, 0.1f, p_end,
    pb_flip_u, _T("FlipU"), TYPE_BOOL, 0, IDS_ROL_UV,
        p_default, TRUE, p_ui, MAP_UV, TYPE_SINGLECHECKBOX, IDC_UV_FLIP_U, p_end,
    pb_flip_v, _T("FlipV"), TYPE_BOOL, 0, IDS_ROL_UV,
        p_default, TRUE, p_ui, MAP_UV, TYPE_SINGLECHECKBOX, IDC_UV_FLIP_V, p_end,
    pb_rand_off_u, _T("RandomOffsetU"), TYPE_BOOL, 0, IDS_ROL_UV,
        p_default, TRUE, p_ui, MAP_UV, TYPE_SINGLECHECKBOX, IDC_UV_RAND_U, p_end,
    pb_rand_off_v, _T("RandomOffsetV"), TYPE_BOOL, 0, IDS_ROL_UV,
        p_default, TRUE, p_ui, MAP_UV, TYPE_SINGLECHECKBOX, IDC_UV_RAND_V, p_end,

    // Warnings & Update
    pb_warn_max, _T("WarnMaxBoard"), TYPE_INT, 0, IDS_ROL_WARNINGS,
        p_default, 10000, p_range, 100, 1000000,
        p_ui, MAP_WARNINGS, TYPE_SPINNER, EDITTYPE_INT, IDC_WARN_MAX_EDIT, IDC_WARN_MAX_SPIN, 10.0f, p_end,
    pb_live_update, _T("LiveUpdate"), TYPE_BOOL, 0, IDS_ROL_UPDATE,
        p_default, TRUE, p_ui, MAP_UPDATE, TYPE_RADIO, 2, IDC_UPDATE_MANUAL, IDC_UPDATE_ALWAYS, p_end,

    p_end
);

FloorGeneratorMod::FloorGeneratorMod()
{
    floorGenDesc.MakeAutoParamBlocks(this);
}

Interval FloorGeneratorMod::LocalValidity(TimeValue t)
{
    Interval valid = FOREVER;
    if (pblock) pblock->GetValidity(t, valid);
    return valid;
}

RefResult FloorGeneratorMod::NotifyRefChanged(const Interval& /*changeInt*/, RefTargetHandle hTarget,
                                               PartID& /*partID*/, RefMessage message, BOOL /*propagate*/)
{
    if (message == REFMSG_CHANGE && hTarget == pblock)
    {
        ParamID pid = pblock->LastNotifyParamID();
        TimeValue t = GetCOREInterface()->GetTime();
        if (pid == pb_length && pblock->GetInt(pb_length_l, t))
            pblock->SetValue(pb_length_r, t, pblock->GetFloat(pb_length, t));
        else if (pid == pb_width && pblock->GetInt(pb_width_l, t))
            pblock->SetValue(pb_width_r, t, pblock->GetFloat(pb_width, t));
        else if (pid == pb_grout_len && pblock->GetInt(pb_grout_l, t))
            pblock->SetValue(pb_grout_wid, t, pblock->GetFloat(pb_grout_len, t));
        else if (pid == pb_min_row_off && pblock->GetInt(pb_row_off_l, t))
            pblock->SetValue(pb_max_row_off, t, pblock->GetFloat(pb_min_row_off, t));
        else if (pid == pb_bevel && pblock->GetInt(pb_bevel_l, t))
            pblock->SetValue(pb_outline, t, pblock->GetFloat(pb_bevel, t));
        else if (pid == pb_off_x && pblock->GetInt(pb_off_l, t))
            pblock->SetValue(pb_off_y, t, pblock->GetFloat(pb_off_x, t));
        else if (pid == pb_off_x_r && pblock->GetInt(pb_off_l, t))
            pblock->SetValue(pb_off_y_r, t, pblock->GetFloat(pb_off_x_r, t));
        else if (pid == pb_off_x_s && pblock->GetInt(pb_off_l, t))
            pblock->SetValue(pb_off_y_s, t, pblock->GetFloat(pb_off_x_s, t));
    }
    return REF_SUCCEED;
}

RefTargetHandle FloorGeneratorMod::Clone(RemapDir& remap)
{
    auto* newMod = new FloorGeneratorMod();
    newMod->ReplaceReference(0, remap.CloneRef(pblock));
    BaseClone(this, newMod, remap);
    return newMod;
}

void FloorGeneratorMod::BeginEditParams(IObjParam* ip_, ULONG flags, Animatable* prev)
{
    ip = ip_;
    floorGenDesc.BeginEditParams(ip, this, flags, prev);
    UpdateUIControls();
}

void FloorGeneratorMod::EndEditParams(IObjParam* ip_, ULONG flags, Animatable* next)
{
    floorGenDesc.EndEditParams(ip_, this, flags, next);
    ip = nullptr;
}

void FloorGeneratorMod::UpdateUIControls()
{
    if (!pblock) return;
    TimeValue t = GetCOREInterface()->GetTime();
    int pat = pblock->GetInt(pb_floor_pattern, t);
    bool isStd = (pat == 1);
    bool isOct = (pat == 7);

    if (IParamMap2* mPat = pblock->GetMap(MAP_PATTERN))
    {
        HWND hw = mPat->GetHWnd();
        auto showPair = [hw](int e, int s, bool vis) {
            int cmd = vis ? SW_SHOW : SW_HIDE;
            if (HWND h1 = GetDlgItem(hw, e)) ShowWindow(h1, cmd);
            if (HWND h2 = GetDlgItem(hw, s)) ShowWindow(h2, cmd);
        };
        showPair(IDC_PAT_PARALLELS_EDIT, IDC_PAT_PARALLELS_SPIN, pat == 2);
        showPair(IDC_PAT_CHEVRON_EDIT, IDC_PAT_CHEVRON_SPIN, pat == 3);
        showPair(IDC_PAT_SUBBOARDS_EDIT, IDC_PAT_SUBBOARDS_SPIN, pat == 4);
        showPair(IDC_PAT_INSERTSIZE_EDIT, IDC_PAT_INSERTSIZE_SPIN, pat == 7);

        if (HWND hLbl = GetDlgItem(hw, IDC_PAT_DYN_LABEL))
        {
            if (pat == 2) { SetWindowText(hLbl, _T("Parallel Boards")); ShowWindow(hLbl, SW_SHOW); }
            else if (pat == 3) { SetWindowText(hLbl, _T("Angle")); ShowWindow(hLbl, SW_SHOW); }
            else if (pat == 4) { SetWindowText(hLbl, _T("Sub Boards")); ShowWindow(hLbl, SW_SHOW); }
            else if (pat == 7) { SetWindowText(hLbl, _T("Insert Size")); ShowWindow(hLbl, SW_SHOW); }
            else ShowWindow(hLbl, SW_HIDE);
        }

        if (pat == 7)
        {
            float lenVal = pblock->GetFloat(pb_length, t);
            float widVal = pblock->GetFloat(pb_width, t);
            bool widL = pblock->GetInt(pb_width_l, t) != 0;
            float gL = pblock->GetFloat(pb_grout_len, t);
            float gW = pblock->GetInt(pb_grout_l, t) ? gL : pblock->GetFloat(pb_grout_wid, t);
            float minDim = widL ? lenVal : (std::min)(lenVal, widVal);
            float maxIns = (std::max)(0.0f, (minDim * 0.45f - 1.41421356f * gL + 0.5f * (gL + gW)) * 1.41421356f);
            if (ISpinnerControl* sp = GetISpinner(GetDlgItem(hw, IDC_PAT_INSERTSIZE_SPIN)))
            {
                sp->SetLimits(0.0f, (std::max)(0.1f, maxIns), TRUE);
                ReleaseISpinner(sp);
            }
            if (pblock->GetFloat(pb_oct_insertsize, t) > maxIns)
                pblock->SetValue(pb_oct_insertsize, t, maxIns);
        }
    }

    if (IParamMap2* mBS = pblock->GetMap(MAP_BOARDSIZE))
    {
        bool lenL = pblock->GetInt(pb_length_l, t) != 0;
        bool widL = pblock->GetInt(pb_width_l, t) != 0;
        bool grL = pblock->GetInt(pb_grout_l, t) != 0;
        bool rowL = pblock->GetInt(pb_row_off_l, t) != 0;
        bool doExt = pblock->GetInt(pb_do_extrude, t) != 0;
        bool doBev = pblock->GetInt(pb_do_bevel, t) != 0;
        bool bevL = pblock->GetInt(pb_bevel_l, t) != 0;
        bool doGr = pblock->GetInt(pb_do_grout, t) != 0;

        mBS->Enable(pb_length_r, isStd && !lenL);
        mBS->Enable(pb_length_s, isStd && !lenL);
        mBS->Enable(pb_length_l, isStd);

        mBS->Enable(pb_width, (pat == 1 || pat == 2 || pat == 3 || (isOct && !widL)));
        mBS->Enable(pb_width_r, isStd && !widL);
        mBS->Enable(pb_width_s, isStd && !widL);
        mBS->Enable(pb_width_l, isStd || isOct);

        mBS->Enable(pb_grout_wid, (pat == 1 || pat == 3 || isOct) && !grL);
        mBS->Enable(pb_grout_l, pat == 1 || pat == 3 || isOct);

        mBS->Enable(pb_min_row_off, isStd);
        mBS->Enable(pb_max_row_off, isStd && !rowL);
        mBS->Enable(pb_row_off_l, isStd);

        mBS->Enable(pb_extrude, doExt);
        mBS->Enable(pb_bevel, doBev);
        mBS->Enable(pb_outline, doBev && !bevL);
        mBS->Enable(pb_bevel_l, doBev);
        mBS->Enable(pb_grout_depth, doGr);
        mBS->Enable(pb_grout_matid, doGr);
    }

    if (IParamMap2* mVar = pblock->GetMap(MAP_VARIATION))
    {
        bool offL = pblock->GetInt(pb_off_l, t) != 0;
        mVar->Enable(pb_off_y, !offL);
        mVar->Enable(pb_off_y_r, !offL);
        mVar->Enable(pb_off_y_s, !offL);
    }

    if (IParamMap2* mGen = pblock->GetMap(MAP_GENERAL))
    {
        bool doWeld = pblock->GetInt(pb_do_weld, t) != 0;
        mGen->Enable(pb_weld, doWeld);
    }

    if (IParamMap2* mUpd = pblock->GetMap(MAP_UPDATE))
    {
        bool live = pblock->GetInt(pb_live_update, t) != 0;
        if (HWND hBtn = GetDlgItem(mUpd->GetHWnd(), IDC_UPDATE_BTN))
            EnableWindow(hBtn, !live);
    }
}

void FloorGeneratorMod::ModifyObject(TimeValue t, ModContext& /*mc*/, ObjectState* os, INode* /*node*/)
{
    if (!os || !os->obj || !os->obj->IsSubClassOf(triObjectClassID)) return;
    auto* triObj = static_cast<TriObject*>(os->obj);
    if (!pblock) return;

    bool live = pblock->GetInt(pb_live_update, t) != 0;
    if (!live && !forceRefresh && hasCachedMesh)
    {
        triObj->GetMesh() = cachedMesh;
        triObj->UpdateValidity(GEOM_CHAN_NUM, FOREVER);
        triObj->UpdateValidity(TOPO_CHAN_NUM, FOREVER);
        return;
    }

    forceRefresh = false;

    BoardConfig cfg;
    cfg.pattern = pblock->GetInt(pb_floor_pattern, t);
    cfg.hbParallels = pblock->GetInt(pb_hb_parallels, t);
    cfg.chevronAngle = pblock->GetFloat(pb_chevron_angle, t);
    cfg.bwSubBoards = pblock->GetInt(pb_bw_subboards, t);
    cfg.octInsertSize = pblock->GetFloat(pb_oct_insertsize, t);

    cfg.length = pblock->GetFloat(pb_length, t);
    cfg.lengthL = pblock->GetInt(pb_length_l, t) != 0;
    cfg.lengthR = cfg.lengthL ? cfg.length : pblock->GetFloat(pb_length_r, t);
    cfg.lengthS = pblock->GetFloat(pb_length_s, t);

    cfg.width = pblock->GetFloat(pb_width, t);
    cfg.widthL = pblock->GetInt(pb_width_l, t) != 0;
    cfg.widthR = cfg.widthL ? cfg.width : pblock->GetFloat(pb_width_r, t);
    cfg.widthS = pblock->GetFloat(pb_width_s, t);

    cfg.groutLen = pblock->GetFloat(pb_grout_len, t);
    cfg.groutL = pblock->GetInt(pb_grout_l, t) != 0;
    cfg.groutWid = cfg.groutL ? cfg.groutLen : pblock->GetFloat(pb_grout_wid, t);

    cfg.minRowOff = pblock->GetFloat(pb_min_row_off, t);
    cfg.rowOffL = pblock->GetInt(pb_row_off_l, t) != 0;
    cfg.maxRowOff = cfg.rowOffL ? cfg.minRowOff : pblock->GetFloat(pb_max_row_off, t);

    cfg.doExtrude = pblock->GetInt(pb_do_extrude, t) != 0;
    cfg.extrude = pblock->GetFloat(pb_extrude, t);
    cfg.doBevel = pblock->GetInt(pb_do_bevel, t) != 0;
    cfg.bevel = pblock->GetFloat(pb_bevel, t);
    cfg.bevelL = pblock->GetInt(pb_bevel_l, t) != 0;
    cfg.outline = cfg.bevelL ? cfg.bevel : pblock->GetFloat(pb_outline, t);
    cfg.doGrout = pblock->GetInt(pb_do_grout, t) != 0;
    cfg.groutDepth = pblock->GetFloat(pb_grout_depth, t);
    cfg.groutMatID = pblock->GetInt(pb_grout_matid, t);

    cfg.maxRot = pblock->GetFloat(pb_max_rot, t);
    cfg.minRot = pblock->GetFloat(pb_min_rot, t);
    cfg.rotSpread = pblock->GetFloat(pb_rot_spread, t);

    cfg.offX = pblock->GetFloat(pb_off_x, t);
    cfg.offXR = pblock->GetFloat(pb_off_x_r, t);
    cfg.offXS = pblock->GetFloat(pb_off_x_s, t);
    cfg.offL = pblock->GetInt(pb_off_l, t) != 0;
    cfg.offY = cfg.offL ? cfg.offX : pblock->GetFloat(pb_off_y, t);
    cfg.offYR = cfg.offL ? cfg.offXR : pblock->GetFloat(pb_off_y_r, t);
    cfg.offYS = cfg.offL ? cfg.offXS : pblock->GetFloat(pb_off_y_s, t);

    cfg.tilt = pblock->GetFloat(pb_tilt, t);
    cfg.tiltR = pblock->GetFloat(pb_tilt_r, t);
    cfg.tiltS = pblock->GetFloat(pb_tilt_s, t);
    cfg.maxOverlap = pblock->GetFloat(pb_max_overlap, t);

    cfg.scale = pblock->GetFloat(pb_scale, t);
    cfg.direction = pblock->GetFloat(pb_direction, t);
    cfg.seed = pblock->GetInt(pb_seed, t);
    cfg.objOffX = pblock->GetFloat(pb_obj_off_x, t);
    cfg.objOffY = pblock->GetFloat(pb_obj_off_y, t);
    cfg.doWeld = pblock->GetInt(pb_do_weld, t) != 0;
    cfg.weld = pblock->GetFloat(pb_weld, t);

    cfg.uvChannel = pblock->GetInt(pb_uv_channel, t);
    cfg.flipU = pblock->GetInt(pb_flip_u, t) != 0;
    cfg.flipV = pblock->GetInt(pb_flip_v, t) != 0;
    cfg.randOffU = pblock->GetInt(pb_rand_off_u, t) != 0;
    cfg.randOffV = pblock->GetInt(pb_rand_off_v, t) != 0;
    cfg.warnMaxBoard = pblock->GetInt(pb_warn_max, t);

    if (buildFloorOnMesh(triObj->GetMesh(), cfg))
    {
        cachedMesh = triObj->GetMesh();
        hasCachedMesh = true;
    }
    else if (hasCachedMesh)
    {
        triObj->GetMesh() = cachedMesh;
    }

    Interval valid = LocalValidity(t);
    triObj->UpdateValidity(GEOM_CHAN_NUM, valid);
    triObj->UpdateValidity(TOPO_CHAN_NUM, valid);
    triObj->UpdateValidity(TEXMAP_CHAN_NUM, valid);
}

void FloorGeneratorMod::SavePresetINI(const MCHAR* path, TimeValue t)
{
    const MCHAR* sec = _T("Params");
    auto writeStr = [&](const MCHAR* k, const std::wstring& v) {
        MaxSDK::Util::WritePrivateProfileStringW(sec, k, v.c_str(), path);
    };
    int pat = pblock->GetInt(pb_floor_pattern, t);
    int patCode = 2;
    switch (pat)
    {
    case 1: patCode = 2; break;
    case 2: patCode = 4; break;
    case 3: patCode = 8; break;
    case 4: patCode = 16; break;
    case 5: patCode = 32; break;
    case 6: patCode = 64; break;
    case 7: patCode = 128; break;
    }
    writeStr(_T("FloorPattern"), std::to_wstring(patCode));
    writeStr(_T("HerringboneParallels"), std::to_wstring(pblock->GetInt(pb_hb_parallels, t)));
    writeStr(_T("ChevronAngle"), std::to_wstring(pblock->GetFloat(pb_chevron_angle, t) * kDegToRad));
    writeStr(_T("BasketWeaveSubBoards"), std::to_wstring(pblock->GetInt(pb_bw_subboards, t)));
    writeStr(_T("OctagonInsertSize"), std::to_wstring(pblock->GetFloat(pb_oct_insertsize, t)));
    writeStr(_T("Length"), std::to_wstring(pblock->GetFloat(pb_length, t)));
    writeStr(_T("Length_L"), pblock->GetInt(pb_length_l, t) ? _T("1") : _T("0"));
    writeStr(_T("Length_R"), std::to_wstring(pblock->GetFloat(pb_length_r, t)));
    writeStr(_T("Length_S"), std::to_wstring(pblock->GetFloat(pb_length_s, t)));
    writeStr(_T("Width"), std::to_wstring(pblock->GetFloat(pb_width, t)));
    writeStr(_T("Width_L"), pblock->GetInt(pb_width_l, t) ? _T("1") : _T("0"));
    writeStr(_T("Width_R"), std::to_wstring(pblock->GetFloat(pb_width_r, t)));
    writeStr(_T("Width_S"), std::to_wstring(pblock->GetFloat(pb_width_s, t)));
    writeStr(_T("GroutLength"), std::to_wstring(pblock->GetFloat(pb_grout_len, t)));
    writeStr(_T("GroutWidth"), std::to_wstring(pblock->GetFloat(pb_grout_wid, t)));
    writeStr(_T("Grout_L"), pblock->GetInt(pb_grout_l, t) ? _T("1") : _T("0"));
    writeStr(_T("DoGrout"), pblock->GetInt(pb_do_grout, t) ? _T("1") : _T("0"));
    writeStr(_T("GroutDepth"), std::to_wstring(pblock->GetFloat(pb_grout_depth, t)));
    writeStr(_T("GroutMatID"), std::to_wstring(pblock->GetInt(pb_grout_matid, t)));
    writeStr(_T("Scale"), std::to_wstring(pblock->GetFloat(pb_scale, t) * 0.01));
    writeStr(_T("Direction"), std::to_wstring(pblock->GetFloat(pb_direction, t) * kDegToRad));
    writeStr(_T("Seed"), std::to_wstring(pblock->GetInt(pb_seed, t)));
}

void FloorGeneratorMod::LoadPresetINI(const MCHAR* path, TimeValue t)
{
    const MCHAR* sec = _T("Params");
    auto readFloat = [&](const MCHAR* k, float def) -> float {
        wchar_t buf[64]{};
        MaxSDK::Util::GetPrivateProfileStringW(sec, k, L"", buf, 64, path);
        return buf[0] ? static_cast<float>(_wtof(buf)) : def;
    };
    auto readInt = [&](const MCHAR* k, int def) -> int {
        return static_cast<int>(MaxSDK::Util::GetPrivateProfileIntW(sec, k, def, path));
    };

    int patRaw = readInt(_T("FloorPattern"), 2);
    int pat = 1;
    switch (patRaw)
    {
    case 2: pat = 1; break;
    case 4: pat = 2; break;
    case 8: pat = 3; break;
    case 16: pat = 4; break;
    case 32: pat = 5; break;
    case 64: pat = 6; break;
    case 128: pat = 7; break;
    default: pat = std::clamp(patRaw, 1, 7); break;
    }
    pblock->SetValue(pb_floor_pattern, t, pat);
    pblock->SetValue(pb_hb_parallels, t, readInt(_T("HerringboneParallels"), 1));
    float chv = readFloat(_T("ChevronAngle"), 0.785398f);
    pblock->SetValue(pb_chevron_angle, t, (chv <= 3.15f) ? static_cast<float>(chv * kRadToDeg) : chv);
    pblock->SetValue(pb_bw_subboards, t, readInt(_T("BasketWeaveSubBoards"), 3));
    pblock->SetValue(pb_oct_insertsize, t, readFloat(_T("OctagonInsertSize"), 200.0f));
    pblock->SetValue(pb_length_l, t, readInt(_T("Length_L"), 1) != 0);
    pblock->SetValue(pb_length, t, readFloat(_T("Length"), 1000.0f));
    pblock->SetValue(pb_length_r, t, readFloat(_T("Length_R"), 1000.0f));
    pblock->SetValue(pb_length_s, t, readFloat(_T("Length_S"), 0.5f));
    pblock->SetValue(pb_width_l, t, readInt(_T("Width_L"), 1) != 0);
    pblock->SetValue(pb_width, t, readFloat(_T("Width"), 70.0f));
    pblock->SetValue(pb_width_r, t, readFloat(_T("Width_R"), 70.0f));
    pblock->SetValue(pb_width_s, t, readFloat(_T("Width_S"), 0.5f));
    pblock->SetValue(pb_grout_l, t, readInt(_T("Grout_L"), 1) != 0);
    pblock->SetValue(pb_grout_len, t, readFloat(_T("GroutLength"), 0.2f));
    pblock->SetValue(pb_grout_wid, t, readFloat(_T("GroutWidth"), 0.2f));
    pblock->SetValue(pb_do_grout, t, readInt(_T("DoGrout"), 0) != 0);
    pblock->SetValue(pb_grout_depth, t, readFloat(_T("GroutDepth"), 0.5f));
    pblock->SetValue(pb_grout_matid, t, readInt(_T("GroutMatID"), 3));
    pblock->SetValue(pb_scale, t, readFloat(_T("Scale"), 1.0f) * 100.0f);
    pblock->SetValue(pb_direction, t, static_cast<float>(readFloat(_T("Direction"), 0.0f) * kRadToDeg));
    pblock->SetValue(pb_seed, t, readInt(_T("Seed"), 12345));

    if (IParamMap2* mPat = pblock->GetMap(MAP_PATTERN))
    {
        if (HWND hCombo = GetDlgItem(mPat->GetHWnd(), IDC_PAT_COMBO))
            SendMessage(hCombo, CB_SETCURSEL, pat - 1, 0);
    }
    UpdateUIControls();
}
