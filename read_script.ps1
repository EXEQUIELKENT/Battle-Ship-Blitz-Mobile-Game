$l = Get-Content lib\widgets\battle_grid.dart
400..790 | ForEach-Object {
  $line = $l[$_-1]
  if ($line -match "wreckSkin|wreck") {
    Write-Host "$_ : $line"
  }
}