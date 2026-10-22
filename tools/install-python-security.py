"""Install only the verified local pip/certifi wheels, without Python startup hooks.

Invoked by Install-VerifiedRuntimeUpdate.ps1 using Python -I -S.
"""
import os
from pathlib import Path
import runpy
import sys
import sysconfig

if not sys.flags.isolated or not sys.flags.no_site:
    raise RuntimeError("Run with -I -S to skip startup hooks and user paths")
directory = Path(sys.argv[1]).resolve(strict=True)
sys.path.append(sysconfig.get_path("purelib"))
os.environ["PIP_CONFIG_FILE"] = os.devnull
sys.argv = ["pip", "--isolated", "--disable-pip-version-check", "--no-input",
            "install", "--no-index", "--no-deps", "--find-links", str(directory),
            "--upgrade", "pip==26.2.2", "certifi==2026.10.19"]
runpy.run_module("pip", run_name="__main__", alter_sys=True)
