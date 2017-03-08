mkdir %SRC_DIR%\build
cd %SRC_DIR%\build

cmake -G "NMake Makefiles" ^
      -D CMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
      -D CMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
      -D BUILD_SHARED_LIBS=ON ^
      -D CMAKE_BUILD_TYPE=Release ^
      -D NETCDF_INCLUDE=%LIBRARY_INC% ^
      -D NETCDF_LIBRARY=%LIBRARY_LIB%\lib\netcdf.lib ^
      -D HDF5_LIBRARY=%LIBRARY_LIB%\lib\libhdf.lib ^
      -D HDF5_HL_LIBRARY=%LIBRARY_LIB%\lib\libhdf_hl.lib ^
      -D ZLIB_LIBRARY=%LIBRARY_LIB%\zlib.lib ^
      -D CURL_LIBRARY="%LIBRARY_LIB%\libcurl.lib wsock32.lib wldap32.lib winmm.lib" ^
      -D CMAKE_C_FLAGS="-Drestrict=__restrict" ^
      %SRC_DIR%
if errorlevel 1 exit 1


:: -D ZLIB_INCLUDE_DIR=%LIBRARY_INC% ^
:: -D HDF5_INCLUDE_DIR=%LIBRARY_PREFIX%\include ^
:: -D HDF5_LIB_PATH=%LIBRARY_PREFIX%\lib ^
:: -D HDF5_LIB=%LIBRARY_LIB%\hdf5.lib ^
:: SZIP_LIBRARY

nmake
if errorlevel 1 exit 1

nmake install
if errorlevel 1 exit 1
