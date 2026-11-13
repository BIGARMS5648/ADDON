#!/usr/bin/env python3
"""Load BIGARMS into a Lua 5.1 runtime with a mocked WoW API and run tests.

Requires the `lupa` package (pip install lupa).
    python3 tests/run_bigarms_tests.py

Besides the behavior tests this checks:
  * every file in the TOC exists and loads
  * every global the addon reads is a known WoW API name (tests/bigarms_api_whitelist.txt)
  * every event the addon registers is one the mock client knows
  * every locale key used in the code is defined in English and Korean
"""

import os
import re
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "BIGARMS"
ADDON_DIR = os.path.join(ROOT, ADDON)
TESTS = os.path.join(ROOT, "tests")
WHITELIST = os.path.join(TESTS, "bigarms_api_whitelist.txt")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def toc_files():
    files = []
    for line in read(os.path.join(ADDON_DIR, ADDON + ".toc")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def check_locale(files):
    code = "\n".join(read(os.path.join(ADDON_DIR, n)) for n in files if n.endswith(".lua") and not n.endswith("Locale.lua"))
    locale = read(os.path.join(ADDON_DIR, "Core/Locale.lua"))
    used = set(re.findall(r"\bL\.([A-Z][A-Z0-9_]*)", code))
    used |= set(re.findall(r'(?:label|tooltip|text) = "([A-Z][A-Z0-9_]*)"', code))
    used.discard("BIGARMS")
    for name in re.findall(r'NewModule\("([A-Za-z]+)"', code):
        used.add("MOD_" + name)
        used.add("MOD_" + name + "_DESC")
    for group in re.findall(r'group = "([A-Z]+)"', code):
        used.add("GROUP_" + group)
    for button in re.findall(r'button = "([A-Z]+)"', code):
        used.add("BUTTON_" + button)
    for key in re.findall(r'ns\.L\.([A-Z][A-Z0-9_]*)', code):
        used.add(key)
    split = locale.index('if GetLocale() == "koKR"')
    english = set(re.findall(r"^L\.([A-Za-z0-9_]+) = ", locale[:split], re.M))
    korean = set(re.findall(r"^\s+L\.([A-Za-z0-9_]+) = ", locale[split:], re.M))
    problems = []
    for key in sorted(used):
        if key not in english:
            problems.append(f"missing English string: {key}")
        if key not in korean:
            problems.append(f"missing Korean string: {key}")
    for key in sorted(korean - english):
        problems.append(f"Korean string without English default: {key}")
    return problems


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
    mock = run_chunk(read(os.path.join(TESTS, "bigarms_mock.lua")), "tests/bigarms_mock.lua")
    mock.locale = locale
    ns = lua.eval("{}")
    lua.globals().ns = ns

    lua.execute(
        """
        local allowed = {
            BIGARMSDB = true, BIGARMSCharDB = true, GetMinimapShape = true, CHAT_TIMESTAMP_FORMAT = true,
            StaticPopupDialogs = true, SLASH_BIGARMS1 = true, SLASH_BIGARMS2 = true, SLASH_BIGARMS3 = true,
            SLASH_BIGARMS_WAY1 = true, SLASH_BIGARMS_WAY2 = true, SLASH_BIGARMS_RL1 = true, SLASH_BIGARMS_CLEAR1 = true,
            BIGARMS_OnAddonCompartmentClick = true, BIGARMS_OnAddonCompartmentEnter = true,
            BIGARMS_OnAddonCompartmentLeave = true,
        }
        setmetatable(_G, {
            __newindex = function(t, k, v)
                if not allowed[k] and not tostring(k):find("^BIGARMS") and not tostring(k):find("^BINDING_") and not tostring(k):find("^SLASH_BIGARMS") then
                    error("addon created global '" .. tostring(k) .. "'", 2)
                end
                rawset(t, k, v)
            end,
            __index = function(_, k)
                mock.unknownGlobals[k] = true
                return nil
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
        if name.endswith(".xml"):
            continue
        run_chunk(read(path), f"{ADDON}/{name}", ADDON, ns)

    failed = run_chunk(read(os.path.join(TESTS, "test_bigarms.lua")), "tests/test_bigarms.lua")
    status = 1 if failed else 0

    whitelist = set()
    if os.path.exists(WHITELIST):
        whitelist = {line.strip() for line in read(WHITELIST).splitlines() if line.strip() and not line.startswith("#")}
    unknown = sorted(str(k) for k in dict(mock.unknownGlobals).keys())
    bad = [name for name in unknown if name not in whitelist]
    if bad:
        print("globals read but not in tests/bigarms_api_whitelist.txt (typo, or add them):")
        for name in bad:
            print("   ", name)
        status = 1
    events = sorted(str(k) for k in dict(mock.unknownEvents).keys())
    if events:
        print("events the mock client does not know (typo, or add them to KNOWN_EVENTS):")
        for name in events:
            print("   ", name)
        status = 1
    return status


def main():
    files = toc_files()
    problems = check_locale(files)
    for problem in problems:
        print(problem)
    status = 1 if problems else 0
    for locale in ("koKR", "enUS"):
        status |= run(locale)
    return status


if __name__ == "__main__":
    sys.exit(main())
