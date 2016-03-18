#!/bin/bash

export HAVE_ANTLR=yes
export HAVE_NETCDF4_H=yes
export NETCDF_ROOT=$PREFIX

if [[ $(uname) == Darwin ]]; then
  export LDFLAGS="-headerpad_max_install_names"
  ARGS="--disable-regex --disable-shared --disable-doc"
else
  ARGS="--disable-dependency-tracking"
fi

./configure --prefix=$PREFIX --enable-esmf $ARGS

make

if [[ $(uname) != Darwin ]]; then
make check
fi

make install
