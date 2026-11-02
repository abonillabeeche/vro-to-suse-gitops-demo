# Optional pillar (Aria Automation Config pillar, Salt master /srv/pillar, or SUSE Multi-Linux Manager custom pillar).
# No secrets here: database and admin passwords are generated on the VM (/etc/wordpress/*.pass).
wordpress:
  site_title: "Deployed by SUSE Multi-Linux Manager"
  url: "http://wp-01.example.com"
  admin_user: wpadmin
  admin_email: admin@example.com
