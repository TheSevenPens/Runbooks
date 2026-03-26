@REM Copyright (C) 2012 Anaconda, Inc
@REM SPDX-License-Identifier: BSD-3-Clause

@REM Replaced by mamba executable with the MAMBA_EXE and MAMBA_ROOT_PREFIX variable pointing
@REM to the correct locations.
@SET "MAMBA_EXE=C:\Users\seven\miniconda3\Scripts\micromamba.exe"
@SET "MAMBA_ROOT_PREFIX=C:Userssevenmicromamba"

@IF [%1]==[activate]   "%~dp0_micromamba_activate" %*
@IF [%1]==[deactivate] "%~dp0_micromamba_activate" %*

@CALL "%MAMBA_EXE%" %*

@IF %errorlevel% NEQ 0 EXIT /B %errorlevel%

@IF [%1]==[install]   "%~dp0_micromamba_activate" reactivate
@IF [%1]==[update]    "%~dp0_micromamba_activate" reactivate
@IF [%1]==[upgrade]   "%~dp0_micromamba_activate" reactivate
@IF [%1]==[remove]    "%~dp0_micromamba_activate" reactivate
@IF [%1]==[uninstall] "%~dp0_micromamba_activate" reactivate
@IF [%1]==[self-update] @CALL DEL /f %MAMBA_EXE%.bkup

@EXIT /B %errorlevel%
