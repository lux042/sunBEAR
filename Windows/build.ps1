$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & dotnet publish .\sunBEAR.csproj -c Release -r win-x64 --self-contained true -o .\publish
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    Write-Host 'Windows app created in the publish folder. Open sunBEAR.exe.'
}
finally { Pop-Location }
