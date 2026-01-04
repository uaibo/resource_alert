# Send yourself as Telegram alert when your server performance is degraded.

## Set permissions
```
sudo chown root:root /usr/local/bin/resource_alert.sh
sudo chmod 700 /usr/local/bin/resource_alert.sh
```

## Create cron job
```
sudo crontab -e
```
```
* * * * * /usr/local/bin/resource_alert.sh
```
