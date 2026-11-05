#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
exec /bin/bash "$root/release-kit/publisher/run.sh" "$root" "$@"
