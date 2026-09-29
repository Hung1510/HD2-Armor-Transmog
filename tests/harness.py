"""
Test harness: runs the REAL generated mod Lua (engine + panel) in LuaJIT against a
fake game. The Windows memory API, the engine's GUI (stingray), the keyboard and
the mouse are mocked; the fake memory holds one perk record per armor passive,
laid out like the game's (LDLD header, 56-byte record, inline rows).

    from harness import FakeGame
    g = FakeGame("build/test.lua")      # a Lua file from: picker.py build X --dump-lua build/test.lua
    g.tick(400)                         # scan + apply
    g.rows(7)                           # Med-Kit's passive rows as the game now sees them

Needs: pip install lupa   (pillow too, for FakeGame.render)
"""
import os
import struct
import sys

from lupa.luajit21 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import picker  # noqa: E402

TYPE_PASSIVE = 0x63CE0FEB
GAME_BASE = 0x10000000

MOCK = r"""
DRAW, WORLDS, KEYS, CURSOR, MOUSE_DOWN = {}, { {}, {} }, {}, { 0, 0 }, false
local function callable(fields, make)
    return setmetatable(fields, { __call = function(_, ...) return make(...) end })
end
stingray = {
    Vector3 = callable({ x = function(v) return v[1] end }, function(x, y, z) return { x, y, z } end),
    Vector2 = callable({ x = function(v) return v[1] end }, function(x, y) return { x, y } end),
    Color = function(a, r, g, b) return { a, r, g, b } end,
    Gui = {
        resolution = function() return 1920, 1080 end,
        rect = function(g, p, s, c) DRAW[#DRAW + 1] = { 'rect', p[1], p[2], p[3], s[1], s[2], c[1], c[2], c[3], c[4] } end,
        text = function(g, t, f, size, m, p, c) DRAW[#DRAW + 1] = { 'text', p[1], p[2], p[3], size, t, c[1], c[2], c[3], c[4] } end,
        text_extents = function(g, t, f, size) return { 0, 0 }, { #t * size * 0.52, size } end,
        material = function() return {} end,
    },
    Material = { set_texture = function() end },
    World = { create_screen_gui = function(w) DRAW = {}; return {} end, destroy_gui = function() DRAW = {} end },
    Application = { worlds = function() return WORLDS end, main_world = function() return WORLDS[1] end,
                    can_get = function() return true end },
    IdString64 = { from_hex = function(s) return s end },
    Mouse = { button = function() return MOUSE_DOWN and 1 or 0 end, button_id = function() return 0 end },
}
PP_TEST_INPUT = {
    focused = function() return true end,
    key_down = function(vk) return KEYS[vk] == true end,
    cursor = function() return CURSOR[1], CURSOR[2], 1920, 1080 end,
    show_cursor = function() return 0 end,
    get_clip = function() return nil end,
    set_clip = function() end,
    get_clipboard = function() return CLIP end,
    set_clipboard = function(text) CLIP = text; return true end,
}
CLIP = nil
CowboyBingusModLoader = { api = 1 }
FAKE_T, FAKE_NOW = 1000, 0
os.time = function() return FAKE_T end
update = function() end
"""


