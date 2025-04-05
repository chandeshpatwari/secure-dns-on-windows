# secure-dns-on-windows
1. Install [cloudflared](https://github.com/cloudflare/cloudflared)
```sh
winget install cloudflared.cloudflared
```

2. Setup
```sh
irm https://github.com/chandeshpatwari/secure-dns-on-windows/raw/refs/heads/main/cloudflared-windows/runme.ps1 > runme.ps1; ./runme.ps1
```
