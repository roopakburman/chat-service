
ArgumentsValidator = require './ArgumentsValidator.coffee'
EventEmitter = require('events').EventEmitter
MaintenanceAPI = require './MaintenanceAPI.coffee'
MemoryState = require './MemoryState.coffee'
Promise = require 'bluebird'
RedisState = require './RedisState.coffee'
ServiceAPI = require './ServiceAPI.coffee'
SocketIOTransport = require './SocketIOTransport.coffee'
_ = require 'lodash'
uid = require 'uid-safe'

{ extend } = require './utils.coffee'

# @note This class describes socket.io server outgoing messages, not
#   actual methods.
#
# List of server messages that are sent to a client.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (userName) ->
#     socket.on 'directMessage', (fromUser, msg) ->
#       # just the same as any event. no reply is required.
#
class ServerMessages
  # Direct message. A message will have timestamp and author fields,
  # but other fields can be used if {ChatService#constructor}
  # `directMessagesChecker` hook is set.
  # @param fromUser [String] Message sender.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessage : (msg) ->

  # Direct message echo. If an user have several connections from
  # different sockets, and if one client sends
  # {UserCommands#directMessage}, others will receive a message echo.
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessageEcho : (toUser, msg) ->

  # Disconnected from a server.
  # @note Socket.io system event.
  # @param reason [Object] Socket.io disconnect info.
  disconnect : (reason) ->

  # Error events, like socket.io middleware error.
  # @note Socket.io system event.
  # @param error [Object]
  error : (error) ->

  # Indicates a successful login.
  # @param userName [String] UserName.
  # @param data [Object] Additional login data with an id of the socket.
  # @option data [String] id Socket id.
  loginConfirmed : (userName, data) ->

  # Indicates a login error.
  # @param error [Object] Error.
  loginRejected : (error) ->

  # Indicates that a user has lost a room access permission.
  # @param roomName [String] Room name.
  # @see UserCommands#roomAddToList
  # @see UserCommands#roomRemoveFromList
  roomAccessRemoved : (roomName) ->

  # Indicates a room access list add.
  # @param roomName [String] Rooms name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param userNames [Array<String>] UserNames removed from the list.
  # @see UserCommands#roomAddToList
  roomAccessListAdded : (roomName, listName, userNames) ->

  # Indicates a room access list remove.
  # @param roomName [String] Rooms name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param userNames [Array<String>] UserNames added to the list.
  # @see UserCommands#roomRemoveFromList
  roomAccessListRemoved : (roomName, listName, userNames) ->

  # Echoes room join from other user's connections.
  # @param roomName [String] UserName.
  # @param id [String] Socket id.
  # @param njoined [Number] Number of sockets that are still joined.
  # @see UserCommands#roomJoin
  roomJoinedEcho : (roomName, id, njoined) ->

  # Echoes room leave from other user's connections.
  # @param roomName [String] UserName.
  # @param id [String] Socket id.
  # @param njoined [Number] Number of sockets that are still joined.
  # @see UserCommands#roomLeave
  roomLeftEcho : (roomName, id, njoined) ->

  # Room message. A message will have timestamp, id and author fields,
  # but other fields can be used if {ChatService#constructor}
  # `roomMessagesChecker` hook is set.
  # @param roomName [String] Rooms name.
  # @param msg [Object<textMessage:String, timestamp:Number,
  #   author:String, id:Number>] Message.
  # @see UserCommands#roomMessage
  roomMessage : (roomName, msg) ->

  # Indicates a room mode change.
  # @param roomName [String] Rooms name.
  # @param mode [Boolean]
  # @see UserCommands#roomSetWhitelistMode
  roomModeChanged : (roomName, mode) ->

  # Indicates that an another user has joined a room.
  # @param roomName [String] Rooms name.
  # @param userName [String] UserName.
  # @see UserCommands#roomJoin
  roomUserJoined : (roomName, userName) ->

  # Indicates that an another user has left a room.
  # @param roomName [String] Rooms name.
  # @param userName [String] UserName.
  # @see UserCommands#roomLeave
  roomUserLeft : (roomName, userName) ->

  # Indicates a connection of an another socket with the same user.
  # @param id [String] Socket id.
  # @param nconnected [Number] Total number of users's sockets.
  socketConnectEcho : (id, nconnected) ->

  # Indicates a disconnection of an another socket with the same user.
  # @param id [String] Socket id.
  # @param nconnected [Number] Total number of users's sockets.
  socketDisconnectEcho : (id, nconnected) ->

  # Custom message from a server or from an another socket of the same
  #   user.
  # @param data [Object] Arbitrary data.
  systemMessage : (data) ->


