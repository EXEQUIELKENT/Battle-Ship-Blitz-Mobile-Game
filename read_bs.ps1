$l = Get-Content lib\screens\battle_screen.dart; for ($i = 240; $i -le 320; $i++) { Write-Host "$i : $($l[$i-1])" }
