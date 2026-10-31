-- Assign Crew (x4_ext_assign_crew)
-- Adds "All -> Service crew" / "All -> Marines" buttons to the crew section of the
-- map menu's ship information panel, directly above the Confirm/Reset row.
--
-- Dependency free: works with the vanilla menu_map and with kuertee's UI Extensions,
-- because both build the panel through menu.addCrewSection(), which we wrap. While the
-- original runs, we intercept the row group's addRow("UpdateCrew") (the Confirm/Reset
-- row) and insert our button row right before it.

local ffi = require("ffi")
local C = ffi.C

-- Declarations may already exist in this Lua state (menu_map declares them), so each
-- one is declared separately and redefinition errors are ignored.
local function cdef(decl) pcall(ffi.cdef, decl) end
cdef("typedef uint64_t UniverseID;")
cdef("typedef uint64_t NPCSeed;")
cdef("typedef struct { const char* newroleid; NPCSeed seed; uint32_t amount; } CrewTransferContainer;")
cdef("typedef struct { const char* id; const char* name; const char* desc; uint32_t amount; uint32_t numtiers; bool canhire; } PeopleInfo;")
cdef("typedef struct { const char* name; int32_t skilllevel; uint32_t amount; } RoleTierData;")
cdef("uint32_t GetNumAllRoles(void);")
cdef("uint32_t GetPeople2(PeopleInfo* result, uint32_t resultlen, UniverseID controllableid, bool includearriving);")
cdef("uint32_t GetRoleTierNPCs(NPCSeed* result, uint32_t resultlen, UniverseID controllableid, const char* role, int32_t skilllevel);")
cdef("uint32_t GetRoleTiers(RoleTierData* result, uint32_t resultlen, UniverseID controllableid, const char* role);")
cdef("bool HasPersonArrived(UniverseID controllableid, NPCSeed person);")
cdef("bool IsPersonTransferScheduled(UniverseID controllableid, NPCSeed person);")
cdef("void ReassignPeople(UniverseID controllableid, CrewTransferContainer* reassignedcrew, uint32_t amount);")

local TEXTPAGE = 1739420
local FALLBACK = {
	[1] = "Assign all crew as service crew",
	[2] = "Assign all crew as marines",
	[3] = "Immediately assign all crew members on board (except the captain) as service crew.",
	[4] = "Immediately assign all crew members on board (except the captain) as marines.",
}

local function text(id)
	local t = ReadText(TEXTPAGE, id)
	if (t == nil) or (t == "") or string.find(t, "^ReadText") then
		return FALLBACK[id]
	end
	return t
end

-- For each target role: the roles whose members get moved into it.
local SOURCES = {
	service = { "marine", "unassigned" },
	marine  = { "service", "unassigned" },
}

local function log(msg)
	DebugError("[AssignCrew] " .. tostring(msg))
end

-- Returns { [roleid] = { amount = n, canhire = bool } } for the object.
local function getRoles(object)
	local roles = {}
	local num = C.GetNumAllRoles()
	local buf = ffi.new("PeopleInfo[?]", num)
	num = C.GetPeople2(buf, num, object, true)
	for i = 0, num - 1 do
		roles[ffi.string(buf[i].id)] = { amount = buf[i].amount, numtiers = buf[i].numtiers, canhire = buf[i].canhire }
	end
	return roles
end

local function canAssign(object, target)
	local roles = getRoles(object)
	if not (roles[target] and roles[target].canhire) then
		return false
	end
	for _, src in ipairs(SOURCES[target]) do
		if roles[src] and roles[src].amount > 0 then
			return true
		end
	end
	return false
end

