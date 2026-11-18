#!/bin/bash

set -ex

# strip std settings from conda
CXXFLAGS="${CXXFLAGS/-std=c++14/}"
CXXFLAGS="${CXXFLAGS/-std=c++11/}"
if [[ "${target_platform}" == osx-* ]]; then
  # Build against older SDKs with conda-forge's newer libc++.
  CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
  # PDAL's CMake configuration manages the install rpath. Keeping the same
  # rpath in LDFLAGS makes install_name_tool try to add it a second time.
  pdal_rpath_flag="-Wl,-rpath,${PREFIX}/lib"
  export LDFLAGS="${LDFLAGS//${pdal_rpath_flag}/}"
  CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_BUILD_RPATH=${PREFIX}/lib"
fi
export CXXFLAGS

if [ "$CONDA_BUILD_CROSS_COMPILATION" == "1" ]; then
  mkdir native; pushd native;

  CFLAGS_NATIVE=${CFLAGS//$PREFIX/$BUILD_PREFIX}
  CXXFLAGS_NATIVE=${CXXFLAGS//$PREFIX/$BUILD_PREFIX}
  LDFLAGS_NATIVE=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
  # Remove target architecture flags when building the native code generator.
  native_arch_flags='s/-m(arch|cpu|tune)=[^ ]*//g; s/-m(sse|ssse|avx)[^ ]*//g'
  CFLAGS_NATIVE="$(printf '%s\n' "$CFLAGS_NATIVE" | sed -E "$native_arch_flags")"
  CXXFLAGS_NATIVE="$(printf '%s\n' "$CXXFLAGS_NATIVE" | sed -E "$native_arch_flags")"

  CC=$CC_FOR_BUILD CXX=$CXX_FOR_BUILD \
    LDFLAGS=${LDFLAGS_NATIVE} \
    CFLAGS=${CFLAGS_NATIVE} \
    CXXFLAGS=${CXXFLAGS_NATIVE} \
    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_BUILD_RPATH="$BUILD_PREFIX/lib" \
        -DNLOHMANN_INCLUDE_DIR="$SRC_DIR/vendor/nlohmann" \
        -DUTFCPP_INCLUDE_DIR="$SRC_DIR/vendor/utfcpp/source" \
        ${EXTRA_CMAKE_ARGS} \
        ../dimbuilder

  export DIMBUILDER="$(pwd)/dimbuilder"
  ninja dimbuilder
  popd
else
  export DIMBUILDER=dimbuilder

fi

rm -rf build
mkdir -p build
cd build

export PDAL_BUILD_DIR=`pwd`/install
mkdir $PDAL_BUILD_DIR

cmake -G Ninja \
  ${CMAKE_ARGS} \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DCMAKE_PREFIX_PATH=$PREFIX \
  -DDIMBUILDER_EXECUTABLE=$DIMBUILDER \
  -DBUILD_PLUGIN_E57=OFF \
  -DBUILD_PLUGIN_PGPOINTCLOUD=OFF \
  -DBUILD_PLUGIN_ARROW=OFF \
  -DENABLE_CTEST=OFF \
  -DWITH_TESTS=OFF \
  -DWITH_ZLIB=ON \
  -DWITH_ZSTD=ON \
  ..

ninja -j${CPU_COUNT}
ninja install

## Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d, see
## https://conda-forge.org/docs/maintainer/adding_pkgs.html#activate-scripts
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/scripts/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
