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
