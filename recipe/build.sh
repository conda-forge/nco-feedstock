#!/bin/bash

set -xe

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* ./autobld

if [[ $(uname) == Darwin ]]; then
  ARGS="--disable-openmp --enable-regex --disable-shared --disable-doc"
elif [[ $(uname) == Linux ]]; then
  ARGS="--enable-openmp --disable-dependency-tracking"
fi

export HAVE_ANTLR=yes
export HAVE_NETCDF4_H=yes
export NETCDF_ROOT=$PREFIX

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
    # The following is borrowed from `configure`.
    # Note that we don't `export` and thus don't pollute
    # `configure` itself.
    # Avoid depending upon Character Ranges.
    as_cr_letters='abcdefghijklmnopqrstuvwxyz'
    as_cr_LETTERS='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    as_cr_Letters=$as_cr_letters$as_cr_LETTERS
    as_cr_digits='0123456789'
    as_cr_alnum=$as_cr_Letters$as_cr_digits
    # Sed expression to map a string onto a valid variable name.
    as_tr_sh="eval sed 'y%*+%pp%;s%[^_$as_cr_alnum]%_%g'"

    # Now follow cache variables for dep checks
    # GSL header check
    GSL_ROOT=$(gsl-config --prefix)
    GSL_INC=${GSL_ROOT}/include
    as_ac_File=`printf "%s\n" "ac_cv_file_${GSL_INC}/gsl/gsl_sf_gamma.h" | $as_tr_sh`
    eval "export $as_ac_File=yes"

    # General UDUNITS2 check
    export UDUNITS2_PATH=${PREFIX}

    # UDUNITS2 database check
    nco_udunits2_xml=${UDUNITS2_PATH}/share/udunits/udunits2.xml
    as_ac_File=`printf "%s\n" "ac_cv_file_$nco_udunits2_xml" | $as_tr_sh`
    eval "export $as_ac_File=yes"
    # UDUNITS2 header check
    as_ac_File=`printf "%s\n" "ac_cv_file_${UDUNITS2_PATH}/include/udunits2.h" | $as_tr_sh`
    eval "export $as_ac_File=yes"

    # Hardcode flex output root
    export ac_cv_prog_lex_root=lex.yy

    export LEX=${BUILD_PREFIX}/bin/flex
fi

./configure --prefix=$PREFIX $ARGS

make -j$CPU_COUNT
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
make check
fi
make install
