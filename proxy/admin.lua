--[[ $%BEGINLICENSE%$
 Copyright (c) 2008, 2009, Oracle and/or its affiliates. All rights reserved.

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License as
 published by the Free Software Foundation; version 2 of the
 License.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 02110-1301  USA

 $%ENDLICENSE%$ --]]

require("init")

function set_error(errmsg) 
	proxy.response = {
		type = proxy.MYSQLD_PACKET_ERR,
		errmsg = errmsg or "error"
	}
end

function read_query(packet)
	if packet:byte() ~= proxy.COM_QUERY then
		set_error("[admin] we only handle text-based queries (COM_QUERY)")
		return proxy.PROXY_SEND_RESULT
	end

	local query = packet:sub(2)

	local rows = { }
	local fields = { }

	if query:lower() == "select * from backends" then
		fields = { 
			{ name = "backend_ndx", 
			  type = proxy.MYSQL_TYPE_LONG },

			{ name = "address",
			  type = proxy.MYSQL_TYPE_STRING },
			{ name = "state",
			  type = proxy.MYSQL_TYPE_STRING },
            { name = "master",
              type = proxy.MYSQL_TYPE_STRING },
			{ name = "type",
			  type = proxy.MYSQL_TYPE_STRING },
			{ name = "uuid",
			  type = proxy.MYSQL_TYPE_STRING },
			{ name = "connected_clients", 
			  type = proxy.MYSQL_TYPE_LONG },
		}

		for i = 1, #proxy.global.backends do
			local states = {
				"unknown",
				"up",
				"down"
			}
			local types = {
				"unknown",
				"rw",
				"ro"
			}
			local b = proxy.global.backends[i]
            local master;
            if proxy.global.master == i then
               master = "Yes"
            else
               master = "No"
            end


			rows[#rows + 1] = {
				i,
				b.dst.name,          -- configured backend address
				states[b.state + 1], -- the C-id is pushed down starting at 0
                master,
				types[b.type + 1],   -- the C-id is pushed down starting at 0
				b.uuid,              -- the MySQL Server's UUID if it is managed
				b.connected_clients  -- currently connected clients
			}
         end
     elseif string.find(query:lower(),"set master %d") then
        local m = tonumber(string.sub(query:lower(),string.find(query:lower(),"%d")))
        if m > #proxy.global.backends then
           set_error("no such backend: " .. m)
           return proxy.PROXY_SEND_RESULT
        end
        if proxy.global.backends[m].type ~= proxy.BACKEND_TYPE_RW then
           set_error("backend " .. m .. " is not a rw backend")
           return proxy.PROXY_SEND_RESULT
        end
        if proxy.global.backends[m].state == proxy.BACKEND_STATE_DOWN then
           set_error("backend " .. m .. " is down")
           return proxy.PROXY_SEND_RESULT
        end
        proxy.global.master = m
        proxy.response.type = proxy.MYSQLD_PACKET_OK
        return proxy.PROXY_SEND_RESULT
     elseif query:lower() == "select * from help" then
		fields = { 
			{ name = "command", 
			  type = proxy.MYSQL_TYPE_STRING },
			{ name = "description", 
			  type = proxy.MYSQL_TYPE_STRING },
		}
		rows[#rows + 1] = { "SELECT * FROM help", "shows this help" }
		rows[#rows + 1] = { "SELECT * FROM backends", "lists the backends and their state" }


    else
		set_error("use 'SELECT * FROM help' to see the supported commands")
		return proxy.PROXY_SEND_RESULT
	end

	proxy.response = {
		type = proxy.MYSQLD_PACKET_OK,
		resultset = {
			fields = fields,
			rows = rows
		}
	}
	return proxy.PROXY_SEND_RESULT
end
