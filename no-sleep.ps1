#Requires -Version 5.1
<#
.SYNOPSIS
    Script automatizado para suspender (S0 Connected Standby) a una hora específica.

.DESCRIPTION
    - Pide una hora objetivo por consola (formato HH:mm).
    - Si pasan 10 segundos sin ingreso, asume 18:00 por defecto.
    - Espera hasta la hora definida.
    - A la hora indicada, bloquea la sesión y apaga la pantalla (S0).
#>

Add-Type -AssemblyName System.Windows.Forms

if (-not ([System.Management.Automation.PSTypeName]'SleepScriptV4').Type) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;

    public class SleepScriptV4 {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool LockWorkStation();
    }
"@
}

# Constantes
$WM_SYSCOMMAND = 0x0112
$SC_MONITORPOWER = 0xF170
$MONITOR_OFF = 2
$HWND_BROADCAST = [IntPtr]0xFFFF
$VK_F13 = 0x7C
$KEYEVENTF_KEYUP = 0x0002

function Press-F13 {
    [SleepScriptV4]::keybd_event($VK_F13, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [SleepScriptV4]::keybd_event($VK_F13, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

function Suspend-PC {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Bloqueando sesion y apagando pantalla en 3 segundos..."
    Start-Sleep -Seconds 3

    # Bloquear la sesion de Windows
    [SleepScriptV4]::LockWorkStation() | Out-Null
    Write-Host "  Sesion bloqueada"
    Start-Sleep -Seconds 2

    # Apagar la pantalla (en laptops Modern Standby esto activa Connected Standby S0)
    [SleepScriptV4]::SendMessage($HWND_BROADCAST, $WM_SYSCOMMAND, [IntPtr]$SC_MONITORPOWER, [IntPtr]$MONITOR_OFF) | Out-Null
    Write-Host "  Pantalla apagada - entrando en Connected Standby"
}

# ===== INICIO =====

Write-Host "================================================================"
Write-Host " Script de Suspension Programada"
Write-Host "================================================================"

$timeoutSeconds = 10
$endTime = (Get-Date).AddSeconds($timeoutSeconds)
$inputString = ""
Write-Host "Ingrese la hora para suspender el equipo (HH:mm)."
Write-Host "Tiene 10 segundos [Por defecto 18:00]: " -NoNewline

while ((Get-Date) -lt $endTime) {
    if ([console]::KeyAvailable) {
        $keyInfo = [console]::ReadKey($true)
        if ($keyInfo.Key -eq [ConsoleKey]::Enter) {
            Write-Host
            break
        } elseif ($keyInfo.Key -eq [ConsoleKey]::Backspace) {
            if ($inputString.Length -gt 0) {
                $inputString = $inputString.Substring(0, $inputString.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        } else {
            $inputString += $keyInfo.KeyChar
            Write-Host $keyInfo.KeyChar -NoNewline
        }
    }
    Start-Sleep -Milliseconds 50
}

if ($inputString.Trim() -eq "") {
    Write-Host "`nNo se ingresó hora. Se usará 18:00 por defecto."
    $targetTime = (Get-Date).Date.AddHours(18)
} else {
    $parsedTime = $null
    if ([datetime]::TryParse($inputString, [ref]$parsedTime)) {
        $targetTime = (Get-Date).Date.AddHours($parsedTime.Hour).AddMinutes($parsedTime.Minute)
    } else {
        Write-Host "`nFormato invalido. Se usara 18:00 por defecto."
        $targetTime = (Get-Date).Date.AddHours(18)
    }
}

# Si la hora ya pasó hoy, programar para mañana
if ($targetTime -le (Get-Date)) {
    $targetTime = $targetTime.AddDays(1)
}

$sleepSeconds = [math]::Max(1, [int]($targetTime - (Get-Date)).TotalSeconds)
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] El equipo se suspendera a las $($targetTime.ToString('HH:mm:ss')) (en $([math]::Round($sleepSeconds/60, 1)) minutos)."

# Bucle de espera hasta la hora objetivo, manteniendo el PC despierto con F13
$lastF13 = Get-Date
while ((Get-Date) -lt $targetTime) {
    $now = Get-Date
    if (($now - $lastF13).TotalSeconds -ge 60) {
        Press-F13
        $lastF13 = $now
    }
    Start-Sleep -Milliseconds 500
}

Suspend-PC
