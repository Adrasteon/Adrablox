$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
Start-Process -FilePath 'cmd.exe' -ArgumentList "/k `"$here\\mcp-server.exe`"" -WorkingDirectory $here
