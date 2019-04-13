#!/bin/bash

# Purpose: Regrid (subsets of) netCDF files between different Swath, Curvilinear, Rectangular, and Unstructured data (SCRUD) grids, generate any required/requested global or regional rectangular grid, output SCRIP, UGRID, and/or skeleton data formats

# Copyright (C) 2015--present Charlie Zender
# This file is part of NCO, the netCDF Operators. NCO is free software.
# You may redistribute and/or modify NCO under the terms of the
# GNU General Public License (GPL) Version 3.

# As a special exception to the terms of the GPL, you are permitted
# to link the NCO source code with the HDF, netCDF, OPeNDAP, and UDUnits
# libraries and to distribute the resulting executables under the terms
# of the GPL, but in addition obeying the extra stipulations of the
# HDF, netCDF, OPeNDAP, and UDUnits licenses.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

# The original author of this software, Charlie Zender, seeks to improve
# it with your suggestions, contributions, bug-reports, and patches.
# Please contact the NCO project at http://nco.sf.net or write to
# Charlie Zender
# Department of Earth System Science
# University of California, Irvine
# Irvine, CA 92697-3100

# Prerequisites: Bash, NCO
# Script could use other shells, e.g., dash (Debian default) after rewriting function definitions and loops
# For full functionality also install ESMF_RegridWeightGen and/or TempestRemap

# Source: https://github.com/nco/nco/tree/master/data/ncremap
# Documentation: http://nco.sf.net/nco.html#ncremap
# Additional Documentation:
# HowTo: https://acme-climate.atlassian.net/wiki/display/SIM/Generate%2C+Regrid%2C+and+Split+Climatologies+%28climo+files%29+with+ncclimo+and+ncremap
# E3SM/ACME Climatology Requirements: https://acme-climate.atlassian.net/wiki/display/ATM/Climo+Files+-+v0.3+AMIP+runs

# Regridder works in one of four modes:
# 1. Free-will: Infer source and destination grids to generate map-file, then regrid
# 2. Old Grid: Use known-good destination grid to generate map-file then regrid
# 3. New Grid: Generate source-grid from ncks parameter string
# 4. Pre-Destination: Apply supplied map-file to all input files
# By default, ncremap deletes any intermediate grids and map-file that it generates
# Use Free-Will, Old-Grid, or New-Grid mode to process Swath-Like-Data (SLD) where each input may be a granule on a new grid, yet all inputs are to be regridded to the same output grid
# Use Pre-Destination mode to post-process models or analyses where all files are converted from the same source grid to the same destination grid so the map-file can be pre-generated and never change

# Insta-install:
# scp ~/nco/data/ncremap zender1@acme1.llnl.gov:bin
# scp ~/nco/data/ncremap zender1@aims4.llnl.gov:bin
# scp ~/nco/data/ncremap blues.lcrc.anl.gov:bin
# scp ~/nco/data/ncremap cheyenne.ucar.edu:bin
# scp ~/nco/data/ncremap cooley.alcf.anl.gov:bin
# scp ~/nco/data/ncremap cori.nersc.gov:bin_cori
# scp ~/nco/data/ncremap dust.ess.uci.edu:bin
# scp ~/nco/data/ncremap edison.nersc.gov:bin_edison
# scp ~/nco/data/ncremap rhea.ccs.ornl.gov:bin_rhea
# scp ~/nco/data/ncremap skyglow.ess.uci.edu:bin
# scp ~/nco/data/ncremap theta.alcf.anl.gov:bin_theta
# scp dust.ess.uci.edu:nco/data/ncremap ~/bin

