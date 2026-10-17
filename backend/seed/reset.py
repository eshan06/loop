"""Put the Vanderbilt demo campus back to its clean seeded state (S-25).

Same as `python -m seed.seed`; kept as its own command so the demo checklist reads
"reset". Run on the server from backend/:  .venv/bin/python -m seed.reset
From the Mac:  bash scripts/reseed.sh
"""

from __future__ import annotations

import sys

from seed.seed import main

if __name__ == "__main__":
    sys.exit(main(sys.argv))
