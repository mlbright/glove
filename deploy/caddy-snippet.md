# Caddy configuration (runs on the separate Caddy machine)

Nothing Caddy-related is installed on the glove machine. The Caddy reverse
proxy lives on its own host and serves glove at the `/glove` subpath,
forwarding over Tailscale to this machine's Thruster on port **3004**.

Rails needs two things for the subpath to work, both already wired up:

1. `X-Script-Name: /glove` header on proxied requests — the
   `Rack::ScriptNameFromHeader` middleware turns it into `SCRIPT_NAME`.
2. `RAILS_RELATIVE_URL_ROOT=/glove` in the glove machine's `.env` — prefixes
   generated asset and URL paths.

Snippet for the Caddy machine's Caddyfile (replace `<glove-machine>` with
this machine's Tailscale hostname):

```caddy
hippo.chameleon-gopher.ts.net {
    tls /etc/caddy/tls/hippo.chameleon-gopher.ts.net.crt /etc/caddy/tls/hippo.chameleon-gopher.ts.net.key

    # Glove app at /glove — handle_path strips the prefix before forwarding.
    handle_path /glove/* {
        reverse_proxy http://<glove-machine>:3004 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Host {host}
            header_up X-Script-Name /glove
        }
    }

    # Handle /glove without trailing slash.
    handle /glove {
        redir /glove/ permanent
    }
}
```

After editing, reload Caddy on that machine (`sudo systemctl reload caddy`)
and verify `https://<public-host>/glove/up` returns 200.
