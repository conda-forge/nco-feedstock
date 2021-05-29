#!/bin/bash

if [[ $(uname) == Darwin ]]; then
  ARGS="--disable-openmp --enable-regex --disable-shared --disable-doc"
elif [[ $(uname) == Linux ]]; then
  ARGS="--enable-openmp --disable-dependency-tracking"
fi

export HAVE_ANTLR=yes
export HAVE_NETCDF4_H=yes
export NETCDF_ROOT=$PREFIX

./configure --prefix=$PREFIX $ARGS

make -j$CPU_COUNT
make check
make install
