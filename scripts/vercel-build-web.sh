#!/usr/bin/env bash
# Builds the Flutter web app on Vercel, whose build image has no Flutter SDK.
# Used by the root vercel.json (the web project). The backend is a separate
# Vercel project rooted at backend/ and doesn't run this.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.1}"

# Flutter unpacks its Dart SDK with unzip.
command -v unzip >/dev/null || dnf install -y unzip

if [ ! -x .flutter-sdk/bin/flutter ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git .flutter-sdk
fi
export PATH="$PWD/.flutter-sdk/bin:$PATH"

flutter --disable-analytics >/dev/null
flutter config --enable-web >/dev/null
flutter pub get

# Pass API_BASE_URL / TMDB_API_KEY as Vercel env vars to override the
# defaults in lib/services/config.dart.
DEFINES=()
for name in API_BASE_URL TMDB_API_KEY; do
  if [ -n "${!name:-}" ]; then DEFINES+=("--dart-define=$name=${!name}"); fi
done

flutter build web --release ${DEFINES[@]+"${DEFINES[@]}"}