class FakeGame:
    def __init__(self, lua_path, retire=None, appdata=None, perks=None, game=None, junk_mb=0):
        # game: {perk: (name, rows, stats)} the fake game holds; default = the catalog
        src = open(lua_path, encoding="utf-8").read()
        if retire is not None:
            src = src.replace("retire = true,", "retire = %s," % ("true" if retire else "false"), 1)
            src = src.replace("retire = false,", "retire = %s," % ("true" if retire else "false"), 1)
        assert "    api = build_api()\n" in src, "engine startup changed; update the test hook"
        src = src.replace("    api = build_api()\n", "    api = TEST_API\n")
        if appdata:
            os.environ["LOCALAPPDATA"] = appdata
        else:
            os.environ.pop("LOCALAPPDATA", None)

        self.L = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.mem = {}
        self.nalloc = 0
        self.game = game or picker.CATALOG
        self.bytes_read = 0
        if junk_mb:   # a big unrelated allocation, like the rest of the game's memory
            self.mem[0x40000000] = bytearray(junk_mb * 1024 * 1024)
        self._build_memory(perks or list(self.game))
        g = self.L.globals()
        self.L.execute(MOCK.encode())
        g[b"TEST_API"] = self.L.table_from({
            b"read": self._read, b"write": self._write, b"alloc": self._alloc, b"regions": self._regions,
            b"address_of": lambda t: None, b"mkdir": self._mkdir,
            b"now": lambda: self.L.globals()[b"FAKE_NOW"], b"module_base": lambda n: None,
        })
        self.L.execute(src.encode("utf-8"))
        self.state = g[b"PassivePickerV4"]

    # ------------------------------------------------------------- memory
    def _region(self, addr, size):
        for b, buf in self.mem.items():
            if b <= addr and addr + size <= b + len(buf):
                return b, buf
        return None, None

    def _read(self, addr, size):
        addr, size = int(addr), int(size)
        self.bytes_read += size
        b, buf = self._region(addr, size)
        return None if buf is None else bytes(buf[addr - b:addr - b + size])

    def _write(self, addr, data):
        addr, data = int(addr), bytes(data)
        b, buf = self._region(addr, len(data))
        if buf is None:
            return False
        buf[addr - b:addr - b + len(data)] = data
        return True

    def _alloc(self, size):
        base = 0x20000000 + self.nalloc * 0x100000
        self.nalloc += 1
        self.mem[base] = bytearray(int(size))
        return base

    def _regions(self):
        t = self.L.table()
        for i, (b, buf) in enumerate(sorted(self.mem.items(), key=lambda kv: -len(kv[1]))):
            t[i + 1] = self.L.table_from({b"base": b, b"size": len(buf), b"allocation_base": b})
        return t

    def _mkdir(self, path):
        os.makedirs(path.decode() if isinstance(path, bytes) else path, exist_ok=True)
        return True

    def _build_memory(self, perks):
        game = bytearray(0x20000)
        self.mem[GAME_BASE] = game
        self.records = {}
        off = 0x100
        for pid in perks:
            name, rows, stats = self.game[pid]
            rec = GAME_BASE + off + 24
            body = bytearray(56)
            struct.pack_into("<I", body, 0, pid)
            struct.pack_into("<QQ", body, 16, rec + 56 if rows else 0, len(rows))
            struct.pack_into("<QQ", body, 32, rec + 56 + 16 * len(rows) if stats else 0, len(stats))
            for i, (m, t, v) in enumerate(rows):
                body += struct.pack("<IIfI", m, t, v, 0xD0000000 + pid * 16 + i)   # game rows carry a text hash
            for s, a, b in stats:
                body += struct.pack("<Iff", s, a, b)
            hdr = b"LDLD" + struct.pack("<III", 1, TYPE_PASSIVE, len(body)) + b"\0" * 8
            game[off:off + 24 + len(body)] = hdr + body
            self.records[pid] = rec
            off += (24 + len(body) + 64 + 15) & ~15
        self.pristine = bytes(game)

    # ------------------------------------------------------------- driving
    def tick(self, n=1, dt=1 / 60):
        upd = self.L.eval(b"update")
        g = self.L.globals()
        for _ in range(n):
            g[b"FAKE_NOW"] = g[b"FAKE_NOW"] + dt
            upd()

    def advance_wall(self, seconds):
        g = self.L.globals()
        g[b"FAKE_T"] = g[b"FAKE_T"] + seconds

    def desc(self, pid, which="pm"):
        rec = self.records[pid]
        return self._read(rec + (16 if which == "pm" else 32), 16)

    def rows(self, pid):
        rec = self.records[pid]
        pp, pc = struct.unpack("<QQ", self._read(rec + 16, 16))
        return [struct.unpack("<IIfI", self._read(pp + 16 * i, 16)) for i in range(pc)]

    def stats(self, pid):
        rec = self.records[pid]
        sp, sc = struct.unpack("<QQ", self._read(rec + 32, 16))
        return [struct.unpack("<Iff", self._read(sp + 12 * i, 12)) for i in range(sc)]

    def record_bytes(self, pid):
        rec = self.records[pid]
        return self._read(rec - 24, 24 + 56 + 16 * 8)

    def pristine_record_bytes(self, pid):
        rec = self.records[pid] - GAME_BASE
        return self.pristine[rec - 24: rec - 24 + 24 + 56 + 16 * 8]

    def phase(self):
        return self.state[b"phase"].decode()

    # ------------------------------------------------------------- panel
    def key(self, vk, frames=2):
        keys = self.L.globals()[b"KEYS"]
        keys[vk] = True
        self.tick(frames)
        keys[vk] = None
        self.tick(frames)

    def regions(self):
        ui = self.state[b"ui"]
        out = {}
        regs = ui[b"regions"]
        for i in range(1, len(regs) + 1):
            r = regs[i]
            out[r[b"key"].decode()] = (r[b"x"], r[b"y"], r[b"w"], r[b"h"], r[b"enabled"])
        return out

    def click(self, key):
        regs = self.regions()
        assert key in regs, "no region %r (have %s)" % (key, sorted(regs)[:40])
        x, y, w, h, _ = regs[key]
        g = self.L.globals()
        cur = g[b"CURSOR"]
        cur[1], cur[2] = x + w / 2, 1080 - (y + h / 2)
        self.tick(2)
        g[b"MOUSE_DOWN"] = True
        self.tick(1)
        g[b"MOUSE_DOWN"] = False
        self.tick(2)

    def type_text(self, text):
        keys = self.L.globals()[b"KEYS"]
        for ch in text:
            shift = ch.isupper() or ch in "_"
            vk = {".": 0xBE, "-": 0xBD, "_": 0xBD, "+": 0x6B, " ": 0x20}.get(ch)
            if vk is None:
                vk = 0x30 + int(ch) if ch.isdigit() else ord(ch.upper())
            if shift:
                keys[0x10] = True
            self.key(vk, 1)
            if shift:
                keys[0x10] = None

    def clipboard(self, value=None):
        g = self.L.globals()
        if value is not None:
            g[b"CLIP"] = value.encode() if isinstance(value, str) else value
        c = g[b"CLIP"]
        return c.decode() if isinstance(c, bytes) else c

    def ctrl(self, vk):
        keys = self.L.globals()[b"KEYS"]
        keys[0x11] = True
        self.key(vk, 2)
        keys[0x11] = None
        self.tick(2)

    def draw_calls(self):
        d = self.L.globals()[b"DRAW"]
        out = []
        for i in range(1, len(d) + 1):
            c = d[i]
            out.append([c[k] for k in range(1, len(c) + 1)])
        return out

    def texts(self):
        return [c[5].decode("utf-8", "replace") for c in self.draw_calls() if c[0] == b"text"]

    def render(self, path, width=1920, height=1080, crop=True):
        from PIL import Image, ImageDraw, ImageFont
        img = Image.new("RGB", (width, height), (60, 70, 60))
        dr = ImageDraw.Draw(img, "RGBA")
        calls = sorted(self.draw_calls(), key=lambda c: c[3])
        fonts = {}
        for c in calls:
            if c[0] == b"rect":
                _, x, y, z, w, h, a, r, g, b = c
                dr.rectangle([x, height - y - h, x + w, height - y], fill=(int(r), int(g), int(b), int(a)))
            else:
                _, x, y, z, size, t, a, r, g, b = c
                sz = max(6, int(round(size)))
                if sz not in fonts:
                    try:
                        fonts[sz] = ImageFont.truetype("DejaVuSans.ttf", sz)
                    except OSError:
                        fonts[sz] = ImageFont.load_default()
                top = height - y - size * 0.8
                dr.text((x, top), t.decode("utf-8", "replace"), font=fonts[sz], fill=(int(r), int(g), int(b), int(a)))
        if crop:
            rects = [c for c in calls if c[0] == b"rect"]
            if rects:
                x0 = min(c[1] for c in rects); x1 = max(c[1] + c[4] for c in rects)
                y0 = min(height - c[2] - c[5] for c in rects); y1 = max(height - c[2] for c in rects)
                img = img.crop((int(x0) - 10, int(y0) - 10, int(x1) + 10, int(y1) + 10))
        img.save(path)
        return path
