#!/usr/bin/env python3
"""
The game-window input filter's machine code (tools/window_filter.py), run on an x64
emulator (unicorn) exactly as tools/panel.lua lays it out in memory.

    pip install unicorn keystone-engine     # keystone only for the "same as the source" check
    python tests/test_window_filter.py

1. The bytes in tools/panel.lua are the assembled tools/window_filter.py.
2. Flag off: every message passes to the game's procedure with the right arguments
   (CallWindowProcW(previous, window, message, wParam, lParam), 5th on the stack, stack
   aligned); its return value comes back.
3. Flag on: key presses and typed characters are dropped, key releases and Alt keys pass;
   button presses and double clicks are dropped; a release passes only if the game saw its
   press; wheel turns are added up (signed) and dropped; mouse movement passes.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import window_filter as wf  # noqa: E402

failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


try:
    from unicorn import UC_ARCH_X86, UC_HOOK_CODE, UC_MODE_64, Uc
    from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_R8, UC_X86_REG_R9, UC_X86_REG_RAX, UC_X86_REG_RCX,
                                   UC_X86_REG_RDX, UC_X86_REG_RIP, UC_X86_REG_RSP)
except ImportError:
    print("unicorn not installed; window filter emulation skipped")
    sys.exit(0)

panel = open(os.path.join(HERE, "..", "tools", "panel.lua"), encoding="utf-8").read()
code = wf.code_from_lua(panel)
try:
    check(code == wf.assemble(), "tools/panel.lua carries the assembled tools/window_filter.py (%d bytes)" % len(code))
except ImportError:
    print("keystone not installed; source check skipped")
table = [int(x, 16) for x in __import__("re").search(r"FILTER_TABLE = \{([^}]*)\}", panel).group(1).replace(" ", "").split(",") if x]
check(table == wf.TABLE, "... and its message table")

BLOCK, CALL, STACK, RET = 0x100000, 0x200000, 0x300000, 0x400000
WINDOW, PREV = 0x1234_5678_9ABC, 0x7FFF_0000_1111
mu = Uc(UC_ARCH_X86, UC_MODE_64)
for base in (BLOCK, CALL, STACK, RET):
    mu.mem_map(base, 0x10000)
page = bytearray(4096)
struct.pack_into("<QQ", page, 16, PREV, CALL)
page[48:48 + len(table)] = bytes(table)
page[64:74] = b"\x49\xBA" + struct.pack("<Q", BLOCK)          # mov r10, <block>
page[74:74 + len(code)] = code
mu.mem_write(BLOCK, bytes(page))
mu.mem_write(CALL, b"\xB8\x77\x00\x00\x00\xC3")                # fake CallWindowProcW: mov eax, 0x77; ret
calls = []


def at_call(uc, address, size, _):
    if address == CALL:
        rsp = uc.reg_read(UC_X86_REG_RSP)
        fifth = struct.unpack("<Q", uc.mem_read(rsp + 0x28, 8))[0]
        calls.append((uc.reg_read(UC_X86_REG_RCX), uc.reg_read(UC_X86_REG_RDX), uc.reg_read(UC_X86_REG_R8) & 0xFFFFFFFF,
                      uc.reg_read(UC_X86_REG_R9), fifth, rsp % 16))


mu.hook_add(UC_HOOK_CODE, at_call, begin=CALL, end=CALL)


def flag(on):
    mu.mem_write(BLOCK, struct.pack("<I", 1 if on else 0))


def u32(off, signed=False):
    return struct.unpack("<i" if signed else "<I", mu.mem_read(BLOCK + off, 4))[0]


def send(msg, wparam=0, lparam=0xABCD):
    """the game window gets a message: (passed to the game?, return value)"""
    calls.clear()
    rsp = STACK + 0x8000 - 8                                    # as after a call: rsp = 8 (mod 16)
    mu.mem_write(rsp, struct.pack("<Q", RET))
    mu.reg_write(UC_X86_REG_RSP, rsp)
    mu.reg_write(UC_X86_REG_RCX, WINDOW)
    mu.reg_write(UC_X86_REG_RDX, 0xFFFFFFFF_00000000 | msg)        # only edx counts
    mu.reg_write(UC_X86_REG_R8, wparam)
    mu.reg_write(UC_X86_REG_R9, lparam)
    mu.reg_write(UC_X86_REG_RAX, 0xDEAD)
    mu.emu_start(BLOCK + 64, RET)
    assert mu.reg_read(UC_X86_REG_RIP) == RET and mu.reg_read(UC_X86_REG_RSP) == rsp + 8, "returned to its caller"
    if calls:
        c = calls[0]
        assert c[:5] == (PREV, WINDOW, msg, wparam, lparam), "CallWindowProcW args %r" % (c,)
        assert c[5] == 8, "stack aligned at the call"
    return bool(calls), mu.reg_read(UC_X86_REG_EAX)


KEYDOWN, KEYUP, CHAR, DEADCHAR, SYSKEYDOWN, UNICHAR = 0x100, 0x101, 0x102, 0x103, 0x104, 0x109
MOVE, LDOWN, LUP, LDBL, RDOWN, RUP, RDBL, MDOWN, MUP, WHEEL, XDOWN, XUP = (
    0x200, 0x201, 0x202, 0x203, 0x204, 0x205, 0x206, 0x207, 0x208, 0x20A, 0x20B, 0x20C)

# ------------------------------------------------------------------ flag off
flag(False)
check(all(send(m) == (True, 0x77) for m in (KEYDOWN, CHAR, MOVE, WHEEL, 0x10, 0x5)),
      "flag off: messages pass to the game's procedure (args, 5th on the stack, aligned) and return its value")
send(LDOWN)
send(XDOWN, 0x10000)
check(u32(32) == 0b1001, "flag off: presses the game saw are noted (left, X)")
check(u32(4) == 0, "flag off: the wheel isn't counted")

# ------------------------------------------------------------------ flag on
flag(True)
check([send(m)[0] for m in (KEYDOWN, CHAR, DEADCHAR, UNICHAR)] == [False] * 4 and u32(8) == 4,
      "flag on: key presses and typed characters are dropped (and counted)")
check(send(KEYDOWN)[1] == 0, "... returning 0 (handled)")
check(send(KEYUP)[0] and send(SYSKEYDOWN)[0], "key releases and Alt keys pass (nothing sticks; Alt+Tab works)")
check(not send(RDOWN)[0] and not send(RDBL)[0] and not send(MDOWN)[0] and not send(LDBL)[0], "button presses and double clicks are dropped")
check(send(LUP)[0] and u32(32) & 1 == 0, "a release passes when the game saw the press (left was down before)")
check(not send(LUP)[0], "... and not again")
check(not send(RUP)[0] and not send(MUP)[0], "releases of presses the game never saw are dropped")
check(send(XUP, 0x20000)[0] and u32(32) == 0, "X button release passes (its press was seen)")
send(WHEEL, 120 << 16)
send(WHEEL, (0x10000 - 360) << 16 | 0x8)
check(u32(4, signed=True) == -240 and send(WHEEL, 0)[0] is False, "wheel turns are added up, signed, and dropped")
check(send(MOVE)[0], "mouse movement passes (the cursor still moves)")

flag(False)
check(send(KEYDOWN)[0] and send(LDOWN)[0] and send(WHEEL)[0], "flag off again: everything passes")
check(u32(4, signed=True) == -240, "... the wheel total stays for the panel to read")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall window filter checks passed")
