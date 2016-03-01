
Deque = require 'collections/deque'
FastSet = require 'collections/fast-set'
Map = require 'collections/fast-map'
_ = require 'lodash'
async = require 'async'

{ withEH, asyncLimit } = require './utils.coffee'


# @private
# @nodoc
initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


# Implements state API lists management.
# @private
# @nodoc
class ListsStateMemory

  # @private
  checkList : (listName, cb) ->
    unless @hasList listName
      error = @errorBuilder.makeError 'noList', listName
    process.nextTick -> cb error

  # @private
  addToList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @[listName].addEach elems
      cb()

  # @private
  removeFromList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @[listName].deleteEach elems
      cb()

  # @private
  getList : (listName, cb) ->
    @checkList listName, withEH cb, =>
      data = @[listName].toArray()
      cb null, data

  # @private
  hasInList : (listName, elem, cb) ->
    @checkList listName, withEH cb, =>
      data = @[listName].has elem
      data = if data then true else false
      cb null, data

  # @private
  whitelistOnlySet : (mode, cb) ->
    @whitelistOnly = if mode then true else false
    process.nextTick -> cb()

  # @private
  whitelistOnlyGet : (cb) ->
    m = @whitelistOnly
    process.nextTick -> cb null, m


# Implements room state API.
# @private
# @nodoc
class RoomStateMemory extends ListsStateMemory

  # @private
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    @historyMaxGetMessages = @server.historyMaxGetMessages
    @historyMaxMessages = @server.historyMaxMessages
    @whitelist = new FastSet
    @blacklist = new FastSet
    @adminlist = new FastSet
    @userlist = new FastSet
    @lastMessages = new Deque
    @whitelistOnly = false
    @owner = null

  # @private
  initState : (state = {}, cb) ->
    { whitelist, blacklist, adminlist
    , lastMessages, whitelistOnly, owner } = state
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    initState @adminlist, adminlist
    initState @lastMessages, lastMessages
    @whitelistOnly = if whitelistOnly then true else false
    @owner = if owner then owner else null
    process.nextTick -> cb()

  # @private
  removeState : (cb) ->
    process.nextTick -> cb()

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  ownerGet : (cb) ->
    owner = @owner
    process.nextTick -> cb null, owner

  # @private
  ownerSet : (owner, cb) ->
    @owner = owner
    process.nextTick -> cb()

  # @private
  messageAdd : (msg, cb) ->
    if @historyMaxMessages <= 0 then return process.nextTick -> cb()
    @lastMessages.unshift msg
    if @lastMessages.length > @historyMaxMessages
      @lastMessages.pop()
    process.nextTick -> cb()

  # @private
  messagesGet : (cb) ->
    data = @lastMessages.toArray()
    process.nextTick -> cb null, data

  # @private
  getCommonUsers : (cb) ->
    diff = (@userlist.difference @whitelist).difference @adminlist
    data = diff.toArray()
    process.nextTick -> cb null, data


# Implements direct messaging state API.
# @private
# @nodoc
class DirectMessagingStateMemory extends ListsStateMemory

  # @private
  constructor : (@server, @username) ->
    @whitelistOnly
    @whitelist = new FastSet
    @blacklist = new FastSet

  # @private
  initState : ({ whitelist, blacklist, whitelistOnly } = {}, cb) ->
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    @whitelistOnly = if whitelistOnly then true else false
    process.nextTick -> cb()

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]


