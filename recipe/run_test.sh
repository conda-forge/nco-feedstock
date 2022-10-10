#!/bin/bash

echo ncgen -o data/in.nc data/in.cdl
ncgen -o data/in.nc data/in.cdl
echo fin=data/in.nc
fin=data/in.nc

echo ncks -H --trd -v one $fin
ncks -H --trd -v one $fin

echo ncap2 -O -v -s 'erf_one=float(gsl_sf_erf(1.0f));print(erf_one,"%g")' $fin foo.nc
ncap2 -O -v -s 'erf_one=float(gsl_sf_erf(1.0f));print(erf_one,"%g")' $fin foo.nc

echo ncks -O --thr_nbr=3 --rgr lat_nbr=2 --dbg=2 $fin foo.nc
ncks -O --thr_nbr=3 --rgr lat_nbr=2 --dbg=2 $fin foo.nc

echo ncks --tst_udunits='5 meters',centimeters $fin
ncks --tst_udunits='5 meters',centimeters $fin

echo ncks -v 'H2O$' $fin
ncks -v 'H2O$' $fin

echo ncks -r
ncks -r

echo ncks -O --rgr skl=skl_t42.nc \
        --rgr grid=grd_t42.nc \
        --rgr latlon=64,128 \
        --rgr lat_typ=gss \
        --rgr lon_typ=Grn_ctr \
        $fin \
        foo.nc

ncks -O --rgr skl=skl_t42.nc \
        --rgr grid=grd_t42.nc \
        --rgr latlon=64,128 \
        --rgr lat_typ=gss \
        --rgr lon_typ=Grn_ctr \
        $fin \
        foo.nc

echo ncks -O --rgr grid=grd_2x2.nc \
        --rgr latlon=90,180 \
        --rgr lat_typ=eqa \
        --rgr lon_typ=Grn_wst \
        -D 3 \
        $fin \
        foo.nc

ncks -O --rgr grid=grd_2x2.nc \
        --rgr latlon=90,180 \
        --rgr lat_typ=eqa \
        --rgr lon_typ=Grn_wst \
        -D 3 \
        $fin \
        foo.nc

echo ncap2 -O -s 'tst[lat,lon]=1.0f' skl_t42.nc dat_t42.nc
ncap2 -O -s 'tst[lat,lon]=1.0f' skl_t42.nc dat_t42.nc

echo ncremap --no_stdin -a conserve -s grd_t42.nc -g grd_2x2.nc -m map_t42_to_2x2.nc
ncremap --no_stdin -a conserve -s grd_t42.nc -g grd_2x2.nc -m map_t42_to_2x2.nc
echo ncremap --no_stdin -i dat_t42.nc -m map_t42_to_2x2.nc -o dat_2x2.nc
ncremap --no_stdin -i dat_t42.nc -m map_t42_to_2x2.nc -o dat_2x2.nc
echo ncremap --no_stdin -a fv2fv_flx -s grd_t42.nc -g grd_2x2.nc -m map_tempest_t42_to_2x2.nc
ncremap --no_stdin -a fv2fv_flx -s grd_t42.nc -g grd_2x2.nc -m map_tempest_t42_to_2x2.nc
echo ncremap --no_stdin -i dat_t42.nc -m map_tempest_t42_to_2x2.nc -o dat_tempest_2x2.nc
ncremap --no_stdin -i dat_t42.nc -m map_tempest_t42_to_2x2.nc -o dat_tempest_2x2.nc
echo ncwa -O dat_2x2.nc dat_avg.nc
ncwa -O dat_2x2.nc dat_avg.nc
echo ncks -C -H -v tst dat_avg.nc
ncks -C -H -v tst dat_avg.nc
