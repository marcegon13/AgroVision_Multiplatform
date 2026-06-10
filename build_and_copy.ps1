# Script para compilar el APK de producción optimizado con split-per-abi y copiarlo a D:\
Write-Host "Limpiando caché del proyecto..."
C:\src\flutter\bin\flutter.bat clean
Write-Host "Obteniendo dependencias..."
C:\src\flutter\bin\flutter.bat pub get

Write-Host "1/2: Ejecutando flutter build apk --release --split-per-abi..."

# Ejecutar la compilación nativa apuntando a la ruta exacta del SDK en Marcelo's Machine
C:\src\flutter\bin\flutter.bat build apk --release --split-per-abi

if ($LASTEXITCODE -eq 0) {
    Write-Host "Compilación exitosa de APKs divididos por ABI."
    Write-Host "2/2: Copiando los APKs resultantes a la raíz de D:\..."
    
    $apkDir = "build\app\outputs\flutter-apk"
    $targetDir = "D:\"
    
    $abis = @("arm64-v8a", "armeabi-v7a", "x86_64")
    $copiedCount = 0

    foreach ($abi in $abis) {
        $sourcePath = Join-Path $apkDir "app-$abi-release.apk"
        $destinationPath = Join-Path $targetDir "AgroVision_$abi.apk"
        
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Force
            Write-Host "Copiado con éxito: $sourcePath -> $destinationPath"
            $copiedCount++
        }
    }

    # Copiar también el APK completo si existiese
    $fullApk = Join-Path $apkDir "app-release.apk"
    if (Test-Path $fullApk) {
        Copy-Item -Path $fullApk -Destination "D:\AgroVision_Completo.apk" -Force
        Write-Host "Copiado con éxito APK completo a: D:\AgroVision_Completo.apk"
    }

    if ($copiedCount -eq 0) {
        Write-Warning "No se encontró ningún APK específico de ABI en $apkDir"
    } else {
        Write-Host "Proceso finalizado. Se copiaron $copiedCount APKs optimizados."
    }
} else {
    Write-Error "Falló la compilación del APK."
    exit $LASTEXITCODE
}