# Implements user state API.
# @private
# @nodoc
class UserStateMemory

  # @private
  constructor : (@server, @username) ->
    @socketsToRooms = new Map
    @roomsToSockets = new Map
    @echoChannel = @makeEchoChannelName @username

  # @private
  makeEchoChannelName : (userName) ->
    "echo:#{userName}"

  # @private
  addSocket : (id, cb) ->
    roomsset = new FastSet
    @socketsToRooms.set id, roomsset
    nconnected = @socketsToRooms.length
    process.nextTick -> cb null, nconnected

  # @private
  getAllSockets : (cb) ->
    sockets = @socketsToRooms.keys()
    process.nextTick -> cb null, sockets

  # @private
  getAllRooms : (cb) ->
    rooms = @roomsToSockets.keys()
    process.nextTick -> cb null, rooms

  # @private
  getSocketsToRooms : (cb) ->
    result = {}
    sockets = @socketsToRooms.keys()
    for id in sockets
      socketsset = @socketsToRooms.get id
      result[id] = socketsset.toArray()
    process.nextTick -> cb null, result

  # @private
  addSocketToRoom : (id, roomName, cb) ->
    roomsset = @socketsToRooms.get id
    socketsset = @roomsToSockets.get roomName
    unless socketsset
      socketsset = new FastSet
      @roomsToSockets.set roomName, socketsset
    roomsset.add roomName
    socketsset.add id
    njoined = socketsset.length
    process.nextTick -> cb null, njoined

  # @private
  removeSocketFromRoom : (id, roomName, cb) ->
    roomsset = @socketsToRooms.get id
    socketsset = @roomsToSockets.get roomName
    roomsset.delete roomName
    socketsset.delete id
    njoined = socketsset?.length || 0
    process.nextTick -> cb null, njoined

  # @private
  removeAllSocketsFromRoom : (roomName, cb) ->
    sockets = @socketsToRooms.keys()
    socketsset = @roomsToSockets.get roomName
    removedSockets = socketsset?.toArray()
    for id in removedSockets
      roomsset = @socketsToRooms.get id
      roomsset.delete roomName
    socketsset = socketsset?.difference sockets
    @roomsToSockets.set roomName, socketsset
    process.nextTick -> cb null, removedSockets

  # @private
  removeSocket : (id, cb) ->
    rooms = @roomsToSockets.toArray()
    roomsset = @socketsToRooms.get id
    removedRooms = roomsset?.toArray()
    joinedSockets = []
    for roomName, idx in removedRooms
      socketsset = @roomsToSockets.get roomName
      socketsset.delete id
      njoined = socketsset.length
      joinedSockets[idx] = njoined
    roomsset = roomsset?.difference removedRooms
    @socketsToRooms.delete id
    nconnected = @socketsToRooms.length
    process.nextTick -> cb null, removedRooms, joinedSockets, nconnected

  # @private
  lockSocketRoom : (id, roomName, cb) ->
    process.nextTick -> cb()

  # @private
  setRoomAccessRemoved : (roomName, cb) ->
    process.nextTick -> cb()

  # @private
  setSocketDisconnecting : (id, cb) ->
    process.nextTick -> cb()

  # @private
  bindUnlock : (lock, op, username, id, cb) ->
    (args...) ->
      process.nextTick -> cb args...


# Implements global state API.
# @private
# @nodoc
class MemoryState

  # @private
  constructor : (@server, @options) ->
    @errorBuilder = @server.errorBuilder
    @users = {}
    @rooms = {}
    @RoomState = RoomStateMemory
    @UserState = UserStateMemory
    @DirectMessagingState = DirectMessagingStateMemory

  # @private
  getRoom : (name, cb) ->
    r = @rooms[name]
    unless r
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error, r

  # @private
  addRoom : (name, state, cb) ->
    room = @server.makeRoom name
    unless @rooms[name]
      @rooms[name] = room
    else
      error = @errorBuilder.makeError 'roomExists', name
      return process.nextTick -> cb error
    if state
      room.initState state, cb
    else
      process.nextTick -> cb()

  # @private
  removeRoom : (name, cb) ->
    if @rooms[name]
      delete @rooms[name]
    else
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error

  # @private
  listRooms : (cb) ->
    process.nextTick => cb null, _.keys @rooms

  # @private
  removeSocket : (uid, id, cb) ->
    process.nextTick -> cb()

  # @private
  loginUser : (uid, name, socket, cb) ->
    user = @users[name]
    if user
      user.registerSocket socket, cb
    else
      newUser = @server.makeUser name
      @users[name] = newUser
      newUser.registerSocket socket, cb

  # @private
  getUser : (name, cb) ->
    user = @users[name]
    unless user
      error = @errorBuilder.makeError 'noUser', name
    process.nextTick -> cb error, user

  # @private
  addUser : (name, state, cb) ->
    user = @users[name]
    if user
      error = @errorBuilder.makeError 'userExists', name
      return process.nextTick -> cb error
    user = @server.makeUser name
    @users[name] = user
    if state
      user.initState state, cb
    else
      process.nextTick -> cb()

  # @private
  removeUserData : (name, cb) ->
    #TODO


module.exports = MemoryState