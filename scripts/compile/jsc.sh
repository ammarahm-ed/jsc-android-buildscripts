#!/bin/bash -e

SCRIPT_DIR=$(cd `dirname $0`; pwd)
source $SCRIPT_DIR/common.sh

CMAKE_FOLDER=$(cd $ANDROID_HOME/cmake && ls -1 | sort -r | head -1)
PATH=$TOOLCHAIN_DIR/bin:$ANDROID_HOME/cmake/$CMAKE_FOLDER/bin/:$PATH

CCACHE_CMAKE_ARGS=""
if [[ -n "$JSC_CCACHE_BIN" ]]; then
  CCACHE_CMAKE_ARGS="-DCMAKE_C_COMPILER_LAUNCHER=${JSC_CCACHE_BIN} -DCMAKE_CXX_COMPILER_LAUNCHER=${JSC_CCACHE_BIN}"
fi

rm -rf $TARGETDIR/webkit/$CROSS_COMPILE_PLATFORM-${FLAVOR}
rm -rf $TARGETDIR/webkit/WebKitBuild
cd $TARGETDIR/webkit/Tools/Scripts

ARCH_NAME_PLATFORM_arm="armv7-a"
ARCH_NAME_PLATFORM_arm64="aarch64"
ARCH_NAME_PLATFORM_x86="i686"
ARCH_NAME_PLATFORM_x86_64="x86_64"
var="ARCH_NAME_PLATFORM_$JSC_ARCH"
export ARCH_NAME=${!var}

BASE_C_FLAGS="$COMMON_CFLAGS $PLATFORM_CFLAGS"
BASE_CXX_FLAGS="$COMMON_CXXFLAGS $BASE_C_FLAGS"
BASE_CXX_FLAGS="$BASE_CXX_FLAGS -std=c++${JSC_TOOLCHAIN_CXX_STANDARD:-23}"
BASE_LD_FLAGS="-latomic -lm -lc++_shared $JSC_LDFLAGS $PLATFORM_LDFLAGS"

# Restrict libjsc's exported symbols to the JavaScriptCore public C API, hiding
# ~13k internal C++ symbols (shrinks dynamic symbol tables + enables dead-strip).
# Applied ONLY to the shared library link, not the JSC CLI/test executables
# (bin/jsc, bin/testapi, ...), which reference those internal symbols directly.
JSC_EXPORTS_MAP="$SCRIPT_DIR/jsc-api-exports.map"
SHARED_LD_FLAGS="$BASE_LD_FLAGS -Wl,--version-script=$JSC_EXPORTS_MAP"

export CFLAGS="$BASE_C_FLAGS"
export CXXFLAGS="$BASE_CXX_FLAGS"
export LDFLAGS="$BASE_LD_FLAGS"

if [[ "$BUILD_TYPE" = "Release" ]]
then
    BUILD_TYPE_CONFIG="--release"
    BUILD_TYPE_FLAGS=""
else
    BUILD_TYPE_CONFIG="--debug"
    BUILD_TYPE_FLAGS="-DDEBUG_FISSION=OFF"
fi

# JIT / optimization tiers.
#
# Baseline + DFG JIT are enabled on every ABI. This is a large win over the
# C_LOOP interpreter and covers the bulk of the optimizing-JIT speedup.
#
# The FTL (B3) tier is intentionally left OFF. In this WebKit fork, B3's abstract
# heap repository (b3/B3AbstractHeapRepository.{h,cpp}) references WebAssembly
# types unconditionally (no ENABLE(WEBASSEMBLY) guards), so B3 — and therefore
# FTL — cannot be compiled while WebAssembly is disabled. We keep WebAssembly OFF
# (smaller binary, no WASM surface), so FTL stays off too. With both FTL and
# WebAssembly off, ENABLE(B3_JIT) is off and the B3 sources are not built.
#
# Enabling ENABLE_JIT also flips on the LLInt ASM interpreter and, via
# jsc_fix_concurrent_gc_issue.patch, ENABLE_CONCURRENT_JS (concurrent baseline/
# DFG compilation + concurrent GC guards).
# Arch-aware default: JIT (baseline + DFG) on the 64-bit ABIs; the 32-bit ABIs
# run the portable C_LOOP interpreter with JIT off. armv7 does have a Thumb2 JIT
# backend, but x86 (32-bit) has none in modern JSC, so for consistency both
# 32-bit ABIs ship the interpreter. FTL/WebAssembly stay off everywhere.
case "$JSC_ARCH" in
  arm64|x86_64)
    JSC_FEATURE_FLAGS=" \
  -DENABLE_JIT=ON \
  -DENABLE_C_LOOP=OFF \
  -DENABLE_DFG_JIT=ON \
  -DENABLE_FTL_JIT=OFF \
  -DENABLE_WEBASSEMBLY=OFF \
"
    ;;
  *)
    JSC_FEATURE_FLAGS=" \
  -DENABLE_JIT=OFF \
  -DENABLE_C_LOOP=ON \
  -DENABLE_DFG_JIT=OFF \
  -DENABLE_FTL_JIT=OFF \
  -DENABLE_WEBASSEMBLY=OFF \
"
    ;;
esac