# @note This class describes socket.io server incoming messages, not
#   actual methods.
#
# List of commands that are sent from a client. Result is sent back as
# a socket.io ack with the standard (error, data) callback parameters
# format. Error is ether a String or an Object, depending on
# {ChatService#constructor} `useRawErrorObjects` option. See
# {ChatServiceError} for an errors list. Some messages will echo
# {ServerMessages} to other user's sockets or trigger sending
# {ServerMessages} to other users. It is also possible to run this
# commands server-side using {ServiceAPI~execUserCommand}.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (userName, authData) ->
#     socket.emit 'roomJoin', roomName, (error, data) ->
#       # this is a socket.io ack waiting callback. socket is joined
#       # the room, or an error occurred, we get here only when the
#       # server has finished roomJoin command processing.
#
class UserCommands
  # Adds userNames to user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param userNames [Array<String>] UserNames to add to the list.
  # @param cb [Function<error, null>] Send ack with an error or an
  #   empty data.
  directAddToList : (listName, userNames, cb) ->

  # Gets direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param cb [Function<error, Array<String>>] Sends ack with an error or
  #   the requested list.
  directGetAccessList : (listName, cb) ->

  # Gets direct messaging whitelist only mode. If it is true then
  # direct messages are allowed only for users that are in the
  # whitelist. Otherwise direct messages are accepted from all
  # users that are not in the blacklist.
  # @param cb [Function<error, Boolean>] Sends ack with an error or
  #   the user's whitelist only mode.
  directGetWhitelistMode : (cb) ->

  # Sends {ServerMessages#directMessage} to an another user, if
  # {ChatService#constructor} `enableDirectMessages` option is
  # true. Also sends {ServerMessages#directMessageEcho} to other
  # senders's sockets.
  # @see ServerMessages#directMessage
  # @see ServerMessages#directMessageEcho
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage : String>] Message. Other fields
  #   can be used if {ChatService#constructor} `directMessagesChecker`
  #   hook is set.
  # @param cb [Function<error, Object<textMessage:String,
  #   timestamp:Number, author:String>>] Sends ack with an error or
  #   a processed message.
  directMessage : (toUser, msg, cb) ->

  # Removes userNames from user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param userNames [Array<String>] User names to remove from the list.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  directRemoveFromList : (listName, userNames, cb) ->

  # Sets direct messaging whitelist only mode.
  # @see UserCommands#directGetWhitelistMode
  # @param mode [Boolean]
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  directSetWhitelistMode : (mode, cb) ->

  # Emitted when a socket disconnects from the server.
  # @note Can't be send by a client as a Socket.io message, use
  #   socket.disconnect() instead.
  # @param reason [String] Reason.
  # @param cb [Function<error, null>] Callback.
  disconnect : (reason, cb) ->

  # Gets a list of all sockets with corresponding joined rooms. This
  # returns information about all user's sockets.
  # @param cb [Function<error, Object<Hash>>] Sends ack with an error
  #   or an object, where sockets are keys and arrays of rooms are
  #   values.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomLeftEcho
  listOwnSockets : (cb) ->

  # Adds userNames to room's blacklist, adminlist and whitelist. Also
  # removes users that have lost an access permission in the result of
  # an operation, sending {ServerMessages#roomAccessRemoved}. Also
  # sends {ServerMessages#roomAccessListAdded} to all room users if
  # {ChatService#constructor} `enableAccessListsUpdates` option is
  # true.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param userNames [Array<String>] User names to add to the list.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  # @see ServerMessages#roomAccessRemoved
  # @see ServerMessages#roomAccessListAdded
  roomAddToList : (roomName, listName, userNames, cb) ->

  # Creates a room if {ChatService#constructor}
  # `enableRoomsManagement` option is true.
  # @param roomName [String] Rooms name.
  # @param mode [bool] Room mode.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  roomCreate : (roomName, mode, cb) ->

  # Deletes a room if {ChatService#constructor}
  # `enableRoomsManagement` is true and the user has an owner
  # status. Sends {ServerMessages#roomAccessRemoved} to all room
  # users.
  # @param roomName [String] Rooms name.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  roomDelete : (roomName, cb) ->

  # Gets room messaging userlist, blacklist, adminlist and whitelist.
  # @param roomName [String] Room name.
  # @param listName [String] 'userlist', 'blacklist', 'adminlist', 'whitelist'.
  # @param cb [Function<error, Array<String>>] Sends ack with an error
  #   or the requested list.
  roomGetAccessList : (roomName, listName, cb) ->

  # Gets the room owner.
  # @param roomName [String] Room name.
  # @param cb [Function<error, String>] Sends ack with an error or
  #   the room owner.
  roomGetOwner : (roomName, cb) ->

  # Gets the room messaging whitelist only mode. If it is true, then
  # join is allowed only for users that are in the
  # whitelist. Otherwise all users that are not in the blacklist can
  # join.
  # @param roomName [String] Room name.
  # @param cb [Function<error, Boolean>] Sends ack with an error or
  #   whitelist only mode.
  roomGetWhitelistMode : (roomName, cb) ->

  # Gets latest room messages. The maximum size is set by
  # {ChatService#constructor} `historyMaxGetMessages` option. Messages
  # are sorted as newest first.
  # @param roomName [String] Room name.
  # @param cb [Function<error, Array<Object>>] Sends ack with an
  #   error or array of messages.
  # @see UserCommands#roomMessage
  roomRecentHistory : (roomName, cb)->

  # Returns messages that were sent after a message with the specified
  # id. The returned number of messages is limited by the limit
  # parameter. The maximum limit is bounded by
  # {ChatService#constructor} `historyMaxGetMessages` option. If the
  # specified id was deleted due to history limit, it returns messages
  # starting from the oldest available. Messages are sorted as newest
  # first.
  # @param roomName [String] Room name.
  # @param id [Number] Starting message id.
  # @param limit [Number] Maximum number of messages to return. The
  #   maximum number is limited by {ChatService#constructor}
  #   `historyMaxGetMessages` option.
  # @param cb [Function<error, Array<Object>>] Sends ack with an
  #   error or array of messages.
  # @see UserCommands#roomHistoryLastId
  # @see UserCommands#roomMessage
  roomHistoryGet : (roomName, id, limit, cb) ->

  # Gets the the room history information.
  # @param roomName [String] Room name.
  # @param cb [Function<error, Object<historyMaxGetMessages:Number,
  #   historyMaxSize:Number, historySize:Number,
  #   lastMessageId:Number>>] Sends ack with an error or an object
  #   contains the room history information.
  # @see UserCommands#roomHistoryGet
  roomHistoryInfo : (roomName, cb) ->

  # Joins room, an user must join the room to receive messages or
  # execute room commands. Sends {ServerMessages#roomJoinedEcho} to other
  # user's sockets. Also sends {ServerMessages#roomUserJoined} to other
  # room users if {ChatService#constructor} `enableUserlistUpdates` option is
  # true.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomUserJoined
  # @param roomName [String] Room name.
  # @param cb [Function<error, Number>] Sends ack with an error or a
  #   number of joined user's sockets.
  roomJoin : (roomName, cb) ->

  # Leaves room. Sends {ServerMessages#roomLeftEcho} to other user's
  # sockets. Also sends {ServerMessages#roomUserLeft} to other room
  # users if {ChatService} `enableUserlistUpdates` option is true.
  # @see ServerMessages#roomLeftEcho
  # @see ServerMessages#roomUserLeft
  # @param roomName [String] Room name.
  # @param cb [Function<error, Number>] Sends ack with an error or a
  #   number of joined user's sockets.
  roomLeave : (roomName, cb) ->

  # Sends {ServerMessages#roomMessage} to all room users.
  # @see ServerMessages#roomMessage
  # @param roomName [String] Room name.
  # @param msg [Object<textMessage : String>] Message. Other fields
  #   can be used if {ChatService#constructor} `roomMessagesChecker`
  #   hook is set.
  # @param cb [Function<error, Number>] Sends ack with an error or the
  #   message id.
  roomMessage : (roomName, msg, cb) ->

  # Removes userNames from room's blacklist, adminlist and
  # whitelist. Also removes users that have lost an access permission
  # in the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}. Also sends
  # {ServerMessages#roomAccessListRemoved} to all room users if
  # {ChatService#constructor} `enableAccessListsUpdates` option is
  # true.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param userNames [Array<String>] UserNames to remove from the list.
  # @param cb [Function<error, null>] Sends ack with an error or an
  #   empty data.
  # @see ServerMessages#roomAccessRemoved
  # @see ServerMessages#roomAccessListRemoved
  roomRemoveFromList : (roomName, listName, userNames, cb) ->

  # Sets room messaging whitelist only mode. Also removes users that
  # have lost an access permission in the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}.
  # @see UserCommands#roomGetWhitelistMode
  # @see ServerMessages#roomAccessRemoved
  # @param roomName [String] Room name.
  # @param mode [Boolean]
  # @param cb [Function<error, null>] Sends ack with an error or an
  #   empty data.
  roomSetWhitelistMode : (roomName, mode, cb) ->

  # Send user's joined state and last state change timestamp.
  # @param roomName [String] Rooms name.
  # @param userName [String] UserName.
  # @param cb [Function<error, Object<timestamp:Number,
  #   joined:Boolean> >] Sends ack with an error or an object with a
  #   joined state and a state switch timestamp.
  roomUserSeen : (roomName, userName, cb) ->

  # Send data to other connected users's sockets. Or can be used with
  # {ServiceAPI~execUserCommand} and the null id to send data from a
  # server to all users's sockets.
  # @param data [Object] Arbitrary data.
  # @param cb [Function<error, null>] Sends ack with an error or an
  #   empty data.
  systemMessage : (data, cb) ->


