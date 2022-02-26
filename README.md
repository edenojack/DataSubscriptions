# DataSubscriptions

A method of ensuring that each client has a copy of only data they need, recieving updates when they need.
##
##

## DataSet
- A DataSet is an array of data that will be reflected to clients at some point. It can be made up of further arrays.
- They can be identified by using a DataID, a reference to each specific DataSet.
- You cannot overwrite an active DataID, but you can fully edit/remove an active DataID.

## Subsciptions
- On the server, a subscription is used to define if a player is/isn't meant to be recieving updates about a particular DataSet.
- On the client, a subscription is used to help determine what DataSets we are expected to have, and then further actions needed.

##
##

## Server
- Registers a DataSet with a unique DataID
- Makes changes to that DataSet
- Manages subscriptions to that data; subscribing/unsubscribing.

## Client
- Holds a cache of subscribed DataSets.
- Only ever recieves Data for subscribed DataSets.
- An all-covering function is able to be written to under "Recieve"
- Each DataSet can have a unique action assigned to "Update" and to "Remove"


### -> Recieve - Any new DataSets that are recieved will fire this event, only passing it's DataID.
### -> Update - Any updates to DataSets will fire a per-DataSet update event if one is attached, passing the DataID, the path to the changed data and the changed value.
### -> Remove - We are removing this DataSet as a whole, we can write a unique function here to help clean up.

##
