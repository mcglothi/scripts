#!/bin/bash
# Ensure home.timmcg.net routes through Tailscale
sudo route delete -net 10.10.0.0/16 2>/dev/null
sudo route add -net 10.10.0.0/16 -interface utun4
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "Headscale routes and DNS flushed."
