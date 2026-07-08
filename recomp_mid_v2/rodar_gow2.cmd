@echo off
rem God of War II HD recompilado — launcher com o ambiente correto
rem Intro em video+audio (ffmpeg/overlay) + jogo rodando por baixo (D3D12)
cd /d "%~dp0"

set PS3_MOVIE_HLE=1
set PS3_NOMOVIES=1
set PS3_PAD_AUTOSTART=1
set PS3_RSX_BACKEND=d3d12
set PS3_RSX_FIFO=1
set PS3_VFS_ROOT=../extracted/USRDIR
set PS3_CELLSYS_REORDER=1

boot_v2_new.exe ../EBOOT.ELF
pause
