cd nco-src\data

ncgen -o in.nc in.cdl || exit 1

ncks -H --trd -v one in.nc || exit 1

ncap2 -O -v -s "erf_one=float(gsl_sf_erf(1.0f));" in.nc foo.nc || exit 1

ncks -v erf_one foo.nc || exit 1

ncks -O --thr_nbr=3 --rgr lat_nbr=2 --dbg=2 in.nc foo.nc || exit 1

ncks --tst_udunits="5 meters",centimeters in.nc || exit 1

ncks -r || exit 1