# Set script name, directory, PID, run directory
drc_pwd=${PWD}
# Security: Explicitly unset IFS before wordsplitting, so Bash uses default IFS=<space><tab><newline>
unset IFS
# Set these before 'module' command which can overwrite ${BASH_SOURCE[0]}
# NB: dash supports $0 syntax, not ${BASH_SOURCE[0]} syntax
# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
spt_src="${BASH_SOURCE[0]}"
[[ -z "${spt_src}" ]] && spt_src="${0}" # Use ${0} when BASH_SOURCE is unavailable (e.g., dash)
while [ -h "${spt_src}" ]; do # Recursively resolve ${spt_src} until file is no longer a symlink
  drc_spt="$( cd -P "$( dirname "${spt_src}" )" && pwd )"
  spt_src="$(readlink "${spt_src}")"
  [[ ${spt_src} != /* ]] && spt_src="${drc_spt}/${spt_src}" # If ${spt_src} was relative symlink, resolve it relative to path where symlink file was located
done
cmd_ln="${spt_src} ${@}"
drc_spt="$( cd -P "$( dirname "${spt_src}" )" && pwd )"
spt_nm=$(basename ${spt_src}) # [sng] Script name (unlike $0, ${BASH_SOURCE[0]} works well with 'source <script>')
spt_pid=$$ # [nbr] Script PID (process ID)

#echo "test_ncremap: Done!"
#exit 1

# Configure paths at High-Performance Computer Centers (HPCCs) based on ${HOSTNAME}
if [ -z "${HOSTNAME}" ]; then
    if [ -f /bin/hostname ] && [ -x /bin/hostname ]; then
	export HOSTNAME=`/bin/hostname`
    elif [ -f /usr/bin/hostname ] && [ -x /usr/bin/hostname ]; then
	export HOSTNAME=`/usr/bin/hostname`
    fi # !hostname
fi # HOSTNAME
# Default input and output directory is ${DATA}
if [ -z "${DATA}" ]; then
    case "${HOSTNAME}" in
	constance* | node* ) DATA='/scratch' ; ;; # PNNL
	blues* | blogin* | b[0123456789][0123456789][0123456789] ) DATA="/lcrc/project/ACME/${USER}" ; ;; # ALCF blues compute nodes named bNNN, 36|64 cores|GB/node
	*cheyenne* ) DATA="/glade/p/work/${USER}" ; ;; # NCAR cheyenne compute nodes named, e.g., r8i0n8, r5i3n16, r12i5n29 ... 18|(64/128) cores|GB/node (cheyenne login nodes 256 GB)
	cooley* | cc[0123456789][0123456789][0123456789] | mira* ) DATA="/projects/HiRes_EarthSys_2/${USER}" ; ;; # ALCF cooley compute nodes named ccNNN, 384 GB/node
	cori* | edison* ) DATA="${SCRATCH}" ; ;; # NERSC cori/edison compute nodes all named nidNNNNN, edison 24|64 cores|GB/node; cori 32|(96/128) cores|GB/node (knl/haswell) (cori login nodes 512 GB)
	rhea* | titan* ) DATA="/lustre/atlas/world-shared/cli115/${USER}" ; ;; # OLCF rhea compute nodes named rheaNNN, 128 GB/node
	theta* ) DATA="/projects/ClimateEnergy_2/${USER}" ; ;; # ALCF theta compute nodes named fxm, 64|192 cores|GB/node
	* ) DATA='/tmp' ; ;; # Other
    esac # !HOSTNAME
fi # DATA

# Ensure batch jobs access correct 'mpirun' (or, with SLURM, 'srun') command, netCDF library, and NCO executables and library
# 20170914 Entire block is identical between ncclimo and ncremap---keep it that way!
# hrd_pth could be a command-line option to control environment if this block placed below getopt() block (not trivial)
# Set NCO_PATH_OVERRIDE to 'No' to prevent NCO from executing next block that overrides PATH:
# export NCO_PATH_OVERRIDE='No'
hrd_pth='Yes' # [sng] Hard-code machine-dependent paths/modules if HOSTNAME in database
if [ "${hrd_pth}" = 'Yes' ] && [ "${NCO_PATH_OVERRIDE}" != 'No' ]; then
    # If HOSTNAME is not in database, change hrd_pth_fnd to 'No' in case-statement default fall-through
    hrd_pth_fnd='Yes' # [sng] Machine-dependent paths/modules for HOSTNAME found in database
    case "${HOSTNAME}" in
	aims* )
	    export PATH='/export/zender1/bin'\:${PATH}
            export LD_LIBRARY_PATH='/export/zender1/lib'\:${LD_LIBRARY_PATH} ; ;;
	blues* | blogin* | b[0123456789][0123456789][0123456789] )
	    soft add @openmpi-gcc
	    export PATH='/home/zender/bin'\:${PATH}
	    export LD_LIBRARY_PATH='/home/zender/lib'\:${LD_LIBRARY_PATH} ; ;;
	cooley* )
	    # 20160421: Split cooley from mira binary locations to allow for different system libraries
	    # http://www.mcs.anl.gov/hs/software/systems/softenv/softenv-intro.html
	    soft add +mvapich2
            export PBS_NUM_PPN=12 # Spoof PBS on Soft (which knows nothing about node capabilities)
	    export PATH='/home/zender/bin_cooley'\:${PATH}
	    export LD_LIBRARY_PATH='/home/zender/lib_cooley'\:${LD_LIBRARY_PATH} ; ;;
	*cheyenne* )
	    # 20180112: Cheyenne support not yet tested in batch mode
	    if [ ${spt_nm} = 'ncremap' ]; then
		# On cheyenne, module load ncl installs ERWG in /glade/u/apps/ch/opt/ncl/6.4.0/intel/17.0.1/bin (i.e., ${NCARG_ROOT}/bin)
		module load ncl
	    fi # !ncremap
	    if [ -n "${NCARG_ROOT}" ]; then
		export PATH="${PATH}:/glade/u/apps/ch/opt/ncl/6.4.0/intel/17.0.1/bin"
	    fi # !NCARG_ROOT
            export PATH='/glade/u/home/zender/bin'\:${PATH}
            export LD_LIBRARY_PATH='/glade/u/apps/ch/opt/netcdf/4.6.1/intel/17.0.1/lib:/glade/u/home/zender/lib'\:${LD_LIBRARY_PATH} ; ;;
	cori* )
	    # 20160407: Separate cori from edison binary locations to allow for different system libraries
	    # 20160420: module load gsl, udunits required for non-interactive batch submissions by Wuyin Lin
	    # Not necessary for interactive, nor for CSZ non-interactive, batch submisssions
	    # Must be due to home environment differences between CSZ and other users
	    # Loading gsl and udunits seems to do no harm, so always do it
	    # This is equivalent to LD_LIBRARY_PATH method used for netCDF and SZIP on rhea
	    # Why do cori/edison and rhea require workarounds for different packages?
	    module load gsl
	    module load udunits
	    if [ ${spt_nm} = 'ncremap' ]; then
		module load ncl # 20170916 OK
	    fi # !ncremap
	    if [ -n "${NCARG_ROOT}" ]; then
		export PATH="${PATH}:${NCARG_ROOT}/bin"
	    fi # !NCARG_ROOT
	    export PATH='/global/homes/z/zender/bin_cori'\:${PATH}
            export LD_LIBRARY_PATH='/global/homes/z/zender/lib_cori'\:${LD_LIBRARY_PATH} ; ;;
	edison* )
	    module load gsl
	    module load udunits2 # 20170816 Name changed to udunits2
	    if [ ${spt_nm} = 'ncremap' ]; then
		module load ncl # 20170916 OK
	    fi # !ncremap
	    if [ -n "${NCARG_ROOT}" ]; then
		export PATH="${PATH}:${NCARG_ROOT}/bin"
	    fi # !NCARG_ROOT
	    export PATH='/global/homes/z/zender/bin_edison'\:${PATH}
            export LD_LIBRARY_PATH='/global/homes/z/zender/lib_edison'\:${LD_LIBRARY_PATH} ; ;;
	mira* )
	    export PATH='/home/zender/bin_mira'\:${PATH}
	    export LD_LIBRARY_PATH='/soft/libraries/netcdf/current/library:/home/zender/lib_mira'\:${LD_LIBRARY_PATH} ; ;;
	rhea* )
	    # 20151017: CSZ next three lines guarantee finding mpirun
	    source ${MODULESHOME}/init/sh # 20150607: PMC Ensures find module commands will be found
	    module unload PE-intel # Remove Intel-compiled mpirun environment
	    module load PE-gnu # Provides GCC-compiled mpirun environment (CSZ uses GCC to build NCO on rhea)
	    # 20160219: CSZ UVCDAT setup causes failures with mpirun, attempting a work-around
	    if [ -n "${UVCDAT_SETUP_PATH}" ]; then
		module unload python ompi paraview PE-intel PE-gnu
		module load gcc
		source /lustre/atlas1/cli900/world-shared/sw/rhea/uvcdat/latest_full/bin/setup_runtime.sh
		export ${UVCDAT_SETUP_PATH}
	    fi # !UVCDAT_SETUP_PATH
	    if [ ${spt_nm} = 'ncremap' ]; then
		# 20170825: Use module load ncl/6.3.0 (6.4.0 lacks ERWG)
		module load ncl/6.3.0
	    fi # !ncremap
	    if [ -n "${NCARG_ROOT}" ]; then
		export PATH="${PATH}:${NCARG_ROOT}/bin"
	    fi # !NCARG_ROOT
            export PATH='/ccs/home/zender/bin_rhea'\:${PATH}
	    export LD_LIBRARY_PATH='/autofs/nccs-svm1_sw/rhea/.swci/0-core/opt/spack/20170224/linux-rhel6-x86_64/gcc-4.4.7/netcdf-4.4.1-uroyzcwi6fc3kerfidguoof7g2vimo57/lib:/sw/redhat6/szip/2.1/rhel6.6_gnu4.8.2/lib:/ccs/home/zender/lib_rhea'\:${LD_LIBRARY_PATH} ; ;;
	theta* )
	    export PATH='/opt/cray/pe/netcdf/4.6.1.2/gnu/7.1/bin'\:${PATH}
	    export LD_LIBRARY_PATH='/opt/cray/pe/netcdf/4.6.1.2/gnu/7.1/lib'\:${LD_LIBRARY_PATH} ; ;;
	titan* )
	    source ${MODULESHOME}/init/sh # 20150607: PMC Ensures find module commands will be found
	    module load gcc
	    if [ ${spt_nm} = 'ncremap' ]; then
		# 20170831: Use module load ncl (6.3.0 lacks ERWG)
		module load ncl # 20170916 OK
	    fi # !ncremap
	    if [ -n "${NCARG_ROOT}" ]; then
		export PATH="${PATH}:${NCARG_ROOT}/bin"
	    fi # !NCARG_ROOT
            export PATH='/ccs/home/zender/bin_titan'\:${PATH}
	    export LD_LIBRARY_PATH='/opt/cray/netcdf/4.4.1.1/GNU/49/lib:/sw/xk6/udunits/2.1.24/sl_gcc4.5.3/lib:/ccs/home/zender/lib_titan'\:${LD_LIBRARY_PATH} ; ;;
	* ) # Default fall-through
	    hrd_pth_fnd='No' ; ;;
    esac # !HOSTNAME
fi # !hrd_pth && !NCO_PATH_OVERRIDE

# Test cases (for Charlie's machines)
# Map-only:
# ncremap -D 1 -s ${DATA}/grids/oEC60to30.SCRIP.150729.nc -g ${DATA}/grids/t62_SCRIP.20150901.nc -m ~/map.nc -a bilinear
# ncremap -D 1 -s ${DATA}/grids/oEC60to30.SCRIP.150729.nc -g ${DATA}/grids/t62_SCRIP.20150901.nc -m ~/map.nc -a tempest
# ncremap -D 1 -s ${DATA}/grids/oEC60to30.SCRIP.150729.nc -d ${DATA}/dstmch90/dstmch90_clm.nc -m ~/map.nc -a tempest
# ncremap -D 1 -s ${DATA}/grids/128x256_SCRIP.20160301.nc -d ${DATA}/dstmch90/dstmch90_clm.nc -m ~/map.nc -a tempest
# Regrid:
# ls ${DATA}/ne30/raw/*1979*.nc | ncremap -m ${DATA}/maps/map_ne30np4_to_fv129x256_aave.20150901.nc -O ~/rgr
# ncremap -a conserve -v FSNT -s ${DATA}/grids/ne30np4_pentagons.091226.nc -d ${DATA}/dstmch90/dstmch90_clm.nc -I ${DATA}/ne30/raw  -O ~/rgr
# ls ${DATA}/essgcm14/essgcm14*cam*0007*.nc | ncremap -a conserve -M -d ${DATA}/dstmch90/dstmch90_clm.nc -O ~/rgr
# ncremap -a conserve -v FSNT -s ${DATA}/grids/ne30np4_pentagons.091226.nc -d ${DATA}/dstmch90/dstmch90_clm.nc -I ${DATA}/ne30/raw -O ~/rgr
# ncremap -P airs -v TSurfAir -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/AIRS.2014.10.01.202.L2.RetStd.v6.0.11.0.G14275134307.hdf ~/airs_out.nc
# ncremap -v CloudFrc_A -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/AIRS.2002.08.01.L3.RetStd_H031.v4.0.21.0.G06104133732.hdf ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/MOD04_L2.A2000055.0005.006.2014307165927.hdf ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/OMI-Aura_L2-OMIAuraSO2_2012m1222-o44888_v01-00-2014m0107t114720.h5 ~/foo.nc
# ncremap -v T -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/wrfout_v2_Lambert_notime.nc ~/foo.nc
# ncremap -v StepTwoO3 -d ${DATA}/hdf/cam_time.nc ${DATA}/hdf/OMI-Aura_L2-OMTO3_2015m0731t0034-o58727_v003-2015m0731t080836.he5.nc ~/foo.nc
# ncremap -v TSurfStd -G "--rgr grd_ttl='Default internally-generated grid' --rgr grid=~/rgr/ncremap_tmp_grd_dst.nc --rgr latlon=100,100 --rgr snwe=30.0,70.0,-130.0,-90.0" ${DATA}/sld/raw/AIRS.2014.10.01.202.L2.TSurfStd.Regrid010.1DLatLon.hole.nc ~/foo.nc
# ncremap -x TSurfStd_ct -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/sld/raw/AIRS.2014.10.01.202.L2.TSurfStd.Regrid010.1DLatLon.hole.nc ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/cice_hi_flt.nc ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/hdf/cam_time.nc ~/foo.nc
# CESM & E3SM/ACME:
# ncremap -s ${DATA}/grids/ne120np4_pentagons.100310.nc -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/ne120/raw/b1850c5_m2a.cam.h0.0060-01.nc ~/foo.nc
# ncremap -s ${DATA}/grids/ne120np4_pentagons.100310.nc -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/ne120/raw/b1850c5_m2a.clm2.h0.0060-01.nc ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/ne120/raw/b1850c5_m2a.cice.h.0060-01.nc ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/ne120/raw/b1850c5_m2a.pop.h.0060-01.nc ~/foo.nc
# ncremap -g ${DATA}/grids/180x360_SCRIP.20150901.nc ${DATA}/ne120/raw/b1850c5_m2a.rtm.h0.0060-01.nc ~/foo.nc
# Old MPAS filename conventions (until ~201609)::
# ncremap -P mpas -m ${DATA}/maps/map_oEC60to30_to_t62_bilin.20160301.nc ${DATA}/hdf/hist.ocn.0003-12-01_00.00.00.nc ~/foo.nc
# ncremap -P mpas -m ${DATA}/maps/map_mpas120_TO_T62_aave.121116.nc ${DATA}/hdf/hist.ice.0003-12-01_00.00.00.nc ~/foo.nc
# New MPAS filename conventions (as of ~201612):
# ncremap -P mpas -m ${DATA}/maps/map_oEC60to30_to_t62_bilin.20160301.nc ${DATA}/hdf/mpaso.hist.am.timeSeriesStatsMonthly.0001-01-01.nc ~/foo.nc
# ncremap -P mpas -m ${DATA}/maps/map_oEC60to30_to_t62_bilin.20160301.nc ${DATA}/hdf/mpascice.hist.am.timeSeriesStatsMonthly.0251-01-01.nc ~/foo.nc
# ncremap -P mpas --mss_val=-1.0e36 -s ${DATA}/grids/ais20km.150910.SCRIP.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/hdf/ais20km.20180117.nc ~/foo.nc
# ncremap -P mpas --mss_val=-1.0e36 -s ${DATA}/grids/ais20km.150910.SCRIP.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/hdf/mpasLIoutput.nc ~/foo.nc
# E3SM/ACME benchmarks:
# ncremap -v FSNT,AODVIS -m ${DATA}/maps/map_ne30np4_to_fv129x256_aave.20150901.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo.nc
# ncremap -v FSNT,AODVIS -a conserve -s ${DATA}/grids/ne30np4_pentagons.091226.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo.nc
# ncremap -v FSNT,AODVIS -a conserve2nd -s ${DATA}/grids/ne30np4_pentagons.091226.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo.nc
# ncremap -v FSNT,AODVIS --rnr=0.99 --xtr_mth=idavg -s ${DATA}/grids/ne30np4_pentagons.091226.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo.nc
# ncremap -v FSNT,AODVIS -a tempest -s ${DATA}/grids/ne30np4_pentagons.091226.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo.nc
# Positional arguments:
# ncremap --var=FSNT,AODVIS --map=${DATA}/maps/map_ne30np4_to_fv129x256_aave.20150901.nc --drc_out=~/rgr ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-??.nc
# Omit cell_measures:
# ncremap --no_cll_msr --var=FSNT,AODVIS -i ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc -m ${DATA}/maps/map_ne30np4_to_fv129x256_aave.20150901.nc -o ~/foo.nc
# SGS (201705):
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -s ${DATA}/grids/ne30np4_pentagons.091226.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/ne30/raw/F_acmev03_enso_camse_clm45bgc_ne30_co2cycle.clm2.h0.2000-01.nc ~/alm_rgr.nc # 20170510 1D->2D works conserve and bilinear, no inferral
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -s ${DATA}/grids/t42_SCRIP.20150901.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/essgcm14/essgcm14.clm2.h0.0000-01.nc ~/t42_rgr.nc # 20170510 2D->2D works conserve and bilinear, no inferral
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -s ${DATA}/grids/t42_SCRIP.20150901.nc -d ${DATA}/dstmch90/dstmch90_clm.nc ${DATA}/essgcm14/essgcm14.clm2.h0.0000-01.nc ~/t42_rgr.nc # 20170510 2D->2D works bilinear and conserve, infer D not S
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -d ${DATA}/dstmch90/dstmch90_clm.nc ${DATA}/essgcm14/essgcm14.clm2.h0.0000-01.nc ~/t42_rgr.nc # 20170510 2D->2D works bilinear and conserve ~2% wrong, infer S and D
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -d ${DATA}/hdf/b1850c5cn_doe_polar_merged_0_cesm1_2_0_HD+MAM4+tun2b.hp.e003.cam.h0.0001-01.nc ${DATA}/essgcm14/essgcm14.clm2.h0.0000-01.nc ~/t42_rgr.nc # 20170510 2D->2D works bilinear and conserve ~2% wrong, infer S and D
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -d ${DATA}/essgcm14/essgcm14.cam2.h0.0000-01.nc ${DATA}/ne30/rgr/F_acmev03_enso_camse_clm45bgc_ne30_co2cycle.clm2.h0.2000-01.nc ~/fv09_rgr.nc # 20170510 2D->2D bilinear works and conserve ~2% wrong, infer S and D
# ncremap --vrb=3 -P sgs --var=area,FSDS,landfrac,landmask,TBOT -d ${HOME}/skl_t42.nc ${DATA}/ne30/rgr/F_acmev03_enso_camse_clm45bgc_ne30_co2cycle.clm2.h0.2000-01.nc ~/fv09_rgr.nc # 20170510 2D->2D works bilinear and conserve ~2% wrong, infer S and D
# ncremap --vrb=3 -p nil -P sgs -s ${DATA}/grids/ne30np4_pentagons.091226.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc -O ${DATA}/ne30/rgr ${DATA}/ne30/raw/F_acmev03_enso_camse_clm45bgc_ne30_co2cycle.clm2.h0.2000-??.nc > ~/ncremap.out 2>&1 &
# ncremap --vrb=3 -a conserve --sgs_frc=aice --sgs_msk=tmask --sgs_nrm=100 --var=hi,uvel,aice,aisnap,albsno,blkmask,evap,evap_ai,fswabs,fswabs_ai,fswdn,fswthru,fswthru_ai,ice_present,snow,snow_ai,tarea,tmask,uarea -s ${DATA}/grids/gx1v7_151008.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/hdf/ctl_brcp85c5cn_deg1.enm.cice.h.2050-07.nc ~/foo.nc # 20170525 normalization required to get mask right
# ncremap --vrb=3 -P cice -a conserve --var=hi,uvel,aice,aisnap,albsno,blkmask,evap,evap_ai,fswabs,fswabs_ai,fswdn,fswthru,fswthru_ai,ice_present,snow,snow_ai,tarea,tmask,uarea -s ${DATA}/grids/gx1v7_151008.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/hdf/ctl_brcp85c5cn_deg1.enm.cice.h.2050-07.nc ~/foo.nc # 20170525 cice short-cut
# CICE/CESM on POP grid: full grid inferral (and thus conservative remapping) fails because masked vertices/cells missing, must use bilinear or supply grid-file for conservative
# ncremap -a bilinear -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/hdf/ctl_brcp85c5cn_deg1.enm.cice.h.2050-07.nc ~/foo.nc # 20170515: grid centers/bounds in non-masked regions suffice for bilinear interpolation
# ncremap -a conserve -s ${DATA}/grids/gx1v7_151008.nc -g ${DATA}/grids/129x256_SCRIP.20150901.nc ${DATA}/hdf/ctl_brcp85c5cn_deg1.enm.cice.h.2050-07.nc ~/foo.nc # 20170521: conservative requires supplied tri-pole grid for centers/bounds in masked regions
# File-format
# ncremap -v FSNT,AODVIS -s ${DATA}/grids/ne30np4_pentagons.091226.nc -d ${DATA}/dstmch90/dstmch90_clm.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo.nc
# TempestRemap boutique:
# GenerateCSMesh --alt --res 30 --file ${DATA}/grids/ne30.g
# ncremap --dbg=1 -a se2fv_flx --src_grd=${DATA}/grids/ne30.g --dst_grd=${DATA}/grids/129x256_SCRIP.20150901.nc -m ~/map_ne30np4_to_fv129x256_mono.20180301.nc
# ncremap --dbg=1 -m ~/map_ne30np4_to_fv129x256_mono.20180301.nc ${DATA}/ne30/raw/famipc5_ne30_v0.3_00003.cam.h0.1979-01.nc ~/foo_fv129x256.nc
# ncremap --dbg=1 -a fv2se_stt --src_grd=${DATA}/grids/129x256_SCRIP.20150901.nc --dst_grd=${DATA}/grids/ne30.g -m ~/map_fv129x256_to_ne30np4_highorder.20180301.nc
# ncremap --dbg=1 -a fv2se_flx --src_grd=${DATA}/grids/129x256_SCRIP.20150901.nc --dst_grd=${DATA}/grids/ne30.g -m ~/map_fv129x256_to_ne30np4_monotr.20180301.nc
# ncremap --dbg=1 -m ~/map_fv129x256_to_ne30np4_highorder.20180301.nc ~/foo_fv129x256.nc ~/foo_ne30.nc
# Atmosphere->Ocean:
# ncremap --dbg=1 --a2o -a se2fv_flx --src_grd=${DATA}/grids/ne30.g --dst_grd=${DATA}/grids/129x256_SCRIP.20150901.nc -m ~/map_ne30np4_to_fv129x256_mono.20180301.nc
# Debugging and Benchmarking:
# ncremap -D 1 -d ${DATA}/dstmch90/dstmch90_clm.nc ${DATA}/sld/raw/AIRS.2014.10.01.202.L2.TSurfStd.Regrid010.1DLatLon.hole.nc ~/foo.nc > ~/ncremap.out 2>&1 &
# RRG (201807):
# ncremap -D 1 -a conserve --rnm_sng='_128e_to_134e_9s_to_16s' --bb_wesn='128.0,134.0,-16.0,-9.0' --dat_glb=${HOME}/dat_glb.nc --grd_glb=${HOME}/grd_glb.nc --grd_rgn=${HOME}/grd_rgn.nc ~/dat_rgn.nc ~/foo.nc > ~/ncremap.out 2>&1 &
# ncremap -D 0 --vrb=1 -a conserve --rnm_sng='_128e_to_134e_9s_to_16s' --bb_wesn='128.0,134.0,-16.0,-9.0' --dat_glb=${HOME}/dat_glb.nc --grd_glb=${HOME}/grd_glb.nc --grd_dst=${HOME}/grd_rgn.nc --grd_src=${HOME}/grd_src.nc --map=${HOME}/map.nc ~/dat_rgn.nc ~/foo.nc
# ncremap -D 0 --vrb=1 -a conserve --dat_glb=${HOME}/dat_glb.nc --grd_glb=${HOME}/grd_glb.nc --grd_dst=${HOME}/grd_rgn.nc --grd_src=${HOME}/grd_src.nc --map=${HOME}/map.nc ~/dat_rgn.nc ~/foo.nc
# ncremap -D 0 --vrb=1 -a conserve --dat_glb=${HOME}/dat_glb.nc --grd_glb=${HOME}/grd_glb.nc -g ${HOME}/grd_rgn.nc ~/dat_rgn.nc ~/foo.nc
# MWF (201807):
# ncremap -D 2 -P mwf --grd_src=${DATA}/grids/129x256_SCRIP.20150901.nc --grd_dst=${DATA}/grids/ne30.g --nm_src=fv129x256 --nm_dst=ne30np4 --dt_sng=20181201 --drc_out=$TMPDIR > ~/ncremap.out 2>&1 &
# ncremap -D 2 -P mwf --grd_src=${DATA}/grids/ocean.RRS.30-10km_scrip_150722.nc --grd_dst=${DATA}/grids/T62_040121.nc --nm_src=oRRS30to10 --nm_dst=T62 --dt_sng=20180901 --drc_out=$TMPDIR > ~/ncremap.out 2>&1 &
# ncremap -D 2 -P mwf --grd_src=${DATA}/grids/ocean.RRS.30-10km_scrip_150722.nc --grd_dst=${DATA}/grids/ne30.g --nm_src=oRRS30to10 --nm_dst=ne30np4 --dt_sng=20180901 --drc_out=$TMPDIR > ~/ncremap.out 2>&1 &
# ncremap -D 2 -P mwf --wgt_cmd='mpirun -np 12 ESMF_RegridWeightGen' --grd_src=${DATA}/grids/ocean.RRS.30-10km_scrip_150722.nc --grd_dst=${DATA}/grids/T62_040121.nc --nm_src=oRRS30to10 --nm_dst=T62 --dt_sng=20180901 --drc_out=$TMPDIR > ~/ncremap.out 2>&1 &
# Add depth (201901):
# ncremap -P mpas --dpt_fl=${DATA}/grids/mpas_refBottomDepth_60lyr.nc -m ${DATA}/maps/map_oEC60to30v3_to_cmip6_180x360_aave.20181001.nc ${DATA}/hdf/mpaso.lrz.hist.am.timeSeriesStatsMonthly.0001-12-01.nc ~/foo.nc

# dbg_lvl: 0 = Quiet, print basic status during evaluation
#          1 = Print configuration, full commands, and status to output during evaluation
#          2 = As in dbg_lvl=1, but DO NOT EXECUTE COMMANDS (i.e., pretend to run but do not regrid anything)
#          3 = As in dbg_lvl=1, and pass debug level through to NCO/ncks

# Set NCO version and directory
nco_exe=`which ncks`
if [ -z "${nco_exe}" ]; then
    echo "ERROR: Unable to find NCO, nco_exe = ${nco_exe}"
    exit 1
fi # !nco_exe
# StackOverflow method finds NCO directory
while [ -h "${nco_exe}" ]; do
  drc_nco="$( cd -P "$( dirname "${nco_exe}" )" && pwd )"
  nco_exe="$(readlink "${nco_exe}")"
  [[ ${nco_exe} != /* ]] && nco_exe="${drc_nco}/${nco_exe}"
done
drc_nco="$( cd -P "$( dirname "${nco_exe}" )" && pwd )"
nco_vrs=$(ncks --version 2>&1 > /dev/null | grep NCO | awk '{print $5}')
# 20190218: Die quickly when NCO is found yet cannot run, e.g., due to linker errors
if [ -z "${nco_vrs}" ]; then
    echo "${spt_nm}: ERROR Running ${nco_exe} dies with error message on next line:"
    $(ncks --version)
    exit 1
fi # !nco_vrs
lbr_vrs=$(ncks --library 2>&1 > /dev/null | awk '{print $6}')

#echo "test_ncremap: Done!"
#exit 1

# Detect and warn about mixed modules (for Qi Tang 20170531)
if [ "${drc_spt}" != "${drc_nco}" ]; then
    echo "WARNING: Possible mixture of NCO versions from different locations. Script ${spt_nm} is from directory ${drc_spt} while NCO binaries are from directory ${drc_nco}. Normally the script and binaries are from the same executables directory. This WARNING may be safely ignored for customized scripts and/or binaries that the user has intentionally split into different directories."
    echo "HINT: Conflicting script and binary directories may result from 1) Hardcoding an NCO script and/or binary pathname, 2) Having incomplete NCO installations in one or more directories in the \$PATH environment variable, 3) Loading multiple NCO modules with different locations."
fi # drc_spt

# When running in a terminal window (not in an non-interactive batch queue)...
if [ -n "${TERM}" ]; then
    # Set fonts for legibility
    if [ -x /usr/bin/tput ] && tput setaf 1 &> /dev/null; then
	fnt_bld=`tput bold` # Bold
	fnt_nrm=`tput sgr0` # Normal
	fnt_rvr=`tput smso` # Reverse
	fnt_tlc=`tput sitm` # Italic
    else
	fnt_bld="\e[1m" # Bold
	fnt_nrm="\e[0m" # Normal
	fnt_rvr="\e[07m" # Reverse
	fnt_tlc="\e[3m" # Italic
    fi # !tput
fi # !TERM

# Defaults for command-line options and some derived variables
# Modify these defaults to save typing later
a2o_flg='No' # [flg] Atmosphere-to-ocean (only used by Tempest mesh generator)
alg_typ='bilinear' # [sng] Algorithm for remapping (bilinear|conserve|conserve2nd|nearestdtos|neareststod|patch|tempest|se2fv_flx|se2fv_stt|se2fv_alt|fv2se_flx|fv2se_stt|fv2se_alt)
bch_pbs='No' # [sng] PBS batch (non-interactive) job
bch_slr='No' # [sng] SLURM batch (non-interactive) job
cln_flg='Yes' # [flg] Clean-up (remove) intermediate files before exiting
clm_flg='No' # [flg] Invoked by ncclimo script
d2f_flg='No' # [flg] Convert double-precision fields to single-precision
d2f_opt='-M dbl_flt' # [sng] Option string to convert double-precision fields to single-precision
dbg_lvl=0 # [nbr] Debugging level
dfl_lvl='' # [enm] Deflate level
dpt_exe_mpas='add_depth.py' # [sng] Depth coordinate addition command for MPAS
dpt_flg='No' # [flg] Add depth coordinate to MPAS files
dpt_fl='' # [sng] Depth file with refBottomDepth for MPAS ocean
#drc_in="${drc_pwd}" # [sng] Input file directory
drc_in='' # [sng] Input file directory
drc_in_xmp='~/drc_in' # [sng] Input file directory for examples
drc_out="${drc_pwd}" # [sng] Output file directory
drc_out_xmp="~/rgr" # [sng] Output file directory for examples
dst_fl='' # [sng] Destination file
dst_xmp='dst.nc' # [sng] Destination file for examples
dt_sng=`date +%Y%m%d` # [sng] Date string for MWF map names
fl_fmt='' # [enm] Output file format
fl_nbr=0 # [nbr] Number of files to remap
flg_grd_only='No' # [flg] Create grid then exit before regridding
gaa_sng="--gaa remap_script=${spt_nm} --gaa remap_command=\"'${cmd_ln}'\" --gaa remap_hostname=${HOSTNAME} --gaa remap_version=${nco_vrs}" # [sng] Global attributes to add
gll_fl='' # [sng] GLL grid metadata (geometry+connectivity+Jacobian) file
grd_dst='' # [sng] Destination grid-file
grd_dst_xmp='grd_dst.nc' # [sng] Destination grid-file for examples
grd_sng='' # [sng] Grid string
grd_src='' # [sng] Source grid-file
grd_src_xmp='grd_src.nc' # [sng] Source grid-file for examples
hdr_pad='10000' # [B] Pad at end of header section
hnt_dst='' # [sng] ERWG hint for destination grid
hnt_src='' # [sng] ERWG hint for source grid
in_fl='' # [sng] Input file
in_xmp='in.nc' # [sng] Input file for examples
inp_aut='No' # [sng] Input file list automatically generated (in ncclimo, or specified with -i in ncremap)
inp_glb='No' # [sng] Input file list from globbing directory
inp_psn='No' # [sng] Input file list from positional arguments
inp_std='No' # [sng] Input file list from stdin
job_nbr=2 # [nbr] Job simultaneity for parallelism
map_fl='' # [sng] Map-file
map_rsl_fl='' # [sng] File containing results of weight-generation command (i.e., map_fl or map_trn_fl for monotr)
map_trn_fl='' # [sng] Map-file transpose (for Tempest)
map_mk='No' # [flg] Generate map-file (i.e., map does not yet exist)
map_usr_flg='No' # [flg] User supplied argument to --map option
map_xmp='map.nc' # [sng] Map-file for examples
mlt_map_flg='Yes' # [sng] Multi-map flag
mpi_flg='No' # [sng] Parallelize over nodes
msh_fl='' # [sng] Mesh-file (for Tempest)
msk_dst='' # [sng] Mask-template variable in destination file
msk_out='' # [sng] Mask variable in regridded file
msk_src='' # [sng] Mask-template variable in source file
mss_val='-9.99999979021476795361e+33' # [frc] Missing value for MPAS (ocean+seaice)
#mss_val='-1.0e36' # [frc] Missing value for MPAS (landice)
nco_opt='--no_tmp_fl' # [sng] NCO defaults (e.g., '-6 -t 1')
nco_usr='' # [sng] NCO user-configurable options (e.g., '-D 1')
nd_nbr=1 # [nbr] Number of nodes
out_fl='' # [sng] Output file
out_xmp='out.nc' # [sng] Output file for examples
par_typ='nil' # [sng] Parallelism type
ppc_prc='' # [nbr] Precision-preserving compression number of significant digits
prc_typ='' # [sng] Procedure type
rgr_opt='--rgr lat_nm_out=lat#lon_nm_out=lon' # [sng] Regridding options
#rgr_opt='--rgr lat_dnm_nm=x#lon_dmn_nm=y' # [sng] Regridding options for projection grid
rnr_thr='' # [frc] Renormalization option
sgs_frc='landfrac' # [sng] Sub-grid fraction variable
sgs_msk='landmask' # [sng] Sub-grid mask variable
sgs_nrm='1.0' # [frc] Sub-grid normalization
skl_fl='' # [sng] Skeleton file
std_flg='No' # [sng] Input available from pipe to stdin
thr_nbr=2 # [nbr] Thread number for regridder
trn_map='No' # [flg] Tempest transpose map (i.e., fv2se_flx == monotr)
ugrid_fl='' # [sng] UGRID file
unq_sfx=".pid${spt_pid}" # [sng] Unique suffix
#var_lst='FSNT,AODVIS' # [sng] Variables to process (empty means all)
var_lst='' # [sng] Variables to process (empty means all)
var_rgr='' # [sng] CF template variable
var_xmp='FSNT' # [sng] Variable list for examples
vrb_lvl=2 # [sng] Verbosity level
vrb_0=0 # [enm] Verbosity level: Quiet
vrb_1=1 # [enm] Verbosity level: Standard, minimal file I/O
vrb_2=2 # [enm] Verbosity level: All file I/O
vrb_3=3 # [enm] Verbosity level: English
vrb_4=4 # [enm] Verbosity level: Pedantic
vrs_prn='No' # [sng] Print version information
wgt_exe_esmf='ESMF_RegridWeightGen' # [sng] ESMF executable
wgt_exe_tps='GenerateOfflineMap' # [sng] TempestRemap executable
wgt_typ='esmf' # [sng] Weight-generator program ('esmf' or 'tempest')
wgt_opt='' # [sng] Weight-generator options
wgt_opt_esmf='--no_log --ignore_unmapped' # [sng] ESMF_RegridWeightGen options (ESMF < 7.1.0r)
#wgt_opt_esmf='--ignore_unmapped --ignore_degenerate' # [sng] ESMF_RegridWeightGen options (ESMF >= 7.1.0r) (ignore_degenerate is required for CICE regridding with ESMF >= 7.1.0r, and is not supported or required with ESMF < 7.1.0r)
#wgt_opt_tps='--mono' # [sng] TempestRemap options
wgt_opt_tps='' # [sng] TempestRemap options
xtn_var='' # [sng] Extensive variables (e.g., 'TSurfStd_ct')
xtr_nsp=8 # [nbr] Extrapolation number of source points
xtr_typ='' # [sng] Extrapolation type
xtr_xpn=2.0 # [frc] Extrapolation exponent

# Set temporary-file directory
if [ -d "${TMPDIR}" ]; then
    # Fancy %/ syntax removes trailing slash (e.g., from $TMPDIR)
    drc_tmp="${TMPDIR%/}"
elif [ -d '/tmp' ]; then
    drc_tmp='/tmp'
else
    drc_tmp=${PWD}
fi # !gpfs

#echo "test_ncremap: Done!"
#exit 1

function fnc_usg_prn { # NB: dash supports fnc_nm (){} syntax, not function fnc_nm{} syntax
    # Print usage
    printf "${fnt_rvr}Basic usage:\n${fnt_nrm} ${fnt_bld}${spt_nm} -d dst_fl in_fl out_fl${fnt_nrm}\n"
    printf "${fnt_nrm} ${fnt_bld}${spt_nm} --destination=dst_fl --input_file=in_fl --output_file=out_fl${fnt_nrm}\n\n"
    echo "Command-line options [long-option synonyms in ${fnt_tlc}italics${fnt_nrm}]:"
    echo "${fnt_rvr}-3${fnt_nrm}          Output file format CLASSIC (netCDF3 classic CDF1) [${fnt_tlc}fl_fmt, file_format=classic${fnt_nrm}]"
    echo "${fnt_rvr}-4${fnt_nrm}          Output file format NETCDF4 (netCDF4 extended HDF5) [${fnt_tlc}fl_fmt, file_format=netcdf4${fnt_nrm}]"
    echo "${fnt_rvr}-5${fnt_nrm}          Output file format 64BIT_DATA (netCDF3/PnetCDF CDF5) [${fnt_tlc}fl_fmt, file_format=64bit_data${fnt_nrm}]"
    echo "${fnt_rvr}-6${fnt_nrm}          Output file format 64BIT_OFFSET (netCDF3 64bit CDF2) [${fnt_tlc}fl_fmt, file_format=64bit_offset${fnt_nrm}]"
    echo "${fnt_rvr}-7${fnt_nrm}          Output file format NETCDF4_CLASSIC (netCDF4 classic HDF5) [${fnt_tlc}fl_fmt, file_format=netcdf4_classic${fnt_nrm}]"
    echo "${fnt_rvr}-a${fnt_nrm} ${fnt_bld}alg_typ${fnt_nrm}  Algorithm for weight generation (default ${fnt_bld}${alg_typ}${fnt_nrm}) [${fnt_tlc}alg_typ, algorithm, regrid_algorithm${fnt_nrm}]"
    echo "            ESMF algorithms: bilinear|conserve|conserve2nd|nearestdtos|neareststod|patch"
    echo "            Tempest algorithms: tempest|se2fv_flx|se2fv_stt|se2fv_alt|fv2se_flx|fv2se_stt|fv2se_alt"
    echo "${fnt_rvr}-d${fnt_nrm} ${fnt_bld}dst_fl${fnt_nrm}   Data file to infer destination grid from (empty means none, i.e., use grd_fl, grd_sng, or map_fl)) (default ${fnt_bld}${dst_fl}${fnt_nrm}) [${fnt_tlc}dst_fl, destination_file, template_file, template${fnt_nrm}]"
    echo " ${fnt_bld}--a2o${fnt_nrm}      Atmosphere-to-ocean remap (for Tempest only) (default ${fnt_bld}${a2o_flg}${fnt_nrm}) [${fnt_tlc}a2o, atm2ocn, b2l, big2ltl, l2s, lrg2sml${fnt_nrm}]"
    echo "${fnt_rvr}-D${fnt_nrm} ${fnt_bld}dbg_lvl${fnt_nrm}  Debug level (default ${fnt_bld}${dbg_lvl}${fnt_nrm}) [${fnt_tlc}dbg_lvl, dbg, debug, debug_level${fnt_nrm}]"
    echo " ${fnt_bld}--d2f${fnt_nrm}      Convert double-precision fields to single-precision (default ${fnt_bld}${d2f_flg}${fnt_nrm}) [${fnt_tlc}d2f | d2s | dbl_flt | dbl_sgl | double_float${fnt_nrm}]"
    echo " ${fnt_bld}--dpt${fnt_nrm}      Add depth coordinate to MPAS files (default ${fnt_bld}${dpt_flg}${fnt_nrm}) [${fnt_tlc}dpt | depth | add_dpt | add_depth${fnt_nrm}]"
    echo " ${fnt_bld}--dpt_fl${fnt_nrm}   Depth file with refBottomDepth for MPAS ocean (empty means none) (default ${fnt_bld}${dpt_fl}${fnt_nrm}) [${fnt_tlc}dpt_fl, mpas_fl, mpas_depth, depth_file${fnt_nrm}]"
    echo " ${fnt_bld}--dt_sng${fnt_nrm}   Date string (for MWF map names) (default ${fnt_bld}${dt_sng}${fnt_nrm}) [${fnt_tlc}dt_sng, date_string${fnt_nrm}]"
    echo " ${fnt_bld}--fl_fmt${fnt_nrm}   File format (empty is netCDF3 64bit CDF2) (default ${fnt_bld}${fl_fmt}${fnt_nrm}) [${fnt_tlc}fl_fmt, fmt_out, file_format, format_out${fnt_nrm}]"
    echo "${fnt_rvr}-G${fnt_nrm} ${fnt_bld}grd_sng${fnt_nrm}  Grid generation arguments (empty means none) (default ${fnt_bld}${grd_sng}${fnt_nrm}) [${fnt_tlc}grd_sng, grid_generation, grid_gen, grid_string${fnt_nrm}]"
    echo "${fnt_rvr}-g${fnt_nrm} ${fnt_bld}grd_dst${fnt_nrm}  Grid-file (destination) (empty means none, i.e., infer from dst_fl or use map_fl) (default ${fnt_bld}${grd_dst}${fnt_nrm}) [${fnt_tlc}grd_dst, grid_dest, dst_grd, dest_grid, destination_grid${fnt_nrm}]"
    echo " ${fnt_bld}--gll_fl${fnt_nrm}   GLL metadata (SE grid geometry+connectivity+Jacobian) file (default ${fnt_bld}${gll_fl}${fnt_nrm}) [${fnt_tlc}gll_fl, gll_mtd, se_gmt, se_mtd${fnt_nrm}]"
#    echo " ${fnt_bld}--hrd_pth${fnt_nrm}  Use hard-coded paths on known machines (e.g., cheyenne, cori) [${fnt_tlc}hrd_pth, hard_path, csz_exe, csz_bin_lib${fnt_nrm}]"
    echo "${fnt_rvr}-I${fnt_nrm} ${fnt_bld}drc_in${fnt_nrm}   Input directory (empty means none) (default ${fnt_bld}${drc_in}${fnt_nrm}) [${fnt_tlc}drc_in, in_drc, dir_in, in_dir, input${fnt_nrm}]"
    echo "${fnt_rvr}-i${fnt_nrm} ${fnt_bld}in_fl${fnt_nrm}    Input file (empty means pipe to stdin or drc_in) (default ${fnt_bld}${in_fl}${fnt_nrm}) [${fnt_tlc}in_fl, in_file, input_file${fnt_nrm}]"
    echo "${fnt_rvr}-j${fnt_nrm} ${fnt_bld}job_nbr${fnt_nrm}  Job simultaneity for parallelism (default ${fnt_bld}${job_nbr}${fnt_nrm}) [${fnt_tlc}job_nbr, job_number, jobs${fnt_nrm}]"
    echo "${fnt_rvr}-L${fnt_nrm} ${fnt_bld}dfl_lvl${fnt_nrm}  Deflate level (empty is none) (default ${fnt_bld}${dfl_lvl}${fnt_nrm}) [${fnt_tlc}dfl_lvl, dfl, deflate${fnt_nrm}]"
    echo "${fnt_rvr}-M${fnt_nrm}          Multi-map-file toggle (unset means generate one map-file per input file) [${fnt_tlc}mlt_map, no_multimap${fnt_nrm}]"
    echo "${fnt_rvr}-m${fnt_nrm} ${fnt_bld}map_fl${fnt_nrm}   Map-file (empty means generate internally) (default ${fnt_bld}${map_fl}${fnt_nrm}) [${fnt_tlc}map_fl, map, map_file, rgr_map, regrid_map${fnt_nrm}]"
    echo " ${fnt_bld}--msk_dst${fnt_nrm}  Mask-template variable in destination file (empty means none) (default ${fnt_bld}${msk_dst}${fnt_nrm}) [${fnt_tlc}msk_dst, dst_msk, mask_destination, mask_dst${fnt_nrm}]"
    echo " ${fnt_bld}--msk_out${fnt_nrm}  Mask variable in regridded file (empty means none) (default ${fnt_bld}${msk_out}${fnt_nrm}) [${fnt_tlc}msk_out, out_msk, mask_output, mask_rgr${fnt_nrm}]"
    echo " ${fnt_bld}--msk_src${fnt_nrm}  Mask-template variable in source file (empty means none) (default ${fnt_bld}${msk_src}${fnt_nrm}) [${fnt_tlc}msk_src, src_msk, mask_source, mask_src${fnt_nrm}]"
    echo " ${fnt_bld}--mss_val${fnt_nrm}  Missing value for MPAS (empty means none) (default ${fnt_bld}${mss_val}${fnt_nrm}) [${fnt_tlc}mss_val, fll_val, missing_value, fill_value${fnt_nrm}]"
    echo "${fnt_rvr}-n${fnt_nrm} ${fnt_bld}nco_opt${fnt_nrm}  NCO options (empty means none) (default ${fnt_bld}${nco_opt}${fnt_nrm}) [${fnt_tlc}nco_opt, nco_options${fnt_nrm}]"
    echo " ${fnt_bld}--nm_dst${fnt_nrm}   Short name of destination grid (required for MWF, no default) [${fnt_tlc}nm_dst, name_dst, nm_sht_dst, short_name_destination${fnt_nrm}]"
    echo " ${fnt_bld}--nm_src${fnt_nrm}   Short name of source grid (required for MWF, no default) [${fnt_tlc}nm_src, name_src, nm_sht_src, short_name_source${fnt_nrm}]"
    echo " ${fnt_bld}--no_cll_msr${fnt_nrm}  Omit cell_measures variables (e.g., 'area') [${fnt_tlc}no_area, no_cll_msr, no_cell_measures${fnt_nrm}]"
    echo " ${fnt_bld}--no_frm_trm${fnt_nrm}  Omit formula_terms variables (e.g., 'hyba', 'PS') [${fnt_tlc}no_frm_trm, no_formula_terms${fnt_nrm}]"
    echo " ${fnt_bld}--no_stg_grd${fnt_nrm}  Omit staggered grid variables ('slat, slon, w_stag') [${fnt_tlc}no_stg_grd, no_stg, no_stagger, no_staggered_grid${fnt_nrm}]"
    echo "${fnt_rvr}-O${fnt_nrm} ${fnt_bld}drc_out${fnt_nrm}  Output directory (default ${fnt_bld}${drc_out}${fnt_nrm}) [${fnt_tlc}drc_out, out_drc, dir_out, out_dir, output${fnt_nrm}]"
    echo "${fnt_rvr}-o${fnt_nrm} ${fnt_bld}out_fl${fnt_nrm}   Output-file (regridded file) (empty copies Input filename) (default ${fnt_bld}${out_fl}${fnt_nrm}) [${fnt_tlc}out_fl, out_file, output_file${fnt_nrm}]"
    echo "${fnt_rvr}-P${fnt_nrm} ${fnt_bld}prc_typ${fnt_nrm}  Procedure type (empty means none) (default ${fnt_bld}${prc_typ}${fnt_nrm}) [${fnt_tlc}prc_typ, pdq_typ, prm_typ, procedure${fnt_nrm}]"
    echo "${fnt_rvr}-p${fnt_nrm} ${fnt_bld}par_typ${fnt_nrm}  Parallelism type (default ${fnt_bld}${par_typ}${fnt_nrm}) [${fnt_tlc}par_typ, par_md, parallel_type, parallel_mode, parallel${fnt_nrm}]"
# 20171101: Implement but do not yet advertise PPC in ncremap
    echo " ${fnt_bld}--ppc_prc${fnt_nrm}  Precision-preserving compression (empty means none) (default ${fnt_bld}${ppc_prc}${fnt_nrm}) [${fnt_tlc}ppc, ppc_prc, precision, quantize${fnt_nrm}]"
    echo "${fnt_rvr}-R${fnt_nrm} ${fnt_bld}rgr_opt${fnt_nrm}  Regrid options (empty means none) (default ${fnt_bld}${rgr_opt}${fnt_nrm}) [${fnt_tlc}rgr_opt, regrid_options${fnt_nrm}]"
    echo "${fnt_rvr}-r${fnt_nrm} ${fnt_bld}rnr_thr${fnt_nrm}  Renormalization threshold (empty means none) (default ${fnt_bld}${rnr_thr}${fnt_nrm}) [${fnt_tlc}rnr_thr, thr_rnr, rnr, renormalize_threshold${fnt_nrm}]"
    echo " ${fnt_bld}--rgn_dst${fnt_nrm}  Regional destination grid [${fnt_tlc}rgn_dst, dst_rgn, regional_destination${fnt_nrm}]"
    echo " ${fnt_bld}--rgn_src${fnt_nrm}  Regional source grid [${fnt_tlc}rgn_src, src_rgn, regional_source${fnt_nrm}]"
    echo " ${fnt_bld}--rrg_bb_wesn${fnt_nrm}  Regional regridding bounding-box WESN order (empty means none) (default ${fnt_bld}${bb_wesn}${fnt_nrm}) [${fnt_tlc}rrg_bb_wesn, bb, bb_wesn, wesn_sng${fnt_nrm}]"
    echo " ${fnt_bld}--rrg_dat_glb${fnt_nrm}  Regional regridding global data file (empty means none) (default ${fnt_bld}${dat_glb}${fnt_nrm}) [${fnt_tlc}rrg_dat_glb, dat_glb, data_global, global_data${fnt_nrm}]"
    echo " ${fnt_bld}--rrg_grd_glb${fnt_nrm}  Regional regridding global grid file (empty means none) (default ${fnt_bld}${grd_glb}${fnt_nrm}) [${fnt_tlc}rrg_grd_glb, grd_glb, grid_global, global_grid${fnt_nrm}]"
    echo " ${fnt_bld}--rrg_grd_rgn${fnt_nrm}  Regional regridding regional grid file (empty means none) (default ${fnt_bld}${grd_rgn}${fnt_nrm}) [${fnt_tlc}rrg_grd_rgn, grd_rgn, grid_regional, regional_grid${fnt_nrm}]"
    echo " ${fnt_bld}--rrg_rnm_sng${fnt_nrm}  Regional regridding rename string (empty means none) (default ${fnt_bld}${rnm_sng}${fnt_nrm}) [${fnt_tlc}rrg_rnm_sng, rnm_sng, rename_string${fnt_nrm}]"
    echo "${fnt_rvr}-s${fnt_nrm} ${fnt_bld}grd_src${fnt_nrm}  Grid-file (source) (empty means infer or use map_fl) (default ${fnt_bld}${grd_src}${fnt_nrm}) [${fnt_tlc}grd_src, grid_source, source_grid, src_grd${fnt_nrm}]"
    echo " ${fnt_bld}--sgs_frc${fnt_nrm}  Sub-grid fraction variable (empty means none) (default ${fnt_bld}${sgs_frc}${fnt_nrm}) [${fnt_tlc}sgs_frc, ice_frc, lnd_frc, ocn_frc, subgrid_fraction${fnt_nrm}]"
    echo " ${fnt_bld}--sgs_msk${fnt_nrm}  Sub-grid mask variable (empty means none) (default ${fnt_bld}${sgs_msk}${fnt_nrm}) [${fnt_tlc}sgs_msk, ice_msk, lnd_msk, ocn_msk, subgrid_mask${fnt_nrm}]"
    echo " ${fnt_bld}--sgs_nrm${fnt_nrm}  Sub-grid fraction normalization (empty means none) (default ${fnt_bld}${sgs_nrm}${fnt_nrm}) [${fnt_tlc}sgs_nrm, subgrid_normalization${fnt_nrm}]"
    echo " ${fnt_bld}--skl_fl${fnt_nrm}   Skeleton file (empty means none) (default ${fnt_bld}${skl_fl}${fnt_nrm}) [${fnt_tlc}skl_fl, skl, skeleton, skeleton_file${fnt_nrm}]"
    echo " ${fnt_bld}--std_flg${fnt_nrm}  Stdin used for input (default ${fnt_bld}${inp_std}${fnt_nrm}) [${fnt_tlc}stdin, std_flg, inp_std, redirect, standard_input${fnt_nrm}]"
    echo "${fnt_rvr}-T${fnt_nrm} ${fnt_bld}drc_tmp${fnt_nrm}  Temporary directory (for intermediate files) (default ${fnt_bld}${drc_tmp}${fnt_nrm}) [${fnt_tlc}drc_tmp, tmp_drc, dir_tmp, tmp_dir, tmp${fnt_nrm}]"
    echo "${fnt_rvr}-t${fnt_nrm} ${fnt_bld}thr_nbr${fnt_nrm}  Thread number for regridder (default ${fnt_bld}${thr_nbr}${fnt_nrm}) [${fnt_tlc}thr_nbr, thread_number, thread, threads${fnt_nrm}]"
    echo "${fnt_rvr}-U${fnt_nrm}          Unpack input prior to regridding [${fnt_tlc}unpack, upk, upk_inp${fnt_nrm}]"
    echo "${fnt_rvr}-u${fnt_nrm} ${fnt_bld}unq_sfx${fnt_nrm}  Unique suffix (prevents intermediate files from sharing names) (default ${fnt_bld}${unq_sfx}${fnt_nrm}) [${fnt_tlc}unq_sfx, unique_suffix, suffix${fnt_nrm}]"
    echo " ${fnt_bld}--ugrid_fl${fnt_nrm} UGRID file (empty means none) (default ${fnt_bld}${ugrid_fl}${fnt_nrm}) [${fnt_tlc}ugrid_fl, ugrid, ugrid_file${fnt_nrm}]"
    echo "${fnt_rvr}-V${fnt_nrm} ${fnt_bld}var_rgr${fnt_nrm}  CF template variable (empty means none) (default ${fnt_bld}${var_rgr}${fnt_nrm}) [${fnt_tlc}var_rgr, rgr_var, var_cf, cf_var, cf_variable${fnt_nrm}]"
    echo "${fnt_rvr}-v${fnt_nrm} ${fnt_bld}var_lst${fnt_nrm}  Variable list (empty means all) (default ${fnt_bld}${var_lst}${fnt_nrm}) [${fnt_tlc}var_lst, variable_list, var, vars, variable, variables${fnt_nrm}]"
    echo " ${fnt_bld}--version${fnt_nrm}  Version and configuration information [${fnt_tlc}version, vrs, config, configuration, cnf${fnt_nrm}]"
    echo " ${fnt_bld}--vrb_lvl${fnt_nrm}  Verbosity level (default ${fnt_bld}${vrb_lvl}${fnt_nrm}) [${fnt_tlc}vrb_lvl, vrb, verbosity, print_verbosity${fnt_nrm}]"
    echo "${fnt_rvr}-W${fnt_nrm} ${fnt_bld}wgt_opt${fnt_nrm}  Weight-generator options (default ${fnt_bld}${wgt_opt_esmf}${fnt_nrm}) [${fnt_tlc}wgt_opt, esmf_opt, esmf_options, tempest_opt, tps_opt${fnt_nrm}]"
    echo "${fnt_rvr}-w${fnt_nrm} ${fnt_bld}wgt_cmd${fnt_nrm}  Weight-generator command (default ${fnt_bld}${wgt_exe_esmf}${fnt_nrm}) [${fnt_tlc}wgt_cmd, wgt_gnr, weight_command, weight_generator${fnt_nrm}]"
    echo "${fnt_rvr}-x${fnt_nrm} ${fnt_bld}xtn_var${fnt_nrm}  Extensive variables (empty means none) (default ${fnt_bld}${xtn_var}${fnt_nrm}) [${fnt_tlc}xtn_var, xtn_lst, extensive, var_xtn, extensive_variables${fnt_nrm}]"
    echo " ${fnt_bld}--xtr_typ${fnt_nrm}  ESMF Extrapolation type (empty means none) (default ${fnt_bld}${xtr_typ}${fnt_nrm}) [${fnt_tlc}xtr_typ, xtr_mth, extrap_type, extrap_method${fnt_nrm}]"
    echo " ${fnt_bld}--xtr_nsp${fnt_nrm}  ESMF Extrapolation number of source points (default ${fnt_bld}${xtr_nsp}${fnt_nrm}) [${fnt_tlc}xtr_nsp, xtr_pnt_src_nbr, extrap_num_src_pnts${fnt_nrm}]"
    echo " ${fnt_bld}--xtr_xpn${fnt_nrm}  ESMF Extrapolation distance exponent (default ${fnt_bld}${xtr_xpn}${fnt_nrm}) [${fnt_tlc}xtr_xpn, xtr_dst_xpn, extrap_dist_exponent${fnt_nrm}]"
    printf "\n"
    printf "Examples: ${fnt_bld}$spt_nm -m ${map_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -d ${dst_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -g ${grd_dst_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -s ${grd_src_xmp} -g ${grd_dst_xmp} -m ${map_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -a bilinear -d ${dst_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -a conserve -d ${dst_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -a tempest  -d ${dst_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -v ${var_xmp} -m ${map_xmp} ${in_xmp} ${out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -m ${map_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -M -d ${dst_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -M -g ${grd_dst_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -s ${grd_src_xmp} -d ${dst_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -s ${grd_src_xmp} -g ${grd_dst_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -d ${dst_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}$spt_nm -g ${grd_dst_xmp} -I ${drc_in_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}ls mdl*2005*nc | $spt_nm -m ${map_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "          ${fnt_bld}ls mdl*2005*nc | $spt_nm -d ${dst_xmp} -O ${drc_out_xmp} ${fnt_nrm}\n"
    printf "\nComplete documentation at http://nco.sf.net/nco.html#${spt_nm}\n\n"
    exit 1
} # end fnc_usg_prn()

# RRG processing needs NCO filters documented in http://nco.sf.net/nco.html#filter
function ncvarlst { ncks --trd -m ${1} | grep -E ': type' | cut -f 1 -d ' ' | sed 's/://' | sort ; }
function ncdmnlst { ncks --cdl -m ${1} | cut -d ':' -f 1 | cut -d '=' -s -f 1 ; }

function dst_is_grd {
    # Purpose: Is destination grid specified as SCRIP grid-file?
    # fxm: Not working yet
    # Figure-out whether data-file or grid-file and proceed accordingly
    # Allow ncremap to combine -d and -g switches
    # Usage: dst_is_grd ${fl}
    fl=${1}
    flg='Yes'
    #flg='No'
} # end dst_is_grd()

# Check argument number and complain accordingly
arg_nbr=$#
if [ ${arg_nbr} -eq 0 ]; then
  fnc_usg_prn
fi # !arg_nbr

# Parse command-line options:
# http://stackoverflow.com/questions/402377/using-getopts-in-bash-shell-script-to-get-long-and-short-command-line-options
# http://tuxtweaks.com/2014/05/bash-getopts
while getopts :34567a:CD:d:f:g:G:h:I:i:j:L:Mm:n:O:o:P:p:R:r:s:T:t:Uu:V:v:W:w:x:-: OPT; do
    case ${OPT} in
	3) fl_fmt='3' ;; # File format
	4) fl_fmt='4' ;; # File format
	5) fl_fmt='5' ;; # File format
	6) fl_fmt='6' ;; # File format
	7) fl_fmt='7' ;; # File format
	a) alg_typ="${OPTARG}" ;; # Algorithm
	C) clm_flg='Yes' ;; # Climo flag (undocumented)
	D) dbg_lvl="${OPTARG}" ;; # Debugging level
	d) dst_fl="${OPTARG}" ;; # Destination file
	g) grd_dst="${OPTARG}" ;; # Destination grid-file
	G) grd_sng="${OPTARG}" ;; # Grid generation string
	I) drc_in="${OPTARG}" ;; # Input directory
	i) in_fl="${OPTARG}" ;; # Input file
	j) job_usr="${OPTARG}" ;; # Job simultaneity
	L) dfl_lvl="${OPTARG}" ;; # Deflate level
	M) mlt_map_flg='No' ;; # Multi-map flag
	m) map_fl="${OPTARG}" ;; # Map-file
	n) nco_usr="${OPTARG}" ;; # NCO options
	O) drc_usr="${OPTARG}" ;; # Output directory
	o) out_fl="${OPTARG}" ;; # Output file
	P) prc_typ="${OPTARG}" ;; # Procedure type
	p) par_typ="${OPTARG}" ;; # Parallelism type
	r) rnr_thr="${OPTARG}" ;; # Renormalization threshold
	R) rgr_opt="${OPTARG}" ;; # Regridding options
	s) grd_src="${OPTARG}" ;; # Source grid-file
	T) tmp_usr="${OPTARG}" ;; # Temporary directory
	t) thr_usr="${OPTARG}" ;; # Thread number
	U) pdq_opt='-U' ;;        # Unpack input
	u) unq_usr="${OPTARG}" ;; # Unique suffix
	V) var_rgr="${OPTARG}" ;; # CF template variable
	v) var_lst="${OPTARG}" ;; # Variables
	W) wgt_opt_usr="${OPTARG}" ;; # Weight-generator options
	w) wgt_usr="${OPTARG}" ;; # Weight-generator command
	x) xtn_var="${OPTARG}" ;; # Extensive variables
	-) LONG_OPTARG="${OPTARG#*=}"
	   case ${OPTARG} in
	       # Hereafter ${OPTARG} is long argument key, and ${LONG_OPTARG}, if any, is long argument value
	       # Long options with no argument, no short option counterpart
	       # Long options with argument, no short option counterpart
	       # Long options with short counterparts, ordered by short option key
	       a2o | atm2ocn | b2l | big2ltl | l2s | lrg2sml ) a2o_flg='Yes' ;; # # Atmosphere-to-ocean
	       a2o=?* | atm2ocn=?* | b2l=?* | big2ltl=?* | l2s=?* | lrg2sml=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Atmosphere-to-ocean
	       alg_typ=?* | algorithm=?* | regrid_algorithm=?* ) alg_typ="${LONG_OPTARG}" ;; # -a # Algorithm
	       clm_flg | climatology_flag ) clm_flg='Yes' ;; # -C # Climo flag (undocumented)
	       clm_flg=?* | climatology_flag=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # clm_flg
	       d2f | d2s | dbl_flt | dbl_sgl | double_float ) d2f_flg='Yes' ;; # # Convert double-precision fields to single-precision
	       d2f=?* | d2s=?* | dbl_flt=?* | dbl_sgl=?* | double_float=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # D2F
	       dbg_lvl=?* | dbg=?* | debug=?* | debug_level=?* ) dbg_lvl="${LONG_OPTARG}" ;; # -d # Debugging level
	       dfl_lvl=?* | deflate=?* | dfl=?* ) dfl_lvl="${LONG_OPTARG}" ;; # -L # Deflate level
	       dpt | depth | add_dpt | add_depth ) dpt_flg='Yes' ;; # # Add depth coordinate to MPAS files
	       dpt=?* | depth=?* | add_dpt=?* | add_depth=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # DPT
	       dpt_fl=?* | mpas_fl=?* | mpas_file=?* | depth_file=?* ) dpt_fl="${LONG_OPTARG}" ;; # # Depth file with refBottomDepth for MPAS ocean
	       dst_fl=?* | destination_file=?* | template_file=?* | template=?* ) dst_fl="${LONG_OPTARG}" ;; # -d # Destination file
	       grd_dst=?* | grid_dest=?* | dst_grd=?* | dest_grid=?* | destination_grid=?* ) grd_dst="${LONG_OPTARG}" ;; # -g # Destination grid-file
	       grd_sng=?* | grid_generation=?* | grid_gen=?* | grid_string=?* ) grd_sng="${LONG_OPTARG}" ;; # -G # Grid generation string
	       drc_in=?* | in_drc=?* | dir_in=?* | in_dir=?* | input=?* ) drc_in="${LONG_OPTARG}" ;; # -i # Input directory
	       dt_sng=?* | date_string=?* ) dt_sng="${LONG_OPTARG}" ;; # # Date string for MWF map names
	       fl_fmt=?* | fmt_out=?* | file_format=?* | format_out=?* ) fl_fmt="${LONG_OPTARG}" ;; # # Output file format
	       gll_fl=?* | gll_mtd=?* | se_gmt=?* | se_mtd=?* ) gll_fl="${LONG_OPTARG}" ;; # # GLL grid metadata (geometry+connectivity+Jacobian) file
	       hrd_pth=?* | hard_path=?* | csz_exe=?* | csz_bin_lib=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Use hard-coded paths on known machines
	       in_fl=?* | in_file=?* | input_file=?* ) in_fl="${LONG_OPTARG}" ;; # -i # Input file
	       job_nbr=?* | job_number=?* | jobs=?* ) job_usr="${LONG_OPTARG}" ;; # -j # Job simultaneity
	       mlt_map | multimap | no_multimap | nomultimap ) mlt_map_flg='No' ;; # -M # Multi-map flag
	       mlt_map=?* | multimap=?* | no_multimap=?* | nomultimap=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # -M # Multi-map flag
	       map_fl=?* | map=?* | map_file=?* | rgr_map=?* | regrid_map=?* ) map_fl="${LONG_OPTARG}" ;; # -m # Map-file
	       msk_dst=?* | dst_msk=?* | mask_destination=?* | mask_dst=?* ) msk_dst="${LONG_OPTARG}" ;; # # Mask-template variable in destination file
	       msk_out=?* | out_msk=?* | mask_output=?* | mask_out=?* ) msk_out="${LONG_OPTARG}" ;; # # Mask variable in regridded file
	       msk_src=?* | src_msk=?* | mask_source=?* | mask_src=?* ) msk_src="${LONG_OPTARG}" ;; # # Mask-template variable in source file
	       mss_val=?* | fll_val=?* | missing_value=?* | fill_value=?* ) mss_val="${LONG_OPTARG}" ;; # # Missing value for MPAS
	       nco_opt=?* | nco=?* | nco_options=?* ) nco_usr="${LONG_OPTARG}" ;; # -n # NCO options
	       nm_dst=?* | name_dst=?* | nm_sht_dst=?* | short_name_destination=?* ) nm_dst="${LONG_OPTARG}" ;; # # Short name of destination grid
	       nm_src=?* | name_src=?* | nm_sht_src=?* | short_name_source=?* ) nm_src="${LONG_OPTARG}" ;; # # Short name of source grid
	       no_area | no_cll_msr | no_cell_measures ) no_cll_msr='Yes' ;; # # Omit cell_measures variables
	       no_area=?* | no_cell_msr=?* | no_cell_measures=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Omit cell_measures variables
	       no_frm_trm | no_frm | no_formula_terms ) no_frm_trm='Yes' ;; # # Omit formula_terms variables
	       no_frm_trm=?* | no_frm=?* | no_formula_terms=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Omit formula_terms variables
	       no_stg_grd | no_stg | no_stagger | no_staggered_grid ) no_stg_grd='Yes' ;; # # Omit staggered grid variables
	       no_stg_grd=?* | no_stg=?* | no_stagger=?* | no_staggered_grid ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Omit staggered grid variables
	       drc_out=?* | out_drc=?* | dir_out=?* | out_dir=?* | output=?* ) drc_usr="${LONG_OPTARG}" ;; # -O # Output directory
	       out_fl=?* | output_file=?* | out_file=?* ) out_fl="${LONG_OPTARG}" ;; # -o # Output file
	       prc_typ=?* | pdq_typ=?* | prm_typ=?* | procedure=?* ) prc_typ="${LONG_OPTARG}" ;; # -P # Procedure type
	       par_typ=?* | par_md=?* | parallel_type=?* | parallel_mode=?* | parallel=?* ) par_typ="${LONG_OPTARG}" ;; # -p # Parallelism type
	       ppc=?* | ppc_prc=?* | precision=?* | quantize=?* ) ppc_prc="${LONG_OPTARG}" ;; # # Precision-preserving compression
	       rgr_opt=?* | regrid_options=?* ) rgr_opt="${LONG_OPTARG}" ;; # -R # Regridding options
	       rnr_thr=?* | thr_rnr=?* | rnr=?* | renormalization_threshold=?* ) rnr_thr="${LONG_OPTARG}" ;; # -r # Renormalization threshold
	       rgn_dst=?* | dst_rgn=?* | regional_destination=?* ) hnt_dst='--dst_regional' ;; # # Regional destination grid
	       rgn_dst=?* | dst_rgn=?* | regional_destination=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Regional destination grid
	       rgn_src=?* | src_rgn=?* | regional_source=?* ) hnt_src='--src_regional' ;; # # Regional source grid
	       rgn_src=?* | src_rgn=?* | regional_source=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Regional source grid
	       rrg_bb_wesn=?* | bb_wesn=?* | bb=?* | bounding_box=?* ) bb_wesn="${LONG_OPTARG}" ; prc_typ='rrg' ; ;; # # Regional regridding bounding-box WESN order
	       rrg_dat_glb=?* | dat_glb=?* | data_global=?* | global_data=?* ) dat_glb="${LONG_OPTARG}" ; prc_typ='rrg' ; ;; # # Regional regridding global data file
	       rrg_grd_glb=?* | grd_glb=?* | grid_global=?* | global_grid=?* ) grd_glb="${LONG_OPTARG}" ; prc_typ='rrg' ; ;; # # Regional regridding global grid file
	       rrg_grd_rgn=?* | grd_rgn=?* | grid_regional=?* | regional_grid=?* ) grd_rgn="${LONG_OPTARG}" ; prc_typ='rrg' ; ;; # # Regional regridding regional grid file
	       rrg_rnm_sng=?* | rnm_sng=?* | rename_string=?* ) rnm_sng="${LONG_OPTARG}" ; prc_typ='rrg' ; ;; # # Regional regridding rename string
	       grd_src=?* | grid_source=?* | source_grid=?* | src_grd=?* ) grd_src="${LONG_OPTARG}" ;; # -s # Source grid-file
	       sgs_frc=?* | ice_frc=?* | lnd_frc=?* | ocn_frc=?* | subgrid_fraction=?* ) sgs_frc="${LONG_OPTARG}" ; prc_typ='sgs' ; ;; # # Sub-grid fraction variable
	       sgs_msk=?* | ice_msk=?* | lnd_msk=?* | ocn_msk=?* | subgrid_mask=?* ) sgs_msk="${LONG_OPTARG}" ; prc_typ='sgs' ; ;; # # Sub-grid mask variable
	       sgs_nrm=?* | subgrid_normalization=?* ) sgs_nrm="${LONG_OPTARG}" ; prc_typ='sgs' ; ;; # # Sub-grid fraction normalization
	       skl_fl=?* | skl=?* | skeleton=?* | skeleton_file=?* ) skl_fl="${LONG_OPTARG}" ;; # # Skeleton file
	       stdin | inp_std | std_flg | redirect | standard_input ) inp_std='Yes' ;; # # Input file list from stdin
	       stdin=?* | inp_std=?* | std_flg=?* | redirect=?* | standard_input=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # # Input file list from stdin
	       drc_tmp=?* | tmp_drc=?* | dir_tmp=?* | tmp_dir=?* | tmp=?* ) tmp_usr="${LONG_OPTARG}" ;; # -T # Temporary directory
	       thr_nbr=?* | thread_number=?* | thread=?* | threads=?* ) thr_usr="${LONG_OPTARG}" ;; # -t # Thread number
	       unpack=?* | upk=?* | upk_inp=?* ) pdq_opt='-U' ;; # -U # Unpack input
	       unpack=?* | upk=?* | upk_inp=?* ) echo "No argument allowed for --${OPTARG switch}" >&2; exit 1 ;; # -U # Unpack input
	       ugrid_fl=?* | ugrid=?* | ugrid_file=?* ) ugrid_fl="${LONG_OPTARG}" ;; # # UGRID file
	       unq_sfx=?* | unique_suffix=?* | suffix=?* ) unq_usr="${LONG_OPTARG}" ;; # -u # Unique suffix
	       var_rgr=?* | rgr_var=?* | var_cf=?* | cf_var=?* | cf_variable=?* ) var_rgr="${LONG_OPTARG}" ;; # -V # CF template variable
	       var_lst=?* | variable_list=?* | var=?* | vars=?* | variable=?* | variables=?* ) var_lst="${LONG_OPTARG}" ;; # -v # Variables
	       vrb_lvl=?* | vrb=?* | verbosity=?* | print_verbosity=?* ) vrb_lvl="${LONG_OPTARG}" ;; # # Print verbosity
	       version | vrs | config | configuration | cnf ) vrs_prn='Yes' ;; # # Print version information
	       wgt_opt=?* | esmf_opt=?* | esmf_options=?* | tps_opt=?* | tempest_opt=?* | tempest_options=?* ) wgt_opt_usr="${LONG_OPTARG}" ;; # -W # Weight-generator options
	       wgt_cmd=?* | weight_command=?* | wgt_gnr=?* | weight_generator=?* ) wgt_usr="${LONG_OPTARG}" ;; # -w # Weight-generator command
	       xtn_var=?* | extensive=?* | var_xtn=?* | extensive_variables=?* ) xtn_var="${LONG_OPTARG}" ;; # -x # Extensive variables
	       xtr_nsp=?* | xtr_pnt_src_nbr=?* | extrap_num_src_pts=?* ) xtr_nsp_usr="${LONG_OPTARG}" ;; # # Extrapolation number of source points
	       xtr_typ=?* | xtr_mth=?* | extrap_type=?* | extrap_method=?* ) xtr_typ="${LONG_OPTARG}" ;; # # Extrapolation type
	       xtr_xpn=?* | xtr_dst_xpn=?* | extrap_dist_exponent=?* ) xtr_xpn_usr="${LONG_OPTARG}" ;; # # Extrapolation exponent
               '' ) break ;; # "--" terminates argument processing
               * ) printf "\nERROR: Unrecognized option ${fnt_bld}--${OPTARG}${fnt_nrm}\n" >&2; fnc_usg_prn ;;
	   esac ;; # !OPTARG
	\?) # Unrecognized option
	    printf "\nERROR: Option ${fnt_bld}-${OPTARG}${fnt_nrm} not recognized\n" >&2
	    fnc_usg_prn ;;
    esac # !OPT
done # !getopts
shift $((OPTIND-1)) # Advance one argument
psn_nbr=$#
if [ ${psn_nbr} -ge 1 ]; then
    inp_psn='Yes'
fi # !psn_nbr
if [ "${d2f_flg}" != 'Yes' ]; then
    d2f_opt=''
fi # !d2f_flg

#echo "test_ncremap: Done!"
#exit 1

cmd_wgt_esmf=`command -v ${wgt_exe_esmf} --no_log 2> /dev/null`
if [ "$?" -eq 0 ]; then
    # 20180830 Add --ignore_degenerate to default ERWG options for ESMF >= 7.1.0r
    # 20181114 Add --no_log so ERWG does not try to write logfile into current (possibly write-protected) directory
    erwg_vrs_sng=`ESMF_RegridWeightGen --no_log --version | grep ESMF_VERSION_STRING | cut -f 2 -d ':'`
    # Remove whitespace, answer should be something like "7.1.0r" or "6.3.0rp1"
    erwg_vrs_sng="${erwg_vrs_sng#"${erwg_vrs_sng%%[![:space:]]*}"}"
    # Extract first character
    erwg_vrs_mjr="${erwg_vrs_sng:0:1}"
    if [ "${erwg_vrs_mjr}" -ge 7 ]; then
	wgt_opt_esmf="${wgt_opt_esmf} --ignore_degenerate"
    fi # !erwg_vrs_mjr
fi # !err
cmd_wgt_tps=`command -v ${wgt_exe_tps} 2> /dev/null`
cmd_dpt_mpas=`command -v ${dpt_exe_mpas} --no_log 2> /dev/null`
if [ ${vrs_prn} = 'Yes' ]; then
    printf "${spt_nm}, the NCO regridder and map- and grid-generator, version ${nco_vrs}\n"
    printf "Copyright (C) 2016--present Charlie Zender\n"
    printf "This program is part of NCO, the netCDF Operators\n"
    printf "NCO is free software and comes with a BIG FAT KISS and ABSOLUTELY NO WARRANTY\n"
    printf "You may redistribute and/or modify NCO under the terms of the\n"
    printf "GNU General Public License (GPL) Version 3 with exceptions described in the LICENSE file\n"
    printf "GPL: http://www.gnu.org/copyleft/gpl.html\n"
    printf "LICENSE: https://github.com/nco/nco/tree/master/LICENSE\n"
    printf "Config: ${spt_nm} running from directory ${drc_spt}\n"
    printf "Config: Calling NCO binaries in directory ${drc_nco}\n"
    printf "Config: Binaries linked to netCDF library version ${lbr_vrs}\n"
    if [ "${hrd_pth_fnd}" = 'Yes' ]; then
	printf "Config: Employ NCO machine-dependent hardcoded paths/modules for ${HOSTNAME}\n"
	printf "Config: (Turn-off NCO hardcoded paths with \"export NCO_PATH_OVERRIDE=No\")\n"
    else
	printf "Config: No hardcoded path/module overrides\n"
    fi # !hrd_pth_fnd
    if [ -n "${cmd_wgt_esmf}" ]; then
	printf "Config: ESMF weight-generation command ${wgt_exe_esmf} version ${erwg_vrs_sng} found as ${cmd_wgt_esmf}\n"
    else
	printf "Config: ESMF weight-generation command ${wgt_exe_esmf} not found\n"
    fi # !err
    if [ -n "${cmd_wgt_tps}" ]; then
	printf "Config: Tempest weight-generation command ${wgt_exe_tps} found as ${cmd_wgt_tps}\n"
    else
	printf "Config: Tempest weight-generation command ${wgt_exe_tps} not found\n"
    fi # !err
    if [ -n "${cmd_dpt_mpas}" ]; then
	printf "Config: MPAS depth coordinate addition command ${dpt_exe_mpas} found as ${cmd_dpt_mpas}\n"
    else
	printf "Config: MPAS depth coordinate addition command ${dpt_exe_mpas} not found\n"
    fi # !err
    exit 0
fi # !vrs_prn

# Detect input on pipe to stdin:
# http://stackoverflow.com/questions/2456750/detect-presence-of-stdin-contents-in-shell-script
# http://unix.stackexchange.com/questions/33049/check-if-pipe-is-empty-and-run-a-command-on-the-data-if-it-isnt
# 20170119 "if [ ! -t 0 ]" tests whether unit 0 (stdin) is connected to terminal, not whether pipe has data
# Non-interactive batch mode (e.g., qsub, sbatch) disconnects stdin from terminal and triggers false-positives with ! -t 0
# 20170123 "if [ -p foo ]" tests whether foo exists and is a pipe or named pipe
# Non-interactive batch mode (i.e., sbatch) behaves as desired for -p /dev/stdin on SLURM
# Non-interactive batch mode (e.g., qsub) always returns true for -p /dev/stdin on PBS, leads to FALSE POSITIVES!
# This is because PBS uses stdin to set the job name
# Hence -p /dev/stdin test works everywhere tested except PBS non-interactive batch environment
if [ -n "${PBS_ENVIRONMENT}" ]; then
    if [ "${PBS_ENVIRONMENT}" = 'PBS_BATCH' ]; then
	# PBS batch detection suggested by OLCF ticket CCS #338970 on 20170127
	bch_pbs='Yes'
    fi # !PBS_ENVIRONMENT
fi # !PBS
if [ -n "${SLURM_JOBID}" ] && [ -z "${SLURM_PTY_PORT}" ]; then
    # SLURM batch detection suggested by NERSC ticket INC0096873 on 20170127
    bch_slr='Yes'
fi # !SLURM
if [ ${bch_pbs} = 'Yes' ] || [ ${bch_slr} = 'Yes' ]; then
    # Batch environment
    if [ ${bch_pbs} = 'Yes' ]; then
	if [ ! -p /dev/stdin ]; then
	    # PBS batch jobs cause -p to return true except for stdin redirection
	    # When -p returns true we do not know whether stdin pipe contains any input
	    # User must explicitly indicate use of stdin pipes with --stdin option
	    # Redirection in PBS batch jobs unambiguously causes -p to return false
	    inp_std='Yes'
	fi # !stdin
    fi # !bch_slr
    if [ ${bch_slr} = 'Yes' ]; then
	if [ -p /dev/stdin ]; then
	    # SLURM batch jobs cause -p to return true for stdin pipes
	    # When -p returns false we do not know whether output was redirectd
	    # User must explicitly indicate use of redirection with --stdin option
	    # Stdin pipes in SLURM batch jobs unambiguously cause -p to return true
	    inp_std='Yes'
	fi # !stdin
    fi # !bch_slr
else # !bch
    # Interactive environment
    if [ -p /dev/stdin ] || [ ! -t 0 ]; then
	# Interactive environments unambiguously cause -p to return true for stdin pipes
	# Interactive environments unambiguously cause -t 0 to return false for stdin redirection
	inp_std='Yes'
    fi # !stdin
fi # !bch
if [ ${inp_std} = 'Yes' ] && [ ${inp_psn} = 'Yes' ]; then
    echo "${spt_nm}: ERROR expecting input both from stdin and positional command-line arguments\n"
    exit 1
fi # !inp_std

# Derived variables
if [ -n "${drc_usr}" ]; then
    drc_out="${drc_usr%/}"
else
    if [ -n "${out_fl}" ]; then
	drc_out="$(dirname ${out_fl})"
    fi # !out_fl
fi # !drc_usr

if [ -n "${tmp_usr}" ]; then
    # Fancy %/ syntax removes trailing slash (e.g., from $TMPDIR)
    drc_tmp=${tmp_usr%/}
fi # !out_fl
att_fl="${drc_tmp}/ncremap_tmp_att.nc" # [sng] Missing value workflow (MPAS) default
d2f_fl="${drc_tmp}/ncremap_tmp_d2f.nc" # [sng] File with doubles converted to float
dmm_fl="${drc_tmp}/ncremap_tmp_dmm.nc" # [sng] Dummy input file
dpt_tmp_fl="${drc_tmp}/ncremap_tmp_dpt.nc" # [sng] File with depth coordinate added
grd_dst_dfl="${drc_tmp}/ncremap_tmp_grd_dst.nc" # [sng] Grid-file (destination) default
grd_src_dfl="${drc_tmp}/ncremap_tmp_grd_src.nc" # [sng] Grid-file (source) default
hnt_dst_fl="${drc_tmp}/ncremap_tmp_hnt_dst.txt" # [sng] Hint (for ERWG) destination
hnt_src_fl="${drc_tmp}/ncremap_tmp_hnt_src.txt" # [sng] Hint (for ERWG) source
ncwa_fl="${drc_tmp}/ncremap_tmp_ncwa.nc" # [sng] ncwa workflow (HIRDLS, MLS) default
nnt_fl="${drc_tmp}/ncremap_tmp_nnt.nc" # [sng] Annotated global datafile (RRG) default
pdq_fl="${drc_tmp}/ncremap_tmp_pdq.nc" # [sng] Permuted/Unpacked data default (AIRS, HIRDLS, MLS, MOD04, MPAS)
rgn_fl="${drc_tmp}/ncremap_tmp_rgn.nc" # [sng] Regional file with coordinates (RRG) default
rnm_fl="${drc_tmp}/ncremap_tmp_rnm.nc" # [sng] Renamed regional (RRG) default
tmp_out_fl="${drc_tmp}/ncremap_tmp_out.nc" # [sng] Temporary output file
znl_fl="${drc_tmp}/ncremap_tmp_znl.nc" # [sng] Zonal workflow (HIRDLS, MLS) default

if [ -n "${unq_usr}" ]; then
    if [ "${unq_usr}" = 'noclean' ]; then
	cln_flg='No'
    else
	if [ "${unq_usr}" != 'none' ] && [ "${unq_usr}" != 'nil' ]; then
	    unq_sfx="${unq_usr}"
	else # !unq_usr
	    unq_sfx=""
	fi # !unq_usr
    fi # !unq_usr
fi # !unq_sfx
att_fl=${att_fl}${unq_sfx}
d2f_fl=${d2f_fl}${unq_sfx}
dmm_fl=${dmm_fl}${unq_sfx}
dpt_tmp_fl=${dpt_tmp_fl}${unq_sfx}
grd_dst_dfl=${grd_dst_dfl}${unq_sfx}
grd_src_dfl=${grd_src_dfl}${unq_sfx}
hnt_dst_fl=${hnt_dst_fl}${unq_sfx}
hnt_src_fl=${hnt_src_fl}${unq_sfx}
ncwa_fl=${ncwa_fl}${unq_sfx}
nnt_fl=${nnt_fl}${unq_sfx}
pdq_fl=${pdq_fl}${unq_sfx}
rgn_fl=${rgn_fl}${unq_sfx}
rnm_fl=${rnm_fl}${unq_sfx}
tmp_out_fl=${tmp_out_fl}${unq_sfx}
znl_fl=${znl_fl}${unq_sfx}

echo "spot 1"

# Algorithm options are bilinear|conserve|conserve2nd|nearestdtos|neareststod|patch|tempest|se2fv_flx|se2fv_stt|se2fv_alt|fv2se_flx|fv2se_stt|fv2se_alt
if [ ${alg_typ} = 'bilinear' ] || [ ${alg_typ} = 'bilin' ] || [ ${alg_typ} = 'blin' ] || [ ${alg_typ} = 'bln' ]; then
    alg_opt='bilinear'
elif [ ${alg_typ} = 'conserve' ] || [ ${alg_typ} = 'conservative' ] || [ ${alg_typ} = 'cns' ] || [ ${alg_typ} = 'c1' ] || [ ${alg_typ} = 'aave' ]; then
    alg_opt='conserve'
elif [ ${alg_typ} = 'conserve2nd' ] || [ ${alg_typ} = 'conservative2nd' ] || [ ${alg_typ} = 'c2' ] || [ ${alg_typ} = 'c2nd' ]; then
    alg_opt='conserve2nd'
elif [ ${alg_typ} = 'nearestdtos' ] || [ ${alg_typ} = 'ndtos' ] || [ ${alg_typ} = 'dtos' ] || [ ${alg_typ} = 'nds' ]; then
    alg_opt='nearestdtos'
elif [ ${alg_typ} = 'neareststod' ] || [ ${alg_typ} = 'nstod' ] || [ ${alg_typ} = 'stod' ] || [ ${alg_typ} = 'nsd' ]; then
    alg_opt='neareststod'
elif [ ${alg_typ} = 'patch' ] || [ ${alg_typ} = 'patc' ] || [ ${alg_typ} = 'pch' ]; then
    alg_opt='patch'
elif [ ${alg_typ} = 'tempest' ] || [ ${alg_typ} = 'tps' ] || [ ${alg_typ} = 'tmp' ]; then
    # 20171108 'tempest' invokes TempestRemap with no automatic options, suitable for RLL re-mapping?
    # 20171108 TempestRemap boutique options based on particular remapping type
    # https://acme-climate.atlassian.net/wiki/spaces/Docs/pages/178848194/Transition+to+TempestRemap+for+Atmosphere+grids
    # alg_sng in comments is for E3SM naming convention map_src_to_dst_${alg_sng}.${dt_sng}.nc
    alg_opt='tempest'
    wgt_typ='tempest'
elif [ ${alg_typ} = 'se2fv_flx' ] || [ ${alg_typ} = 'mono_se2fv' ] || [ ${alg_typ} = 'conservative_monotone_se2fv' ]; then # alg_sng='mono'
    wgt_opt_tps='--in_type cgll --in_np 4 --out_type fv --out_double --mono'
    alg_opt='se2fv_flx'
    wgt_typ='tempest'
elif [ ${alg_typ} = 'se2fv_stt' ] || [ ${alg_typ} = 'highorder_se2fv' ] || [ ${alg_typ} = 'accurate_conservative_nonmonotone_se2fv' ]; then # alg_sng='highorder'
    wgt_opt_tps='--in_type cgll --in_np 4 --out_type fv --out_double'
    alg_opt='se2fv_stt'
    wgt_typ='tempest'
elif [ ${alg_typ} = 'se2fv_alt' ] || [ ${alg_typ} = 'intbilin_se2fv' ] || [ ${alg_typ} = 'accurate_monotone_nonconservative_se2fv' ]; then # alg_sng='intbilin'
    wgt_opt_tps='--in_type cgll --in_np 4 --out_type fv --out_double --mono3 --noconserve'
    alg_opt='se2fv_alt'
    wgt_typ='tempest'
elif [ ${alg_typ} = 'fv2se_flx' ] || [ ${alg_typ} = 'monotr_fv2se' ] || [ ${alg_typ} = 'conservative_monotone_fv2se' ]; then # alg_sng='monotr'
    # NB: Generate mono map for opposite direction regridding (i.e., reverse switches and grids), then transpose
    wgt_opt_tps='--in_type cgll --in_np 4 --out_type fv --out_double --mono'
    alg_opt='fv2se_flx'
    wgt_typ='tempest'
    trn_map='Yes'
elif [ ${alg_typ} = 'fv2se_stt' ] || [ ${alg_typ} = 'highorder_fv2se' ] || [ ${alg_typ} = 'accurate_conservative_nonmonotone_fv2se' ]; then # alg_sng='highorder'
    wgt_opt_tps='--in_type fv --in_np 2 --out_type cgll --out_np 4 --out_double --volumetric'
    alg_opt='fv2se_stt'
    wgt_typ='tempest'
elif [ ${alg_typ} = 'fv2se_alt' ] || [ ${alg_typ} = 'mono_fv2se' ] || [ ${alg_typ} = 'conservative_monotone_fv2se_alt' ]; then # alg_sng='mono'
    wgt_opt_tps='--in_type fv --in_np 1 --out_type cgll --out_np 4 --out_double --mono --volumetric'
    alg_opt='fv2se_alt'
    wgt_typ='tempest'
else
    echo "${spt_nm}: ERROR ${alg_typ} is not a valid remapping algorithm"
    echo "${spt_nm}: HINT Valid ESMF remapping algorithms and synonyms are bilinear,bilin,bln | conserve,cns,c1,aave | conserve2nd,c2,c2nd | nearestdtos,nds,dtos | neareststod,nsd,stod | patch,pch"
    echo "${spt_nm}: HINT Valid TempestRemap remapping options and synonyms are tempest | se2fv_flx,mono_se2fv | se2fv_stt,highorder_se2fv | se2fv_alt,intbilin | fv2se_flx,monotr_fv2se | fv2se_stt,highorder_fv2se | fv2se_alt,mono_fv2se"
    exit 1
fi # !alg_typ
# NB: As of 20190215 ncremap has never used gll_fl for E3SM, though I think Tempest does support it
echo "spot 2"
if [ -n "${gll_fl}" ]; then
    if [ "${alg_opt}" = 'se2fv_flx' ] || [ "${alg_opt}" = 'se2fv_stt' ] || [ "${alg_opt}" = 'se2fv_alt' ] || [ "${alg_opt}" = 'fv2se_flx' ]; then
	wgt_opt_tps="--in_meta ${gll_fl} ${wgt_opt_tps}"
    elif [ "${alg_opt}" = 'fv2se_stt' ] || [ "${alg_opt}" = 'fv2se_alt' ]; then
	wgt_opt_tps="${wgt_opt_tps} --out_meta ${gll_fl}"
    fi # !se2fv || fv2se_flx
fi # !gll_fl
if [ -n "${fl_fmt}" ]; then
    if [ "${fl_fmt}" = '3' ] || [ "${fl_fmt}" = 'classic' ] || [ "${fl_fmt}" = 'netcdf3' ]; then
	nco_fl_fmt='--fl_fmt=classic'
    fi # !fl_fmt
    if [ "${fl_fmt}" = '4' ] || [ "${fl_fmt}" = 'netcdf4' ] || [ "${fl_fmt}" = 'hdf5' ]; then
	nco_fl_fmt='--fl_fmt=netcdf4'
	if [ -n "${erwg_vrs_mjr}" ]; then
	    if [ "${erwg_vrs_mjr}" -ge 6 ]; then
		wgt_opt_esmf="${wgt_opt_esmf} --netcdf4"
	    fi # !erwg_vrs_mjr
	fi # !erwg_vrs_mjr
    fi # !fl_fmt
    if [ "${fl_fmt}" = '5' ] || [ "${fl_fmt}" = '64bit_data' ] || [ "${fl_fmt}" = 'cdf5' ]; then
	nco_fl_fmt='--fl_fmt=64bit_data'
#	wgt_opt_esmf="${wgt_opt_esmf} --64bit_offset" # Change when ERWG supports CDF5
    fi # !fl_fmt
    if [ "${fl_fmt}" = '6' ] || [ "${fl_fmt}" = '64bit_offset' ] || [ "${fl_fmt}" = '64' ]; then
	nco_fl_fmt='--fl_fmt=64bit_offset'
	wgt_opt_esmf="${wgt_opt_esmf} --64bit_offset"
    fi # !fl_fmt
    if [ "${fl_fmt}" = '7' ] || [ "${fl_fmt}" = 'netcdf4_classic' ]; then
	nco_fl_fmt='--fl_fmt=netcdf4_classic'
	if [ -n "${erwg_vrs_mjr}" ]; then
	    if [ "${erwg_vrs_mjr}" -ge 6 ]; then
		wgt_opt_esmf="${wgt_opt_esmf} --netcdf4" # Change when ERWG supports netCDF7
	    fi # !erwg_vrs_mjr
	fi # !erwg_vrs_mjr
    fi # !fl_fmt
    nco_opt="${nco_opt} ${nco_fl_fmt}"
fi # !fl_fmt
if [ -n "${xtr_nsp_usr}" ]; then
    xtr_nsp=${xtr_nsp_usr}
fi # !xtr_nsp_usr
if [ -n "${xtr_xpn_usr}" ]; then
    xtr_xpn=${xtr_xpn_usr}
fi # !xtr_xpn_usr
if [ -n "${xtr_typ}" ]; then
    if [ ${xtr_typ} = 'neareststod' ] || [ ${xtr_typ} = 'stod' ] || [ ${xtr_typ} = 'nsd' ]; then
	xtr_opt='neareststod'
    elif [ ${xtr_typ} = 'nearestidavg' ] || [ ${xtr_typ} = 'idavg' ] || [ ${xtr_typ} = 'id' ]; then
	xtr_opt='nearestidavg'
    elif [ ${xtr_typ} = 'none' ] || [ ${xtr_typ} = 'nil' ] || [ ${xtr_typ} = 'nowaydude' ]; then
	xtr_opt='none'
    else
	echo "${spt_nm}: ERROR ${xtr_typ} is not a valid extrapolation method"
	echo "${spt_nm}: HINT Valid ESMF extrapolation methods and synonyms are neareststod,stod,nsd | nearestidavg,idavg,id | none,nil"
	exit 1
    fi # !xtr_typ
    wgt_opt_esmf="${wgt_opt_esmf} --extrap_method ${xtr_opt} --extrap_num_src_pnts ${xtr_nsp} --extrap_dist_exponent ${xtr_xpn}"
fi # !xtr_typ
if [ ${wgt_typ} = 'esmf' ]; then
    wgt_cmd="${wgt_exe_esmf}"
    wgt_exe="${wgt_exe_esmf}"
    wgt_opt="${wgt_opt_esmf}"
else
    wgt_cmd="${wgt_exe_tps}"
    wgt_exe="${wgt_exe_tps}"
    wgt_opt="${wgt_opt_tps}"
fi # !wgt_typ
# NB: Define after wgt_typ-block so user can override default options
if [ -n "${wgt_opt_usr}" ]; then
    wgt_opt=${wgt_opt_usr}
fi # !wgt_usr
if [ -n "${wgt_usr}" ]; then
    wgt_cmd=${wgt_usr}
fi # !wgt_usr

echo "spot 3"

if [ -z "${drc_in}" ]; then
    drc_in="${drc_pwd}"
else # !drc_in
    drc_in_usr_flg='Yes'
fi # !drc_in
if [ -n "${in_fl}" ]; then
    inp_aut='Yes'
fi # !in_fl
if [ -n "${job_usr}" ]; then
    job_nbr="${job_usr}"
fi # !job_usr
if [ -n "${nco_usr}" ]; then
    nco_opt="${nco_usr}"
fi # !var_lst
if [ ${dbg_lvl} -ge 2 ]; then
    nco_opt="-D ${dbg_lvl} ${nco_opt}"
fi # !dbg_lvl
if [ -n "${ppc_prc}" ]; then
    nco_opt="${nco_opt} --ppc default=${ppc_prc}"
fi # !ppc_prc
if [ -n "${dfl_lvl}" ]; then
    nco_opt="${nco_opt} --dfl_lvl=${dfl_lvl}"
fi # !dfl_lvl
if [ -n "${gaa_sng}" ]; then
    nco_opt="${nco_opt} ${gaa_sng}"
fi # !gaa_sng
if [ -n "${hdr_pad}" ]; then
    nco_opt="${nco_opt} --hdr_pad=${hdr_pad}"
fi # !hdr_pad
if [ "${no_cll_msr}" = 'Yes' ]; then
    nco_opt="${nco_opt} --no_cll_msr"
fi # !no_cll_msr
if [ "${no_frm_trm}" = 'Yes' ]; then
    nco_opt="${nco_opt} --no_frm_trm"
fi # !no_frm_trm
if [ "${no_stg_grd}" = 'Yes' ]; then
    rgr_opt="${rgr_opt} --rgr no_stagger"
fi # !no_stg_grd
if [ -n "${rnr_thr}" ]; then
    if [ "${rnr_thr}" != 'off' ]; then
	rgr_opt="${rgr_opt} --rnr_thr=${rnr_thr}"
    fi # !rnr_thr
fi # !rnr_thr
if [ -n "${var_lst}" ]; then
    nco_var_lst="-v ${var_lst}"
fi # !var_lst
if [ -n "${msk_dst}" ]; then
    nco_msk_dst="--rgr msk_var=${msk_dst}"
fi # !msk_dst
if [ -n "${msk_out}" ]; then
    nco_msk_out="--rgr msk_var=${msk_out}"
fi # !msk_out
if [ -n "${msk_src}" ]; then
    nco_msk_src="--rgr msk_var=${msk_src}"
fi # !msk_src
if [ -n "${skl_fl}" ]; then
    nco_skl_fl="--rgr skl=\"${skl_fl}\""
fi # !skl_fl
if [ -n "${ugrid_fl}" ]; then
    nco_ugrid_fl="--rgr ugrid=\"${ugrid_fl}\""
fi # !ugrid_fl
if [ -n "${var_rgr}" ]; then
    nco_var_rgr="--rgr_var=${var_rgr}"
fi # !var_rgr
if [ -n "${xtn_var}" ]; then
    rgr_opt="${rgr_opt} --xtn=${xtn_var}"
fi # !var_lst
if [ -n "${out_fl}" ]; then
    out_usr_flg='Yes'
fi # !out_fl
if [ -n "${par_typ}" ]; then
    if [ "${par_typ}" != 'bck' ] && [ "${par_typ}" != 'mpi' ] && [ "${par_typ}" != 'nil' ]; then
	    echo "ERROR: Invalid -p par_typ option = ${par_typ}"
	    echo "HINT: Valid par_typ arguments are 'bck', 'mpi', and 'nil'. For background parallelism, select 'bck' which causes ${spt_nm} to spawn parallel processes as background tasks on a single node. For MPI parallelism, select 'mpi' which causes ${spt_nm} to spawn parallel processes on across available cluster nodes. For no parallelism, select 'nil', which causes ${spt_nm} to spawn all processes serially on a single compute node."
	    exit 1
    fi # !par_typ
fi # !par_typ
if [ "${par_typ}" = 'bck' ]; then
    par_opt=' &'
    par_sng='Background'
elif [ "${par_typ}" = 'mpi' ]; then
    mpi_flg='Yes'
    par_opt=' &'
    par_sng='MPI'
elif [ "${par_typ}" = 'nil' ] || [ -z "${par_typ}" ]; then
    par_sng='Serial'
fi # !par_typ
if [ -n "${prc_typ}" ]; then
    if [ "${prc_typ}" != 'airs' ] && [ "${prc_typ}" != 'alm' ] && [ "${prc_typ}" != 'clm' ] && [ "${prc_typ}" != 'cice' ] && [ "${prc_typ}" != 'ctsm' ] && [ "${prc_typ}" != 'elm' ] && [ "${prc_typ}" != 'hirdls' ] && [ "${prc_typ}" != 'mls' ] && [ "${prc_typ}" != 'mod04' ] && [ "${prc_typ}" != 'mpas' ] && [ "${prc_typ}" != 'mpascice' ] && [ "${prc_typ}" != 'mwf' ] && [ "${prc_typ}" != 'nil' ] && [ "${prc_typ}" != 'rrg' ] && [ "${prc_typ}" != 'sgs' ] ; then
	    echo "ERROR: Invalid -P prc_typ option = ${prc_typ}"
	    echo "HINT: Valid prc_typ arguments are 'airs', 'alm', 'clm', 'cice', 'ctsm', 'elm', 'hirdls', 'mls', 'mod04', 'mpas', 'mpascice', 'mwf', 'nil', 'rrg', and 'sgs'"
	    exit 1
    fi # !prc_typ
fi # !prc_typ
if [ "${prc_typ}" = 'airs' ]; then
    pdq_opt='-a StdPressureLev,GeoTrack,GeoXTrack'
fi # !airs
if [ "${prc_typ}" = 'hirdls' ]; then
    pdq_opt='-a Pressure,Latitude,lon'
fi # !hirdls
if [ "${prc_typ}" = 'mls' ]; then
    pdq_opt='-a CO_Pressure,CO_Latitude,lon'
fi # !mls
if [ "${prc_typ}" = 'mod04' ]; then
    pdq_opt='-U'
    hnt_dst='--dst_regional'
fi # !mod04
if [ "${prc_typ}" = 'mpas' ] || [ "${prc_typ}" = 'mpascice' ]; then
    prc_mpas='Yes'
fi # !mpas, !mpascice
if [ "${prc_mpas}" = 'Yes' ]; then
    # Add depth coordinate to MPAS file when requested to by specifying coordinate file, that file exists, and commmand is found
    if [ -n "${dpt_fl}" ] || [ "${dpt_flg}" = 'Yes' ]; then
	if [ -n "${dpt_fl}" ]; then
	    if [ ! -f "${dpt_fl}" ]; then
		echo "ERROR: Unable to find specified MPAS depth coordinate file ${dpt_fl}"
		exit 1
	    fi # ! -f
	    cmd_dpt_opt="-c \"${dpt_fl}\""
	fi # !dpt_fl
	if [ -z "${cmd_dpt_mpas}" ]; then
	    printf "${spt_nm}: ERROR MPAS depth coordinate addition requested but command ${dpt_exe_mpas} not found\n"
	fi # !err
	dpt_flg='Yes'
    fi # !dpt_fl
#    pdq_opt='-a Time,nVertLevels,maxEdges,MaxEdges2,nEdges,nCells' # Ocean
#    pdq_opt='-a Time,nCategories,ONE,nEdges,nCells' # SeaIce
#    pdq_opt='-a Time,nCategories,TWO,nEdges,nCells' # LandIce
    pdq_opt='-a Time,depth,nVertLevels,nVertLevelsP1,maxEdges,MaxEdges2,nCategories,ONE,nEdges,nCells' # Ocean and Ice in one swell foop
    if [ -n "${rnr_thr}" ]; then
	# rnr_thr='off' in MPAS mode turns-off renormalization
	if [ "${rnr_thr}" != 'off' ]; then
	    rgr_opt="${rgr_opt} --rnr_thr=${rnr_thr}"
	fi # !rnr_thr
    else
	rgr_opt="${rgr_opt} --rnr_thr=0.0"
    fi # !rnr_thr
    # 20181130 No known reason to include staggered grid with regridded MPAS data
    rgr_opt="${rgr_opt} --rgr no_stagger"
fi # !mpas
if [ "${prc_typ}" = 'mwf' ]; then
    [[ ${dbg_lvl} -ge 1 ]] && date_mwf=$(date +"%s")
    # Assume destination grids ending in .nc and .g are FV and SE, respectively
    # https://stackoverflow.com/questions/407184/how-to-check-the-extension-of-a-filename-in-a-bash-script
    if [[ ${grd_dst} == *.g ]]; then
	alg_lst='fv2se_flx fv2se_stt fv2se_alt'
    else
	alg_lst='aave blin ndtos nstod patc tempest'
    fi # !grd_dst
    # Compute FV->SE maps
    if [ -n "${hnt_src}" ]; then
       hnt_src_sng="--hnt_src=${hnt_src}"
    fi # !hnt_src
    if [ -n "${hnt_dst}" ]; then
       hnt_dst_sng="--hnt_dst=${hnt_dst}"
    fi # !hnt_dst
    for alg_typ in ${alg_lst}; do
	alg_sng=${alg_typ}
	[[ ${alg_typ} = 'fv2se_flx' ]] && alg_sng='monotr'
	[[ ${alg_typ} = 'fv2se_stt' ]] && alg_sng='highorder'
	[[ ${alg_typ} = 'fv2se_alt' ]] && alg_sng='mono'
	map_nm="${drc_out}/map_${nm_src}_to_${nm_dst}_${alg_sng}.${dt_sng}.nc"
	wgt_sng=''
	if [ -n "${wgt_usr}" ]; then
	    erwg_alg_typ_rx='aave blin ndtos nstod patc'
	    # https://stackoverflow.com/questions/229551/string-contains-a-substring-in-bash
	    if [[ ${erwg_alg_typ_rx} = *"${alg_typ}"* ]]; then
		wgt_sng="--wgt_cmd='${wgt_usr}'"
	    fi # !ERWG
	fi # !wgt_usr
	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "MWF: Create ${alg_typ} map ${map_nm}\n"
	fi # !vrb_lvl
	cmd_mwf="ncremap ${wgt_sng} --alg_typ=${alg_typ} --grd_src=\"${grd_src}\" --grd_dst=\"${grd_dst}\" ${hnt_src_sng} ${hnt_dst_sng} --map=\"${map_nm}\""
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_mwf}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_mwf}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to generate MWF map. Debug this:\n${cmd_mwf}\n"
		exit 1
	    fi # !err
	fi # !dbg
	if [ ${dbg_lvl} -ge 1 ]; then
	    date_crr=$(date +"%s")
	    date_dff=$((date_crr-date_mwf))
	    echo "Elapsed time to generate ${alg_typ} map $((date_dff/60))m$((date_dff % 60))s"
	fi # !dbg
    done # !alg_typ
    # Compute SE->FV maps
    if [[ ${grd_dst} == *.g ]]; then
	alg_lst='se2fv_flx se2fv_stt se2fv_alt'
    else
	alg_lst='aave blin ndtos nstod patc tempest'
    fi # !grd_dst
    if [ -n "${hnt_src}" ]; then
       hnt_dst_sng="--hnt_dst=${hnt_src/src/dst}"
    fi # !hnt_src
    if [ -n "${hnt_dst}" ]; then
       hnt_src_sng="--hnt_src=${hnt_dst/dst/src}"
    fi # !hnt_dst
    for alg_typ in ${alg_lst}; do
	# Swap grd_src with grd_dst
	alg_sng=${alg_typ}
	[[ ${alg_typ} = 'se2fv_flx' ]] && alg_sng='mono'
	[[ ${alg_typ} = 'se2fv_stt' ]] && alg_sng='highorder'
	[[ ${alg_typ} = 'se2fv_alt' ]] && alg_sng='intbilin'
	map_nm="${drc_out}/map_${nm_dst}_to_${nm_src}_${alg_sng}.${dt_sng}.nc"
	# MWF-mode must be invoked with ocean as grd_src, atmosphere as grd_dst
	a2o_sng=''
	if [ "${alg_typ}" = 'se2fv_flx' ] || [ "${alg_typ}" = 'se2fv_stt' ] || [ "${alg_typ}" = 'se2fv_alt' ] || [ "${alg_typ}" = 'tempest' ]; then
	    a2o_sng='--a2o'
	fi # !alg_typ
	wgt_sng=''
	if [ -n "${wgt_usr}" ]; then
	    erwg_alg_typ_rx='aave blin ndtos nstod patc'
	    # https://stackoverflow.com/questions/229551/string-contains-a-substring-in-bash
	    if [[ ${erwg_alg_typ_rx} = *"${alg_typ}"* ]]; then
		wgt_sng="--wgt_cmd='${wgt_usr}'"
	    fi # !ERWG
	fi # !wgt_usr
	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "MWF: Create ${alt_typ} map ${map_nm}\n"
	fi # !vrb_lvl
	cmd_fwm="ncremap ${wgt_sng} ${a2o_sng} --alg_typ=${alg_typ} --grd_src=\"${grd_dst}\" --grd_dst=\"${grd_src}\" ${hnt_src_sng} ${hnt_dst_sng} --map=\"${map_nm}\""
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_fwm}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_fwm}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to generate FWM map. Debug this:\n${cmd_fwm}\n"
		exit 1
	    fi # !err
	fi # !dbg
	if [ ${dbg_lvl} -ge 1 ]; then
	    date_crr=$(date +"%s")
	    date_dff=$((date_crr-date_mwf))
	    echo "Elapsed time to generate ${alg_typ} map $((date_dff/60))m$((date_dff % 60))s"
	fi # !dbg
    done # !alg_typ
    echo "Finished MWF mode"
    exit 0
fi # !mwf
if [ "${prc_typ}" = 'rrg' ]; then
    if [ -n "${dat_rgn}" ]; then # NB: option currently not implemented, drop it?
	fl_in[0]=${dat_rgn}
    fi # !dat_glb
    if [ -n "${dat_glb}" ]; then
	if [ ! -f "${dat_glb}" ]; then
	    echo "ERROR: Unable to find specified global data file ${dat_glb}"
	    exit 1
	fi # ! -f
    else
	echo "${spt_nm}: ERROR Regional regridding requires global data coordinates in file specified with --rrg_dat_glb argument\n"
	exit 1
    fi # !dat_glb
    if [ -n "${grd_glb}" ]; then
	if [ ! -f "${grd_glb}" ]; then
	    echo "ERROR: Unable to find specified SCRIP-format global grid file ${grd_glb}"
	    exit 1
	fi # ! -f
    else
	echo "${spt_nm}: ERROR Regional regridding requires SCRIP-format grid for global data in file specified with --rrg_grd_glb argument\n"
	exit 1
    fi # !grd_glb
    # User may specify final, regional destination grid with either -g or --rrg_grd_rgn
    if [ -n "${grd_rgn}" ]; then
	grd_dst=${grd_rgn}
    else
	if [ -n "${grd_dst}" ]; then
	    grd_rgn=${grd_dst}
	else
	    echo "${spt_nm}: ERROR Regional regridding requires SCRIP-format destination grid for regional data in file specified with --rrg_grd_rgn or --grd_dst argument\n"
	    exit 1
	fi # !grd_dst
    fi # !grd_rgn
    if [ ! -f "${grd_rgn}" ]; then
	echo "ERROR: Unable to find specified SCRIP-format regional grid file ${grd_rgn}"
	exit 1
    fi # ! -f
    grd_dst_usr_flg='Yes'
    hnt_dst='--dst_regional'
fi # !rrg
if [ "${prc_typ}" = 'alm' ] || [ "${prc_typ}" = 'clm' ] || [ "${prc_typ}" = 'ctsm' ] || [ "${prc_typ}" = 'elm' ]; then
    # Set ALM/CLM/ELM-specific options first, then change prc_typ to sgs
    rds_rth='6.37122e6' # [m] Radius of Earth in ALM/CLM/CTSM/ELM (SHR_CONST_REARTH)
    sgs_frc='landfrac'
    sgs_msk='landmask'
    sgs_nrm='1.0'
    prc_elm='Yes'
    prc_typ='sgs'
fi # !alm, !clm, !ctsm, !elm
if [ "${prc_typ}" = 'cice' ]; then
    # Set CICE-specific options first, then change prc_typ to sgs
    rds_rth='6371229.0' # [m] Radius of Earth in MPAS-CICE (global attribute sphere_radius)
    sgs_frc='aice'
    sgs_msk='tmask'
    sgs_nrm='100.0'
    prc_cice='Yes'
    prc_typ='sgs'
fi # !cice
if [ "${prc_typ}" = 'mpascice' ]; then
    # Set MPAS-CICE-specific options first, then change prc_typ to sgs
    # MPAS-CICE requires two modes, MPAS and SGS, so set prc_mpas to 'Yes'
    rds_rth='6371229.0' # [m] Radius of Earth in MPAS-CICE (global attribute sphere_radius)
    sgs_frc='timeMonthly_avg_iceAreaCell'
    sgs_msk='timeMonthly_avg_icePresent'
    sgs_nrm='1.0'
    prc_mpas='Yes'
    prc_mpascice='Yes'
    prc_typ='sgs'
fi # !mpascice
if [ "${prc_typ}" = 'sgs' ]; then
    nco_dgn_area='--rgr diagnose_area'
    wgt_opt_esmf='--user_areas --ignore_unmapped'
    wgt_opt=${wgt_opt_esmf}
fi # !sgs
if [ -n "${thr_usr}" ]; then
    thr_nbr="${thr_usr}"
fi # !thr_usr

echo "spot 4"

if [ -n "${dst_fl}" ]; then
    if [ ! -f "${dst_fl}" ]; then
	echo "ERROR: Unable to find specified destination-file ${dst_fl}"
	echo "HINT: Supply the full path-name for the destination-file"
	exit 1
    fi # ! -f
    dst_usr_flg='Yes'
fi # !dst_fl
if [ -z "${grd_sng}" ]; then
    grd_sng_dfl="grd_ttl='Default internally-generated grid'#latlon=10,10#lat_typ=uni#lon_typ=Grn_ctr" # [sng] Grid string default
    grd_sng="${grd_sng_dfl}"
else
    grd_sng_usr_flg='Yes'
fi # !grd_sng
if [ -n "${grd_dst}" ]; then
    if [ -f "${grd_dst}" ]; then
	if [ "${dst_usr_flg}" = 'Yes' ]; then
	    printf "${spt_nm}: WARNING ${grd_dst} already exists and will be overwritten by inferred grid\n"
	fi # !dst_usr_flg
	if [ "${grd_sng_usr_flg}" = 'Yes' ]; then
	    printf "${spt_nm}: WARNING ${grd_dst} already exists and will be overwritten by created grid\n"
	fi # !grd_sng_usr_flg
    else
	if [ "${dst_usr_flg}" != 'Yes' ] && [ "${grd_sng_usr_flg}" != 'Yes' ]; then
	    echo "ERROR: Unable to find specified destination grid-file ${grd_dst}"
	    echo "HINT: Supply full path-name for destination grid, or generate it with -G option and arguments"
	exit 1
	fi # !dst_usr_flg
    fi # ! -f
    grd_dst_usr_flg='Yes'
else
    grd_dst=${grd_dst_dfl} # [sng] Grid-file default
fi # !grd_dst
if [ -n "${grd_src}" ]; then
    if [ "${prc_typ}" != 'rrg' ]; then
	if [ ! -f "${grd_src}" ]; then
	    echo "ERROR: Unable to find specified source grid-file ${grd_src}"
	    exit 1
	fi # ! -f
	grd_src_usr_flg='Yes'
    fi # !rrg
else
    grd_src=${grd_src_dfl} # [sng] Grid-file default
fi # !grd_src
if [ "${dst_usr_flg}" = 'Yes' ] || [ "${grd_sng_usr_flg}" = 'Yes' ] || [ "${grd_dst_usr_flg}" = 'Yes' ] || [ "${grd_src_usr_flg}" = 'Yes' ]; then
    # Map-file will be created if -d, -G, -g, or -s was specified
    map_mk='Yes'
fi # !map_mk
if [ -n "${map_fl}" ]; then
    map_usr_flg='Yes'
    if [ "${map_mk}" = 'Yes' ]; then
	# Confirm before overwriting maps
        if [ -f "${map_fl}" ]; then
	    # 20160803: fxm invoke iff in interactive shell (block hangs on read() in non-interactive shells)
#	    if [ -t 0 ] || [ ! -p /dev/stdin ]; then
#           if [ -n "${TERM}" ]; then
#           if [ -n "${PS1}" ]; then
            if [ 1 -eq 0 ]; then
		rsp_kbd_nbr=0
		while [ ${rsp_kbd_nbr} -lt 10 ]; do
		    echo "WARNING: Map-file ${map_fl} already exists and will be over-written."
		    read -p "Continue (y/n)? " rsp_kbd
		    let rsp_kbd_nbr+=1
		    case "${rsp_kbd}" in
			N*|n*) exit 1 ;;
			Y*|y*) break ;;
			*) continue ;;
		    esac
		done # !rsp_kbd_nbr
		if [ ${rsp_kbd_nbr} -ge 10 ]; then
		    echo "ERROR: Too many invalid responses, exiting"
		    exit 1
		fi # !rsp_kbd_nbr
	    fi # !0
	fi # !map_fl
    else # !map_mk
        if [ ! -f "${map_fl}" ]; then
	    echo "ERROR: Unable to find specified regrid map ${map_fl}"
	    echo "HINT: Supply a valid map-file (weight-file) name or supply the grid files or data files and let ncremap create a mapfile for you"
	    exit 1
	fi # ! -f
    fi # !map_mk
else # !map_fl
    if [ "${wgt_typ}" = 'esmf' ]; then
	map_fl_dfl="${drc_tmp}/ncremap_tmp_map_${wgt_typ}_${alg_opt}.nc${unq_sfx}" # [sng] Map-file default
    fi # !esmf
    if [ "${wgt_typ}" = 'tempest' ]; then
	map_fl_dfl="${drc_tmp}/ncremap_tmp_map_${wgt_typ}.nc${unq_sfx}" # [sng] Map-file default
    fi # !tempest
    map_fl=${map_fl_dfl}
fi # !map_fl
map_rsl_fl=${map_fl}
if [ "${map_mk}" = 'Yes' ] && [ "${wgt_typ}" = 'tempest' ]; then
    msh_fl_dfl="${drc_tmp}/ncremap_tmp_msh_ovr_${wgt_typ}.g${unq_sfx}" # [sng] Mesh-file default
    msh_fl=${msh_fl_dfl}
    if [ "${trn_map}" = 'Yes' ]; then
	map_trn_fl="${drc_tmp}/ncremap_tmp_map_trn_${wgt_typ}.nc${unq_sfx}" # [sng] Map-file transpose default
	map_rsl_fl=${map_trn_fl}
    fi # !trn_map
fi # !tempest

echo "spot 5"

# Read files from stdin pipe, positional arguments, or directory glob
# Code block taken from ncclimo
# ncclimo sets inp_aut flag when file list is automatically (i.e., internally) generated
# ncremap uses convention that input files specified with -i set inp_aut flag
# That way, ncremap code block looks closer to ncclimo without introducing a new "inp_cmd" flag
#printf "dbg: inp_aut  = ${inp_aut}\n"
#printf "dbg: inp_glb  = ${inp_glb}\n"
#printf "dbg: inp_psn  = ${inp_psn}\n"
#printf "dbg: inp_std  = ${inp_std}\n"
if [ ${inp_aut} = 'No' ] && [ ${inp_psn} = 'No' ] && [ ${inp_std} = 'No' ] && [ "${drc_in_usr_flg}" = 'Yes' ]; then
    inp_glb='Yes'
fi # !inp_psn, !inp_std
echo "spot 5.1"
if [ "${map_mk}" != 'Yes' ] && [ ${inp_aut} = 'No' ] && [ ${inp_glb} = 'No' ] && [ ${inp_psn} = 'No' ] && [ ${inp_std} = 'No' ]; then
    echo "${spt_nm}: ERROR Specify input file(s) with -i \$in_fl or with -I \$drc_in or with positional argument(s) or with stdin"
    if [ ${bch_pbs} = 'Yes' ]; then
	echo "${spt_nm}: HINT PBS batch job environment detected, pipe to stdin not allowed, try positional arguments instead"
    else # !bch_pbs
	echo "${spt_nm}: HINT Pipe input file list to stdin with, e.g., 'ls *.nc | ${spt_nm}'"
    fi # !bch_pbs
    exit 1
fi # !sbs_flg
echo "spot 5.2"
if [ ${inp_aut} = 'Yes' ]; then
    # Single file argument
    fl_in[0]=${in_fl}
    fl_nbr=1
fi # !inp_aut
echo "spot 5.3"
if [ ${inp_glb} = 'Yes' ]; then
    for fl in "${drc_in}"/*.nc "${drc_in}"/*.nc3 "${drc_in}"/*.nc4 "${drc_in}"/*.cdf "${drc_in}"/*.hdf "${drc_in}"/*.he5 "${drc_in}"/*.h5 ; do
	if [ -f "${fl}" ]; then
	    fl_in[${fl_nbr}]=${fl}
	    let fl_nbr=${fl_nbr}+1
	fi # !file
    done
fi # !inp_glb
echo "spot 5.4"
if [ ${inp_psn} = 'Yes' ]; then
    if [ ${psn_nbr} -eq 1 ]; then
	fl_in[0]=${1}
	fl_nbr=1
    elif [ ${psn_nbr} -eq 2 ]; then
	if [ -z "${out_fl}" ]; then
	    fl_in[0]=${1}
	    out_fl=${2}
	    out_usr_flg='Yes'
	    fl_nbr=1
	else # !out_fl
	    echo "ERROR: Output file specified with -o (${out_fl}) conflicts with second positional argument ${2}"
	    echo "HINT: Use -o out_fl or positional argument, not both"
	    exit 1
	fi # !out_fl
    elif [ ${psn_nbr} -ge 3 ]; then
	for ((psn_idx=1;psn_idx<=psn_nbr;psn_idx++)); do
	    fl_in[(${psn_idx}-1)]=${!psn_idx}
	    fl_nbr=${psn_nbr}
	done # !psn_idx
    fi # !psn_nbr
fi # !inp_psn
echo "spot 5.5"
if [ ${inp_std} = 'Yes' ]; then
    # Input awaits on unit 0, i.e., on stdin
    while read -r line; do # NeR05 p. 179
	fl_in[${fl_nbr}]=${line}
	let fl_nbr=${fl_nbr}+1
    done < /dev/stdin
fi # !inp_std

echo "spot 6"

if [ "${mpi_flg}" = 'Yes' ]; then
    if [ -n "${COBALT_NODEFILE}" ]; then
	nd_fl="${COBALT_NODEFILE}"
    elif [ -n "${PBS_NODEFILE}" ]; then
	nd_fl="${PBS_NODEFILE}"
    elif [ -n "${SLURM_NODELIST}" ]; then
	# SLURM returns compressed lists (e.g., "nid00[076-078,559-567]")
	# Convert this to file with uncompressed list (like Cobalt, PBS)
	# http://www.ceci-hpc.be/slurm_faq.html#Q12
	nd_fl='ncremap.slurm_nodelist'
	nd_lst=`scontrol show hostname ${SLURM_NODELIST}`
	echo ${nd_lst} > ${nd_fl}
    else
	echo "ERROR: MPI job unable to find node list"
	echo "HINT: ${spt_nm} uses first node list found in \$COBALT_NODEFILE (= \"${COBALT_NODEFILE}\"), \$PBS_NODEFILE (= \"${PBS_NODEFILE}\"), \$SLURM_NODELIST (= \"${SLURM_NODELIST}\")"
	exit 1
    fi # !PBS
    if [ -n "${nd_fl}" ]; then
	# NB: nodes are 0-based, e.g., [0..11]
	nd_idx=0
	for nd in `cat ${nd_fl} | uniq` ; do
	    nd_nm[${nd_idx}]=${nd}
	    let nd_idx=${nd_idx}+1
	done # !nd
	nd_nbr=${#nd_nm[@]}
	for ((fl_idx=0;fl_idx<fl_nbr;fl_idx++)); do
	    case "${HOSTNAME}" in
		# 20160502: Remove limits on tasks per node so round-robin algorithm can schedule multiple jobs on same node
		cori* | edison* | nid* )
		    # 20160502: Non-interactive batch jobs at NERSC return HOSTNAME as nid*, not cori* or edison*
		    # NB: NERSC staff says srun automatically assigns to unique nodes even without "-L $node" argument?
 		    cmd_mpi[${fl_idx}]="srun --nodelist ${nd_nm[$((${fl_idx} % ${nd_nbr}))]} --nodes=1" ; ;; # NERSC
# 		    cmd_mpi[${fl_idx}]="srun --nodelist ${nd_nm[$((${fl_idx} % ${nd_nbr}))]} --nodes=1 --ntasks=1" ; ;; # NERSC
		hopper* )
		    # NB: NERSC migrated from aprun to srun in 201601. Hopper commands will soon be deprecated.
		    cmd_mpi[${fl_idx}]="aprun -L ${nd_nm[$((${fl_idx} % ${nd_nbr}))]} -n 1" ; ;; # NERSC
		* )
		    cmd_mpi[${fl_idx}]="mpirun -H ${nd_nm[$((${fl_idx} % ${nd_nbr}))]} -n 1" ; ;; # Other (Cobalt)
#		    cmd_mpi[${fl_idx}]="mpirun -H ${nd_nm[$((${fl_idx} % ${nd_nbr}))]} -npernode 1 -n 1" ; ;; # Other
	    esac # !HOSTNAME
	done # !fl_idx
	if [ -n "${SLURM_NODELIST}" ]; then
	    /bin/rm -f ${nd_fl}
	fi # !SLURM
    else # !nd_fl
	mpi_flg='No'
	for ((fl_idx=0;fl_idx<fl_nbr;fl_idx++)); do
	    cmd_mpi[${fl_idx}]=""
	done # !fl_idx
    fi # !nd_fl
    if [ -z "${job_usr}" ]; then
	job_nbr=${nd_nbr}
    fi # !job_usr
    if [ -z "${thr_usr}" ]; then
	if [ -n "${PBS_NUM_PPN}" ]; then
#	NB: use export OMP_NUM_THREADS when thr_nbr > 8
#	thr_nbr=${PBS_NUM_PPN}
	    thr_nbr=$((PBS_NUM_PPN > 8 ? 8 : PBS_NUM_PPN))
	fi # !pbs
    fi # !thr_usr
fi # !mpi_flg

echo "spot 7"

# Print initial state
if [ ${dbg_lvl} -ge 2 ]; then
    printf "dbg: a2o_flg  = ${a2o_flg}\n"
    printf "dbg: alg_opt  = ${alg_opt}\n"
    printf "dbg: cln_flg  = ${cln_flg}\n"
    printf "dbg: d2f_flg  = ${d2f_flg}\n"
    printf "dbg: d2f_opt  = ${d2f_opt}\n"
    printf "dbg: dbg_lvl  = ${dbg_lvl}\n"
    printf "dbg: dfl_lvl  = ${dfl_lvl}\n"
    printf "dbg: dpt_flg  = ${dpt_flg}\n"
    printf "dbg: dpt_fl   = ${dpt_fl}\n"
    printf "dbg: drc_in   = ${drc_in}\n"
    printf "dbg: drc_out  = ${drc_out}\n"
    printf "dbg: drc_tmp  = ${drc_tmp}\n"
    printf "dbg: dst_fl   = ${dst_fl}\n"
    printf "dbg: erwg_vrs = ${erwg_vrs_sng}\n"
    printf "dbg: fl_fmt   = ${fl_fmt}\n"
    printf "dbg: fl_in[0] = ${fl_in[0]}\n"
    printf "dbg: fl_nbr   = ${fl_nbr}\n"
    printf "dbg: gaa_sng  = ${gaa_sng}\n"
    printf "dbg: gll_fl   = ${gll_fl}\n"
    printf "dbg: grd_dst  = ${grd_dst}\n"
    printf "dbg: grd_sng  = ${grd_sng}\n"
    printf "dbg: grd_src  = ${grd_src}\n"
    printf "dbg: inp_aut  = ${inp_aut}\n"
    printf "dbg: inp_glb  = ${inp_glb}\n"
    printf "dbg: inp_psn  = ${inp_psn}\n"
    printf "dbg: inp_std  = ${inp_std}\n"
    printf "dbg: hdr_pad  = ${hdr_pad}\n"
    printf "dbg: hrd_pth  = ${hrd_pth}\n"
    printf "dbg: job_nbr  = ${job_nbr}\n"
    printf "dbg: in_fl    = ${in_fl}\n"
    printf "dbg: map_fl   = ${map_fl}\n"
    printf "dbg: map_mk   = ${map_mk}\n"
    printf "dbg: mlt_map  = ${mlt_map_flg}\n"
    printf "dbg: mpi_flg  = ${mpi_flg}\n"
    printf "dbg: msk_dst  = ${msk_dst}\n"
    printf "dbg: msk_out  = ${msk_out}\n"
    printf "dbg: msk_src  = ${msk_src}\n"
    printf "dbg: nco_opt  = ${nco_opt}\n"
    printf "dbg: nd_nbr   = ${nd_nbr}\n"
    printf "dbg: out_fl   = ${out_fl}\n"
    printf "dbg: par_typ  = ${par_typ}\n"
    printf "dbg: ppc_prc  = ${ppc_prc}\n"
    printf "dbg: rgr_opt  = ${rgr_opt}\n"
    printf "dbg: rnr_thr  = ${rnr_thr}\n"
    printf "dbg: rrg_bb   = ${bb_wesn}\n"
    printf "dbg: rrg_dat  = ${dat_glb}\n"
    printf "dbg: rrg_glb  = ${grd_glb}\n"
    printf "dbg: rrg_rgn  = ${grd_rgn}\n"
    printf "dbg: rrg_rnm  = ${rnm_sng}\n"
    printf "dbg: sgs_frc  = ${sgs_frc}\n"
    printf "dbg: sgs_msk  = ${sgs_msk}\n"
    printf "dbg: sgs_nrm  = ${sgs_nrm}\n"
    printf "dbg: skl_fl   = ${skl_fl}\n"
    printf "dbg: spt_pid  = ${spt_pid}\n"
    printf "dbg: thr_nbr  = ${thr_nbr}\n"
    printf "dbg: ugrid_fl = ${ugrid_fl}\n"
    printf "dbg: unq_sfx  = ${unq_sfx}\n"
    printf "dbg: var_lst  = ${var_lst}\n"
    printf "dbg: var_rgr  = ${var_rgr}\n"
    printf "dbg: wgt_cmd  = ${wgt_cmd}\n"
    printf "dbg: wgt_opt  = ${wgt_opt}\n"
    printf "dbg: wgt_usr  = ${wgt_usr}\n"
    printf "dbg: xtr_typ  = ${xtr_typ}\n"
    printf "dbg: xtr_nsp  = ${xtr_nsp}\n"
    printf "dbg: xtr_xpn  = ${xtr_xpn}\n"
    printf "dbg: Will regrid ${fl_nbr} files:\n"
    for ((fl_idx=0;fl_idx<${fl_nbr};fl_idx++)); do
	printf "${fl_in[${fl_idx}]}\n"
    done # !fl_idx
fi # !dbg
if [ ${dbg_lvl} -ge 2 ]; then
    if [ ${mpi_flg} = 'Yes' ]; then
	for ((nd_idx=0;nd_idx<${nd_nbr};nd_idx++)); do
	    printf "dbg: nd_nm[${nd_idx}] = ${nd_nm[${nd_idx}]}\n"
	done # !nd
    fi # !mpi
fi # !dbg
if [ ${dbg_lvl} -ge 2 ]; then
    psn_nbr=$#
    printf "dbg: Found ${psn_nbr} positional parameters (besides \$0):\n"
    for ((psn_idx=1;psn_idx<=psn_nbr;psn_idx++)); do
	printf "dbg: psn_arg[${psn_idx}] = ${!psn_idx}\n"
    done # !psn_idx
fi # !dbg

echo "spot 8"

# Create output directory
if [ -n "${drc_out}" ]; then
    mkdir -p ${drc_out}
fi # !drc_out
if [ -n "${drc_tmp}" ]; then
    mkdir -p ${drc_tmp}
fi # !drc_tmp

echo "spot 9"

# Human-readable summary
date_srt=$(date +"%s")
if [ ${vrb_lvl} -ge ${vrb_4} ]; then
    printf "NCO regridder invoked with command:\n"
    echo "${cmd_ln}"
fi # !vrb_lvl
if [ -f 'PET0.RegridWeightGen.Log' ]; then
    if [ ${vrb_lvl} -ge ${vrb_4} ]; then
	printf "${spt_nm}: Removing PET0.RegridWeightGen.Log file and any other PET0.* files from current directory before running\n"
    fi # !vrb_lvl
    /bin/rm -f PET0.*
fi # !PETO
if [ ${vrb_lvl} -ge ${vrb_3} ]; then
    printf "Started processing at `date`.\n"
    printf "Running remap script ${spt_nm} from directory ${drc_spt}\n"
    printf "NCO binaries version ${nco_vrs} from directory ${drc_nco}\n"
    printf "Parallelism mode = ${par_sng}\n"
    printf "Input files in or relative to directory ${drc_in}\n"
    printf "Intermediate/temporary files written to directory ${drc_tmp}\n"
    printf "Output files to directory ${drc_out}\n"
fi # !vrb_lvl
if [ "${map_mk}" != 'Yes' ] && [ "${map_usr_flg}" = 'Yes' ] && [ -n "${wgt_usr}" ]; then
    printf "${spt_nm}: ERROR Specifying both '-m map_fl' and '-w wgt_cmd' is only allowed when creating a map (weight-generator is superfluous when user supplies map)\n"
    exit 1
fi # wgt_usr

if [ "${dst_usr_flg}" = 'Yes' ]; then
    if [ "${grd_dst_usr_flg}" = 'Yes' ]; then
	printf "${spt_nm}: INFO Both '-d dst_fl' and '-g grd_dst' were specified so ${spt_nm} will infer ${grd_dst} from ${dst_fl}\n"
    fi # !grd_dst_usr_flg
fi # !dst_usr_flg
if [ "${dst_usr_flg}" != 'Yes' ] && [ "${grd_dst_usr_flg}" != 'Yes' ] && [ "${map_usr_flg}" != 'Yes' ] && [ "${grd_sng_usr_flg}" != 'Yes' ]; then
    printf "${spt_nm}: ERROR Must specify at least one of '-d dst_fl', '-g grd_dst', '-G grd_sng', or '-m map_fl'\n"
    exit 1
fi # !dst_usr_flg
if [ "${dst_usr_flg}" != 'Yes' ] && [ "${grd_dst_usr_flg}" = 'Yes' ] && [ "${map_usr_flg}" != 'Yes' ] && [ "${grd_sng_usr_flg}" = 'Yes' ]; then
    flg_grd_only='Yes'
fi # !flg_grd_only

echo "spot 10"

# Generate destination grid, if necessary, once (only) before loop over input files
# Block 1: Destination grid
# Generate destination grid at most one-time (unlike source grid)
# Eventually we will allow destination grid to be provided as grid-file, map-file, or data-file without a switch
# Currently we require user to know (and specify) means by which destination grid is provided
if [ ${vrb_lvl} -ge ${vrb_3} ]; then
    if [ ${fl_nbr} -eq 0 ]; then
	printf "Map/grid-only run: no input data detected therefore will exit after generating map and/or grid\n"
    fi # !fl_nbr
    if [ -n "${pdq_opt}" ] && [ -n "${pdq_typ}" ]; then
	printf "Input data shaped in \"${prc_typ}\"-order, will permute with \"ncpdq ${pdq_opt}\"\n"
    fi # !pdq_opt
    if [ -n "${pdq_opt}" ]; then
	if [ -n "${pdq_typ}" ]; then
	    printf "Input data shaped in \"${prc_typ}\"-order, will first permute with \"ncpdq ${pdq_opt}\"\n"
	else
	    printf "Input assumed to contain packed data, will first unpack with \"ncpdq ${pdq_opt}\"\n"
	fi # !pdq_typ
    fi # !pdq_opt
    if [ "${prc_mpas}" = 'Yes' ]; then
	printf "MPAS input specified: will renormalize (with --rnr=0.0) regridding\n"
	if [ "${clm_flg}" = 'No' ]; then
 	    printf "MPAS input specified: will annotate NC_DOUBLE variables with _FillValue = ${mss_val} prior to regridding\n"
	fi # !clm_flg
	if [ "${dpt_flg}" = 'Yes' ]; then
 	    printf "MPAS input specified: will add depth coordinate to all 3D variables prior to regridding\n"
	fi # !clm_flg
    fi # !mpas
    if [ "${d2f_flg}" = 'Yes' ]; then
	printf "Will convert all non-coordinate double precision input fields to single precision\n"
    fi # !d2f_flg
    if [ "${prc_typ}" = 'sgs' ]; then
	printf "Input assumed to contain sub-gridscale (SGS, aka \"fractional area\") data: Intensive values valid for gridcell fraction specified by \"${sgs_frc}\" variable, not for entire gridcell_area (except where ${sgs_frc} = 1.0). Will first conservatively regrid ${sgs_frc}, and then normalize subsequent regridding to conserve ${sgs_frc}*gridcell_area*field_value (not gridcell_area*field_value).\n"
	if [ ${fl_nbr} -eq 0 ]; then
	    printf "${spt_nm}: ERROR Sub-gridscale handling currently requires at least one data file (for the surface fractions of each gridcell)\n"
	    echo "${spt_nm}: HINT Supply a data file with \"-i fl_in\""
	    exit 1
	fi # !fl_nbr
	if [ "${wgt_typ}" = 'tempest' ]; then
	    printf "${spt_nm}: ERROR Sub-gridscale handling currently does not support TempestRemap.\n"
	    echo "${spt_nm}: HINT Use ESMF weight-generator (and ask Charlie to implement SGS for Tempest)"
	    exit 1
	fi # !wgt_typ
	if [ "${grd_src_usr_flg}" != 'Yes' ]; then
	    printf "${spt_nm}: ERROR Sub-gridscale handling currently requires the user to specify the SCRIP-format source grid-file. Moreover, the source grid-file must include the (normally non-essential) grid_area field. It is infeasible to permit SGS source-grid inferral, because weight-generators assume great circle arcs but 2D-grids usually have small-circles in latitude, and this can lead to significant area mis-matches. Despite this, sub-gridscale handling is happy to infer destination (not source) grids.\n"
	    echo "${spt_nm}: HINT Supply source grid-file with \"-s grd_src\".\nALTERNATIVE TO SGS: If the source grid-file is unavailable, first multiply sub-grid fields by ${sgs_frc} (with, e.g., ncap2 -s \"foo*=${sgs_frc};\" in.nc out.nc) and then regrid as normal without invoking sub-gridscale handling, i.e., omit the '-P sgs' and '--sgs_*' options."
	    exit 1
	    # 20170511: fxm Inferring source grids leads to ~2% biases with conservative regridding and 2D source grids. Not sure why.
	    # printf "${spt_nm}: Sub-gridscale handling will attempt to infer the source SCRIP grid-file from the input data file. This will only work for rectangular 2D data files, because SGS requires the source grid-file to contain the (normally non-essential) grid_area field for the input grid.\n"
	fi # !grd_src_usr_flg
	if [ "${grd_dst_usr_flg}" != 'Yes' ]; then
	    printf "${spt_nm}: Sub-gridscale handling will attempt to infer the destination SCRIP grid-file from the provided output data file template (which will not be touched).\n"
	fi # !grd_dst_usr_flg
	if [ "${map_usr_flg}" = 'Yes' ] && [ "${map_mk}" != 'Yes' ]; then
	    printf "${spt_nm}: WARNING Sub-grid handling (SGS-mode) forbids specification of a precomputed map-file. Sub-grid handling must generate map-files from specially pre-processed SCRIP grid-files. Allowing pre-computed map-files risks users inadvertently supplying incorrect map-files. The supplied or inferred SCRIP grid-files must include the (normally non-essential) grid_area field, which ${spt_nm} can normally infer from rectangular 2-D datafiles, though not from 1-D (unstructured) datafiles.\n"
	    echo "${spt_nm}: HINT Either remove map-file specification by eliminating the \"-m map_fl\" option, or use this pre-computed map but not in SGS mode (eliminate the \"-P sgs\" option)"
	    exit 1
	fi # !fl_nbr
    fi # !sgs
fi # !vrb_lvl
if [ "${map_mk}" != 'Yes' ] && [ "${map_usr_flg}" = 'Yes' ]; then
    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "Source and destination grids will both be read from supplied map-file\n"
    fi # !vrb_lvl
else # !map_usr_flg
    fl_idx=0 # [idx] Current file index
    if [ "${dst_usr_flg}" = 'Yes' ]; then
	# Block 1 Loop 1: Generate, check, and store (but do not yet execute) commands
	# Infer destination grid-file from data file
	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "Destination grid will be inferred from data-file\n"
	fi # !vrb_lvl
	cmd_dst[${fl_idx}]="ncks -O ${nco_opt} --rgr infer --rgr hnt_dst=\"${hnt_dst_fl}\" ${nco_dgn_area} ${nco_msk_dst} ${nco_var_rgr} ${nco_ugrid_fl} --rgr scrip=\"${grd_dst}\" \"${dst_fl}\" \"${tmp_out_fl}\""
    else # !dst_usr_flg
	if [ "${grd_dst_usr_flg}" = 'Yes' ] && [ "${grd_sng_usr_flg}" != 'Yes' ]; then
	    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
		printf "Destination grid supplied by user\n"
	    fi # !vrb_lvl
	fi # !grd_dst_usr_flg
	if [ "${grd_dst_usr_flg}" != 'Yes' ] && [ "${grd_sng_usr_flg}" != 'Yes' ]; then
	    printf "${spt_nm}: ERROR No destination grid specified with -g, inferral file specified with -d, or grid string specified with -G\n"
	fi # !grd_dst_usr_flg
	if [ "${grd_sng_usr_flg}" = 'Yes' ]; then
	    # 20180903 Must quote grd_sng otherwise whitespace and shell redirection characters (e.g., in ttl argument) will confuse interpreter
	    cmd_dst[${fl_idx}]="ncks -O --dmm_in_mk ${nco_opt} --rgr scrip=\"${grd_dst}\" ${nco_skl_fl} --rgr '${grd_sng}' \"${dmm_fl}\" \"${tmp_out_fl}\""
	    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
		if [ "${grd_dst_usr_flg}" = 'Yes' ]; then
		    printf "Destination grid will be generated in SCRIP format from NCO grid-formula ${grd_sng} and stored in ${grd_dst}\n"
		else
		    printf "Destination grid will be generated in SCRIP format from NCO grid-formula ${grd_sng} and stored in a temporary, internal location\n"
		fi # !grd_sng_usr_flg
	    fi # !vrb_lvl
	fi # !grd_sng_usr_flg
    fi # !dst_usr_flg
    if [ "${dst_usr_flg}" = 'Yes' ] || [ "${grd_sng_usr_flg}" = 'Yes' ]; then
	# Block 1 Loop 2: Execute and/or echo commands
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_dst[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_dst[${fl_idx}]}
	    if [ "$?" -ne 0 ]; then
		if [ "${grd_sng_usr_flg}" = 'Yes' ]; then
		    printf "${spt_nm}: ERROR Failed to generate grid from user-supplied grid-string. Debug this:\n${cmd_dst[${fl_idx}]}\n"
		else # !grd_sng_usr_flg
		    printf "${spt_nm}: ERROR Failed to infer destination grid. Debug this:\n${cmd_dst[${fl_idx}]}\n"
		fi # !grd_sng_usr_flg
		exit 1
	    fi # !err
	    if [ "${grd_sng_usr_flg}" = 'Yes' ]; then
		/bin/rm -f ${tmp_out_fl}
	    fi # !grd_sng_usr_flg
	fi # !dbg
    fi # !dst_usr_flg || grd_dst_usr_flg
    if [ ${vrb_lvl} -ge ${vrb_3} ] && [	${flg_grd_only} != 'Yes' ]; then
	printf "Weight-generation type: ${wgt_typ}\n"
	printf "Algorithm selected to generate weights in map-file is: ${alg_opt}\n"
	printf "Will generate mapping weights and map-file with \'${wgt_cmd}\'\n"
    fi # !vrb_lvl
    command -v ${wgt_exe} 2>&1 > /dev/null || { printf "${spt_nm}: ERROR cannot find weight-generation command executable ${wgt_exe}. Please install the executable, or change your PATH to find it.\n${spt_nm}: HINT ESMF_RegridWeightGen is often provided in NCL packages. Tempest executables must be installed from source (https://github.com/ClimateGlobalChange/tempestremap).\n"; exit 1; }
    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	if [ ${fl_nbr} -ge 2 ]; then
	    if [ "${mlt_map_flg}" = 'Yes' ]; then
		printf "Input files assumed to use unique input grids\nOne source grid-file will be inferred and one map-file generated per input file\n"
	    else # !mlt_map_flg
		printf "Input files assumed to use same input grid\nOnly one source grid-file and one map-file will be generated\n"
	    fi # !mlt_map_flg
	fi # !fl_nbr
    fi # !vrb_lvl
fi # !map_usr

echo "spot 11"

if [ "${prc_typ}" = 'rrg' ]; then
    fl_idx=0

    if [ -z "${rnm_sng}" ]; then
	# Discern rename string from input file, assume dimension is 'ncol', strip whitespace
	rnm_sng=`ncks -m ${fl_in[${fl_idx}]} | cut -d ':' -f 1 | cut -d '=' -s -f 1 | grep ncol | sed 's/ncol//' | sed -e 's/^ *//' -e 's/ *$//'`
	rgn_nbr=`echo ${rnm_sng} | wc -l`
	if [ "${rgn_nbr}" -ne 1 ]; then
	    echo "ERROR: Inferred regional regridding suffix '${rnm_sng}' indicates multiple regions present in input file. ncremap only works on one region at a time."
	    echo "HINT: Give a single region string as the argument to --rrg_rnm_sng"
	    exit 1
	fi # !rgn_nbr
	echo "${spt_nm}: INFO Parsed input file dimension list to obtain regional suffix string '${rnm_sng}'"
    fi # !rnm_sng
    if [ -n "${rnm_sng}" ]; then
	if [ -n "${bb_wesn}" ]; then
	    echo "${spt_nm}: INFO Will use explicitly specified comma-separated rectangular WESN bounding box string ${bb_west} instead of parsing string suffix ${rnm_sng}."
	else # !bb_wesn
	    rnm_rx='^_(.*)_to_(.*)_(.*)_to_(.*)$'
	    if [[ "${rnm_sng}" =~ ${rnm_rx} ]]; then
		lon1=${BASH_REMATCH[1]%?}
		lon2=${BASH_REMATCH[2]%?}
		if [ "${BASH_REMATCH[1]: -1}" = 'w' ]; then
		    let lon1=360-${lon1}
		fi # !w
		if [ "${BASH_REMATCH[2]: -1}" = 'w' ]; then
		    let lon2=360-${lon2}
		fi # !w
		if [ ${lon1} -lt ${lon2} ]; then
		    lon_min=${lon1}
		    lon_max=${lon2}
		else
		    lon_min=${lon2}
		    lon_max=${lon1}
		fi # !lon1
		lat1=${BASH_REMATCH[3]%?}
		lat2=${BASH_REMATCH[4]%?}
		if [ "${BASH_REMATCH[3]: -1}" = 's' ]; then
		    let lat1=-${lat1}
		fi # !w
		if [ "${BASH_REMATCH[4]: -1}" = 's' ]; then
		    let lat2=-${lat2}
		fi # !w
		if [ ${lat1} -lt ${lat2} ]; then
		    lat_min=${lat1}
		    lat_max=${lat2}
		else
		    lat_min=${lat2}
		    lat_max=${lat1}
		fi # !lat1
	    else # !rnm_sng
		echo "ERROR: Regional regridding suffix string '${rnm_sng}' does not match regular expression '${rnm_rx}'"
		echo "HINT: Regional regridding suffix string must have form like '_128e_to_134e_9s_to_16s' or '_20w_to_20e_10s_to_10n'"
		exit 1
	    fi # !rnm_sng
	    bb_wesn="${lon_min},${lon_max},${lat_min},${lat_max}"
	    echo "${spt_nm}: INFO Parsed suffix string ${rnm_sng} to obtain comma-separated rectangular WESN bounding box string ${bb_wesn}"
	fi # !bb_wesn
    else
	echo "${spt_nm}: ERROR Regional regridding requires string suffix appended to variables in regional data file to be specified with --rrg_rnm_sng argument"
	exit 1
    fi # !rnm_sng

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "Input assumed to be EAM/CAM-SE format regional data to regrid (aka RRG). RRG data are usually produced by explicitly requesting (sometimes multiple) regions from EAM/CAM-SE models with the \"finclNlonlat\" namelist variable. Will infer SCRIP-format regional source grid by cutting vertice information (originally from global dual-grid file ${grd_glb}) from rectangular WESN bounding box \"${bb_wesn}\" of identity-remapped (and thus vertice-annotated) copy of global data file ${dat_glb}. Will then create single map-file to regrid copy of requested fields with \"${rnm_sng}\" removed from dimension and variable names.\n"
    fi # !vrb_lvl

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "RRG: Identity-remap global data file from/to dual-grid to annotate it with vertices...\n"
    fi # !vrb_lvl
    cmd_nnt[${fl_idx}]="ncremap --vrb=0 -a bilin -s \"${grd_glb}\" -g \"${grd_glb}\" \"${dat_glb}\" \"${nnt_fl}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_nnt[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_nnt[${fl_idx}]}
	if [ "$?" -ne 0 ]; then
	    printf "${spt_nm}: ERROR Failed to identity-remap to annotate global data file. Debug this:\n${cmd_nnt[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "RRG: Subset coordinates to rectangular WESN regional bounding box ${bb_wesn}...\n"
    fi # !vrb_lvl
    cmd_sbs[${fl_idx}]="ncks -O -v lat,lon -X ${bb_wesn} \"${nnt_fl}\" \"${rgn_fl}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_sbs[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_sbs[${fl_idx}]}
	if [ "$?" -ne 0 ]; then
	    printf "${spt_nm}: ERROR Failed to subset and hyperslab coordinates into regional file. Debug this:\n${cmd_sbs[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "RRG: Infer source grid from subsetted, annotated, regional coordinate file...\n"
    fi # !vrb_lvl
    cmd_nfr[${fl_idx}]="ncks -O ${nco_opt} --rgr infer --rgr hnt_src=\"${hnt_src_fl}\" ${nco_msk_src} ${nco_var_rgr} --rgr scrip=\"${grd_src}\" \"${rgn_fl}\" \"${tmp_out_fl}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_nfr[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_nfr[${fl_idx}]}
	if [ "$?" -ne 0 ]; then
	    printf "${spt_nm}: ERROR Failed to infer source grid from subsetted, annotated, regional coordinate file. Debug this:\n${cmd_nfr[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg
fi # !rrg

echo "spot 12"

if [ "${prc_typ}" = 'sgs' ]; then

    fl_idx=0
    grd_dst_sgs="${drc_tmp}/ncremap_tmp_grd_dst_sgs.nc${unq_sfx}" # [sng] Fractional destination grid-file
    grd_src_sgs="${drc_tmp}/ncremap_tmp_grd_src_sgs.nc${unq_sfx}" # [sng] Fractional source grid-file
    frc_in_sgs="${drc_tmp}/ncremap_tmp_frc_in_sgs.nc${unq_sfx}" # [sng] Sub-grid fraction on input data grid
    frc_out_sgs="${drc_tmp}/ncremap_tmp_frc_out_sgs.nc${unq_sfx}" # [sng] Sub-grid fraction on output data grid

    if [ "${grd_src_usr_flg}" != 'Yes' ]; then
	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "Source grid will be inferred from data-file\n"
	    if [ ${fl_nbr} -ge 2 ]; then
		printf "Sub-grid mode assumes all input data-files on same grid as first file, so only one source grid-file will be inferred, and only one map-file will be generated, and it will be re-used\n"
	    fi # !fl_nbr
	fi # !vrb_lvl
	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "Infer source grid-file from input data file...\n"
	fi # !vrb_lvl
	cmd_src[${fl_idx}]="ncks -O ${nco_opt} --rgr infer --rgr hnt_src=\"${hnt_src_fl}\" ${nco_dgn_area} ${nco_msk_src} ${nco_ugrid_fl} ${nco_var_rgr} --rgr scrip=\"${grd_src}\" \"${fl_in[${fl_idx}]}\" \"${tmp_out_fl}\""

	# Block 2 Loop 2: Execute and/or echo commands
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_src[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_src[${fl_idx}]}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to infer source grid. Debug this:\n${cmd_src[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !grd_src

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Duplicate destination grid-file for modification into fractional destination grid-file...\n"
    fi # !vrb_lvl
    cmd_cp_dst[${fl_idx}]="/bin/cp -f \"${grd_dst}\" \"${grd_dst_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_cp_dst[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_cp_dst[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${grd_dst_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to duplicate destination grid-file to fractional destination grid-file. Debug this:\n${cmd_cp_dst[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Duplicate source grid for modification into fractional source grid-file...\n"
    fi # !vrb_lvl
    cmd_cp_src[${fl_idx}]="/bin/cp -f \"${grd_src}\" \"${grd_src_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_cp_src[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_cp_src[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${grd_src_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to duplicate source grid to fractional source grid-file. Debug this:\n${cmd_cp_src[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Append sub-grid fraction from data-file to fractional source grid-file\n"
    fi # !vrb_lvl
    cmd_sgs_src[${fl_idx}]="ncks -A -C -v ${sgs_frc} \"${fl_in[${fl_idx}]}\" \"${grd_src_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_sgs_src[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_sgs_src[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${grd_src_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to append sub-grid fraction from data file to fractional source grid-file. Debug this:\n${cmd_sgs_src[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Derive fraction, mask, and area in fractional source grid-file...\n"
    fi # !vrb_lvl
    # 0. Normalize sub-grid fraction (e.g., from percent to fraction) if necessary
    # 1. Eliminate _FillValue and missing_value attributes before using where() which would evaluate _FillValue as false, and necessitate using a weird where() condition
    # 2. Set (formerly) missing values to 0 sub-grid fraction
    # 3. Set 0 sub-grid fraction to 0 imask
    # 4. Compute active grid area
    cmd_wheresrc[${fl_idx}]="ncap2 -O -s '${sgs_frc}=${sgs_frc}; if(${sgs_nrm} != 1.0){${sgs_frc}/=${sgs_nrm}; ${sgs_frc}@units=\"1\";} if(${sgs_frc}@missing_value.exists()) ram_delete(${sgs_frc}@missing_value); delete_miss(${sgs_frc}); where(${sgs_frc} > 1.0f) ${sgs_frc}=0.0f; where(${sgs_frc} == 0.0f) grid_imask=0; grid_area*=${sgs_frc}' \"${grd_src_sgs}\" \"${grd_src_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_wheresrc[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_wheresrc[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${grd_src_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to derive fraction, mask, and area in fractional source grid-file. Debug this:\n${cmd_wheresrc[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Create sub-grid fraction ${sgs_frc} data file for regridding...\n"
    fi # !vrb_lvl
    cmd_sgs_in[${fl_idx}]="ncks -O -v ${sgs_frc} \"${grd_src_sgs}\" \"${frc_in_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_sgs_in[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_sgs_in[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${frc_in_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to extract sub-grid fraction from fractional source grid-file. Debug this:\n${cmd_sgs_in[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Regrid sub-grid fraction ${sgs_frc} to destination grid...\n"
    fi # !vrb_lvl
    # NB: Sub-grid mask is extensive and may contain _FillValue (as does ALM/CLM/CTSM/ELM landmask), so do not regrid it
    cmd_sgs_rmp[${fl_idx}]="ncremap --vrb=0 -a ${alg_opt} -v ${sgs_frc} -i \"${frc_in_sgs}\" -s \"${grd_src}\" -g \"${grd_dst}\" -o \"${frc_out_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_sgs_rmp[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_sgs_rmp[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${frc_out_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to regrid sub-grid fraction. Debug this:\n${cmd_sgs_rmp[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Derive sub-grid mask ${sgs_msk} from regridded sub-grid fraction...\n"
    fi # !vrb_lvl
    # Allow for possibility that sgs_frc is 3D (time,lat,lon) as in CICE
    # And be CAREFUL changing this
    cmd_sgs_msk[${fl_idx}]="ncap2 -O -s 'if(${sgs_frc}.ndims() < 3) sgsarea=${sgs_frc}*area; else sgsarea=${sgs_frc}(0,:,:);${sgs_msk}=0*int(sgsarea);where(sgsarea > 0) ${sgs_msk}=1; elsewhere ${sgs_msk}=0;${sgs_msk}@long_name=\"surface mask (0=invalid and 1=valid)\";if(${sgs_msk}@cell_measures.exists()) ram_delete(${sgs_msk}@cell_measures)' \"${frc_out_sgs}\" \"${frc_out_sgs}\""
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_sgs_msk[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_sgs_msk[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${frc_out_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to derive mask from regridded sub-grid fraction. Debug this:\n${cmd_sgs_msk[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Append regridded sub-grid fraction to destination fractional grid-file...\n"
    fi # !vrb_lvl
    cmd_sgs_dst[${fl_idx}]="ncks -A -C -v ${sgs_frc},area \"${frc_out_sgs}\" \"${grd_dst_sgs}\"" # Min Xu 20190123
    #cmd_sgs_dst[${fl_idx}]="ncks -A -C -v ${sgs_frc} \"${frc_out_sgs}\" \"${grd_dst_sgs}\"" # CSZ until 20190123 uses area directly from destination grid rather than copying remapped area from input grid
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_sgs_dst[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_sgs_dst[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${grd_dst_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to append regridded sub-grid fraction to destination fractional grid-file. Debug this:\n${cmd_sgs_dst[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "SGS: Derive mask and area in fractional destination grid-file...\n"
    fi # !vrb_lvl
    # 1. Set 0 sub-grid fraction to 0 imask
    # 2. Compute active grid area
    # 20190123:
    # Min Xu's lines make ncremap BFB with conv_remap2: conserve physical fields not area
    # CSZ's original lines disagree with conv_remap2: conserve area not physical fields
    # Min Xu defines grid_area using area from remapped source grid
    # CSZ uses area grid_area taken directly from destination grid
    cmd_wheredst[${fl_idx}]="ncap2 -O -s 'where(${sgs_frc} == 0.0f) grid_imask=0; elsewhere grid_imask=1;grid_area=grid_center_lon;grid_area=area*${sgs_frc}' \"${grd_dst_sgs}\" \"${grd_dst_sgs}\"" # Min Xu 20190123
    #cmd_wheredst[${fl_idx}]="ncap2 -O -s 'where(${sgs_frc} == 0.0f) grid_imask=0; elsewhere grid_imask=1;grid_area*=${sgs_frc}' \"${grd_dst_sgs}\" \"${grd_dst_sgs}\"" # CSZ until 20190123
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_wheredst[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_wheredst[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${grd_dst_sgs} ]; then
	    printf "${spt_nm}: ERROR Failed to derive mask and area in fractional destination grid-file. Debug this:\n${cmd_wheredst[${fl_idx}]}\n"
	    exit 1
	fi # !err
    fi # !dbg

    # Ensure map-generation uses modified grid files
    grd_src=${grd_src_sgs}
    grd_dst=${grd_dst_sgs}

    if [ "${prc_cice}" = 'Yes' ] || [ "${prc_mpascice}" = 'Yes' ] && [ ${fl_nbr} -gt 1 ]; then
	# Convey spirit of SGS implementation assumptions described below
	printf "WARNING: SGS-mode invoked for multiple sea-ice datasets. SGS-mode regrids all data files using the sub-grid fraction from the first datafile. This is usually appropriate for land timeseries since land sub-grid fractions generally do not change with time, yet inappropriate for sea-ice timeseries since sea-ice area generally changes with time.\nHINT: Invoke ${spt_nm} once per discrete time interval for sea-ice data. Doublecheck with Charlie if you are unsure what to do.\n"
    fi # !prc_cice, !prc_mpascice

fi # !sgs

echo "spot 13"

# If user provides source gridfile, or it was inferred in RRG or SGS modes, assume it applies to every input file
# Do not infer source gridfiles from input files within file loop
# Generate map-file once outside of file loop, and re-use it for every input file
# This paradigm suits ELM/ALM and CTSM/CLM timeseries since (until at least 201901) land fractions do not change
# A single instance of ncremap efficiently handles (creates/applies one SGS map for) all land datafiles from a single land simulation
# This paradigm is inappropriate for CICE timeseries since ice fractions change dramatically
# Invoke ncremap separately for each discrete time interval from a single sea-ice simulation
# Hence SGS regridding of land compared to sea-ice is fundamentally more efficient
if [ "${grd_src_usr_flg}" = 'Yes' ] || [ "${prc_typ}" = 'rrg' ] || [ "${prc_typ}" = 'sgs' ]; then
    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "Source grid supplied by user (or derived from RRG or SGS procedures) as ${grd_src}\n"
    fi # !vrb_lvl
    echo "spot 13.1"
    fl_idx=0
    if [ ${vrb_lvl} -ge ${vrb_1} ]; then
	printf "Grid(src): ${grd_src}\n"
	printf "Grid(dst): ${grd_dst}\n"
    fi # !vrb_lvl
    echo "spot 13.2"
    if [ "${wgt_typ}" = 'esmf' ]; then
	rgn_opt=''
	if [ -n "${hnt_src}" ]; then
	    rgn_opt="${rgn_opt} ${hnt_src}"
	elif [ -f "${hnt_src_fl}" ]; then
	    rgn_opt="${rgn_opt} `cat ${hnt_src_fl}`"
	fi # !hnt_src_fl
    echo "spot 13.3"
	if [ -n "${hnt_dst}" ]; then
	    rgn_opt="${rgn_opt} ${hnt_dst}"
	elif [ -f "${hnt_dst_fl}" ]; then
	    rgn_opt="${rgn_opt} `cat ${hnt_dst_fl}`"
	fi # !hnt_dst_fl
    echo "spot 13.4"
	cmd_map[${fl_idx}]="${wgt_cmd} -s \"${grd_src}\" -d \"${grd_dst}\" -w \"${map_fl}\" --method ${alg_opt} ${wgt_opt} ${rgn_opt} > /dev/null"
    fi # !esmf
    echo "spot 13.5"
    if [ "${wgt_typ}" = 'tempest' ]; then
	cmd_msh[${fl_idx}]="GenerateOverlapMesh --a \"${grd_src}\" --b \"${grd_dst}\" --out \"${msh_fl}\" > /dev/null"
	if [ "${a2o_flg}" = 'Yes' ]; then
	    cmd_msh[${fl_idx}]="GenerateOverlapMesh --b \"${grd_src}\" --a \"${grd_dst}\" --out \"${msh_fl}\" > /dev/null"
	fi # !a2o_flg
	cmd_map[${fl_idx}]="${wgt_cmd} --in_mesh \"${grd_src}\" --out_mesh \"${grd_dst}\" --ov_mesh \"${msh_fl}\" --out_map \"${map_fl}\" ${wgt_opt} > /dev/null"
	if [ "${trn_map}" = 'Yes' ]; then
	    # NB: Generate mono map for opposite direction regridding (i.e., reverse switches and grids), then transpose
	    cmd_map[${fl_idx}]="${wgt_cmd} --in_mesh \"${grd_dst}\" --out_mesh \"${grd_src}\" --ov_mesh \"${msh_fl}\" --out_map \"${map_trn_fl}\" ${wgt_opt} > /dev/null"
	    cmd_trn[${fl_idx}]="GenerateTransposeMap --in \"${map_trn_fl}\" --out \"${map_fl}\" > /dev/null"
	fi # !trn_map
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_msh[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_msh[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${msh_fl} ]; then
		printf "${spt_nm}: ERROR Failed to generate intersection mesh-file. Debug this:\n${cmd_msh[${fl_idx}]}\n"
		printf "${spt_nm}: HINT GenerateOverlapMesh requires that grids of unequal area be given as arguments in the order smaller first, larger second. ncremap supplies the grid arguments in the order source first, destination second unless explicitly told otherwise. A source grid that is a superset of the destination would violate the GenerateOverlapMesh rule. The solution is to add the \"--a2o\" switch (documented at http://nco.sf.net/nco.html#a2o) that tells ncremap to swap the grid argument order.\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !tempest
    echo "spot 13.6"
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_map[${fl_idx}]}
    fi # !dbg
    echo "spot 13.7"
    if [ ${dbg_lvl} -ne 2 ]; then
	eval ${cmd_map[${fl_idx}]}
	if [ "$?" -ne 0 ] || [ ! -f ${map_rsl_fl} ]; then
	    printf "${spt_nm}: ERROR Failed to generate map-file. Debug this:\n${cmd_map[${fl_idx}]}\n"
	    if [ "${wgt_typ}" = 'esmf' ]; then
		printf "${spt_nm}: HINT When ESMF fails to generate map-files, it often puts additional debugging information in the file named PET0.RegridWeightGen.Log in the invocation directory (${drc_pwd})\n"
	    fi # !esmf
	    exit 1
	fi # !err
    fi # !dbg
    echo "spot 13.8"
    # 20181116: GenerateTransposeMap does not propagate global attributes from input map
    # Moreover, it does not generate any metadata of its own except "Title"
    # Hence monotr maps are naked of usual Tempest map metadata
    if [ "${trn_map}" = 'Yes' ]; then
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_trn[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_trn[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${map_fl} ]; then
		printf "${spt_nm}: ERROR Failed to transpose map-file. Debug this:\n${cmd_trn[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !trn_map
    echo "spot 13.9"
    if [ "${map_usr_flg}" = 'Yes' ]; then
	hst_att="`date`: ${cmd_ln}; ${cmd_map[${fl_idx}]}"
	if [ "${wgt_typ}" = 'tempest' ]; then
	    hst_att="`date`: ${cmd_ln}; ${cmd_msh[${fl_idx}]}; ${cmd_map[${fl_idx}]}"
	    if [ "${trn_map}" = 'Yes' ]; then
		hst_att="${hst_att}; ${cmd_trn[${fl_idx}]}"
	    fi # !trn_map
	fi # !tempest
    echo "spot 13.10"
	cmd_att[${fl_idx}]="ncatted -O ${gaa_sng} --gaa history='${hst_att}' \"${map_fl}\""
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_att[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_att[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${map_fl} ]; then
		printf "${spt_nm}: ERROR Failed to annotate map-file. Debug this:\n${cmd_att[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !map_usr_flg
    echo "spot 13.11"
    # Set map_mk to something besides 'Yes' to avoid re-generating map within file loop
    map_mk='Already made map once. Never again!'
fi # !grd_src_usr_flg

echo "spot 14"

# Begin loop over input files
idx_srt=0
let idx_end=$((job_nbr-1))
for ((fl_idx=0;fl_idx<${fl_nbr};fl_idx++)); do
    in_fl=${fl_in[${fl_idx}]}
    if [ "$(basename "${in_fl}")" = "${in_fl}" ]; then
	in_fl="${drc_pwd}/${in_fl}"
    fi # !basename
    idx_prn=`printf "%02d" ${fl_idx}`
    if [ ${vrb_lvl} -ge ${vrb_1} ]; then
	printf "Input #${idx_prn}: ${in_fl}\n"
    fi # !vrb_lvl
    if [ "${out_usr_flg}" = 'Yes' ]; then
	if [ ${fl_nbr} -ge 2 ]; then
	    echo "ERROR: Single output filename specified with -o for multiple input files"
	    echo "HINT: For multiple input files use -O option to specify output directory and do not use -o or second positional option. Output files will have same name as input files, but will be in different directory."
	    exit 1
	fi # !fl_nbr
	if [ -n "${drc_usr}" ]; then
	    out_fl="${drc_out}/${out_fl}"
	fi # !drc_usr
    else # !out_usr_flg
	out_fl="${drc_out}/$(basename "${in_fl}")"
    fi # !out_fl
    if [ "${in_fl}" = "${out_fl}" ]; then
	echo "ERROR: Input file = Output file = ${in_fl}"
	echo "HINT: To prevent inadvertent data loss, ${spt_nm} insists that Input file and Output filenames differ"
	exit 1
    fi # !basename
    fl_out[${fl_idx}]=${out_fl}

    # Generate new map unless map-file was supplied or already-generated
    # NB: RRG infers source grid outside file loop, and forbids multiple source grids
    # NB: SGS infers (if necessary) source grid outside file loop, and forbids multiple source grids
    # RRG and SGS also produce map before file loop, and will not make maps inside file loop
    if [ "${map_mk}" = 'Yes' ]; then

	# Block 1: Special cases
	if [ "${prc_typ}" = 'hirdls' ] || [ "${prc_typ}" = 'mls' ]; then
	    # Pre-process zonal input files so grid inferral works
	    # 20160214: fix record variable to work around ncpdq problem
	    cmd_znl[${fl_idx}]="ncecat -O -u lon ${nco_opt} ${nco_var_lst} \"${in_fl}\" \"${in_fl}\" \"${in_fl}\" \"${in_fl}\" \"${znl_fl/znl/znl1}\";ncap2 -O ${nco_opt} -s 'lon[\$lon]={0.0,90.0,180.0,270.0}' \"${znl_fl/znl/znl1}\" \"${znl_fl/znl/znl2}\""
	    in_fl="${znl_fl/znl/znl2}"
	    if [ ${dbg_lvl} -ge 1 ]; then
		echo ${cmd_znl[${fl_idx}]}
	    fi # !dbg
	    if [ ${dbg_lvl} -ne 2 ]; then
		eval ${cmd_znl[${fl_idx}]}
		if [ "$?" -ne 0 ] || [ ! -f "${znl_fl/znl/znl2}" ]; then
		    printf "${spt_nm}: ERROR Failed to generate lat-lon file from zonal file. Debug this:\n${cmd_znl[${fl_idx}]}\n"
		    exit 1
		fi # !err
	    fi # !dbg
	fi # !znl

	# Block 2: Source grid
	# Block 2 Loop 1: Source gridfile command
	if [ ! -f "${in_fl}" ]; then
	    echo "${spt_nm}: ERROR Unable to find input file ${in_fl}"
	    echo "HINT: All files implied to exist must be in the directory specified by their filename or in ${drc_in} before ${spt_nm} will proceed"
		exit 1
	fi # ! -f
	# Infer source grid-file from input data file
	cmd_src[${fl_idx}]="ncks -O ${nco_opt} --rgr infer --rgr hnt_src=\"${hnt_src_fl}\" ${nco_msk_src} ${nco_ugrid_fl} ${nco_var_rgr} --rgr scrip=\"${grd_src}\" \"${in_fl}\" \"${tmp_out_fl}\""

	# Block 2 Loop 2: Execute and/or echo commands
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_src[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_src[${fl_idx}]}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to infer source grid. Debug this:\n${cmd_src[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg

	# Block 3: Source->destination maps
	# Block 3 Loop 1: Map-file commands
	if [ ${vrb_lvl} -ge ${vrb_1} ]; then
	    printf "Grid(src): ${grd_src}\n"
	    printf "Grid(dst): ${grd_dst}\n"
	fi # !vrb_lvl
	if [ "${wgt_typ}" = 'esmf' ]; then
	    rgn_opt=''
	    if [ -n "${hnt_src}" ]; then
		rgn_opt="${rgn_opt} ${hnt_src}"
	    elif [ -f "${hnt_src_fl}" ]; then
		rgn_opt="${rgn_opt} `cat ${hnt_src_fl}`"
	    fi # !hnt_src_fl
	    if [ -n "${hnt_dst}" ]; then
		rgn_opt="${rgn_opt} ${hnt_dst}"
	    elif [ -f "${hnt_dst_fl}" ]; then
		rgn_opt="${rgn_opt} `cat ${hnt_dst_fl}`"
	    fi # !hnt_dst_fl
	    cmd_map[${fl_idx}]="${wgt_cmd} -s \"${grd_src}\" -d \"${grd_dst}\" -w \"${map_fl}\" --method ${alg_opt} ${wgt_opt} ${rgn_opt} > /dev/null"
	fi # !esmf
	if [ "${wgt_typ}" = 'tempest' ]; then
	    printf "Mesh-File: ${msh_fl}\n"
	    cmd_msh[${fl_idx}]="GenerateOverlapMesh --a \"${grd_src}\" --b \"${grd_dst}\" --out \"${msh_fl}\" > /dev/null"
	    if [ "${a2o_flg}" = 'Yes' ]; then
		cmd_msh[${fl_idx}]="GenerateOverlapMesh --b \"${grd_src}\" --a \"${grd_dst}\" --out \"${msh_fl}\" > /dev/null"
	    fi # !a2o_flg
	    cmd_map[${fl_idx}]="${wgt_cmd} --in_mesh \"${grd_src}\" --out_mesh \"${grd_dst}\" --ov_mesh \"${msh_fl}\" --out_map \"${map_fl}\" ${wgt_opt} > /dev/null"
	    if [ "${trn_map}" = 'Yes' ]; then
		# NB: Generate mono map for opposite direction regridding (i.e., reverse switches and grids), then transpose
		cmd_map[${fl_idx}]="${wgt_cmd} --in_mesh \"${grd_dst}\" --out_mesh \"${grd_src}\" --ov_mesh \"${msh_fl}\" --out_map \"${map_trn_fl}\" ${wgt_opt} > /dev/null"
		cmd_trn[${fl_idx}]="GenerateTransposeMap --in \"${map_trn_fl}\" --out \"${map_fl}\" > /dev/null"
	    fi # !trn_map
	    if [ ${dbg_lvl} -ge 1 ]; then
		echo ${cmd_msh[${fl_idx}]}
	    fi # !dbg
	    if [ ${dbg_lvl} -ne 2 ]; then
		eval ${cmd_msh[${fl_idx}]}
		if [ "$?" -ne 0 ] || [ ! -f ${msh_fl} ]; then
		    printf "${spt_nm}: ERROR Failed to generate intersection mesh-file. Debug this:\n${cmd_msh[${fl_idx}]}\n"
		    printf "${spt_nm}: HINT GenerateOverlapMesh requires that grids of unequal area be given as arguments in the order smaller first, larger second. ncremap supplies the grid arguments in the order source first, destination second unless explicitly told otherwise. A source grid that is a superset of the destination would violate the GenerateOverlapMesh rule. The solution is to add the \"--a2o\" switch (documented at http://nco.sf.net/nco.html#a2o) that tells ncremap to swap the grid argument order.\n"
		    exit 1
		fi # !err
	    fi # !dbg
	fi # !tempest

	# Block 3 Loop 2: Execute and/or echo commands
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_map[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_map[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${map_rsl_fl} ]; then
		printf "${spt_nm}: ERROR Failed to generate map-file. Debug this:\n${cmd_map[${fl_idx}]}\n"
		if [ "${wgt_typ}" = 'esmf' ]; then
		    printf "${spt_nm}: HINT When ESMF fails to generate map-files, it often puts additional debugging information in the file named PET0.RegridWeightGen.Log in the invocation directory (${drc_pwd})\n"
		fi # !esmf
		exit 1
	    fi # !err
	    if [ "${map_usr_flg}" = 'Yes' ]; then
		hst_att="`date`: ${cmd_ln};${cmd_map[${fl_idx}]}"
		cmd_att[${fl_idx}]="ncatted -O ${gaa_sng} --gaa history='${hst_att}' \"${map_rsl_fl}\""
		eval ${cmd_att[${fl_idx}]}
		if [ "$?" -ne 0 ]; then
		    printf "${spt_nm}: ERROR Failed to annotate map-file. Debug this:\n${cmd_att[${fl_idx}]}\n"
		    exit 1
		fi # !err
	    fi # !map_usr_flg
	fi # !dbg
	if [ "${trn_map}" = 'Yes' ]; then
	    if [ ${dbg_lvl} -ge 1 ]; then
		echo ${cmd_trn[${fl_idx}]}
	    fi # !dbg
	    if [ ${dbg_lvl} -ne 2 ]; then
		eval ${cmd_trn[${fl_idx}]}
		if [ "$?" -ne 0 ] || [ ! -f ${map_fl} ]; then
		    printf "${spt_nm}: ERROR Failed to transpose map-file. Debug this:\n${cmd_trn[${fl_idx}]}\n"
		    exit 1
		fi # !err
	    fi # !dbg
	fi # !trn_map

	# Prevent creating new source gridfile and map-file after first iteration
	if [ "${mlt_map_flg}" = 'No' ] && [ ${fl_idx} -eq 0 ]; then
	    map_mk='Already made map once. Never again.'
	fi # !mlt_map_flg

    fi # !map_mk

    # Block 4: Special cases
    # Block 4a: Add MPAS depth coordinate (prior to permutation)
    if [ "${dpt_flg}" = 'Yes' ]; then
	if [ ${vrb_lvl} -ge ${vrb_2} ]; then
	    printf "DPT(in)  : ${in_fl}\n"
	    printf "DPT(out) : ${dpt_tmp_fl}\n"
	fi # !vrb_lvl
	cmd_dpt[${fl_idx}]="${cmd_dpt_mpas} ${cmd_dpt_opt} -i \"${in_fl}\" -o \"${dpt_tmp_fl}\""
	in_fl=${dpt_tmp_fl}
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_dpt[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_dpt[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${dpt_tmp_fl} ]; then
		printf "${spt_nm}: ERROR Failed to add depth coordinate to MPAS file. Debug this:\n${cmd_dpt[${fl_idx}]}\nHINTS: 1) Verify that ${dpt_exe_mpas} is executable from the command-line, it requires Python and the xarray package to succeed. 2) Verify that ${dpt_fl} or ${in_fl} contains variable \"refBottomDepth\".\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !dpt_flg

    # Block 4b: Generic Permutation/Unpacking (AIRS, HIRDLS, MLS, MOD04, MPAS)
    # Do sub-setting operation (like PDQ) first so cmd_att works on smaller, sub-set files
    if [ -n "${pdq_opt}" ]; then
	if [ ${vrb_lvl} -ge ${vrb_2} ]; then
	    printf "PDQ(in)  : ${in_fl}\n"
	    printf "PDQ(out) : ${pdq_fl}\n"
	fi # !vrb_lvl
	cmd_pdq[${fl_idx}]="ncpdq -O ${nco_opt} ${nco_var_lst} ${pdq_opt} \"${in_fl}\" \"${pdq_fl}\""
	in_fl=${pdq_fl}
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_pdq[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_pdq[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${pdq_fl} ]; then
		printf "${spt_nm}: ERROR Failed to generate pdq-file. Debug this:\n${cmd_pdq[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !pdq_opt

    # Block 4c: Double->Float conversion (by-request and possibly default for MPAS)
    if [ "${d2f_flg}" = 'Yes' ]; then
	if [ ${vrb_lvl} -ge ${vrb_2} ]; then
	    printf "D2F(in)  : ${in_fl}\n"
	    printf "D2F(out) : ${d2f_fl}\n"
	fi # !vrb_lvl
	cmd_d2f[${fl_idx}]="ncpdq -O ${nco_opt} ${nco_var_lst} ${d2f_opt} \"${in_fl}\" \"${d2f_fl}\""
	in_fl=${d2f_fl}
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_d2f[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_d2f[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${d2f_fl} ]; then
		printf "${spt_nm}: ERROR Failed to convert double-precision to single-precision. Debug this:\n${cmd_d2f[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !d2f_flg

    # Block 4d: Add missing metadata to MPAS files unless script was invoked by ncclimo (it makes no sense to give naked files to ncclimo and then to annotate them here, so assume ncclimo is working with annotated files)
    if [ "${prc_mpas}" = 'Yes' ] && [ "${clm_flg}" = 'No' ]; then
	cmd_att[${fl_idx}]="ncatted -O -t -a _FillValue,,o,d,${mss_val} -a _FillValue,,o,f,${mss_val} \"${in_fl}\" \"${att_fl}\";"
	if [ ${vrb_lvl} -ge ${vrb_2} ]; then
	    printf "att(in)  : ${in_fl}\n"
	    printf "att(out) : ${att_fl}\n"
	fi # !vrb_lvl
	in_fl="${att_fl}"
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_att[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_att[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f "${att_fl}" ]; then
		printf "${spt_nm}: ERROR Failed to annotate MPAS file with _FillValue. Debug this:\n${cmd_att[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !prc_mpas

    # Block 4e: RRG
    if [ "${prc_typ}" = 'rrg' ]; then
	rrg_dmn_lst=`ncdmnlst ${fl_in[${fl_idx}]} | grep ${rnm_sng}`
	rrg_var_lst=`ncvarlst ${fl_in[${fl_idx}]} | grep ${rnm_sng}`

	dmn_sng=''
	if [ -n "${rrg_dmn_lst}" ]; then
	    for dmn in ${rrg_dmn_lst} ; do
		dmn_sng="${dmn_sng} -d ${dmn},${dmn/${rnm_sng}/}"
	    done # !dmn
	else # !rrg_dmn_lst
	    echo "ERROR: Regional regridding suffix string '${rnm_sng}' not found in any dimension names in ${fl_in[${fl_idx}]}"
	    echo "HINT: Regional regridding input files must contain dimensions and variables whose names end with the ALM/CAM-SE created (from finclNlonlat namelist input) regional suffix string, e.g., '_128e_to_134e_9s_to_16s'. Valid regional suffix strings for this input file are:"
	    eval "ncks -m ${fl_in[${fl_idx}]} | cut -d ':' -f 1 | cut -d '=' -s -f 1 | grep ncol | sed 's/ncol//' | sed -e 's/^ *//' -e 's/ *$//'"
	    echo "Use exactly one of these strings as the argument to --rrg_rnm_sng"
	    exit 1
	fi # !rrg_dmn_lst

	var_sng=''
	if [ -n "${rrg_var_lst}" ]; then
	    for var in ${rrg_var_lst} ; do
		var_sng="${var_sng} -v ${var},${var/${rnm_sng}/}"
	    done # !rrg_var_lst
	fi # !rrg_var_lst

	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "RRG: Remove \"${rnm_sng}\" from dimension and variable names...\n"
	fi # !vrb_lvl
	cmd_rnm[${fl_idx}]="ncrename -O ${dmn_sng} ${var_sng} \"${fl_in[${fl_idx}]}\" \"${rnm_fl}\""
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_rnm[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_rnm[${fl_idx}]}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to rename regional input file. Debug this:\n${cmd_rnm[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg

	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "RRG: Append regional coordinates and vertices to renamed, annotated regional input data...\n"
	fi # !vrb_lvl
	cmd_apn[${fl_idx}]="ncks -A \"${rgn_fl}\" \"${rnm_fl}\""
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_apn[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_apn[${fl_idx}]}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to append regional coordinates and vertices to annotated, regional input data. Debug this:\n${cmd_apn[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
	in_fl=${rnm_fl}
    fi # !rrg

    # Block 5: Regrid
    if [ ${vrb_lvl} -ge ${vrb_1} ]; then
	printf "Map/Wgt  : ${map_fl}\n"
	printf "Regridded: ${out_fl}\n"
    fi # !vrb_lvl
    cmd_rgr[${fl_idx}]="${cmd_mpi[${fl_idx}]} ncks -O -t ${thr_nbr} ${nco_opt} ${nco_var_rgr} ${nco_var_lst} ${nco_msk_out} ${rgr_opt} --map=\"${map_fl}\" \"${in_fl}\" \"${out_fl}\""

    # Block 5 Loop 2: Execute and/or echo commands
    if [ ${dbg_lvl} -ge 1 ]; then
	echo ${cmd_rgr[${fl_idx}]}
    fi # !dbg
    if [ ${dbg_lvl} -ne 2 ]; then
	if [ -z "${par_opt}" ]; then
	    eval ${cmd_rgr[${fl_idx}]}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to regrid. cmd_rgr[${fl_idx}] failed. Debug this:\n${cmd_rgr[${fl_idx}]}\n"
		exit 1
	    fi # !err
	else # !par_typ
	    eval ${cmd_rgr[${fl_idx}]} ${par_opt}
	    rgr_pid[${fl_idx}]=$!
	fi # !par_typ
    fi # !dbg

    # Block 6: Wait
    # Parallel regridding (both Background and MPI) spawns simultaneous processes in batches of ${job_nbr}
    # Once ${job_nbr} jobs are running, wait() for all to finish before issuing another batch
    if [ -n "${par_opt}" ]; then
	let bch_idx=$((fl_idx / job_nbr))
	let bch_flg=$(((fl_idx+1) % job_nbr))
	#printf "${spt_nm}: fl_idx = ${fl_idx}, bch_idx = ${bch_idx}, bch_flg = ${bch_flg}\n"
	if [ ${bch_flg} -eq 0 ]; then
	    if [ ${dbg_lvl} -ge 1 ] && [ ${idx_srt} -le ${idx_end} ]; then
		printf "${spt_nm}: Waiting for batch ${bch_idx} to finish at fl_idx = ${fl_idx}...\n"
	    fi # !dbg
	    for ((pid_idx=${idx_srt};pid_idx<=${idx_end};pid_idx++)); do
		wait ${rgr_pid[${pid_idx}]}
		if [ "$?" -ne 0 ]; then
		    printf "${spt_nm}: ERROR Failed to regrid. cmd_rgr[${pid_idx}] failed. Debug this:\n${cmd_rgr[${pid_idx}]}\n"
		    exit 1
		fi # !err
	    done # !pid_idx
	    let idx_srt=$((idx_srt + job_nbr))
	    let idx_end=$((idx_end + job_nbr))
	fi # !bch_flg
    fi # !par_typ

    # Block 7: Special case post-processing
    if [ "${prc_typ}" = 'hirdls' ] || [ "${prc_typ}" = 'mls' ]; then
	# NB: Move file to avert problem with --no_tmp_fl causing self-overwrite
	cmd_znl[${fl_idx}]="/bin/mv \"${out_fl}\" \"${ncwa_fl}\";ncwa -O -a lon ${nco_opt} ${nco_var_lst} \"${ncwa_fl}\" \"${out_fl}\""
	# Block 7 Loop 2: Execute and/or echo commands
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_znl[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_znl[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f "${out_fl}" ]; then
		printf "${spt_nm}: ERROR Failed to generate zonal file from lat-lon file. Debug this:\n${cmd_znl[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
    fi # !znl

done # !fl_idx

echo "spot 16"

# Parallel mode might exit loop after a partial batch, wait() for remaining jobs to finish
if [ -n "${par_opt}" ]; then
    let bch_flg=$((fl_nbr % job_nbr))
    if [ ${bch_flg} -ne 0 ]; then
	let bch_idx=$((bch_idx+1))
	if [ ${dbg_lvl} -ge 1 ] && [ ${idx_srt} -lt ${fl_nbr} ]; then
	    printf "${spt_nm}: Waiting for (partial) batch ${bch_idx} to finish...\n"
	fi # !idx_srt
	for ((pid_idx=${idx_srt};pid_idx<${fl_nbr};pid_idx++)); do
	    wait ${rgr_pid[${pid_idx}]}
	    if [ "$?" -ne 0 ]; then
		printf "${spt_nm}: ERROR Failed to regrid. cmd_rgr[${pid_idx}] failed. Debug this:\n${cmd_rgr[${pid_idx}]}\n"
		exit 1
	    fi # !err
	done # !pid_idx
    fi # !bch_flg
fi # !par_typ

echo "spot 17"

# fxm: Parallelize post-processing, if any
if [ "${prc_typ}" = 'sgs' ]; then
    for ((fl_idx=0;fl_idx<${fl_nbr};fl_idx++)); do
	if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	    printf "SGS: Append full gridcell area, regridded sub-grid fraction, and re-derived sub-grid mask to regridded file...\n"
	fi # !vrb_lvl
	# Replace user-areas area, user-areas sub-grid fraction, and naïvely regridded (rather than accurately re-derived) sub-grid mask, respectively
	cmd_sgs_rpl[${fl_idx}]="ncks -A -C -v area,${sgs_frc},${sgs_msk} \"${frc_out_sgs}\" \"${fl_out[${fl_idx}]}\""
	if [ ${dbg_lvl} -ge 1 ]; then
	    echo ${cmd_sgs_rpl[${fl_idx}]}
	fi # !dbg
	if [ ${dbg_lvl} -ne 2 ]; then
	    eval ${cmd_sgs_rpl[${fl_idx}]}
	    if [ "$?" -ne 0 ] || [ ! -f ${fl_out[${fl_idx}]} ]; then
		printf "${spt_nm}: ERROR Failed to replace area, ${sgs_frc}, and ${sgs_msk} with full gridcell area, regridded sub-grid fraction, and re-derived sub-grid mask in output data file. Debug this:\n${cmd_sgs_rpl[${fl_idx}]}\n"
		exit 1
	    fi # !err
	fi # !dbg
	if [ -n "${prc_elm}" ]; then
	    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
		printf "SGS: Implement idiosyncratic ALM/CLM/CTSM/ELM characteristics in regridded file...\n"
	    fi # !vrb_lvl
	    # Convert area from [sr] to [km2]
	    cmd_elm[${fl_idx}]="ncap2 -O -s 'area*=${rds_rth}^2/1.0e6;area@long_name=\"Gridcell area\";area@units=\"km^2\"' \"${fl_out[${fl_idx}]}\" \"${fl_out[${fl_idx}]}\""
	    if [ ${dbg_lvl} -ge 1 ]; then
		echo ${cmd_elm[${fl_idx}]}
	    fi # !dbg
	    if [ ${dbg_lvl} -ne 2 ]; then
		eval ${cmd_elm[${fl_idx}]}
		if [ "$?" -ne 0 ] || [ ! -f ${fl_out[${fl_idx}]} ]; then
		    printf "${spt_nm}: ERROR Failed to convert output area from [sr] to [km2]. Debug this:\n${cmd_elm[${fl_idx}]}\n"
		    exit 1
		fi # !err
	    fi # !dbg
	fi # !prc_elm
	if [ -n "${prc_cice}" ]; then
	    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
		printf "SGS: Implement idiosyncratic CICE characteristics in regridded file...\n"
	    fi # !vrb_lvl
	    # Convert area from [sr] to [m2], and aice from [frc] to [%]
	    cmd_cice[${fl_idx}]="ncap2 -O -s 'area*=${rds_rth}^2;area@long_name=\"Gridcell area\";area@units=\"m^2\";${sgs_frc}*=100;${sgs_frc}@units=\"%\"' \"${fl_out[${fl_idx}]}\" \"${fl_out[${fl_idx}]}\""
	    if [ ${dbg_lvl} -ge 1 ]; then
		echo ${cmd_cice[${fl_idx}]}
	    fi # !dbg
	    if [ ${dbg_lvl} -ne 2 ]; then
		eval ${cmd_cice[${fl_idx}]}
		if [ "$?" -ne 0 ] || [ ! -f ${fl_out[${fl_idx}]} ]; then
		    printf "${spt_nm}: ERROR Failed to convert output area from [sr] to [m2] and ${sgs_frc} from [frc] to [%]. Debug this:\n${cmd_cice[${fl_idx}]}\n"
		    exit 1
		fi # !err
	    fi # !dbg
	fi # !prc_cice
	if [ -n "${prc_mpascice}" ]; then
	    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
		printf "SGS: Implement idiosyncratic MPAS-CICE characteristics in regridded file...\n"
	    fi # !vrb_lvl
	    # Add units to sgs_frc
	    cmd_mpascice[${fl_idx}]="ncap2 -O -s '${sgs_frc}@units=\"1.0\"' \"${fl_out[${fl_idx}]}\" \"${fl_out[${fl_idx}]}\""
	    if [ ${dbg_lvl} -ge 1 ]; then
		echo ${cmd_mpascice[${fl_idx}]}
	    fi # !dbg
	    if [ ${dbg_lvl} -ne 2 ]; then
		eval ${cmd_mpascice[${fl_idx}]}
		if [ "$?" -ne 0 ] || [ ! -f ${fl_out[${fl_idx}]} ]; then
		    printf "${spt_nm}: ERROR Failed to add units to ${sgs_frc}. Debug this:\n${cmd_mpascice[${fl_idx}]}\n"
		    exit 1
		fi # !err
	    fi # !dbg
	fi # !prc_mpascice
    done # !fl_idx
fi # !sgs

echo "spot 18"

if [ "${cln_flg}" = 'Yes' ]; then
    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "Clean-up intermediate files...\n"
    fi # !vrb_lvl
    /bin/rm -f ${att_fl} ${d2f_fl} ${dmm_fl} ${dpt_tmp_fl} ${frc_in_sgs} ${frc_out_sgs} ${grd_dst_sgs} ${grd_dst_dfl} ${grd_src_sgs} ${grd_src_dfl} ${hnt_dst_fl} ${hnt_src_fl} ${map_fl_dfl} ${map_trn_fl} ${msh_fl_dfl} ${ncwa_fl} ${nnt_fl} ${pdq_fl} ${rgn_fl} ${rnm_fl} ${tmp_out_fl} ${znl_fl/znl/znl1} ${znl_fl/znl/znl2}
else # !cln_flg
    if [ ${vrb_lvl} -ge ${vrb_3} ]; then
	printf "Explicitly instructed not to clean-up intermediate files.\n"
    fi # !vrb_lvl
fi # !cln_flg

echo "spot 19"

date_end=$(date +"%s")
if [ ${vrb_lvl} -ge ${vrb_3} ]; then
    if [ ${fl_nbr} -eq 0 ]; then
	printf "Completed generating map/grid-file(s) at `date`.\n"
    else # !fl_nbr
	echo "Quick plots of results from last regridded file:"
	echo "ncview  ${out_fl} &"
	echo "panoply ${out_fl} &"
    fi # !fl_nbr
    date_dff=$((date_end-date_srt))
    echo "Elapsed time $((date_dff/60))m$((date_dff % 60))s"
fi # !vrb_lvl

echo "spot 20"

exit 0
