#!/bin/bash -e

ROOTDIR=$PWD

TARGET_DIR="$ROOTDIR/build/download"
WEBKIT_DIR="$TARGET_DIR/webkit"
ICU_DIR="$TARGET_DIR/icu"

REPO_URL="${npm_package_config_bunWebKitRepo:-https://github.com/oven-sh/WebKit.git}"
WEBKIT_COMMIT="${npm_package_config_bunWebKitCommit}"
ICU_RELEASE="${npm_package_config_icuRelease}"
ICU_ARCHIVE="${npm_package_config_icuArchive}"

# Set JSC_FORCE_DOWNLOAD=1 to re-fetch even when the sources already exist.
FORCE_DOWNLOAD="${JSC_FORCE_DOWNLOAD:-0}"

if [[ -z "$WEBKIT_COMMIT" ]]; then
  echo "Missing bunWebKitCommit in package.json config." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

# ---------------------------------------------------------------------------
# WebKit: only fetch when missing, at the wrong commit, or forced. The checkout
# is large, so re-fetching on every build is wasteful.
# ---------------------------------------------------------------------------
webkit_is_ready() {
  [[ -f "$WEBKIT_DIR/Source/JavaScriptCore/API/JSScriptRef.cpp" ]] || return 1
  local head
  head="$(git -C "$WEBKIT_DIR" rev-parse HEAD 2>/dev/null)" || return 1
  [[ "$head" == "$WEBKIT_COMMIT" ]]
}

if [[ "$FORCE_DOWNLOAD" != "1" ]] && webkit_is_ready; then
  echo "WebKit already checked out at ${WEBKIT_COMMIT}; skipping fetch."
else
  echo "Fetching WebKit ${WEBKIT_COMMIT} from ${REPO_URL}..."
  rm -rf "$WEBKIT_DIR"
  mkdir -p "$WEBKIT_DIR"
  pushd "$WEBKIT_DIR" > /dev/null
  git init -q
  git remote add origin "$REPO_URL"
  git fetch --depth 1 origin "$WEBKIT_COMMIT"
  git checkout --detach -q FETCH_HEAD
  popd > /dev/null
fi

# ---------------------------------------------------------------------------
# ICU: only download when missing or forced.
# ---------------------------------------------------------------------------
icu_is_ready() {
  [[ -f "$ICU_DIR/source/configure" ]]
}

if [[ "$FORCE_DOWNLOAD" != "1" ]] && icu_is_ready; then
  echo "ICU already present at ${ICU_DIR}; skipping download."
else
  if [[ -z "$ICU_RELEASE" ]]; then
    echo "No ICU release configured for download." >&2
    exit 1
  fi
  if [[ -z "$ICU_ARCHIVE" ]]; then
    echo "Missing icuArchive for release ${ICU_RELEASE}" >&2
    exit 1
  fi
  echo "Downloading ICU ${ICU_RELEASE} (${ICU_ARCHIVE})..."
  rm -rf "$ICU_DIR"
  mkdir -p "$ICU_DIR"
  curl -L "https://github.com/unicode-org/icu/releases/download/${ICU_RELEASE}/${ICU_ARCHIVE}" | tar xzf - --strip-components=1 -C "$ICU_DIR"
fi
