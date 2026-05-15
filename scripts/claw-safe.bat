@echo off
REM claw-safe.bat — Run claw-code inside WSL Debian with sandbox enabled
REM Usage: claw-safe [claw args...]
REM Example: claw-safe --model opus "explain this file"

wsl -d Debian -- bash -c "source ~/.cargo/env && cd /mnt/e/claw-code/rust && claw %*"
