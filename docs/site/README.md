# Landing page source

`dusty/` is the source for the live product page at <https://toprak.sh/dusty>.

It is a single self-contained static `index.html` (inline CSS and JS, no build
step). The only external asset it needs is `demo.gif` (the hero capture). The
`og-card.png` referenced in the social meta tags is loaded from the live URL.

The page is served by nginx from the VPS at `/var/www/toprak.sh/dusty/`. To
deploy a change, back up the remote file first, then copy the new one up and fix
permissions (files must be `644` or nginx returns 403):

```sh
ssh <host> "cp /var/www/toprak.sh/dusty/index.html /var/www/toprak.sh/dusty/index.html.bak.$(date +%Y%m%d)"
scp docs/site/dusty/index.html <host>:/var/www/toprak.sh/dusty/index.html
ssh <host> "chmod 644 /var/www/toprak.sh/dusty/index.html"
```
