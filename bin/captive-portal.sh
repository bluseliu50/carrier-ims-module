#!/system/bin/sh
# bin/captive-portal.sh — shell-only captive-portal CN fix/restore/query.
# No priv-app needed; Settings.Global keys are writable by root shell.
# Grounded in CaptivePortalFixer.kt:17-24.
#
# Usage:
#   captive-portal.sh fix      # set CN connectivity-check URLs
#   captive-portal.sh restore  # clear overrides
#   captive-portal.sh query    # print current URLs + whether CN

KEY_HTTP="captive_portal_http_url"
KEY_HTTPS="captive_portal_https_url"
CN_HTTP_URL="http://connectivitycheck.gstatic.cn/generate_204"
CN_HTTPS_URL="https://www.google.cn/generate_204"

case "$1" in
    fix)
        settings put global "$KEY_HTTP" "$CN_HTTP_URL"
        settings put global "$KEY_HTTPS" "$CN_HTTPS_URL"
        settings put global captive_portal_mode 1
        echo '{"ok":true,"action":"fix"}'
        ;;
    restore)
        settings delete global "$KEY_HTTP"
        settings delete global "$KEY_HTTPS"
        settings put global captive_portal_mode 1
        echo '{"ok":true,"action":"restore"}'
        ;;
    query)
        HTTP=$(settings get global "$KEY_HTTP")
        HTTPS=$(settings get global "$KEY_HTTPS")
        echo "{\"http\":$(printf '%s' "$HTTP" | tr -d '\n'),\"https\":$(printf '%s' "$HTTPS" | tr -d '\n')}"
        ;;
    *)
        echo "usage: captive-portal.sh fix|restore|query" >&2
        exit 1
        ;;
esac
