#!/bin/sh
# Xcode Cloud runs this after cloning. Revontulet.xcodeproj is not committed, so generate it
# from project.yml before Xcode Cloud looks for the project.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Every cloud build gets Xcode Cloud's own increasing build number, which TestFlight requires.
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"/" project.yml
  grep -q "CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"" project.yml
fi

brew install xcodegen
xcodegen generate
