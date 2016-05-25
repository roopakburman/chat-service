
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect

{ cleanup
  clientConnect
  setCustomCleanup
  startService
} = require './testutils.coffee'

{ port
  user1
  user2
  user3
  roomName1
  roomName2
} = require './config.coffee'

module.exports = ->

  chatService = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    cleanup chatService, [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should emit consistencyFailure on leave channel errors', (done) ->
    chatService = startService { state : 'memory' }
    orig = chatService.transport.leaveChannel
    chatService.transport.leaveChannel = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    setCustomCleanup (cb) ->
      chatService.transport.leaveChannel = orig
      chatService.close cb
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, (error) ->
          expect(error).not.ok
          async.parallel [
            (cb) ->
              socket1.emit 'roomLeave', roomName1, (error) ->
                expect(error).not.ok
                cb()
            (cb) ->
              chatService.on 'consistencyFailure', (error, data) ->
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'roomName', 'userName', 'id', 'type'
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.id).equal(id)
                expect(data.type).equal('transportChannel')
                cb()
          ], done

  it 'should emit consistencyFailure on room access check errors', (done) ->
    chatService = startService { state : 'memory' }
    chatService.addRoom roomName1, null, ->
      chatService.state.getRoom(roomName1).then (room) ->
        orig = room.roomState.hasInList
        room.roomState.hasInList = ->
          orig.apply room.roomState, arguments
          .then -> throw new Error()
        setCustomCleanup (cb) ->
          room.roomState.hasInList = orig
          chatService.close cb
        async.parallel [
          (cb) ->
            chatService.execUserCommand true
            , 'roomRemoveFromList', roomName1, 'whitelist', [user1]
            , (error) ->
              expect(error).not.ok
              cb()
          (cb) ->
            chatService.once 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'roomName', 'userName', 'type'
              expect(data.roomName).equal(roomName1)
              expect(data.userName).equal(user1)
              expect(data.type).equal('roomUserlist')
              cb()
        ], (error) ->
          expect(error).not.ok
          async.parallel [
            (cb) ->
              chatService.execUserCommand true
              , 'roomAddToList', roomName1, 'whitelist', [user1]
              , (error) ->
                expect(error).not.ok
                cb()
            (cb) ->
              chatService.once 'consistencyFailure', (error, data) ->
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'roomName', 'userName', 'type'
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.type).equal('roomUserlist')
                cb()
          ], done

  it 'should emit consistencyFailure on socket leave errors', (done) ->
    chatService = startService { state : 'memory' }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getUser user1
          .then (user) ->
            orig = user.userState.removeSocketFromRoom
            user.userState.removeSocketFromRoom = ->
              orig.apply user.userState, arguments
              .then -> throw new Error()
            setCustomCleanup (cb) ->
              user.userState.removeSocketFromRoom =  orig
              chatService.close cb
            async.parallel [
              (cb) ->
                socket1.emit 'roomLeave', roomName1, (error, data) ->
                  expect(error).not.ok
                  cb()
              (cb) ->
                chatService.on 'consistencyFailure', (error, data) ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName', 'id', 'type'
                  expect(data.roomName).equal(roomName1)
                  expect(data.userName).equal(user1)
                  expect(data.id).equal(id)
                  expect(data.type).equal('userSockets')
                  cb()
            ], done

  it 'should emit consistencyFailure on leave room errors', (done) ->
    chatService = startService { state : 'memory' }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getRoom roomName1
          .then (room) ->
            orig = room.leave
            room.leave = ->
              orig.apply room, arguments
              .then -> throw new Error()
            setCustomCleanup (cb) ->
              room.leave = orig
              chatService.close cb
            async.parallel [
              (cb) ->
                socket1.emit 'roomLeave', roomName1, (error, data) ->
                  expect(error).not.ok
                  cb()
              (cb) ->
                chatService.on 'consistencyFailure', (error, data) ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName', 'type'
                  expect(data.roomName).equal(roomName1)
                  expect(data.userName).equal(user1)
                  expect(data.type).equal('roomUserlist')
                  cb()
            ], done

  it 'should emit consistencyFailure on remove socket errors', (done) ->
    chatService = startService { state : 'memory' }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getUser user1
          .then (user) ->
            orig = user.userState.removeSocket
            user.userState.removeSocket = ->
              orig.apply user.userState, arguments
              .then -> throw new Error()
            setCustomCleanup (cb) ->
              user.userState.removeSocket = orig
              chatService.close cb
            socket1.disconnect()
            chatService.on 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'userName', 'id', 'type'
              expect(data.userName).equal(user1)
              expect(data.id).equal(id)
              expect(data.type).equal('userSockets')
              done()

  it 'should emit consistencyFailure on on remove from room errors', (done) ->
    chatService = startService { state : 'memory' }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getUser user1
          .then (user) ->
            orig = user.userState.removeAllSocketsFromRoom
            user.userState.removeAllSocketsFromRoom = ->
              orig.apply user.userState, arguments
              .then -> throw new Error()
            setCustomCleanup (cb) ->
              user.userState.removeAllSocketsFromRoom = orig
              chatService.close cb
            chatService.execUserCommand true
            , 'roomAddToList', roomName1, 'blacklist', [user1]
            , (error) ->
              expect(error).not.ok
            chatService.on 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'roomName', 'userName', 'type'
              expect(data.roomName).equal(roomName1)
              expect(data.userName).equal(user1)
              expect(data.type).equal('userSockets')
              done()