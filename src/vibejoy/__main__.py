"""Allow ``python -m vibejoy`` to work the same as the ``vibejoy`` entry point."""

import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main())
