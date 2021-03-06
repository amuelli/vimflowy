require 'blanket'
require 'coffee-script/register'
assert = require 'assert'
_ = require 'lodash'

dataStore = require '../assets/js/datastore.coffee'
Data = require '../assets/js/data.coffee'
View = require '../assets/js/view.coffee'
KeyBindings = require '../assets/js/keyBindings.coffee'
KeyHandler = require '../assets/js/keyHandler.coffee'
Register = require '../assets/js/register.coffee'
Settings = require '../assets/js/settings.coffee'
Logger = require '../assets/js/logger.coffee'

Logger.logger.setStream Logger.STREAM.QUEUE
afterEach 'empty the queue', () ->
  do Logger.logger.empty

class TestCase
  constructor: (serialized = ['']) ->
    @store = new dataStore.InMemory
    @data = new Data @store
    @data.load
      text: ''
      children: serialized

    @settings =  new Settings @store
    @view = new View @data
    @view.render = -> return

    # will have default bindings
    keyBindings = new KeyBindings @settings
    @keyhandler = new KeyHandler @view, keyBindings
    @register = @view.register

  _expectDeepEqual: (actual, expected, message) ->
    if not _.isEqual actual, expected
      do Logger.logger.flush
      console.error \
        "\nExpected:\n#{JSON.stringify(expected, null, 2)}" +
        "\nBut got:\n#{JSON.stringify(actual, null, 2)}"
      throw Error message

  _expectEqual: (actual, expected, message) ->
    if actual != expected
      do Logger.logger.flush
      console.error \
        "\nExpected:\n#{expected}" +
        "\nBut got:\n#{actual}"
      throw Error message

  sendKeys: (keys) ->
    for key in keys
      @keyhandler.handleKey key
    return @

  sendKey: (key) ->
    @sendKeys [key]
    return @

  import: (content, mimetype) ->
    @view.importContent content, mimetype

  expect: (expected) ->
    serialized = @data.serialize @data.root, true
    @_expectDeepEqual serialized.children, expected, "Unexpected serialized content"
    return @

  expectViewRoot: (expected) ->
    @_expectEqual @data.viewRoot, expected, "Unexpected view root"
    return @

  expectCursor: (row, col) ->
    @_expectEqual @view.cursor.row, row, "Unexpected cursor row"
    @_expectEqual @view.cursor.col, col, "Unexpected cursor col"
    return @

  expectJumpIndex: (index, historyLength = null) ->
    @_expectEqual @view.jumpIndex, index, "Unexpected jump index"
    if historyLength != null
      @_expectEqual @view.jumpHistory.length, historyLength, "Unexpected jump history length"
    return @

  expectNumMenuResults: (num_results) ->
    @_expectEqual @view.menu.results.length, num_results, "Unexpected number of results"
    return @

  setRegister: (value) ->
    @register.deserialize value
    return @

  expectRegister: (expected) ->
    current = do @register.serialize
    @_expectDeepEqual current, expected, "Unexpected register content"
    return @

  expectRegisterType: (expected) ->
    current = do @register.serialize
    @_expectDeepEqual current.type, expected, "Unexpected register type"
    return @

  expectExport: (fileExtension, expected) ->
    export_ = @view.exportContent fileExtension
    @_expectEqual export_, expected, "Unexpected export content"
    return @

  expectMarks: (expected) ->
    marks = do @view.data.store.getAllMarks
    @_expectDeepEqual marks, expected, "Unexpected marks"
    return @

module.exports = TestCase
