$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$sqliteAssembly = 'C:\Program Files\HP\SystemOptimizer\System.Data.SQLite.dll'
if (-not (Test-Path $sqliteAssembly)) {
  throw "SQLite assembly not found: $sqliteAssembly"
}
Add-Type -Path $sqliteAssembly

$tiandituKey = 'd9f8596e7de371267b98dd849fa6321a'
$tileSize = 256
$minZoom = 10
$maxZoom = 15
$west = 110.20
$south = 19.95
$east = 110.55
$north = 20.10
$centerLon = ($west + $east) / 2.0
$centerLat = ($south + $north) / 2.0
$approvalNo = 'GS(2025)1508'
$sourceLabel = 'Tianditu'

$output = Join-Path $PSScriptRoot '..\assets\maps\tactical.mbtiles'
$output = [System.IO.Path]::GetFullPath($output)
$outputDir = Split-Path -Parent $output
[System.IO.Directory]::CreateDirectory($outputDir) | Out-Null
if (Test-Path $output) {
  Remove-Item -LiteralPath $output -Force
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-TileX([double]$lon, [int]$zoom) {
  $n = [math]::Pow(2, $zoom)
  return [int][math]::Floor((($lon + 180.0) / 360.0) * $n)
}

function Get-TileY([double]$lat, [int]$zoom) {
  $n = [math]::Pow(2, $zoom)
  $latRad = $lat * [math]::PI / 180.0
  $value = (1.0 - [math]::Log([math]::Tan($latRad) + 1.0 / [math]::Cos($latRad)) / [math]::PI) / 2.0 * $n
  return [int][math]::Floor($value)
}

function Invoke-TiandituTileRequest([string]$layerGroup, [string]$layerId, [int]$zoom, [int]$x, [int]$y) {
  $serverIndex = ($x + $y) % 8
  $url = "https://t$serverIndex.tianditu.gov.cn/$layerGroup/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=$layerId&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX=$zoom&TILEROW=$y&TILECOL=$x&tk=$tiandituKey"

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 30).Content
    } catch {
      if ($attempt -eq 3) {
        throw
      }
      Start-Sleep -Milliseconds (300 * $attempt)
    }
  }
}

function Merge-TiandituTile([int]$zoom, [int]$x, [int]$y) {
  $baseBytes = Invoke-TiandituTileRequest 'vec_w' 'vec' $zoom $x $y
  $labelBytes = Invoke-TiandituTileRequest 'cva_w' 'cva' $zoom $x $y

  $baseStream = [System.IO.MemoryStream]::new($baseBytes, $false)
  $labelStream = [System.IO.MemoryStream]::new($labelBytes, $false)
  try {
    $baseBitmap = [System.Drawing.Bitmap]::new($baseStream)
    $labelBitmap = [System.Drawing.Bitmap]::new($labelStream)
    try {
      $canvas = [System.Drawing.Bitmap]::new($tileSize, $tileSize)
      $graphics = [System.Drawing.Graphics]::FromImage($canvas)
      try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($baseBitmap, 0, 0, $tileSize, $tileSize)
        $graphics.DrawImage($labelBitmap, 0, 0, $tileSize, $tileSize)

        $outStream = [System.IO.MemoryStream]::new()
        try {
          $canvas.Save($outStream, [System.Drawing.Imaging.ImageFormat]::Png)
          return ,([byte[]]$outStream.ToArray())
        } finally {
          $outStream.Dispose()
        }
      } finally {
        $graphics.Dispose()
        $canvas.Dispose()
      }
    } finally {
      $baseBitmap.Dispose()
      $labelBitmap.Dispose()
    }
  } finally {
    $baseStream.Dispose()
    $labelStream.Dispose()
  }
}

$connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$output;Version=3;")
$connection.Open()

try {
  $command = $connection.CreateCommand()
  $command.CommandText = @'
CREATE TABLE metadata (name TEXT NOT NULL, value TEXT NOT NULL);
CREATE TABLE tiles (
  zoom_level INTEGER NOT NULL,
  tile_column INTEGER NOT NULL,
  tile_row INTEGER NOT NULL,
  tile_data BLOB NOT NULL
);
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
'@
  $command.ExecuteNonQuery() | Out-Null
  $command.Dispose()

  $transaction = $connection.BeginTransaction()
  try {
    $metadata = [ordered]@{
      name = 'Rescue Mesh Tactical Grid'
      type = 'baselayer'
      version = '1'
      description = 'Tianditu vector basemap for Rescue Mesh'
      format = 'png'
      minzoom = "$minZoom"
      maxzoom = "$maxZoom"
      bounds = "$west,$south,$east,$north"
      center = "$centerLon,$centerLat,14"
      attribution = "Map source: $sourceLabel; approval: $approvalNo"
    }

    $metaCommand = $connection.CreateCommand()
    $metaCommand.Transaction = $transaction
    $metaCommand.CommandText = 'INSERT INTO metadata (name, value) VALUES (@name, @value)'
    $null = $metaCommand.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter('@name', '')))
    $null = $metaCommand.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter('@value', '')))

    foreach ($entry in $metadata.GetEnumerator()) {
      $metaCommand.Parameters['@name'].Value = [string]$entry.Key
      $metaCommand.Parameters['@value'].Value = [string]$entry.Value
      $metaCommand.ExecuteNonQuery() | Out-Null
    }
    $metaCommand.Dispose()

    $tileCommand = $connection.CreateCommand()
    $tileCommand.Transaction = $transaction
    $tileCommand.CommandText = @'
INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data)
VALUES (@zoom, @column, @row, @data)
'@
    $null = $tileCommand.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter('@zoom', 0)))
    $null = $tileCommand.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter('@column', 0)))
    $null = $tileCommand.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter('@row', 0)))
    $dataParameter = New-Object System.Data.SQLite.SQLiteParameter('@data', [byte[]]@())
    $dataParameter.DbType = [System.Data.DbType]::Binary
    $null = $tileCommand.Parameters.Add($dataParameter)

    for ($zoom = $minZoom; $zoom -le $maxZoom; $zoom++) {
      $xMin = Get-TileX $west $zoom
      $xMax = Get-TileX $east $zoom
      $yMin = Get-TileY $north $zoom
      $yMax = Get-TileY $south $zoom

      for ($x = $xMin; $x -le $xMax; $x++) {
        for ($y = $yMin; $y -le $yMax; $y++) {
          $tileBytes = Merge-TiandituTile $zoom $x $y
          $tmsY = ([math]::Pow(2, $zoom) - 1) - $y

          $tileCommand.Parameters['@zoom'].Value = $zoom
          $tileCommand.Parameters['@column'].Value = $x
          $tileCommand.Parameters['@row'].Value = [int]$tmsY
          $tileCommand.Parameters['@data'].Value = $tileBytes
          $tileCommand.ExecuteNonQuery() | Out-Null
        }
      }
    }

    $tileCommand.Dispose()
    $transaction.Commit()
  } catch {
    $transaction.Rollback()
    throw
  } finally {
    $transaction.Dispose()
  }
} finally {
  $connection.Dispose()
}

Write-Output "Generated $output"
