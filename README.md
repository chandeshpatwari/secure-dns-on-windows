# secure-dns-on-windows
1. Install [cloudflared](https://github.com/cloudflare/cloudflared)
```sh
winget install cloudflared.cloudflared
```

2. Setup
```sh
irm https://raw.githubusercontent.com/chandeshpatwari/secure-dns-on-windows/refs/heads/main/cloudflared.ps1 | iex
```
