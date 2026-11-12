#!/usr/bin/env python3
"""Load each addon into a Lua 5.1 runtime with a mocked WoW API and run tests.

Requires the `lupa` package (pip install lupa).
    python3 tests/run_tests.py            # every addon
    python3 tests/run_tests.py BigPodium  # one addon
"""

import os
import re
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")

# Per addon: test file, globals it may create, globals it may read while unset.
ADDONS = {
    "Twinkle": dict(
        test="test_twinkle.lua",
        allowed=["TwinkleDB", "SLASH_TWINKLE1", "SLASH_TWINKLE2", "SLASH_TWINKLE3",
                 "Twinkle_OnAddonCompartmentClick", "Twinkle_OnAddonCompartmentEnter",
                 "Twinkle_OnAddonCompartmentLeave"],
        optional=["GetSpellInfo", "TwinkleDB", "GetMinimapShape"],
    ),
    "BigPodium": dict(
        test="test_podium.lua",
        allowed=["BigPodiumDB", "SLASH_BIGPODIUM1", "SLASH_BIGPODIUM2", "SLASH_BIGPODIUM3",
                 "BigPodium_OnAddonCompartmentClick", "BigPodium_OnAddonCompartmentEnter",
                 "BigPodium_OnAddonCompartmentLeave", "BigPodiumCeremonyFrame"],
        optional=["GetSpellInfo", "BigPodiumDB", "C_ClassColor", "GetClassAtlas"],
    ),
}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def toc_files(addon):
    files = []
    for line in read(os.path.join(ROOT, addon, addon + ".toc")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line)
    return files


def load(addon, locale):
    """Returns (lua runtime, run_chunk, mock) with the addon loaded."""
    spec = ADDONS[addon]
    addon_dir = os.path.join(ROOT, addon)
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
    to_set = lua.eval("function(names) local t = {} for _, n in ipairs(names) do t[n] = true end return t end")
    lua.globals().ALLOWED = to_set(lua.table_from(spec["allowed"]))
    lua.globals().OPTIONAL = to_set(lua.table_from(spec["optional"]))
    lua.execute(
        """
        local allowed, optional = ALLOWED, OPTIONAL
        ALLOWED, OPTIONAL = nil, nil
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

    files = toc_files(addon)
    for name in files:
        path = os.path.join(addon_dir, name)
        if not os.path.exists(path):
            raise FileNotFoundError(f"TOC lists a missing file: {name}")
        run_chunk(read(path), f"{addon}/{name}", addon, ns)
    return lua, run_chunk, mock


def check_media(addon):
    """Every texture the code references must ship with the addon."""
    addon_dir = os.path.join(ROOT, addon)
    code = "\n".join(read(os.path.join(addon_dir, n)) for n in toc_files(addon))
    names = set(re.findall(r'CreateTex\(fx, "(\w+)"', code))  # Twinkle
    names |= set(re.findall(r'(?:Tex|Img)\(\w+(?:\.\w+)*, "\w+", -?\d+, "(\w+)"', code))  # Podium
    names |= set(re.findall(r'MEDIA \.\. "(\w+)"', code))
    names |= set(re.findall(r'Media\\\\(\w+)', code))
    missing = [n for n in sorted(names) if not os.path.exists(os.path.join(addon_dir, "Media", n + ".tga"))]
    for n in missing:
        print(f"missing texture {addon}/Media/{n}.tga")
    return not missing


def run(addon, locale):
    print(f"[{addon} {locale}]")
    if not check_media(addon):
        return 1
    lua, run_chunk, _ = load(addon, locale)
    test = ADDONS[addon]["test"]
    failed = run_chunk(read(os.path.join(TESTS, test)), f"tests/{test}")
    return 1 if failed else 0


def main():
    only = sys.argv[1:]
    status = 0
    for addon in ADDONS:
        if only and addon not in only:
            continue
        for locale in ("koKR", "enUS"):
            status |= run(addon, locale)
    return status


if __name__ == "__main__":
    sys.exit(main())
