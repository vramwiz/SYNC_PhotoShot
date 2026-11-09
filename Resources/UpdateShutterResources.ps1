# Mp3原本を変更せず、既存 .res の非音声リソースを保持してRCDATA 4件を更新する。
# ビルドイベントとは独立した保守用スクリプト。毎回変更前の.resをBackupへ保存する。
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resource=Join-Path $root 'Source\Plugin\Filter\SYNC_PhotoShot_Audio.res'
$names=@('PHOTOSHOT_SMARTPHONE','PHOTOSHOT_COMPACT','PHOTOSHOT_DSLR','PHOTOSHOT_INSTANT')
$files=@('スマホ.mp3','コンデジ.mp3','一眼レフ.mp3','インスタントカメラ.mp3')
$hashes=@{}
for($i=0;$i -lt 4;$i++){
$p=Join-Path $root ('Mp3\'+$files[$i])
$hashes[$files[$i]]=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$old=[IO.File]::ReadAllBytes($resource)
$backup=Join-Path $root ('Backup\ResourceUpdate_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
[void](New-Item -ItemType Directory -Path $backup)
Copy-Item -LiteralPath $resource -Destination $backup
$stream=New-Object IO.MemoryStream
function Read-ResString([byte[]]$data,[ref]$pos){
$v=[BitConverter]::ToUInt16($data,$pos.Value);$pos.Value+=2
if($v -eq 65535){$n=[BitConverter]::ToUInt16($data,$pos.Value);$pos.Value+=2;return "#$n"}
$chars=New-Object 'Collections.Generic.List[char]'
while($v -ne 0){$chars.Add([char]$v);$v=[BitConverter]::ToUInt16($data,$pos.Value);$pos.Value+=2}
return -join $chars
}
try{
$offset=0
while($offset -lt $old.Length){
if($offset+8 -gt $old.Length){throw 'Truncated resource header'}
$size=[BitConverter]::ToUInt32($old,$offset);$header=[BitConverter]::ToUInt32($old,$offset+4)
$next=[int](($offset+$header+$size+3) -band -4)
if($header -lt 8 -or $next -gt $old.Length -or $next -le $offset){throw 'Invalid resource record'}
$p=$offset+8;$type=Read-ResString $old ([ref]$p);$name=Read-ResString $old ([ref]$p)
if(!($type -eq '#10' -and $names -contains $name)){$stream.Write($old,$offset,$next-$offset)}
$offset=$next
}
for($i=0;$i -lt 4;$i++){
$input=Join-Path $root ('Mp3\'+$files[$i])
$data=[IO.File]::ReadAllBytes($input)
$headerStream=New-Object IO.MemoryStream
$w=New-Object IO.BinaryWriter($headerStream)
try{
$w.Write([uint32]$data.Length);$w.Write([uint32]0)
$w.Write([uint16]65535);$w.Write([uint16]10)
$w.Write([Text.Encoding]::Unicode.GetBytes($names[$i]+[char]0))
while($headerStream.Length%4){$w.Write([byte]0)}
$w.Write([uint32]0);$w.Write([uint16]48);$w.Write([uint16]1033)
$w.Write([uint32]0);$w.Write([uint32]0)
$headerBytes=$headerStream.ToArray()
[BitConverter]::GetBytes([uint32]$headerBytes.Length).CopyTo($headerBytes,4)
$stream.Write($headerBytes,0,$headerBytes.Length)
$stream.Write($data,0,$data.Length)
while($stream.Length%4){$stream.WriteByte(0)}
}finally{$w.Dispose();$headerStream.Dispose()}
}
$new=$stream.ToArray()
$temp=$resource+'.new'
[IO.File]::WriteAllBytes($temp,$new)
Move-Item -LiteralPath $temp -Destination $resource -Force
}finally{$stream.Dispose()}
for($i=0;$i -lt 4;$i++){
$p=Join-Path $root ('Mp3\'+$files[$i])
if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $hashes[$files[$i]]){throw 'Original MP3 changed'}
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'ShutterResourceHashes.json') -Encoding UTF8
Write-Output "Updated $resource with 4 RCDATA sounds. Existing non-audio resources preserved."
Write-Output "Backup: $backup"
