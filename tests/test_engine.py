#!/usr/bin/env python3
"""
Offline test for tools/engine.lua - runs the REAL generated Lua in LuaJIT against
a fake copy of the game's perk table, with the Windows memory API mocked out.

    pip install lupa
    python tools/picker.py build examples/two-profiles.ini --dump-lua build/test.lua
    python tests/test_engine.py build/test.lua

It checks that the Med-Kit (7) and Siege-Ready (16) records get their rows,
overrides keep the game's description hash, an unrelated perk (9) is untouched,
and that retire=false re-applies once after the game resets a record.
This proves the engine logic, NOT that the game's layout still matches - that
only an in-game test can show.
"""
import struct
import sys

from lupa.luajit21 import LuaRuntime

TYPE_PASSIVE = 0x63CE0FEB


def run(lua_path, retire):
    src = open(lua_path, encoding="utf-8").read()
    src = src.replace("retire = true,", "retire = %s," % ("true" if retire else "false"), 1)
    assert "    api = build_api()\n" in src, "engine startup changed; update the test hook"
    src = src.replace("    api = build_api()\n", "    api = TEST_API\n")

    L = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    mem = {}

    def region_of(addr, size):
        for b, buf in mem.items():
            if b <= addr and addr + size <= b + len(buf):
                return b, buf
        return None, None

    def read(addr, size):
        addr, size = int(addr), int(size)
        b, buf = region_of(addr, size)
        return None if buf is None else bytes(buf[addr - b:addr - b + size])

    def write(addr, data):
        addr, data = int(addr), bytes(data)
        b, buf = region_of(addr, len(data))
        if buf is None:
            return False
        buf[addr - b:addr - b + len(data)] = data
        return True

    n = [0]

    def alloc(size):
        base = 0x20000000 + n[0] * 0x100000
        n[0] += 1
        mem[base] = bytearray(int(size))
        return base

    def regions():
        t = L.table()
        for i, (b, buf) in enumerate(sorted(mem.items(), key=lambda kv: -len(kv[1]))):
            t[i + 1] = L.table_from({b"base": b, b"size": len(buf), b"allocation_base": b})
        return t

    game = bytearray(0x4000)
    GB = 0x10000000
    mem[GB] = game

    def record(off, perk, rows, stats):
        rec = GB + off + 24
        body = bytearray(56)
        struct.pack_into("<I", body, 0, perk)
        struct.pack_into("<QQ", body, 16, rec + 56 if rows else 0, len(rows))
        struct.pack_into("<QQ", body, 32, rec + 56 + 16 * len(rows) if stats else 0, len(stats))
        for r in rows:
            body += struct.pack("<IIfI", *r)
        for s in stats:
            body += struct.pack("<Iff", *s)
        hdr = b"LDLD" + struct.pack("<III", 1, TYPE_PASSIVE, len(body)) + b"\0" * 8
        game[off:off + 24 + len(body)] = hdr + body
        return rec

    r7 = record(0x100, 7, [(0x2875F44A, 1, 2.0, 0xAAAA), (0x93EB16A7, 3, 2.0, 0xBBBB)], [])
    r16 = record(0x800, 16, [(0xCC530B21, 2, 1.3, 0xCCCC), (0x33C9C713, 2, 1.2, 0xDDDD)],
                 [(13, 0.0, 1.3), (12, 0.0, 1.2)])
    record(0x1000, 9, [(0xCB814D05, 2, 1.5, 0xEEEE)], [])
    snap9 = bytes(game[0x1000:0x1100])

    g = L.globals()
    g[b"TEST_API"] = L.table_from({b"read": read, b"write": write, b"alloc": alloc,
                                   b"regions": regions, b"address_of": lambda t: None,
                                   b"mkdir": lambda p: False})
    g[b"CowboyBingusModLoader"] = L.table_from({b"api": 1})
    L.execute(b"FAKE_T = 1000; os.time = function() return FAKE_T end; update = function() end")
    L.execute(src.encode("utf-8"))

    def tick(k):
        for _ in range(k):
            L.eval(b"update")()

    def dump(rec):
        pp, pc, sp, sc = struct.unpack_from("<QQQQ", read(rec, 56), 16)
        rows = [struct.unpack("<IIfI", read(pp + 16 * i, 16)) for i in range(pc)]
        stats = [struct.unpack("<Iff", read(sp + 12 * i, 12)) for i in range(sc)] if sc else []
        return pp, rows, stats

    tick(400)
    return dict(L=L, state=g[b"PassivePickerV4"], dump=dump, tick=tick, write=write,
                r7=r7, r16=r16, game=game, snap9=snap9)


def main(path):
    t = run(path, retire=True)
    st = t["state"]
    assert st[b"phase"] == b"done", st[b"status"]
    for name, rec in (("Med-Kit", t["r7"]), ("Siege-Ready", t["r16"])):
        pp, rows, stats = t["dump"](rec)
        assert pp != rec + 56, name + " array was not moved"
        # the game's own rows keep their description hash
        assert rows[0][3] != 0 and rows[1][3] != 0, name + " lost the description hash"
        print("%-12s %d rows, %d stats" % (name, len(rows), len(stats)))
        for r in rows:
            print("    0x%08X type %d value %-8g desc 0x%X" % (r[0], r[1], round(r[2], 4), r[3]))
        for s in stats:
            print("    stat %-3d %g %g" % (s[0], round(s[1], 4), round(s[2], 4)))
    assert bytes(t["game"][0x1000:0x1100]) == t["snap9"], "perk 9 was modified"

    t = run(path, retire=False)
    first = t["dump"](t["r7"])
    t["write"](t["r7"] + 16, struct.pack("<QQ", t["r7"] + 56, 2))   # game reloads record
    t["L"].execute(b"FAKE_T = FAKE_T + 10")
    t["tick"](5)
    assert t["dump"](t["r7"])[1:] == first[1:], "restack produced a different result"
    t["L"].execute(b"FAKE_T = FAKE_T + 10")
    t["tick"](5)
    assert t["state"][b"reapplied"] == 1, "re-apply is not idempotent"
    print("PASS")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
