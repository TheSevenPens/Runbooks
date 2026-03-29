#!/bin/bash
# Opens a new Terminal window cd'ed into the Runbooks directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
open -a Terminal "$SCRIPT_DIR"
