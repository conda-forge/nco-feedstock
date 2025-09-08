:: Antlr

cd antlr2-src
@echo on
setlocal EnableExtensions

set "PLATFORM=x64"

rem VS environment
call "%VSINSTALLDIR%VC\Auxiliary\Build\vcvars64.bat"

rem Exact Windows SDK version (e.g., 10.0.26100.0)
set "SDKVER=%WindowsSDKVersion%"
if defined SDKVER (
  set "SDKVER=%SDKVER:\=%"
  if "%SDKVER:~-1%"=="\" set "SDKVER=%SDKVER:~0,-1%"
) else set "SDKVER=10.0"

rem --- Sanity check: the ANTLR2 runtime sources must be here:
echo Listing %SRC_DIR%\lib\cpp\src
dir /b "%SRC_DIR%\lib\cpp\src" || echo (dir failed)

if not exist "%SRC_DIR%\lib\cpp\src\ANTLRUtil.cpp" (
  echo ERROR: Missing runtime sources under %SRC_DIR%\lib\cpp\src
  echo Showing what exists under %SRC_DIR%\lib\cpp:
  dir /s /b "%SRC_DIR%\lib\cpp"
  exit /b 1
)

copy "%RECIPE_DIR%\antlr.vcxproj" "%SRC_DIR%\lib\cpp\" || exit 1

pushd "%SRC_DIR%\lib\cpp"

msbuild.exe "antlr.vcxproj" ^
  /m ^
  /p:Platform=%PLATFORM% ^
  /p:Configuration=Release ^
  /p:PlatformToolset=v143 ^
  /p:WindowsTargetPlatformVersion=%SDKVER% ^
  /p:PreferredToolArchitecture=x64
if errorlevel 1 exit 1
popd

if not exist "%LIBRARY_LIB%" mkdir "%LIBRARY_LIB%"
if not exist "%LIBRARY_INC%\antlr" mkdir "%LIBRARY_INC%\antlr"

copy /y "%SRC_DIR%\lib\cpp\build\%PLATFORM%\Release\antlr.lib" "%LIBRARY_LIB%\antlr.lib" || exit 1
copy /y "%SRC_DIR%\lib\cpp\antlr\*.hpp" "%LIBRARY_INC%\antlr\" || exit 1

endlocal

cd ..

:: NCO

cd nco-src

mkdir %SRC_DIR%\build
cd %SRC_DIR%\build

set "CFLAGS=%CFLAGS% -DWIN32 -DGSL_DLL"
set "CXXFLAGS=%CXXFLAGS% -DWIN32 -DGSL_DLL"

cmake -G "NMake Makefiles" ^
      -D CMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
      -D CMAKE_BUILD_TYPE=Release ^
      -D MSVC_USE_STATIC_CRT=OFF ^
      -D CMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
      -D NETCDF_INCLUDE=%LIBRARY_INC% ^
      -D NETCDF_LIBRARY=%LIBRARY_LIB%\netcdf.lib ^
      -D HDF5_LIBRARY=%LIBRARY_LIB%\hdf5.lib ^
      -D HDF5_HL_LIBRARY=%LIBRARY_LIB%\hdf5_hl.lib ^
      -D GSL_INCLUDE=%LIBRARY_INC% ^
      -D GSL_LIBRARY=%LIBRARY_LIB%\gsl.lib ^
      -D GSL_CBLAS_LIBRARY=%LIBRARY_LIB%\gslcblas.lib ^
      -D UDUNITS2_INCLUDE=%LIBRARY_LIB% ^
      -D UDUNITS2_LIBRARY=%LIBRARY_LIB%\udunits2.lib ^
      -D EXPAT_LIBRARY=%LIBRARY_LIB%\expat.lib ^
      -D CURL_LIBRARY=%LIBRARY_LIB%\libcurl.lib ^
      -D ANTLR_INCLUDE:PATH=%LIBRARY_INC%\antlr ^
      -D CMAKE_CXX_STANDARD=14 ^
      -D CMAKE_CXX_STANDARD_REQUIRED=ON ^
      %SRC_DIR%
if errorlevel 1 exit 1


nmake
if errorlevel 1 exit 1

nmake install
if errorlevel 1 exit 1

move %LIBRARY_PREFIX%\*.exe %LIBRARY_BIN% || exit 1

rmdir /s /q  "%LIBRARY_INC%\antlr"
del "%LIBRARY_LIB%\antlr.lib"

cd ..