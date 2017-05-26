#!/bin/bash

if [[ $(uname) == Darwin ]]; then
  export LIBRARY_SEARCH_VAR=DYLD_FALLBACK_LIBRARY_PATH
  export LDFLAGS="$LDFLAGS -headerpad_max_install_names"
  # OS X user won't enjoy OMP due to the bad decision in conda-forge to use clang.
  export CC=clang
  export CXX=clang++
  export MACOSX_DEPLOYMENT_TARGET="10.9"
  export CXXFLAGS="-stdlib=libc++ $CXXFLAGS"
  export CXXFLAGS="$CXXFLAGS -stdlib=libc++"
  ARGS="--disable-openmp --disable-regex --disable-shared --disable-doc"
elif [[ $(uname) == Linux ]]; then
  export LIBRARY_SEARCH_VAR=LD_LIBRARY_PATH
  ARGS="--enable-openmp --disable-dependency-tracking"
fi

export HAVE_ANTLR=yes
export HAVE_NETCDF4_H=yes
export NETCDF_ROOT=$PREFIX

./configure --prefix=$PREFIX $ARGS

make
#eval ${LIBRARY_SEARCH_VAR}=$PREFIX/lib make check
make install
