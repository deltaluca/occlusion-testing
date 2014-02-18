#if !js
import nape.util.BitmapDebug;
import nape.geom.Vec2;
#else
typedef Vec2 = { x : Float, y : Float };
#end

class Perlin3D {
    public static inline function noise(x:Float, y:Float = 0.0, z:Float = 0.0) {
        var X:Int = untyped __int__(x); x -= X; X &= 0xff;
        var Y:Int = untyped __int__(y); y -= Y; Y &= 0xff;
        var Z:Int = untyped __int__(z); z -= Z; Z &= 0xff;
        var u = fade(x); var v = fade(y); var w = fade(z);
        var A = p(X)  +Y; var AA = p(A)+Z; var AB = p(A+1)+Z;
        var B = p(X+1)+Y; var BA = p(B)+Z; var BB = p(B+1)+Z;
        return lerp(w, lerp(v, lerp(u, grad(p(AA  ), x  , y  , z   ),
                                       grad(p(BA  ), x-1, y  , z   )),
                               lerp(u, grad(p(AB  ), x  , y-1, z   ),
                                       grad(p(BB  ), x-1, y-1, z   ))),
                       lerp(v, lerp(u, grad(p(AA+1), x  , y  , z-1 ),
                                       grad(p(BA+1), x-1, y  , z-1 )),
                               lerp(u, grad(p(AB+1), x  , y-1, z-1 ),
                                       grad(p(BB+1), x-1, y-1, z-1 ))));
    }

    static inline function fade(t:Float) return t*t*t*(t*(t*6-15)+10);
    static inline function lerp(t:Float, a:Float, b:Float) return a + t*(b-a);
    static inline function grad(hash:Int, x:Float, y:Float, z:Float) {
        var h = hash&15;
        var u = h<8 ? x : y;
        var v = h<4 ? y : h==12||h==14 ? x : z;
        return ((h&1) == 0 ? u : -u) + ((h&2) == 0 ? v : -v);
    }

    static inline function p(i:Int) return perm[i];

    static var perm: haxe.ds.Vector<Int>;
    public static function initNoise() {
        perm = new haxe.ds.Vector<Int>(512);
        var p = [151,160,137,91,90,15,
            131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
            190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
            88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
            77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
            102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
            135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
            5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
            223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
            129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
            251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
            49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
            138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180];
        for(i in 0...256) {
            perm[i]     = p[i];
            perm[256+i] = p[i];
        }
    }
}

typedef Plane = Array<Float>;
typedef AABB = Array<Float>;

class Visible {
    public var x: Int;
    public var y: Int;
    public var renderable: Bool;
    public function new(x, y, renderable) {
        this.x = x;
        this.y = y;
        this.renderable = renderable;
    }
}

class Occluder {
    public var x0: Int;
    public var y0: Int;
    public var x1: Int;
    public var y1: Int;
    public var timestamp: Int;
    public function new(x0, y0, x1, y1, timestamp) {
        this.x0 = x0;
        this.y0 = y0;
        this.x1 = x1;
        this.y1 = y1;
        this.timestamp = timestamp;
    }
}

class OccluderCell {
    public var x: Int;
    public var y: Int;
    public var distance: Float;
    public var timestamp: Int;
    public function new(x, y, distance, timestamp) {
        this.x = x;
        this.y = y;
        this.distance = distance;
        this.timestamp = timestamp;
    }
}

class Main {
    static inline function plane(u:Vec2, v:Vec2):Plane {
        var a = (v.y - u.y);
        var b = (u.x - v.x);
        var c = -(a * u.x + b * u.y);
        return [a, b, c];
    }
    static inline function slane(frustum:Array<Float>, i:Int, ux:Float, uy:Float, vx:Float, vy:Float) {
        i *= 3;
        var a = frustum[i]   = vy - uy;
        var b = frustum[i+1] = ux - vx;
        frustum[i+2] = -(a * ux + b * uy);
    }
    static inline function stop(frustum:Array<Float>, n:Int) {
        var ret = [];
        for (i in 0...n) {
            ret[i] = [frustum[i*3], frustum[i*3+1], frustum[i*3+2]];
        }
        return ret;
    }