-- All persons of a role that are on board and not in transit.
local function collectPersons(object, role, roleinfo, result)
	local function addFrom(skilllevel, count)
		if count <= 0 then return end
		local seeds = ffi.new("NPCSeed[?]", count)
		count = C.GetRoleTierNPCs(seeds, count, object, role, skilllevel)
		for k = 0, count - 1 do
			local person = seeds[k]
			if (not C.IsPersonTransferScheduled(object, person)) and C.HasPersonArrived(object, person) then
				table.insert(result, person)
			end
		end
	end

	local numtiers = roleinfo.numtiers
	if numtiers > 0 then
		local tiers = ffi.new("RoleTierData[?]", numtiers)
		numtiers = C.GetRoleTiers(tiers, numtiers, object, role)
		for j = 0, numtiers - 1 do
			addFrom(tiers[j].skilllevel, tiers[j].amount)
		end
	else
		addFrom(0, roleinfo.amount)
	end
end

local function refresh(menu, instance)
	local pd = menu.infoTablePersistentData
	if pd then
		if pd.left then pd.left.resetcrew = true end
		if pd.right then pd.right.resetcrew = true end
	end
	if (instance == "right") and menu.refreshInfoFrame2 then
		menu.refreshInfoFrame2()
	else
		menu.refreshInfoFrame()
	end
end

local function assignAll(menu, object, target, instance)
	local roles = getRoles(object)
	local persons = {}
	for _, src in ipairs(SOURCES[target]) do
		if roles[src] and roles[src].amount > 0 then
			collectPersons(object, src, roles[src], persons)
		end
	end
	if #persons > 0 then
		local container = ffi.new("CrewTransferContainer[?]", #persons)
		local roleid = Helper.ffiNewString(target)
		for i, person in ipairs(persons) do
			container[i - 1].seed = person
			container[i - 1].newroleid = roleid
		end
		C.ReassignPeople(object, container, #persons)
	end
	refresh(menu, instance)
end

local function addButtonRow(menu, rowgroup, object, instance)
	local object64 = ConvertIDTo64Bit(object)
	local row = rowgroup:addRow("AssignCrewAll", {})
	row[1]:setColSpan(4):createButton({
		active = function() return canAssign(object64, "service") end,
		mouseOverText = text(3),
	}):setText(text(1), { halign = "center" })
	row[1].handlers.onClick = function() return assignAll(menu, object64, "service", instance) end
	row[5]:setColSpan(3):createButton({
		active = function() return canAssign(object64, "marine") end,
		mouseOverText = text(4),
	}):setText(text(2), { halign = "center" })
	row[5].handlers.onClick = function() return assignAll(menu, object64, "marine", instance) end
end

local function install()
	local menu = Helper.getMenu("MapMenu")
	if not menu then
		log("MapMenu not found, buttons disabled")
		return
	end
	local original = menu.addCrewSection
	if type(original) ~= "function" then
		log("menu.addCrewSection not found (game update?), buttons disabled")
		return
	end

	menu.addCrewSection = function(mode, inputtable, inputobject, instance, infocrew, operatorinfo, aipilot, isplayerowned, ...)
		if (mode ~= "ship") or (not isplayerowned) or (not operatorinfo) or (type(inputtable) ~= "table") then
			return original(mode, inputtable, inputobject, instance, infocrew, operatorinfo, aipilot, isplayerowned, ...)
		end

		-- Temporarily shadow the table's addRowGroup (a metatable method) on the instance.
		local originalAddRowGroup = inputtable.addRowGroup
		local patchedGroups = {}
		local injected = false
		inputtable.addRowGroup = function(tbl, ...)
			local group = originalAddRowGroup(tbl, ...)
			local originalAddRow = group.addRow
			group.addRow = function(grp, rowdata, ...)
				if (not injected) and (rowdata == "UpdateCrew") then
					injected = true
					local ok, err = pcall(addButtonRow, menu, grp, inputobject, instance)
					if not ok then log("failed to add buttons: " .. tostring(err)) end
				end
				return originalAddRow(grp, rowdata, ...)
			end
			table.insert(patchedGroups, group)
			return group
		end

		local ok, err = pcall(original, mode, inputtable, inputobject, instance, infocrew, operatorinfo, aipilot, isplayerowned, ...)

		-- Remove the shadows again so the widgets are unchanged afterwards.
		inputtable.addRowGroup = nil
		for _, group in ipairs(patchedGroups) do
			group.addRow = nil
		end

		if not ok then
			error(err, 0)
		end
	end
end

install()
