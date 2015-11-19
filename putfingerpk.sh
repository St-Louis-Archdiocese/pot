#!/bin/sh
/usr/bin/smbclient -U fss -c "lcd /data/school/FSS;prompt;put Finger.pk" //sfb-f96f3ac27a8.borgia.com/fssbiowedge "$(cat /data/school/FSS/fssbiowedge.secret)"