    static inline function inside(v:Vec2, p:Plane) {
        return v.x * p[0] + v.y * p[1] + p[2] >= 0;
    }

    static inline function aabbInside(aabb:AABB, frustum:Array<Plane>) {
        var ret = true;
        for (p in frustum) {
            if ((p[0] * (p[0] < 0 ? aabb[0] : aabb[2]) +
                 p[1] * (p[1] < 0 ? aabb[1] : aabb[3])) + p[2] < 0) {
                ret = false;
                break;
            }
        }
        return ret;
    }

    static inline function aabbInsideS(aabb:AABB, frustum:Array<Float>, n:Int) {
        var n3 = n * 3;
        var i = 0;
        while (i < n3) {
            var a = frustum[i++];
            var b = frustum[i++];
            var c = frustum[i++];
            if ((a * (a < 0 ? aabb[0] : aabb[2]) +
                 b * (b < 0 ? aabb[1] : aabb[3])) + c < 0) {
                i = 0;
                break;
            }
        }
        return i == n3;
    }

    static inline function aabbInsideSxy(x: Float, y: Float, frustum:Array<Float>, n:Int) {
        var n3 = n * 3;
        var i = 0;
        while (i < n3) {
            var a = frustum[i++];
            var b = frustum[i++];
            var c = frustum[i++];
            if ((a * (a < 0 ? x : (x + 1)) +
                 b * (b < 0 ? y : (y + 1))) + c < 0) {
                i = 0;
                break;
            }
        }
        return i == n3;
    }

    static inline function clipAABB(aabb:AABB, frustum:Array<Plane>) {
        // check for each edge (face in 3d) of AABB, how far along the axis
        // can move 'all' points so that AABB is minimal, but covers the area of
        // aabb intersecting frustum.
        function clipX(i, p:Plane) {
            if (p[0] == 0) return;

            var d1 = p[0] * aabb[i] + p[1] * aabb[1] + p[2];
            var d2 = p[0] * aabb[i] + p[1] * aabb[3] + p[2];
            if (d1 < 0 && d2 < 0) { // can clip
                var n0 = (-p[2] - p[1]*aabb[1]) / p[0] - aabb[i];
                var n1 = (-p[2] - p[1]*aabb[3]) / p[0] - aabb[i];
                var n = (n0 * n0 < n1 * n1 ? n0 : n1);
                aabb[i] += n;
            }
        }
        function clipY(i, p:Plane) {
            if (p[1] == 0) return;

            var d1 = p[0] * aabb[0] + p[1] * aabb[i] + p[2];
            var d2 = p[0] * aabb[2] + p[1] * aabb[i] + p[2];
            if (d1 < 0 && d2 < 0) { // can clip
                var n0 = (-p[2] - p[0]*aabb[0]) / p[1] - aabb[i];
                var n1 = (-p[2] - p[0]*aabb[2]) / p[1] - aabb[i];
                var n = (n0 * n0 < n1 * n1 ? n0 : n1);
                aabb[i] += n;
            }
        }
        for (p in frustum) {
            clipX(0, p);
            clipX(2, p);
            clipY(1, p);
            clipY(3, p);
        }
    }

