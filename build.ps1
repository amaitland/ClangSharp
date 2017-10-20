#requires -Version 3

param(
    [Parameter(Position = 0)]
    [string] $ClangVersion = "3.9.0",
    [Parameter(Position = 1)]
    [string] $TargetClangVersion = "3.9.0"
)

#TODO Better param names
# Two different versions are required, one for the current clang version that's supported
# and one for the version we are upgrading to

$WorkingDir = split-path -parent $MyInvocation.MyCommand.Definition
$programFilesDir = (${env:ProgramFiles(x86)}, ${env:ProgramFiles} -ne $null)[0]

Write-Host "Working Directory $WorkingDir" -ForegroundColor Green

$client = New-Object System.Net.WebClient;

$vswherePath = Join-Path $programFilesDir 'Microsoft Visual Studio\Installer\vswhere.exe'
#Check if we already have vswhere which is included in newer versions of VS2017 installer
if(-not (Test-Path $vswherePath))
{
    # Download vswhere if we don't have a copy
    $vswherePath = Join-Path $WorkingDir \vswhere.exe
    
    # TODO: Check hash and download if hash differs
    if(-not (Test-Path $vswherePath))
    {
	    $client.DownloadFile('https://github.com/Microsoft/vswhere/releases/download/2.2.7/vswhere.exe', $vswherePath);
    }
}

#Check for 7zip
if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe"))
{
	Write-Error "$env:ProgramFiles\7-Zip\7z.exe is required"
    Write-Error "Alternatively download the llvm installer from http://releases.llvm.org/download.html and manually extract it into the $ClangLocalPath"
    exit 1
}

set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"

$TargetClangLocalPath = Join-Path $WorkingDir "llvm\$TargetClangVersion"

#Download clang if this is the first run, this requires 7zip
if(-not (Test-Path $TargetClangLocalPath) -or -not (Test-Path "$TargetClangLocalPath\bin\libclang.dll"))
{
    if(-not (Test-Path "$TargetClangLocalPath\$clangExe"))
    {
        New-Item -ItemType Directory -Force -Path $TargetClangLocalPath
        $arch = "win32"
        if([environment]::Is64BitProcess)
        {
            $arch = "win64"
        }
	    $clangExe = "LLVM-$TargetClangVersion-$arch.exe"
	    $remoteUrl = "http://releases.llvm.org/$TargetClangVersion/$clangExe"
	    Write-Host "Download $remoteUrl this will take a while as file is approx 50mb each" -ForegroundColor Green
	    $client.DownloadFile($remoteUrl, "$TargetClangLocalPath\$clangExe");
	    Write-Host "Download $remoteUrl complete" -ForegroundColor Green
    }

    #Extract exe with 7z (Was unable to make built in zip functions work with the installer)    
    sz x "$TargetClangLocalPath\$clangExe" "-o$ClangLocalPath"
}

$ClangLocalPath = Join-Path $WorkingDir "llvm\$ClangVersion"
#Download clang if this is the first run, this requires 7zip
if(-not (Test-Path $ClangLocalPath) -or -not (Test-Path "$ClangLocalPath\bin\libclang.dll"))
{
    if(-not (Test-Path "$ClangLocalPath\$clangExe"))
    {
        New-Item -ItemType Directory -Force -Path $ClangLocalPath
        $arch = "win32"
        if([environment]::Is64BitProcess)
        {
            $arch = "win64"
        }
	    $clangExe = "LLVM-$ClangVersion-$arch.exe"
	    $remoteUrl = "http://releases.llvm.org/$ClangVersion/$clangExe"
	    Write-Host "Download $remoteUrl this will take a while as file is approx 50mb each" -ForegroundColor Green
	    $client.DownloadFile($remoteUrl, "$ClangLocalPath\$clangExe");
	    Write-Host "Download $remoteUrl complete" -ForegroundColor Green
    }

    #Extract exe with 7z (Was unable to make built in zip functions work with the installer)    
    sz x "$ClangLocalPath\$clangExe" "-o$ClangLocalPath"
}

#Always copy libclang.dll - if we switch versions without redownloading then it's possible we'd end up with the incorrect version otherwise
Copy-Item -Force "$ClangLocalPath\bin\libclang.dll" $WorkingDir

#Locate the installed instance of VS2017
$VsProductIds = 'Community', 'Professional', 'Enterprise', 'BuildTools' | foreach { 'Microsoft.VisualStudio.Product.' + $_ }
$VsInstalledInstance = & $vswherePath -version 15 -products $VsProductIds -requires 'Microsoft.Component.MSBuild' -format json `
	| convertfrom-json `
	| select-object -first 1
	
if($VsInstalledInstance -eq $null)
{
	Write-Error "Visual Studio 2017 was not found"
	exit 1
}
	
# Compile ClangSharpPInvokeGenerator
Write-Host Compiling ClangSharpPInvokeGenerator -ForegroundColor Green
$CSC = Join-Path $VsInstalledInstance.installationPath MSBuild\15.0\Bin\Roslyn\csc
& $CSC /out:ClangSharpPInvokeGenerator.exe (Join-Path $WorkingDir "ClangSharpPInvokeGenerator\*.cs")

#Build command line args for ClangSharpPInvokeGenerator
$IncludePath = Join-Path $ClangLocalPath "\include"
$HeaderFiles = '/clang-c/Index.h', '/clang-c/CXString.h', '/clang-c/Documentation.h', '/clang-c/CXErrorCode.h', '/clang-c/BuildSystem.h', '/clang-c/CXCompilationDatabase.h' | foreach { '--file ' + (Join-Path $IncludePath  $_ )}
$GenerateCommandLineArgs = "--m clang --p clang_ --namespace ClangSharp --output $WorkingDir\Generated.cs --libraryPath libclang --include $IncludePath $HeaderFiles"

Write-Host "ClangSharpPInvokeGenerator $GenerateCommandLineArgs" -ForegroundColor Green

#Execute ClangSharpPInvokeGenerator.exe 
& (Join-Path $WorkingDir 'ClangSharpPInvokeGenerator.exe') $GenerateCommandLineArgs

Write-Host "Complete" -ForegroundColor Green