# ---- EXPERIMENT: interpreter-only override for ALL arches (no JIT compilation) ----
# JSC_EXPERIMENT_NO_JIT=1   -> C_LOOP (portable C++ interpreter, smallest, slowest)
# JSC_EXPERIMENT_ASM_LLINT=1-> asm LLInt (offlineasm interpreter: no JIT, but the
#                              fast computed-goto/pinned-register dispatch, ~2-4x
#                              C_LOOP). JIT=OFF + C_LOOP=OFF selects the ARM64
#                              offlineasm backend. Bytecode cache works in both.
if [[ "${JSC_EXPERIMENT_ASM_LLINT:-0}" == "1" ]]; then
  JSC_FEATURE_FLAGS=" \
  -DENABLE_JIT=OFF \
  -DENABLE_C_LOOP=OFF \
  -DENABLE_DFG_JIT=OFF \
  -DENABLE_FTL_JIT=OFF \
  -DENABLE_WEBASSEMBLY=OFF \
"
elif [[ "${JSC_EXPERIMENT_NO_JIT:-0}" == "1" ]]; then
  JSC_FEATURE_FLAGS=" \
  -DENABLE_JIT=OFF \
  -DENABLE_C_LOOP=ON \
  -DENABLE_DFG_JIT=OFF \
  -DENABLE_FTL_JIT=OFF \
  -DENABLE_WEBASSEMBLY=OFF \
"
fi

$TARGETDIR/webkit/Tools/Scripts/build-webkit \
  --jsc-only \
  $BUILD_TYPE_CONFIG \
  --no-fatal-warnings \
  "$SWITCH_BUILD_WEBKIT_OPTIONS_INTL" \
  --no-xslt \
  --no-netscape-plugin-api \
  --no-tools \
  --makeargs="JavaScriptCore" \
  --cmakeargs="-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake \
  -DUSE_LD_GOLD=OFF \
  -DANDROID_ABI=${JNI_ARCH} \
  -DANDROID_PLATFORM=${ANDROID_API} \
  -DANDROID_TARGET_SDK_VERSION=${ANDROID_TARGET_API:-${ANDROID_API}} \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
  -DICU_ROOT=${TARGETDIR}/icu/${CROSS_COMPILE_PLATFORM}-${FLAVOR}/prebuilts \
  -DICU_INCLUDE_DIR=${TARGETDIR}/icu/${CROSS_COMPILE_PLATFORM}-${FLAVOR}/prebuilts/include \
  -DENABLE_API_TESTS=OFF \
  -DCMAKE_C_FLAGS=\"$BASE_C_FLAGS\" \
  -DCMAKE_CXX_FLAGS=\"$BASE_CXX_FLAGS\" \
  -DCMAKE_C_FLAGS_RELEASE=\"$BASE_C_FLAGS\" \
  -DCMAKE_CXX_FLAGS_RELEASE=\"$BASE_CXX_FLAGS\" \
  -DCMAKE_C_FLAGS_RELWITHDEBINFO=\"$BASE_C_FLAGS\" \
  -DCMAKE_CXX_FLAGS_RELWITHDEBINFO=\"$BASE_CXX_FLAGS\" \
  -DCMAKE_C_FLAGS_DEBUG=\"$BASE_C_FLAGS $DEBUG_SYMBOL_LEVEL\" \
  -DCMAKE_CXX_FLAGS_DEBUG=\"$BASE_CXX_FLAGS $DEBUG_SYMBOL_LEVEL\" \
  -DCMAKE_SHARED_LINKER_FLAGS=\"$SHARED_LD_FLAGS\" \
  -DCMAKE_MODULE_LINKER_FLAGS=\"$BASE_LD_FLAGS\" \
  -DCMAKE_EXE_LINKER_FLAGS=\"$BASE_LD_FLAGS\" \
  -DUSE_BUN_JSC_ADDITIONS=ON \
  -DCMAKE_CXX_STANDARD=${JSC_TOOLCHAIN_CXX_STANDARD:-23} \
  -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -DCMAKE_CXX_EXTENSIONS=OFF \
  -DCMAKE_VERBOSE_MAKEFILE=on \
  $CCACHE_CMAKE_ARGS \
  -DENABLE_API_TESTS=OFF \
  -DENABLE_SAMPLING_PROFILER=OFF \
  -DUSE_SYSTEM_MALLOC=OFF \
  -DJSC_VERSION=\"${JSC_VERSION}\" \
  $JSC_FEATURE_FLAGS \
  $BUILD_TYPE_FLAGS \
  "

mkdir -p $INSTALL_UNSTRIPPED_DIR_I18N/$JNI_ARCH
mkdir -p $INSTALL_DIR_I18N/$JNI_ARCH
BUILT_LIB_PATH=$TARGETDIR/webkit/WebKitBuild/JSCOnly/$BUILD_TYPE/lib/libJavaScriptCore.so
OUTPUT_LIB_NAME=libjsc.so
if [[ ! -f $BUILT_LIB_PATH ]]
then
  echo "Failed to find expected JavaScriptCore shared library at $BUILT_LIB_PATH" >&2
  exit 1
fi
cp $BUILT_LIB_PATH $INSTALL_UNSTRIPPED_DIR_I18N/$JNI_ARCH/$OUTPUT_LIB_NAME
cp $BUILT_LIB_PATH $INSTALL_DIR_I18N/$JNI_ARCH/$OUTPUT_LIB_NAME
$TOOLCHAIN_DIR/bin/llvm-strip $INSTALL_DIR_I18N/$JNI_ARCH/$OUTPUT_LIB_NAME
mv $TARGETDIR/webkit/WebKitBuild $TARGETDIR/webkit/${CROSS_COMPILE_PLATFORM}-${FLAVOR}

mkdir -p $INSTALL_CPPRUNTIME_DIR/$JNI_ARCH
cp $TOOLCHAIN_DIR/sysroot/usr/lib/$CROSS_COMPILE_PLATFORM/libc++_shared.so $INSTALL_CPPRUNTIME_DIR/$JNI_ARCH/libc++_shared.so
