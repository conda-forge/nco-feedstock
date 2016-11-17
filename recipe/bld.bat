if "%ARCH%" == "64" (
   set ARCH=x64
) else (
   set ARCH=Win32
)

:: Libraries flags.
set LIB_HDF5=%LIBRARY_LIB%\hdf5.lib ^
    LIB_HDF5_HL=%LIBRARY_LIB%\hdf5_hl.lib ^
    LIB_NETCDF=%LIBRARY_LIB%\netcdf.lib ^
    LIB_ZLIB=%LIBRARY_LIB%\zlibstatic.lib ^
    LIB_CURL=%LIBRARY_LIB%\libcurl.lib ^
    LIB_UDUNITS=%LIBRARY_LIB%\udunits2.lib ^
    LIB_EXPAT=%LIBRARY_LIB%\expat.lib
rem  LIB_GSL
rem  LIB_ANTLR

:: Headers flags.
set HEADER_NETCDF=%LIBRARY_INC% ^
    HEADER_UDUNITS=%LIBRARY_INC%
rem  HEADER_GSL
rem  HEADER_ANTLR

cd qt
if errorlevel 1 exit 1

qmake
if errorlevel 1 exit 1

msbuild nco.sln /p:Configuration="Release" /p:Platform="%ARCH%" /verbosity:normal
if errorlevel 1 exit 1