    static inline function clipAABBS(aabb:AABB, frustum:Array<Float>, n:Int) {
        // check for each edge (face in 3d) of AABB, how far along the axis
        // can move 'all' points so that AABB is minimal, but covers the area of
        // aabb intersecting frustum.
        function clipX(i, a:Float, b:Float, c:Float) {
            if (a == 0) return;

            var d1 = a * aabb[i] + b * aabb[1] + c;
            var d2 = a * aabb[i] + b * aabb[3] + c;
            if (d1 < 0 && d2 < 0) { // can clip
                var n0 = (-c - b*aabb[1]) / a - aabb[i];
                var n1 = (-c - b*aabb[3]) / a - aabb[i];
                var n = (n0 * n0 < n1 * n1 ? n0 : n1);
                aabb[i] += n;
            }
        }
        function clipY(i, a:Float, b:Float, c:Float) {
            if (b == 0) return;

            var d1 = a * aabb[0] + b * aabb[i] + c;
            var d2 = a * aabb[2] + b * aabb[i] + c;
            if (d1 < 0 && d2 < 0) { // can clip
                var n0 = (-c - a*aabb[0]) / b - aabb[i];
                var n1 = (-c - a*aabb[2]) / b - aabb[i];
                var n = (n0 * n0 < n1 * n1 ? n0 : n1);
                aabb[i] += n;
            }
        }
        var n3 = n * 3;
        var i = 0;
        while (i < n3) {
            var a = frustum[i++];
            var b = frustum[i++];
            var c = frustum[i++];
            clipX(0, a, b, c);
            clipX(2, a, b, c);
            clipY(1, a, b, c);
            clipY(3, a, b, c);
        }
    }

    static inline function aabbTotallyInside(aabb:AABB, frustum:Array<Plane>) {
        var ret = true;
        for (p in frustum) {
            if ((p[0] * (p[0] > 0 ? aabb[0] : aabb[2]) +
                 p[1] * (p[1] > 0 ? aabb[1] : aabb[3])) + p[2] < 0) {
                ret = false;
                break;
            }
        }
        return ret;
    }

    static inline function aabbTotallyInsideS(aabb:AABB, frustum:Array<Float>, n:Int) {
        var n3 = n * 3;
        var i = 0;
        while (i < n3) {
            var a = frustum[i++];
            var b = frustum[i++];
            var c = frustum[i++];
            if ((a * (a > 0 ? aabb[0] : aabb[2]) +
                 b * (b > 0 ? aabb[1] : aabb[3])) + c < 0) {
                i = 0;
                break;
            }
        }
        return i == n3;
    }

    static inline function aabbTotallyInsideSxy(x: Float, y: Float, frustum:Array<Float>, n:Int) {
        var n3 = n * 3;
        var i = 0;
        while (i < n3) {
            var a = frustum[i++];
            var b = frustum[i++];
            var c = frustum[i++];
            if ((a * (a > 0 ? x : (x + 1)) +
                 b * (b > 0 ? y : (y + 1))) + c < 0) {
                i = 0;
                break;
            }
        }
        return i == n3;
    }

    static inline function aabbTotallyInsideSxy2(x0: Float, y0: Float, x1: Float, y1: Float, frustum:Array<Float>, n:Int) {
        var n3 = n * 3;
        var i = 0;
        while (i < n3) {
            var a = frustum[i++];
            var b = frustum[i++];
            var c = frustum[i++];
            if ((a * (a > 0 ? x0 : x1 + dim) +
                 b * (b > 0 ? y0 : y1 + dim)) + c < 0) {
                i = 0;
                break;
            }
        }
        return i == n3;
    }

    // assumption made for this application, that y is 'smaller' than x in all cases
    static inline function aabbContains(x:AABB, y:AABB) {
        return y[0] >= x[0] && y[1] >= x[1] && y[2] <= x[2] && y[3] <= x[3];
    }
    static inline function aabbContainsxy(a:AABB, x: Float, y: Float) {
        return x >= a[0] && y >= a[1] && (x + 1) <= a[2] && (y + 1) <= a[3];
    }
    static inline function aabbContainsxy2(x0: Float, y0: Float, x1: Float, y1: Float, x: Float, y: Float) {
        return x >= x0 && y >= y0 && x <= x1 && y <= y1;
    }

