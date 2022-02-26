local EdTech            = require(game:GetService("ReplicatedFirst").EdTech.Starter)
local RunService 		= game:GetService("RunService")

local IsServer 		    = RunService:IsServer()
local Communication     = EdTech.Get("Communication")

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
    local ServerCommunication   = Communication

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

    Communication.BindRemoteEvent("Subscriptions", function(...)
        Subscriptions.IncommingData(...)
    end)
end

return Subscriptions

--[[
    DataSubscription Uses

    --Server functions

    DataSubscriptions.RegisterDataSet(DataID, OriginalDataSet)
        -> Creates a DataSet with the given DataID. This ID is our reference to all things related to this data.

    DataSubscriptions.RemoveDataSet()

    DataSubscriptions.DataSetUpdated()

    DataSubscriptions.SubscribeToData(DataID, UserId) -> Server function, *must* be set via server.
        -> Signals that this Player.UserID should be subscribed to this data + recieve updates to it's given data.
        -> Fires the subscription remote via Communication with; FireRemoteEvent(PlayerID, "Subscriptions", "Set", DataID, DataSets[DataID])
            -> See client "ConnectChangeToEvent" for information regarding the "Set" action

    DataSubscription.SetCache(DataID, ChangeType, Path, UpdatedData)
        -> Creates a cache of Data that has changed, but has not finished. This stops individual changes being fired, where a group change would suffice.

    DataSubscription.DataSetSendCache(DataID)
        -> Any changes we needed to make to the cache have now been implemented. Passing the ID will now send all current changes.

    --Client functions

    DataSubscriptions.IncommingData(Action, DataID, ...)
        -> "Action" dicates what we are about to do with this information;
            - "Set": Creates our data + fires the Receive Change event.
                -! Creates an entry of this Data within our DataSets table, creates tables for Connections.
                    -< Retrieveable by calling DataSubscriptions.RetrieveDataSetFromCache(DataID)
                -> (DataSubscriptions.ConnectChangeToEvent("Recieve", nil, Func)) -> Func(DataID)
            - "Remove": Removes all local entries of this data + fires the Remove Change event.
                -! Removes any entries relating to DataID; DataSets, DataSetAlterations
                -? Is there a function tied to the Removal of this Data? DataID["Remove"]
                    -> (DataSubscriptions.ConnectChangeToEvent(DataID, "Remove", DestroyPlot)) -> DestroyPlot(DataID)
                -! Removes Connections
            - "Update": Calls IncommingUpdate(DataID, unpack(...))
            - "UpdateFromCache": iterates over the given cache (...) of data, calling IncommingUpdate(DataID, unpack(ThisData)) on each one.
            -? If there is an Change Event tied to DataID["Update"]
                    ->(DataSubscriptions.ConnectChangeToEvent(DataID, "Update", UpdatePlot)) -> UpdatePlot(DataID)
            -> Fire DataID["Update"](DataID) - This takes place after all updates have taken place, for both Update & UpdateFromCache

    DataSubscriptions.RetrieveDataSetFromCache(DataID)
        -> Retrieves Data from a local cache, will not request to retrieve any data.

    DataSubscriptions.ConnectChangeToEvent(DataID, Path, Func)
        -> By default "Recieve" as a DataID is automatically fired upon recieving Data with the Action *Set*, Path is un-needed.
        -> DataID + ""

]]

