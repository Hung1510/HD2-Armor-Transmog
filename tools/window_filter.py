#!/usr/bin/env python3
"""
The game-window input filter: a tiny x64 window procedure that the panel puts in front of
the game window's own while the game should get no input (the panel is open).

Helldivers 2 reads mouse movement through Windows raw input (the panel unregisters that),
but key presses, typed characters, mouse buttons and the wheel arrive as window messages.
This filter runs on the window's thread, without Lua:

  flag off  everything passes to the game's procedure; mouse button presses are noted
  flag on   key presses and typed characters are dropped (releases pass, so no key sticks);
            mouse button presses are dropped; a release passes only if the game saw its
            press; wheel turns are added up for the panel's own scrolling and dropped

Block (one 4 KB page, read / write / execute; the panel fills the data, the code is at +64):
  +0  u32 flag             +4  i32 wheel total (120 a notch, + = away from you)
  +8  u32 keys dropped     +12 u32 button presses / releases dropped
  +16 u64 previous procedure                +24 u64 CallWindowProcW
  +32 u32 buttons the game saw pressed (bit 0 left, 1 right, 2 middle, 3 X)
  +48 u8[13] per message WM_LBUTTONDOWN + n: kind * 16 + button (kind 1 press, 2 release)
  +64 code: mov r10, <block>; then CODE below

    python tools/window_filter.py      # assembles CODE (needs keystone-engine) and prints
                                       # the bytes for tools/panel.lua (FILTER_CODE)
"""
import sys

DATA = 64
TABLE = [0x10, 0x20, 0x10, 0x11, 0x21, 0x11, 0x12, 0x22, 0x12, 0x00, 0x13, 0x23, 0x13]

# Windows x64: rcx window, edx message, r8 wParam, r9 lParam; r10 = the block
CODE = """
    lea eax, [rdx - 0x201]
    cmp eax, 12
    ja not_mouse
    movzx r11d, byte ptr [r10 + rax + 48]
    test r11d, r11d
    jz wheel
    mov eax, r11d
    and r11d, 15
    shr eax, 4
    cmp eax, 2
    je release
    cmp dword ptr [r10], 0
    jne drop_button
    bts dword ptr [r10 + 32], r11d
    jmp pass
release:
    btr dword ptr [r10 + 32], r11d
    jc pass
drop_button:
    inc dword ptr [r10 + 12]
    xor eax, eax
    ret
wheel:
    cmp edx, 0x20A
    jne pass
    cmp dword ptr [r10], 0
    je pass
    mov rax, r8
    shr rax, 16
    movsx eax, ax
    add dword ptr [r10 + 4], eax
    xor eax, eax
    ret
not_mouse:
    cmp dword ptr [r10], 0
    je pass
    cmp edx, 0x100
    je drop_key
    cmp edx, 0x102
    je drop_key
    cmp edx, 0x103
    je drop_key
    cmp edx, 0x109
    je drop_key
    jmp pass
drop_key:
    inc dword ptr [r10 + 8]
    xor eax, eax
    ret
pass:
    sub rsp, 0x38
    mov qword ptr [rsp + 0x20], r9
    mov r9, r8
    mov r8d, edx
    mov rdx, rcx
    mov rcx, qword ptr [r10 + 16]
    call qword ptr [r10 + 24]
    add rsp, 0x38
    ret
"""


def assemble():
    from keystone import KS_ARCH_X86, KS_MODE_64, Ks
    ks = Ks(KS_ARCH_X86, KS_MODE_64)            # kept alive until the bytes are copied
    code, _ = ks.asm(CODE, 0)
    out = bytes(code)
    del ks
    return out


def code_from_lua(text):
    """the FILTER_CODE bytes as written in tools/panel.lua"""
    import re
    m = re.search(r"FILTER_CODE = \{(.*?)\}", text, re.S)
    return bytes(int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{2})", m.group(1))) if m else b""


def lua_lines(code):
    hexes = ["0x%02X" % b for b in code]
    return "\n".join("    " + ", ".join(hexes[i:i + 16]) + "," for i in range(0, len(hexes), 16))


if __name__ == "__main__":
    c = assemble()
    print("-- %d bytes, from tools/window_filter.py" % len(c))
    print(lua_lines(c))
    sys.exit(0)
