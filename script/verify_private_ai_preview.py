#!/usr/bin/env python3
"""Compatibility entrypoint; current private preview uses a password form, not HTTP Basic."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('verify_m2_colab_iframe_gate.py')), run_name='__main__')
