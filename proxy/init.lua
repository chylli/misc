module("init", package.seeall)

if not proxy.global.master then
   proxy.global.master = 1 -- deafult is first backend
end
