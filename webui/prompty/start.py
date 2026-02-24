#!/usr/bin/env python3
"""
PromptyUI - Entry Point

Start the PromptyUI server on port 8085.

Usage:
    python webui/prompty/start.py
    python webui/prompty/start.py --port 8086
    ./start-prompty.sh              # recommended
"""

import sys
from pathlib import Path

# Add this directory to path for server package
_this_dir = Path(__file__).parent
sys.path.insert(0, str(_this_dir))

from server import main

if __name__ == '__main__':
    main()