    static inline function shadowFrustum(aabb:AABB, focus:Vec2):Array<Plane> {
        // voronoi region check, probably slower for 3d and missing a trick here.
        var p0, p1;
        if (focus.x < aabb[0] && focus.y < aabb[1]) {
            p0 = Vec2.get(aabb[2], aabb[1]);
            p1 = Vec2.get(aabb[0], aabb[3]);
        }
        else if (focus.x < aabb[0] && focus.y > aabb[3]) {
            p0 = Vec2.get(aabb[0], aabb[1]);
            p1 = Vec2.get(aabb[2], aabb[3]);
        }
        else if (focus.x > aabb[2] && focus.y < aabb[1]) {
            p0 = Vec2.get(aabb[2], aabb[3]);
            p1 = Vec2.get(aabb[0], aabb[1]);
        }
        else if (focus.x > aabb[2] && focus.y > aabb[3]) {
            p0 = Vec2.get(aabb[0], aabb[3]);
            p1 = Vec2.get(aabb[2], aabb[1]);
        }
        else if (focus.x < aabb[0]) {
            p0 = Vec2.get(aabb[0], aabb[1]);
            p1 = Vec2.get(aabb[0], aabb[3]);
        }
        else if (focus.x > aabb[2]) {
            p0 = Vec2.get(aabb[2], aabb[3]);
            p1 = Vec2.get(aabb[2], aabb[1]);
        }
        else if (focus.y < aabb[1]) {
            p0 = Vec2.get(aabb[2], aabb[1]);
            p1 = Vec2.get(aabb[0], aabb[1]);
        }
        else {
            p0 = Vec2.get(aabb[0], aabb[3]);
            p1 = Vec2.get(aabb[2], aabb[3]);
        }
        return [
            plane(p0, focus),
            plane(p0, p1),
            plane(focus, p1)
        ];
    }
    static inline function shadowFrustumS(aabb:AABB, focus0: Float, focus1: Float, frustum: Array<Float>):Int {
        // voronoi region check, probably slower for 3d and missing a trick here.
        var pa0, pa1, pb0, pb1;
        if (focus0 < aabb[0] && focus1 < aabb[1]) {
            pa0 = aabb[2]; pa1 = aabb[1];
            pb0 = aabb[0]; pb1 = aabb[3];
        }
        else if (focus0 < aabb[0] && focus1 > aabb[3]) {
            pa0 = aabb[0]; pa1 = aabb[1];
            pb0 = aabb[2]; pb1 = aabb[3];
        }
        else if (focus0 > aabb[2] && focus1 < aabb[1]) {
            pa0 = aabb[2]; pa1 = aabb[3];
            pb0 = aabb[0]; pb1 = aabb[1];
        }
        else if (focus0 > aabb[2] && focus1 > aabb[3]) {
            pa0 = aabb[0]; pa1 = aabb[3];
            pb0 = aabb[2]; pb1 = aabb[1];
        }
        else if (focus0 < aabb[0]) {
            pa0 = aabb[0]; pa1 = aabb[1];
            pb0 = aabb[0]; pb1 = aabb[3];
        }
        else if (focus0 > aabb[2]) {
            pa0 = aabb[2]; pa1 = aabb[3];
            pb0 = aabb[2]; pb1 = aabb[1];
        }
        else if (focus1 < aabb[1]) {
            pa0 = aabb[2]; pa1 = aabb[1];
            pb0 = aabb[0]; pb1 = aabb[1];
        }
        else {
            pa0 = aabb[0]; pa1 = aabb[3];
            pb0 = aabb[2]; pb1 = aabb[3];
        }
        slane(frustum, 0,
            pa0, pa1,
            focus0, focus1);
        slane(frustum, 1,
            pa0, pa1,
            pb0, pb1);
        slane(frustum, 2,
            focus0, focus1,
            pb0, pb1);
        return 3;
    }
    static inline function shadowFrustumSxy(x0: Float, y0: Float, x1: Float, y1: Float, focus0: Float, focus1: Float, frustum: Array<Float>):Int {
        // voronoi region check, probably slower for 3d and missing a trick here.
        x1++;
        y1++;
        var pa0, pa1, pb0, pb1;
        if (focus0 < x0 && focus1 < y0) {
            pa0 = x1; pa1 = y0;
            pb0 = x0; pb1 = y1;
        }
        else if (focus0 < x0 && focus1 > y1) {
            pa0 = x0; pa1 = y0;
            pb0 = x1; pb1 = y1;
        }
        else if (focus0 > x1 && focus1 < y0) {
            pa0 = x1; pa1 = y1;
            pb0 = x0; pb1 = y0;
        }
        else if (focus0 > x1 && focus1 > y1) {
            pa0 = x0; pa1 = y1;
            pb0 = x1; pb1 = y0;
        }
        else if (focus0 < x0) {
            pa0 = x0; pa1 = y0;
            pb0 = x0; pb1 = y1;
        }
        else if (focus0 > x1) {
            pa0 = x1; pa1 = y1;
            pb0 = x1; pb1 = y0;
        }
        else if (focus1 < y0) {
            pa0 = x1; pa1 = y0;
            pb0 = x0; pb1 = y0;
        }
        else {
            pa0 = x0; pa1 = y1;
            pb0 = x1; pb1 = y1;
        }
        slane(frustum, 0,
            pa0, pa1,
            focus0, focus1);
        slane(frustum, 1,
            pa0, pa1,
            pb0, pb1);
        slane(frustum, 2,
            focus0, focus1,
            pb0, pb1);
        return 3;
    }

