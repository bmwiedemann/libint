#!/bin/sh

${TRAVIS_BUILD_DIR}/bin/travisci_build_eigen3_linux.sh

set -e

if [ "$CXX" = "g++" ]; then
    export CC=/usr/bin/gcc-$GCC_VERSION
    export CXX=/usr/bin/g++-$GCC_VERSION
    export FC=/usr/bin/gfortran-$GCC_VERSION
    export OPENMPFLAGS=-fopenmp
    export EXTRAFLAGS=
    export CXX_TYPE=gnu
else
    # no OpenMP support in clang, will use C++11 threads
    export OPENMPFLAGS=
    export CC=/usr/bin/clang-$CLANG_VERSION
    export CXX=/usr/bin/clang++-$CLANG_VERSION
    export FC=/usr/bin/gfortran-$GCC_VERSION
    export EXTRAFLAGS="-stdlib=libc++"
    export CXX_TYPE=clang
fi
export CXXFLAGS="-std=c++11 -Wno-enum-compare $OPENMPFLAGS $EXTRAFLAGS"
export LDFLAGS=$OPENMPFLAGS
export LIBINT_NUM_THREADS=2

cd ${TRAVIS_BUILD_DIR}
./autogen.sh
cd ${BUILD_PREFIX}
mkdir -p build
cd build
${TRAVIS_BUILD_DIR}/configure CPPFLAGS="-I${INSTALL_PREFIX}/eigen3/include/eigen3" --with-max-am=2,2 --with-eri-max-am=2,2 --with-eri3-max-am=3,2 --enable-eri=1 --enable-eri3=1 --enable-1body=1 --disable-1body-property-derivs --with-multipole-max-order=2
make -j2
make check
cd src/bin/test_eri; ./stdtests.pl; cd ../../..
make export

# try building exported lib in Release mode without system boost to check the bundled boost unpacking and use
if [ "$BUILD_TYPE" = "Release" ]; then
  sudo apt-get purge libboost-dev libboost1.58-dev
  # why is boost still found afterwards?
  sudo apt list --installed | grep boost
fi
cd ${BUILD_PREFIX}
mkdir -p export_build
mv build/libint-*.tgz export_build
cd export_build
tar -xvzf libint-*.tgz
rm -f libint-*.tgz
cd libint-*

cmake . -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DENABLE_FORTRAN=ON -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}/libint2 -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX}/eigen3
cmake --build . --target check
cmake --build . --target install

# test the exported lib
mkdir cmake_test
cd cmake_test
cat > CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.8)
project(hf++)
find_package(Libint2 2.7.0 REQUIRED)
find_package(Threads::Threads)  # clang does not autolink threads even though we are using std::thread
add_executable(hf++ EXCLUDE_FROM_ALL ../tests/hartree-fock/hartree-fock++.cc)
target_link_libraries(hf++ Libint2::cxx Threads::Threads)
EOF
cmake . -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX}/libint2
cmake --build . --target hf++
./hf++ ../tests/hartree-fock/h2o_rotated.xyz | python ../tests/hartree-fock/hartree-fock++-validate.py ../MakeVars.features
cd ..
rm -rf cmake_test

# clean out installed libint files
rm -rf ${INSTALL_PREFIX}/libint2
