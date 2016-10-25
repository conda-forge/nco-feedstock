#!/bin/bash

fin=$SRC_DIR/data/in.nc

# ncks -M http://test.opendap.org:80/opendap/data/ncml/sample_virtual_dataset.ncml
# ncks -F --dimension samples,1 http://test.opendap.org:80/opendap/data/ncml/sample_virtual_dataset.ncml

ncks -O --rgr skl=skl_t42.nc --rgr grid=grd_t42.nc --rgr latlon=64,128 --rgr lat_typ=gss --rgr lon_typ=Grn_ctr $fin foo.nc
ncks -O --rgr grid=grd_2x2.nc --rgr latlon=90,180 --rgr lat_typ=eqa --rgr lon_typ=Grn_wst $fin foo.nc

if [[ $(uname) == Darwin ]]; then
  ncap2 -O -s 'tst[lat,lon]=1.0f' skl_t42.nc dat_t42.nc
  ncremap -a conserve -s grd_t42.nc -g grd_2x2.nc -m map_t42_to_2x2.nc  # FIXME: For some reason this command prevents CircleCI from uploading the package!
  ncremap -i dat_t42.nc -m map_t42_to_2x2.nc -o dat_2x2.nc
  ncwa -O dat_2x2.nc dat_avg.nc
  ncks -C -H -v tst dat_avg.nc
fi
