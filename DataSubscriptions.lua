local RunService 	= game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IsServer 		= RunService:IsServer()
local RemoteFolder	= ReplicatedStorage:WaitForChild("Remotes")

local Subscriptions = {}
local ActiveSubscriptions   = {}
local DataSets              = {} -->
local DataSetAlterations    = {} --> Rather than sending each individual change, we can create a quick cache of changes, and send this instead.

local function DataPathLoop(CurrentPath, Path)
    local EndKey = typeof(Path) == "table" and Path[#Path] or Path
    if EndKey == Path then
        return CurrentPath, EndKey
    end
    if #Path == 1 then
        return CurrentPath[Path[1]], EndKey
    end

    for n, x in pairs(Path) do
        CurrentPath = CurrentPath[x]
        if n == (#Path - 1) then
            return CurrentPath, EndKey --//Returns the step before our current path, resulting in editable data set.
        elseif CurrentPath == nil then
            return --//Returns nil
        end
    end
end

local function AddData(Data, Path, Add) --//We are adding data that doesn't exist
    local CurrentPath, EndKey = DataPathLoop(Data, Path)
    print(CurrentPath, EndKey, Data, Path, Add)
    if (CurrentPath and CurrentPath[EndKey] ~= nil) then
        warn("Path failure or key exists.")
        warn(Path, Data)
        return
    end
    --What are we doing with this data.
    CurrentPath[EndKey] = Add --?? There should be more to do here.
end

local function ChangeData(Data, Path, Change) --//We are updating data that already exists
    local CurrentPath, EndKey = DataPathLoop(Data, Path)
    --Locate the data at our path.
    if not (CurrentPath and CurrentPath[EndKey]) then
        warn("Path failure or no key exists")
        warn(Path, Data)
        return
    end
    if typeof(Change) == "table" then
        local ThisTable = CurrentPath[EndKey]
        for Key, ThisData in pairs(Change) do
            ThisTable[Key] = ThisData
        end
    else
        CurrentPath[EndKey] = Change
    end
end

local function RemoveData(Data, Path) --//We are removing data that exists.
    local CurrentPath, EndKey = DataPathLoop(Data, Path)
    DataPathLoop(CurrentPath, Path)
    if (CurrentPath and CurrentPath[EndKey] == nil) or CurrentPath == nil then
        warn("Path failure or no key exists")
        warn(Path, Data)
        return
    end
    CurrentPath[EndKey] = nil
end

local ChangeTypes = {
    Add     = AddData;
    Update  = ChangeData;
    Remove  = RemoveData;
}

local function DeepCopyTable(t)
	local copy = {}
	for key, value in pairs(t) do
		if type(value) == "table" then
			copy[key] = DeepCopyTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

--//SERVER FUNCTIONS
if IsServer then
    local ServerCommunication   = {
		FireSelectClients = function(PlayerList, RemoteName, ...)
			local ThisRemote = RemoteFolder:FindFirstChild(RemoteName)
			if not ThisRemote then return end
			for n, ThisPlayer in pairs(PlayerList) do
				ThisRemote:FireClient(ThisPlayer, ...)
			end
		end;
		FireRemoteEvent = function(ThisPlayer, RemoteName, ...)
			local ThisRemote = RemoteFolder:FindFirstChild(RemoteName)
			if not ThisRemote then return end
			ThisRemote:FireClient(ThisPlayer, ...)
		end;
	}

    ServerCommunication.RegisterEvent("Subscriptions")

    local function ChangeDataSet(DataID, Type, Path, Changes)
        --print(DataID, Type, Path, Changes)
        local DataSet = DataSets[DataID]
        if DataSet == nil then
            warn("No data exists")
            return
        end
        ChangeTypes[Type](DataSet, Path, Changes)
    end

    function Subscriptions.RegisterDataSet(DataID, DataSet) --//CREATE A REFERENCE TO THE DATA A PLAYER WILL BE SUBSCRIBED TO
        if DataSets[DataID] ~= nil then return end
        --//Create data
        DataSets[DataID]            = DeepCopyTable(DataSet) -- Base Data
        DataSetAlterations[DataID]  = {} -- Cached Changed Data
        ActiveSubscriptions[DataID] = {} -- New Subscriptions available to be made
        print("New Data set has been made", DataID)
    end

    function Subscriptions.RemoveDataSet(DataID) --//REMOVE THE REFERENCE TO THE DATA / SIGNAL ITS REMOVAL TO CLIENTS
        if DataSets[DataID] == nil then return end
        --//Signal removal to subscribed clients
        local ThisList = ActiveSubscriptions[DataID]
        if #ThisList > 0 then
            ServerCommunication.FireSelectClients(ThisList, "Subscriptions", "Remove", DataID) --Players, Event, Action, DataID, ...
        end
        --//Remove Data
        DataSets[DataID]            = nil
        DataSetAlterations[DataID]  = nil
        ActiveSubscriptions[DataID] = nil
    end

    function Subscriptions.DataSetUpdated(DataID, ChangeType, Path, UpdatedData) --//THE DATA HAS BEEN UPDATED, SEND THIS UPDATE TO CLIENTS IMMEDIATELY
        --print(DataID, ChangeType, Path, UpdatedData)
        --//Check if this is going to nullify or alter any cached data.
        local ThisDataPath = {
            ChangeType;
            Path;
            UpdatedData;
        }
        --//Update the data set
        ChangeDataSet(DataID, ChangeType, Path, UpdatedData)
        --//Send to subscribed clients
        local ThisList = ActiveSubscriptions[DataID]
        if #ThisList > 0 then
            ServerCommunication.FireSelectClients(ThisList, "Subscriptions", "Update", DataID, ThisDataPath) --Players, Event, Action, DataID, ...
        end
    end

    function Subscriptions.DataSetCache(DataID, ChangeType, Path, UpdatedData) --//THE DATA HAS BEEN UPDATED, BUT NOT FINISHED; CACHE TO SEND
        if DataSets[DataID] == nil then
            warn("ERROR; Attempting to set cache for non-existant data")
            return
        end
        local ThisDataPath = {
            ChangeType;
            Path;
            UpdatedData;
        }
        table.insert(DataSetAlterations[DataID], ThisDataPath)
        return true --//Succesfully added to the cache
    end

    function Subscriptions.DataSetSendCache(DataID) --//UPDATE DATA SET; SEND ALL CACHED CHANGES TO THIS DATA SET
        local CapturedData = DataSetAlterations[DataID]
        --//Detatch & Delete the cache
        DataSetAlterations[DataID] = nil
        --//Update the data set
        for _, ThisData in pairs(CapturedData) do
            ChangeDataSet(DataID, unpack(ThisData)) --(DataID, Type, Path, Changes)
        end
        --//Send the Cache to subscribed clients;
        local ThisList = ActiveSubscriptions[DataID]
        if #ThisList > 0 then
            ServerCommunication.FireSelectClients(ThisList, "Subscriptions", "UpdateFromCached", DataID, CapturedData) --Players, Event, Action, DataID, ...
        end
    end

    --//Only players subscribed to data will recieve updates.
    function Subscriptions.SubscribeToData(DataID, PlayerID)
        --> Make sure the data is registered; error or wait if not.
        if DataSets[DataID] == nil then
            warn("ERROR; Attempting to subscribe to non existant data")
            return
        end
        if ActiveSubscriptions[DataID] then
            --> Subscribe the player to this data
            table.insert(ActiveSubscriptions[DataID], PlayerID)
            --> Send them the current copy
            ServerCommunication.FireRemoteEvent(PlayerID, "Subscriptions", "Set", DataID, DataSets[DataID])
            print("Player", PlayerID, " subscribed to data")
        end
    end

    function Subscriptions.UnsubscribeFromData(DataID, PlayerID)
        if DataSets[DataID] == nil and ActiveSubscriptions[DataID] == nil then
            warn("ERROR; Attempting to set cache for non-existant data")
            return
        end
        if ActiveSubscriptions[DataID] then
            local FindPlayer = table.find(ActiveSubscriptions[DataID], PlayerID)
            if FindPlayer then
                --> Remove the player from this subscription
                table.remove(ActiveSubscriptions[DataID], FindPlayer)
                --> Send them the remove signal
                ServerCommunication.FireRemoteEvent(PlayerID, "Subscriptions", "Remove", DataID)
                print("Player unsubscribed from data")
            end
        end
    end

    function Subscriptions.UnsubscribePlayer(PlayerID) --//Player has left?
        for DataName, Subscribers in pairs(ActiveSubscriptions) do
            for n, Subscriber in pairs(Subscribers) do
                if Subscriber == PlayerID then
                    table.remove(Subscribers, n)
                end
            end
        end
    end
end

--//CLIENT FUNCTIONS
if IsServer == false then
    local Connections = {}

    function Subscriptions.IncommingData(Action, DataID, ...) --//The player is recieving Data, decipher what we're doing with it.
        print(Action, DataID, ...)
        if Action == "Set" then
            print("Setting data for", DataID)
            DataSets[DataID]    = ...
            Connections[DataID] = {}
            Connections.Recieve(DataID)
        elseif Action == "Remove" then
            DataSets[DataID]            = nil
            DataSetAlterations[DataID]  = nil
            if Connections[DataID] and Connections[DataID]["Remove"] then --//If we want an action tied to the data being removed, we fire this here.
                Connections[DataID]["Remove"](DataID) --< Fires a removal action
            end
            Connections[DataID]         = nil
        else
            if DataSets[DataID] == nil then
                error("We do not have a record of this data, are we not subscribed?")
            end
            local ThisNewData = nil;
            if Action == "Update" then
                ThisNewData = {...}
                --Subscriptions.IncommingUpdate(DataID, unpack(...))
            elseif Action == "UpdateFromCache" then
                ThisNewData = ...
            else
                return
            end
            for _, x in pairs(ThisNewData) do
                Subscriptions.IncommingUpdate(DataID, unpack(x))
                if Connections[DataID] and Connections[DataID]["Update"] then --//If we want a generic update function to fire, call this.
                    Connections[DataID]["Update"](DataID, unpack(x)) --< Fires an update action
                end
            end

            --//WE NEED A METHOD OF CHECKING WHAT GOT PINGED
        end
    end

    function Subscriptions.IncommingUpdate(DataID, Type, Path, Changes)
        local DataSet = DataSets[DataID]
        if DataSet == nil then
            warn("No data exists")
            return
        end
        if ChangeTypes[Type] then
            ChangeTypes[Type](DataSet, Path, Changes)
        else
            warn(DataSet, Type, Path, Changes)
            warn("[ERROR]; We have been passed an invalid update type")
        end
    end

    function Subscriptions.RetrieveDataSetFromCache(DataID) --< Only returns cached data, not a call to retrieve.
        return DataSets[DataID] -- Data or nil
    end

    function Subscriptions.ConnectChangeToEvent(DataID, Path, Func) --Only fire an event if this PathPoint is altered. If no path is present, fire when data changes.
        if DataSets[DataID] then --//Path no longer represents a pathpoint, rather generic activation points.
            Connections[DataID][Path] =  Func
        elseif DataID and not Path then
            Connections[DataID] =  Func
        end
    end

    RemoteFolder.Subscriptions.OnClientEvent(Subscriptions.IncommingData)
end

return Subscriptions
