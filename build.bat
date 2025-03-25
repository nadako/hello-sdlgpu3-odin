shadercross content/shaders/src/shader.frag.hlsl -o content/shaders/out/shader.frag.spv
if %errorlevel% neq 0 exit /b 1

shadercross content/shaders/src/shader.vert.hlsl -o content/shaders/out/shader.vert.spv
if %errorlevel% neq 0 exit /b 1

odin build src -debug -out:hello-sdl3.exe
if %errorlevel% neq 0 exit /b 1

if "%~1" == "run" (
	hello-sdl3.exe
)