# Service class, is the package exported object.
# @extend ServiceAPI
# @extend MaintenanceAPI
class ChatService extends EventEmitter

  extend @, ServiceAPI, MaintenanceAPI

  # Crates an object and starts a new server instance.
  #
  #
  # @option options [Number] closeTimeout Maximum time in ms to wait
  #   before a server disconnects all clients on shutdown, default is
  #   `10000`.
  #
  # @option options [Boolean] enableAccessListsUpdates Enables
  #   {ServerMessages#roomModeChanged},
  #   {ServerMessages#roomAccessListAdded} and
  #   {ServerMessages#roomAccessListRemoved} messages, default is
  #   `false`.
  #
  # @option options [Boolean] enableDirectMessages Enables user to
  #   user {UserCommands#directMessage} communication, default is
  #   `false`.
  #
  # @option options [Boolean] enableRoomsManagement Allows to use
  #   {UserCommands#roomCreate} and {UserCommands#roomDelete}, dafault
  #   is `false`.
  #
  # @option options [Boolean] enableUserlistUpdates Enables
  #   {ServerMessages#roomUserJoined} and
  #   {ServerMessages#roomUserLeft} messages, default is `false`.
  #
  # @option options [Number] historyMaxGetMessages Room history size
  #   available via {UserCommands#roomRecentHistory} or
  #   {UserCommands#roomHistoryGet}, default is `100`.
  #
  # @option options [Number] defaultHistoryLimit Is used for
  #   {UserCommands#roomCreate} or when {ServiceAPI~addRoom} is called
  #   without `historyMaxSize` option, default is `10000`.
  #
  # @option options [Number] port Server port, default is `8000`.
  #
  # @option options [Boolean] useRawErrorObjects Send error objects
  #   instead of strings, default is `false`. See {ChatServiceError}.
  #
  #
  # @option hooks [Function<ChatService, socketid:String,
  #   Callback<Error, username:String, authData:Object>>] onConnect
  #   Client connection hook. Must call a callback with either an
  #   error or an user name and an auth data. User name and auth data
  #   are send back with a {ServerMessages#loginConfirmed}
  #   message. Error is sent as a {ServerMessages#loginRejected}
  #   message.
  #
  # @option hooks [Function<ChatService, Callback<Error>>] onStart
  #   Executes when server is started (after a state and a transport
  #   are up, but before message processing is started). Must call a
  #   callback.
  #
  # @option hooks [Function<ChatService, Error, Callback<Error>>]
  #   onClose Executes when server is closed (after a transport is
  #   closed and all clients are disconnected, but a state is still
  #   up). Must call a callback.
  #
  # @option hooks [Function<Object, Callback<Error>>]
  #   directMessagesChecker Validator for {UserCommands#directMessage}
  #   message objects. When is set allow a custom content in direct
  #   messages. Must call a callback.
  #
  # @option hooks [Function<Object, Callback<Error>>]
  #   roomMessagesChecker Validator for {UserCommands#roomMessage}
  #   message objects. When is set allow a custom content in room
  #   messages. Must call a callback.
  #
  # @option hooks [Function<execInfo, Callback<Rest...>>] {cmd}Before
  #   Before hooks are available for all {UserCommands} and executed
  #   after an arguments validation. Callback must be called either
  #   without arguments to continue command execution, or with
  #   arguments to stop execution and return arguments as results to
  #   the command issuer.
  #
  # @option hooks [Function<execInfo, Callback<Rest...>>] {cmd}After
  #   After hooks are available for all {UserCommands}. Callback must
  #   be called without arguments to return unchanged result or error
  #   to the command issuer, or with arguments to return arguments as
  #   results to the command issuer.
  #
  #
  # @option options [String or Constructor] state Chat state. Can be
  #   either `'memory'` or `'redis'` for built-in states. Default is
  #   `'memory'`.
  #
  # @option options [String or Constructor] transport
  #   Transport. Default is `'socket.io'`.
  #
  # @option options [String or Constructor] adapter
  #   Socket.io adapter, used only if no `io` object is passed in
  #   `transportOptions`. Can be either `'memory'` or `'redis`' for
  #   built-in adapter, or a custom state constructor function that
  #   implements the Socket.io adapter API. Default is `'memory'`.
  #
  # @note `'redis'` state and `'redis'` adapter and theirs options are
  #   NOT related, two separate clients are used with two different
  #   configurations, which can be set to use the same Redis server.
  #
  # @option options [Object] stateOptions Options for a
  #   redis state.
  #
  # @option options [Object] transportOptions Options for a
  #   socket.io transport.
  #
  # @option options [Object or Array<Object>] adapterOptions Socket.io
  #   adapter constructor arguments, used only when no `io` object is
  #   passed in `transportOptions`.
  #
  #
  # @option transportOptions [String] namespace Socket.io namespace,
  #   default is `'/chat-service'`.
  #
  # @option transportOptions [Object] io Socket.io instance that
  #   should be used by ChatService.
  #
  # @option transportOptions [Object] http Use socket.io http server
  #   integration, used only when no `io` object is passed in
  #   `transportOptions`.
  #
  # @option transportOptions [Object] ioOptions Socket.io additional
  #   options, used only when no `io` object is passed in
  #   `transportOptions`.
  #
  #
  # @option stateOptions [Boolean] useCluster Enable Redis cluster,
  #   default is `false`.
  #
  # @option stateOptions [Number] lockTTL Locks timeout in ms,
  #   default is `5000`.
  #
  # @option stateOptions [Object or Array<Object>] redisOptions
  #   ioredis client constructor arguments. If useCluster is set, used
  #   as arguments for a Cluster client.
  #
  #
  constructor : (@options = {}, @hooks = {}) ->
    @setOptions()
    @setServer()
    @startServer()


  # @property [Object] {ArgumentsValidator} instance.
  validator: null

  # @property [Object or null] Socket.io server.
  io: null

  # @property [Object or null] Socket.io server namespace.
  nsp: null

  # @property [Object or null] State ioredis instance.
  redis: null

  # @property [String] Service instance UID.
  instanceUID: ''

  # @private
  # @nodoc
  setOptions : ->
    @instanceUID = uid.sync 18
    @runningCommands = 0
    @closed = false

    @closeTimeout = @options.closeTimeout || 10000
    @enableAccessListsUpdates= @options.enableAccessListsUpdates || false
    @enableDirectMessages = @options.enableDirectMessages || false
    @enableRoomsManagement = @options.enableRoomsManagement || false
    @enableUserlistUpdates = @options.enableUserlistUpdates || false
    @historyMaxGetMessages = @options.historyMaxGetMessages
    if not _.isNumber(@historyMaxGetMessages) or @historyMaxGetMessages < 0
      @historyMaxGetMessages = 100
    @defaultHistoryLimit = @options.defaultHistoryLimit
    if not _.isNumber(@defaultHistoryLimit) or @defaultHistoryLimit < 0
      @defaultHistoryLimit = 10000
    @port = @options.port || 8000
    @useRawErrorObjects = @options.useRawErrorObjects || false

    @adapterConstructor = @options.adapter || 'memory'
    @adapterOptions = _.castArray @options.adapterOptions
    @stateConstructor = @options.state || 'memory'
    @stateOptions = @options.stateOptions || {}
    @transportConstructor = @options.transport || 'socket.io'
    @transportOptions = @options.transportOptions || {}

    @directMessagesChecker = @hooks.directMessagesChecker
    @roomMessagesChecker = @hooks.roomMessagesChecker


  # @private
  # @nodoc
  setServer : ->
    State = switch true
      when @stateConstructor == 'memory' then MemoryState
      when @stateConstructor == 'redis' then RedisState
      when _.isFunction @stateConstructor then @stateConstructor
      else throw new Error "Invalid state: #{@stateConstructor}"
    Transport = switch true
      when @transportConstructor == 'socket.io' then SocketIOTransport
      when _.isFunction @transportConstructor then @transportConstructor
      else throw new Error "Invalid transport: #{@transportConstructor}"
    @userCommands = new UserCommands()
    @serverMessages = new ServerMessages()
    @validator = new ArgumentsValidator @
    @state = new State @, @stateOptions
    @transport = new Transport @, @transportOptions
    , @adapterConstructor, @adapterOptions

  # @private
  # @nodoc
  startServer : ->
    if @hooks.onStart
      @hooks.onStart @, (error) =>
        if error and not @closed
          @closed = true
          Promise.join @transport.close(), @state.close(), =>
            @emit 'closed', error
        else
          @transport.setEvents()
    else
      @transport.setEvents()

  # Closes server.
  # @note __MUST__ be called before node process shutdown to correctly
  #   update the state.
  # @param done [callback] Optional callback.
  # @return [Promise]
  close : (done) ->
    if @closed then return Promise.resolve()
    @closed = true
    @transport.close()
    .then =>
      if @hooks.onClose
        Promise.fromCallback (cb) =>
          @hooks.onClose @, null, cb
    , (error) =>
      if @hooks.onClose
        Promise.fromCallback (cb) =>
          @hooks.onClose @, error, cb
      else
        Promise.reject error
    .finally =>
      @state.close()
      .finally => @emit 'closed', null
    .asCallback done


module.exports = ChatService