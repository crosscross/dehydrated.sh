# dehydrated.sh

使用 https://github.com/lukas2511/dehydrated 建立 Let's Encrypt SSL 憑證

參考 dehydrated 的內容另外編寫一支可以放在 plesk 上使用
會建立 /etc/httpd/conf.d/dehydrated.conf Alias 目錄到 /etc/dehydrated
所以 wellknown 檢查都透過直接透過那個 Alias

## HowTo

```text
mkdir /etc/dehydrated
wget https://raw.githubusercontent.com/lukas2511/dehydrated/master/dehydrated -O /etc/dehydrated/dehydrated
ln -s /etc/dehydrated/dehydrated.sh  /usr/local/bin/dehydrated.sh
chmod +x /usr/local/bin/dehydrated.sh
dehydrated.sh
```