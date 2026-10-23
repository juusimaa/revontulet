#!/bin/sh
# Fails if AuroraCore uses Apple-only frameworks or XMLParser, so the core stays reusable by an
# Android app (constitution Principle III).
set -eu

cd "$(dirname "$0")/../Packages/AuroraCore/Sources"

status=0

if grep -rnE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+(SwiftUI|UIKit|AppKit|CoreLocation|Combine|OSLog|os)([[:space:].]|$)' .; then
  echo "error: AuroraCore imports an Apple-only framework" >&2
  status=1
fi

if grep -rn 'XMLParser' . | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'; then
  echo "error: AuroraCore uses XMLParser" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "AuroraCore is portable."
fi
exit "$status"
