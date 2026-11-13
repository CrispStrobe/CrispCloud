# Include INSIDE the Nextcloud VirtualHost, with mod_headers, mod_setenvif
# and mod_rewrite enabled. Replace https://crispcloud.example everywhere with
# the EXACT origin shown by CrispCloud (scheme + host + optional port, no path).
# Use HTTPS for a public deployment. Do not use a wildcard or allow null origins.
# This covers DAV file operations; OCS/custom-app APIs need their own review.
SetEnvIfExpr "req('Origin') == 'https://crispcloud.example' && %{REQUEST_URI} =~ m#^/remote[.]php/(dav|webdav)(/|$)#" CC_NC_CORS=1
Header always set Access-Control-Allow-Origin "https://crispcloud.example" env=CC_NC_CORS
Header always set Access-Control-Allow-Methods "GET, HEAD, OPTIONS, PROPFIND, PUT, MKCOL, DELETE, COPY, MOVE" env=CC_NC_CORS
Header always set Access-Control-Allow-Headers "Authorization, Depth, Content-Type, Destination, Overwrite, If-Match, Range" env=CC_NC_CORS
Header always set Access-Control-Expose-Headers "ETag, DAV, Allow, Content-Range, Accept-Ranges" env=CC_NC_CORS
Header always merge Vary Origin

# Browser preflight has no DAV credentials. Only the exact approved origin and
# DAV route receive this empty response. Actual DAV requests retain normal auth.
RewriteEngine On
RewriteCond %{REQUEST_METHOD} =OPTIONS
RewriteCond %{HTTP:Origin} =https://crispcloud.example
RewriteCond %{REQUEST_URI} ^/remote[.]php/(dav|webdav)(/|$)
RewriteRule ^ - [R=204,L]
