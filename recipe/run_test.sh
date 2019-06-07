#!/bin/bash

ncgen -o data/in.nc data/in.cdl
fin=data/in.nc

ncap2 -O -v -s 'erf_one=float(gsl_sf_erf(1.0f));print(erf_one,"%g")' $fin fooo.nc

ncks -H --trd -v one $fin

ncks -O --rgr skl=skl_t42.nc \
        --rgr grid=grd_t42.nc \
        --rgr latlon=64,128 \
        --rgr lat_typ=gss \
        --rgr lon_typ=Grn_ctr \
        $fin \
        foo.nc

ncks -O --rgr grid=grd_2x2.nc \
        --rgr latlon=90,180 \
        --rgr lat_typ=eqa \
        --rgr lon_typ=Grn_wst \
        -D 3 \
        $fin \
        foo.nc

ncap2 -O -s 'tst[lat,lon]=1.0f' skl_t42.nc dat_t42.nc

# The next test(s) seems to be hanging in CI (Azure and perhaps others) so they
# are commented out for now
ncremap --no_stdin -a conserve -s grd_t42.nc -g grd_2x2.nc -m map_t42_to_2x2.nc
ncremap --no_stdin -i dat_t42.nc -m map_t42_to_2x2.nc -o dat_2x2.nc
ncremap --no_stdin -a tempest -s grd_t42.nc -g grd_2x2.nc -m map_tempest_t42_to_2x2.nc
ncremap --no_stdin -i dat_t42.nc -m map_tempest_t42_to_2x2.nc -o dat_tempest_2x2.nc
ncwa -O dat_2x2.nc dat_avg.nc
ncks -C -H -v tst dat_avg.nc
