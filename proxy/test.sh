#!/bin/sh

BASE_DIR=/home/chylli/study/misc/proxy
BIN_DIR=${BASE_DIR}/mysql-proxy/bin
export LUA_PATH="${BASE_DIR}/?.lua"

${BIN_DIR}/mysql-proxy \
--proxy-lua-script=${BASE_DIR}/rw-splitting.lua \
--admin-username=chylli --admin-password=123456 \
--admin-lua-script=${BASE_DIR}/admin.lua  \
--proxy-address=:4000 --admin-address=:5000 \
--proxy-backend-addresses=192.168.3.110 \
--proxy-backend-addresses=192.168.3.111 \
--log-use-syslog \
--log-level=debug \

