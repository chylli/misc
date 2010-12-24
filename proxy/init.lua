module("init", package.seeall)

if not proxy.global.ever_up then
   proxy.global.ever_up = {}
	for i = 1, #proxy.global.backends do
        proxy.global.ever_up[i] = true
    end
end
