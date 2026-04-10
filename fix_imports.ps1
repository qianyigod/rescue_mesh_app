# 批量替换测试文件中的包名
$testDir = "test"
$oldPackage = "package:rescue_mesh_app/"
$newPackage = "package:life_network/"

Get-ChildItem -Path $testDir -Recurse -Filter *.dart | ForEach-Object {
    Write-Host "Processing: $($_.Name)"
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    $updated = $content -replace [regex]::Escape($oldPackage), $newPackage
    Set-Content $_.FullName -Value $updated -NoNewline -Encoding UTF8
}

Write-Host "Done! All imports updated from rescue_mesh_app to life_network"