--[[Example use case

-- Players can change plots with furniture, but we only want to load other player's plots when we're close.

> = event
-! An action/action description
-? An explanation
-> We are sending something
-= We are defining something

-Server

    - Player events;
        > ThisPlayer joins;
            -! Create a new blank, or loaded data plot for each new player, called PlotData
            -> DataSubscriptions.RegisterDataSet(ThisPlayerID.."Plot", PlotData)
            -= Let's have PlotData be;
            {
                Plots   = PlayerFolders.Plot;       --A reference to Instances within the game
                Objects = OurData.PlacedObjects;    --A list of data about the objects found ontop of the plots.
            }

        > ThisPlayer is close enough to ThatPlayer's plot;
            -! The Server now tells the client that they have an active subscription to this data + gives it the current data.
            -> DataSubscriptions.SubscribeToData(ThatPlayerID.."Plot", ThisPlayerID)
                -> The client is sent the "Set" command

        > ThisPlayer is too far from ThatPlayer's plot
            -> DataSubscriptions.UnsubscribeFromData(ThatPlayerID.."Plot", ThisPlayerID)
            -! The Server now unsubscribes this player from any future updates of this *specific* DataSet.
                -> The client is sent the "Remove" command.
            -! We are still subscribed to any other subscriptions we've been told about.

        > ThisPlayer leaves;
            > We need to remove their data now that they're not present;
                -> DataSubscriptions.RemoveDataSet(ThisPlayerID.."Plot")
                -! Other players subscribed to this Data are now automatically given the "Remove" command.
            > We ensure that this player is unsubscribed from any other DataSets
                -> DataSubscriptions.UnsubscribePlayer(ThisPlayerID)

    - Plot events;
        -? Upon a player joining, their DataSet is registered. We cannot alter an un-registered DataSet.
        -= ObjectUID, ThisObjectData = Unique ID for an object, Unique data for this object

        > ThisPlayer places a new object on their plot;
            -! Server recieves an external "Place" event, server verifies it's valid and allows us to add the new data;
            -> DataSubscriptions.DataSetUpdated(ThisPlayerID.."Plot", "Add", {"Objects", ObjectUID}, ThisObjectData)

        > ThisPlayer rotates/moves an object on their plot;
            -! Server recieves an external "Update" event, server verifies it's valid and allows us to update ThisObjectData with new ThisObjectData
            -> DataSubscriptions.DataSetUpdated(ThisPlayerID.."Plot", "Update", {"Objects", ThisObjectUID}, ThisNewObjectData)

        > ThisPlayer removes an object on their plot;
            -! Server recives an external "Remove" event, server verifies to make sure this object exists.
            -> DataSubscriptions.DataSetUpdated(ThisPlayerID.."Plot", "Remove", {"Objects", ThisObjectUID})

Client
    -? A Client does not need a subscription to it's own data. Once it has recieved it initially, the server is in charge of reflecting any updates the client requests.
       The player is given the ability to change their data locally, it's up external remotes + server code to verify any changes.

    - Player events;
        > ThisPlayer joins.
            -! Player connects RecieveNewPlotData to the Recieve Change Event;
                -! DataSubscriptions.ConnectChangeToEvent("Recieve", nil, RecieveNewPlotData)
                    -? RecieveNewPlotData(DataID); Fetch the data from DataID, establish our "Remove" and "Update" Change events
                        -! RetrieveDataSetFromCache(DataID)
                        -! DataSubscriptions.ConnectChangeToEvent(DataID, "Remove", RemovePlot)
                            -? RemovePlot(DataID): Removes any physical/cached data from this plot.
                        -! DataSubcriptions.ConnectChangeToEvent(DataID, "Update", UpdatePlot)
                            -? UpdatePlot(DataID): Finds changes to our cached data, updates the physical representation.
            -! Requests their Plot's data from the server + retrieves it.
            -> Loads the plots + objects from the given instructions

        > ThisPlayer alters/adds/removes an object
            -! Tells the server, performs the action locally, awaits verification.

        > ThisPlayer has been told they're subscribed to a new DataSet (we're close to another player's plot)
            -! Server has given us the "Set" Action;
                -! We Cache the given data
                -! We fire the connected "Recieve" Change Event, RecieveNewPlotData(ThisDataID)
                    -? Any future changes, including the removal of the plot is now automatically

        > ThisPlayer has been told they're unsubscribing from a DataSet (We have left another player's plot)
            -! Server has given us the "Remove" action for ThisDataID.
                -! Check if we have a DataSet under ThisDataID
                    -! Check if we have anything Change Event connected to "Remove" for this DataSet, and fire it if we do.
                        -> RemovePlot(ThisDataID)
]]
