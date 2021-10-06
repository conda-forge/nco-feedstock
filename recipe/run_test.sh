#!/bin/bash

ncgen -o data/in.nc data/in.cdl
fin=data/in.nc

ncks -H --trd -v one $fin

ncap2 -O -v -s 'erf_one=float(gsl_sf_erf(1.0f));print(erf_one,"%g")' $fin foo.nc

ncks -O --thr_nbr=3 --rgr lat_nbr=2 --dbg=2 $fin foo.nc

ncks --tst_udunits='5 meters',centimeters $fin

ncks -v 'H2O$' $fin

ncks -r

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

ncremap --no_stdin -a conserve -s grd_t42.nc -g grd_2x2.nc -m map_t42_to_2x2.nc
ncremap --no_stdin -i dat_t42.nc -m map_t42_to_2x2.nc -o dat_2x2.nc
ncremap --no_stdin -a fv2fv_flx -s grd_t42.nc -g grd_2x2.nc -m map_tempest_t42_to_2x2.nc
ncremap --no_stdin -i dat_t42.nc -m map_tempest_t42_to_2x2.nc -o dat_tempest_2x2.nc
ncwa -O dat_2x2.nc dat_avg.nc
ncks -C -H -v tst dat_avg.nc