    static inline var perlinScale = 0.01;
    static inline var threshold = 0.0;
    static inline var dim = 8;
    static inline var sw = 1024;
    static inline var sh = 768;
    static var w = Math.floor(sw / dim);
    static var h = Math.floor(sh / dim);

    static function main() {
        Perlin3D.initNoise();

        var chunks = [for (y in 0...h) for (x in 0...w) {
            var data = [for (j in 0...dim) for (i in 0...dim) {
                Perlin3D.noise((x * dim + i) * perlinScale,
                               (y * dim + j) * perlinScale,
                               1.5) < threshold;
            }];
            var opaque = [true, true, true, true]; // x+ x-, y+, y-
            for (i in 0...dim) {
                opaque[0] = opaque[0] && data[i * dim + (dim - 1)];
                opaque[1] = opaque[1] && data[i * dim];
                opaque[2] = opaque[2] && data[i + (dim - 1) * dim];
                opaque[3] = opaque[3] && data[i];
            }
            var full = true;
            var allair = true;
            for (i in 0...dim * dim) {
                if (data[i]) {
                    allair = false;
                }
                else {
                    full = false;
                }
            }
            {
                opaque: opaque,
                full: full,
                allair: allair,
                data: data
            };
        }];
        for (y in 0...h) for (x in 0...w) {
            var chunk = chunks[y * w + x];
            if (!chunk.full) {
                continue;
            }
            var allneighbours = true;
            for (i in 0...dim) {
                if (x != w-1 && !chunks[y * w + x + 1].data[i * dim]) {
                    allneighbours = false;
                    break;
                }
                if (x != 0 && !chunks[y * w + x - 1].data[i * dim + (dim - 1)]) {
                    allneighbours = false;
                    break;
                }
                if (y != h-1 && !chunks[(y + 1) * w + x].data[i + (dim - 1) * dim]) {
                    allneighbours = false;
                    break;
                }
                if (y != 0 && !chunks[(y - 1) * w + x].data[i]) {
                    allneighbours = false;
                    break;
                }
            }
            chunk.full = chunk.full && allneighbours;
        }

        var map = new flash.display.BitmapData(sw, sh, false, 0xffffff);
        for (y in 0...sh) for (x in 0...sw) {
            var chunkX = Std.int(x / dim);
            var chunkY = Std.int(y / dim);
            var blockX = x % dim;
            var blockY = y % dim;
            var chunk = chunks[chunkY * w + chunkX];
            if (chunk.data[blockY * dim + blockX])
                 map.setPixel(x, y, (chunkX + chunkY) % 2 == 0 ? 0xa0a0a0 : 0xb0b0b0);
            else map.setPixel(x, y, 0xffffff);
        }
        var bit;
        flash.Lib.current.addChild(bit = new flash.display.Bitmap(map));
        bit.alpha = 0.5;

        var debug = new BitmapDebug(sw, sh, 0xffffff, true);
        flash.Lib.current.addChild(debug.display);

#if !js
        function drawFrustum(frustum:Array<Plane>, colour:Int) {
            function intersect(a: Plane, b: Plane) {
                var det = a[0] * b[1] - a[1] * b[0];
                if (det == 0) return null;
                var invDet = 1 / det;
                return Vec2.get(
                    (a[1]*b[2] - a[2]*b[1]) * invDet,
                    (a[2]*b[0] - a[0]*b[2]) * invDet
                );
            }

            for (p in frustum) {
                var list = [];

                var p0, p1;
                if (p[1] != 0) {
                    var y0 = -p[2]/p[1];
                    var y1 = (-p[2]-p[0]*sw)/p[1];
                    p0 = Vec2.get(0, y0);
                    p1 = Vec2.get(sw, y1);
                }
                else {
                    var x0 = -p[2]/p[0];
                    var x1 = (-p[2]-p[1]*sh)/p[0];
                    p0 = Vec2.get(x0, 0);
                    p1 = Vec2.get(x1, sh);
                }

                for (q in frustum) if (p != q) {
                    if (p0 != null && !inside(p0, q)) {
                        p0 = null;
                    }
                    if (p1 != null && !inside(p1, q)) {
                        p1 = null;
                    }
                    var int = intersect(p, q);
                    if (int != null) {
                        for (r in frustum) if (r != p && r != q) {
                            if (!inside(int, r)) {
                                int = null;
                                break;
                            }
                        }
                    }
                    if (int != null) {
                        list.push(int);
                    }
                }
                if (p0 != null) {
                    list.push(p0);
                }
                if (p1 != null) {
                    list.push(p1);
                }
                list.sort(function (a, b) {
                    var del = (a.x * p[1] - a.y * p[0]) - (b.x * p[1] - b.y * p[0]);
                    return del < 0 ? -1 : del > 0 ? 1 : 0;
                });
                debug.drawLine(list[0], list[list.length - 1], colour);
            }
        }
        function napeAABB(aabb:AABB) {
            return new nape.geom.AABB(aabb[0], aabb[1], aabb[2] - aabb[0], aabb[3] - aabb[1]);
        }
        function napeAABBxy(x0: Float, y0: Float, x1: Float, y1: Float) {
            return new nape.geom.AABB(x0, y0, (x1 + 1 - x0), (y1 + 1 - y0));
        }
#end

#if !js
        var draw = true;
        flash.Lib.current.stage.addEventListener(flash.events.KeyboardEvent.KEY_DOWN, function (_) {
            draw = !draw;
        });
        debug.transform = nape.geom.Mat23.scale(dim, dim);
#end

        var cameraFrustum = [];
        var visible = [];
        var numVisible = 0;
        var frustum = [];
        var occluders = [for (y in 0...h) for (x in 0...w) new OccluderCell(x, y, 0, -1)];
        var occ = [];
        var numOCC = 0;
        var timestamp = 0;
        var previousCamera0 = -1.0;
        var previousCamera1 = -1.0;
        var ave:Null<Float> = null;
        var text = new flash.text.TextField();
        var idim = 1 / dim;
        flash.Lib.current.addChild(text);
        flash.Lib.current.stage.addEventListener(flash.events.MouseEvent.MOUSE_MOVE, function (_) {
#if !js
            if (draw) debug.clear();
#end
            var camera0 = flash.Lib.current.mouseX * idim;
            var camera1 = flash.Lib.current.mouseY * idim;

            var direction0 = camera0 - previousCamera0;
            var direction1 = camera1 - previousCamera1;
            previousCamera0 += (camera0 - previousCamera0) * 0.04;
            previousCamera1 += (camera1 - previousCamera1) * 0.04;
            if (direction0 == 0 && direction1 == 0) {
                return;
            }

            var dl = 1 / Math.sqrt(direction0 * direction0 + direction1 * direction1);
            direction0 *= dl;
            direction1 *= dl;

            var fov = -50 * Math.PI / 180;
            // near
            slane(cameraFrustum, 0,
                  camera0 + direction0 * 20 * idim,
                  camera1 + direction1 * 20 * idim,
                  camera0 - direction1 + direction0 * 20 * idim,
                  camera1 + direction0 + direction1 * 20 * idim);
            // far
            var rad = 16*5;
            slane(cameraFrustum, 1,
                  camera0 - direction1 + direction0 * rad,
                  camera1 + direction0 + direction1 * rad,
                  camera0 + direction0 * rad,
                  camera1 + direction1 * rad);
            var angle = Math.atan2(direction1, direction0);
            angle -= fov / 2;
            direction0 = Math.cos(angle);
            direction1 = Math.sin(angle);
            // left
            slane(cameraFrustum, 2,
                  camera0,
                  camera1,
                  camera0 + direction0,
                  camera1 + direction1);
            angle += fov;
            direction0 = Math.cos(angle);
            direction1 = Math.sin(angle);
            // right
            slane(cameraFrustum, 3,
                  camera0 + direction0,
                  camera1 + direction1,
                  camera0,
                  camera1);

#if !js
            if (draw) debug.drawCircle(Vec2.get(camera0, camera1), 2 * idim, 0xff0000);
            if (draw) drawFrustum(stop(cameraFrustum, 4), 0xff0000);
#end
            var pt = flash.Lib.getTimer();
            var kkc = 10;
            for (kk in 0...kkc) {
                numVisible = 0;
                timestamp++;
                var ocs = [];
                for (y in 0...h) for (x in 0...w) {
                    var chunk = chunks[y * w + x];
                    if (chunk.allair) {
                        continue;
                    }
                    if (aabbInsideSxy(x, y, cameraFrustum, 4)) {
                        if (chunk.full) {
                            var dx = camera0 - (x + 0.5);
                            var dy = camera1 - (y + 0.5);
                            var oc = occluders[y * w + x];
                            oc.timestamp = timestamp;
                            oc.distance = dx * dx + dy * dy;
                            ocs.push(oc);
                            continue;
                        }
                        //clipAABBS(aabb, cameraFrustum, 4);
                        var v;
                        var occluder = (chunk.opaque[1] || camera0 >= x) &&
                                       (chunk.opaque[0] || camera0 <= x + 1) &&
                                       (chunk.opaque[3] || camera1 >= y) &&
                                       (chunk.opaque[2] || camera1 <= y + 1);
                        if (occluder) {
                            var dx = camera0 - (x + 0.5);
                            var dy = camera1 - (y + 0.5);
                            var oc = occluders[y * w + x];
                            oc.timestamp = timestamp;
                            oc.distance = dx * dx + dy * dy;
                            ocs.push(oc);
                        }
                        if (numVisible >= visible.length) {
                            visible.push(new Visible(
                                x,
                                y,
                                true
                            ));
                        }
                        else {
                            var v = visible[numVisible];
                            v.x = x;
                            v.y = y;
                            v.renderable = true;
                        }
                        numVisible++;
                    }
                }

                // Iterative combiner
                // Start at occluder closest to camera, and expand out from camera to find largest occluding rectangle
                // occluder does not have to be a covering, it can expand out into non-occluder territory as long as
                // such territory is hidden from the camera already.
                ocs.sort(function (a, b) return a.distance < b.distance ? -1 : 1);

                numOCC = 0;
                while (ocs.length != 0) {
                    var os = ocs.shift();
                    var x0 = os.x;
                    var y0 = os.y;
                    if (occluders[y0 * w + x0].timestamp != timestamp) continue;

                    var x1 = x0;
                    var y1 = y0;
                    if (draw) debug.drawAABB(napeAABBxy(x0, y0, x1, y1), 0x008888);
                    // determine directions we should try and expand to given resultant frustum
                    if (camera0 < x0 && camera1 < y0) {
                        // search +x +y
                        while (x1 < w-1 && occluders[y0 * w + x1 + 1].timestamp == timestamp) x1++;
                        while (y1 < h-1 && occluders[(y1 + 1) * w + x0].timestamp == timestamp) y1++;
                    }
                    else if (camera0 < x0 && camera1 > y0+1) {
                        // search +x -y
                        while (x1 < w-1 && occluders[y0 * w + x1 + 1].timestamp == timestamp) x1++;
                        while (y0 > 0 && occluders[(y0 - 1) * w + x0].timestamp == timestamp) y0--;
                    }
                    else if (camera0 > x0+1 && camera1 < y0) {
                        // search -x +y
                        while (x0 > 0 && occluders[y0 * w + x0 - 1].timestamp == timestamp) x0--;
                        while (y1 < h-1 && occluders[(y1 + 1) * w + x1].timestamp == timestamp) y1++;
                    }
                    else if (camera0 > x0+1 && camera1 > y0+1) {
                        // search -x -y
                        while (x0 > 0 && occluders[y0 * w + x0 - 1].timestamp == timestamp) x0--;
                        while (y0 > 0 && occluders[(y0 - 1) * w + x1].timestamp == timestamp) y0--;
                    }
                    else if (camera0 < x0 || camera0 > x0+1) {
                        // search +-y
                        while (y0 > 0 && occluders[(y0 - 1) * w + x0].timestamp == timestamp) y0--;
                        while (y1 < h-1 && occluders[(y1 + 1) * w + x0].timestamp == timestamp) y1++;
                    }
                    else {
                        // search +-x
                        while (x0 > 0 && occluders[y0 * w + x0 - 1].timestamp == timestamp) x0--;
                        while (x1 < w-1 && occluders[y0 * w + x1 + 1].timestamp == timestamp) x1++;
                    }
                    if (numOCC >= occ.length) {
                        occ.push(new Occluder(
                            x0,
                            y0,
                            x1,
                            y1,
                            timestamp
                        ));
                    }
                    else {
                        var o = occ[numOCC];
                        o.x0 = x0;
                        o.x1 = x1;
                        o.y0 = y0;
                        o.y1 = y1;
                        o.timestamp = timestamp;
                    }
                    numOCC++;
                    for (y in y0...y1+1) {
                        for (x in x0...x1+1) {
                            occluders[y * w + x].timestamp = -1;
                        }
                    }
                }

                var ocs = occ;
                for (k in 0...numOCC) {
                    var v = ocs[k];
                    if (v.timestamp != timestamp) continue;
                    v.timestamp = -1;
                    var pc = shadowFrustumSxy(v.x0, v.y0, v.x1, v.y1, camera0, camera1, frustum);
#if !js
                    if (draw) debug.drawAABB(napeAABBxy(v.x0, v.y0, v.x1, v.y1), 0xff00ff);
                    drawFrustum(stop(frustum, pc), 0xff00ff);
#end
                    var i = 0;
                    while (i < numVisible) {
                        var q = visible[i];
                        if (aabbContainsxy2(v.x0, v.y0, v.x1, v.y1, q.x, q.y) || aabbTotallyInsideSxy(q.x, q.y, frustum, pc)) {
                            q.renderable = false;
                            visible[i] = visible[numVisible - 1];
                            visible[numVisible - 1] = q;
                            --numVisible;
                        }
                        else {
                            i++;
                        }
                    }
                    for (i in 0...numOCC) {
                        var os = ocs[i];
                        if (os.timestamp == timestamp && os != v && aabbTotallyInsideSxy2(os.x0, os.y0, os.x1, os.y1, frustum, pc)) {
                            os.timestamp = -1;
                        }
                    }
                }

#if !js
                if (draw) for (v in 0...numVisible) {
                    var v = visible[v];
                    if (v.renderable) {
                        debug.drawAABB(napeAABB([v.x +1,v.y +1,(v.x + 1)-1,(v.y + 1)-1]), 0xff0000);
                    }
                }
#end
            }
            var ct = flash.Lib.getTimer();
            var dt = (ct - pt) / kkc;
            pt = ct;
            var ave = ave == null ? dt : (ave * 0.98) + (dt * 0.02);
            text.text = '${ave}ms';
            if (draw) debug.flush();
        });
    }
}
