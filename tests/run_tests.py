#!/usr/bin/env python3
"""Load the addon into a Lua 5.1 runtime with a mocked WoW API and run tests.

Requires the `lupa` package (pip install lupa).
    python3 tests/run_tests.py
"""

import os
import re
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "Twinkle"
ADDON_DIR = os.path.join(ROOT, ADDON)
TESTS = os.path.join(ROOT, "tests")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def toc_files():
    files = []
    for line in read(os.path.join(ADDON_DIR, ADDON + ".toc")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line)
    return files


def run(locale):
    print(f"[{locale}]")
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    run_chunk = lua.eval(
        """
        function(code, name, ...)
            local f, err = loadstring(code, "@" .. name)
            if not f then error(err, 0) end
            return f(...)
        end
        """
    )
    mock = run_chunk(read(os.path.join(TESTS, "wow_mock.lua")), "tests/wow_mock.lua")
    mock.locale = locale
    ns = lua.eval("{}")
    lua.globals().ns = ns

    # Strict globals: the addon may only create its saved variable and slash
    # command globals, and reading an undefined global (a typo) is an error.
    lua.execute(
        """
        local allowed = { TwinkleDB = true, SLASH_TWINKLE1 = true, SLASH_TWINKLE2 = true, SLASH_TWINKLE3 = true }
        local optional = { GetSpellInfo = true, TwinkleDB = true }
        setmetatable(_G, {
            __newindex = function(t, k, v)
                if not allowed[k] then error("addon created global '" .. tostring(k) .. "'", 2) end
                rawset(t, k, v)
            end,
            __index = function(_, k)
                if optional[k] then return nil end
                error("read of undefined global '" .. tostring(k) .. "'", 2)
            end,
        })
        """
    )

    files = toc_files()
    for name in files:
        path = os.path.join(ADDON_DIR, name)
        if not os.path.exists(path):
            print(f"TOC lists a missing file: {name}")
            return 1
        run_chunk(read(path), f"{ADDON}/{name}", ADDON, ns)

    # Every texture the code references must ship with the addon.
    code = "\n".join(read(os.path.join(ADDON_DIR, n)) for n in files)
    for tex in set(re.findall(r'CreateTex\(fx, "(\w+)"', code)):
        if not os.path.exists(os.path.join(ADDON_DIR, "Media", tex + ".tga")):
            print(f"missing texture Media/{tex}.tga")
            return 1

    failed = run_chunk(read(os.path.join(TESTS, "test_twinkle.lua")), "tests/test_twinkle.lua")
    return 1 if failed else 0


def main():
    status = 0
    for locale in ("koKR", "enUS"):
        status |= run(locale)
    return status


if __name__ == "__main__":
    sys.exit(main())
