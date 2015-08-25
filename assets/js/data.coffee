# imports
if module?
  _ = require('lodash')
  utils = require('./utils.coffee')
  constants = require('./constants.coffee')
  Logger = require('./logger.coffee')

class Data
  root: 0

  constructor: (store) ->
    @store = store
    @viewRoot = do @store.getLastViewRoot
    return @

  changeViewRoot: (row) ->
    @viewRoot = row
    @store.setLastViewRoot row

  #########
  # lines #
  #########

  # an array of objects:
  # {
  #   char: 'a'
  #   bold: true
  #   italic: false
  # }
  # in the case where all properties are false, it may be simply the character (to save space)
  getLine: (row) ->
    return (@store.getLine row).map (obj) ->
      if typeof obj == 'string'
        obj = {
          char: obj
        }
      return obj

  getText: (row, col) ->
    return @getLine(row).map ((obj) -> obj.char)

  getChar: (row, col) ->
    return @getLine(row)[col]?.char

  setLine: (row, line) ->
    return (@store.setLine row, (line.map (obj) ->
      # if no properties are true, serialize just the character to save space
      if _.all constants.text_properties.map ((property) => (not obj[property]))
        return obj.char
      else
        return obj
    ))

  # get word at this location
  # if on a whitespace character, return nothing
  getWord: (row, col) ->
    text = @getText row

    if utils.isWhitespace text[col]
      return ''

    start = col
    end = col
    while (start > 0) and not (utils.isWhitespace text[start-1])
      start -= 1
    while (end < text.length - 1) and not (utils.isWhitespace text[end+1])
      end += 1
    return text[start..end].join('')

  writeChars: (row, col, chars) ->
    args = [col, 0].concat chars
    line = @getLine row
    [].splice.apply line, args
    @setLine row, line

  deleteChars: (row, col, num) ->
    line = @getLine row
    deleted = line.splice col, num
    @setLine row, line
    return deleted

  getLength: (row) ->
    return @getLine(row).length

  #########
  # marks #
  #########

  # get mark for a row, '' if it doesn't exist
  getMark: (id) ->
    marks = @store.getMarks id
    return marks[id] or ''

  _updateAllMarks: (id, mark = '') ->
    allMarks = do @store.getAllMarks

    if mark of allMarks
      return false

    oldmark = @getMark id
    if oldmark
      delete allMarks[oldmark]

    if mark
      allMarks[mark] = id
    @store.setAllMarks allMarks
    return true

  # recursively update allMarks for id,mark pair
  _updateMarksRecursive: (id, mark = '', from, to) ->
    cur = from
    while true
      marks = @store.getMarks cur
      if mark
        marks[id] = mark
      else
        delete marks[id]
      @store.setMarks cur, marks
      if cur == to
        break
      # TODO: do this properly, canonical parent not right thing
      cur = @getCanonicalParent cur

  setMark: (id, mark = '') ->
    if @_updateAllMarks id, mark
      @_updateMarksRecursive id, mark, id, @root
      return true
    return false

  # detach the marks of an id that is being detached
  # assumes that the old parent of the id is set
  detachMarks: (id) ->
    marks = @store.getMarks id
    for row, mark of marks
      row = parseInt row
      @_updateAllMarks row, ''
      # roll back the mark for this row, but only above me
      # TODO: do this properly, canonical parent not right thing
      @_updateMarksRecursive row, '', (@getCanonicalParent id), @root

  # try to restore the marks of an id that was detached
  # assumes that the new to-be-parent of the id is already set
  # and that the marks dictionary contains the old values
  attachMarks: (id) ->
    marks = @store.getMarks id
    for row, mark of marks
      row = parseInt row
      if not (@setMark row, mark)
        # roll back the mark for this row, but only underneath me
        @_updateMarksRecursive row, '', row, id

  getAllMarks: () ->
    return do @store.getAllMarks

  #############
  # structure #
  #############

  getParents: (row) ->
    return @store.getParents row

  getCanonicalParent: (row) ->
    return (@getParents row)[0]

  getCanonicalPath: (row) ->
    path = [row]
    while row != @root
      row = @getCanonicalParent row
      path.push row
    path.reverse()
    return path

  getChildren: (row) ->
    return @store.getChildren row

  hasChildren: (row) ->
    return ((@getChildren row).length > 0)

  collapsed: (row) ->
    return @store.getCollapsed row

  toggleCollapsed: (id) ->
    @store.setCollapsed id, (not @collapsed id)

  # whether currently viewable.  ASSUMES ROW IS WITHIN VIEWROOT
  viewable: (row) ->
    return (not @collapsed row) or (row == @viewRoot)

  indexOf: (child, parent) ->
    children = @getChildren parent
    return children.indexOf child

  detachChild: (parent, id) ->
    # detach a block from the specified parent
    # though it is detached, it remembers its old parent
    # and remembers its old mark

    children = @getChildren parent
    i = children.indexOf id
    if i == -1
      throw "Row #{id} was not a child of #{parent}"
    children.splice i, 1

    @store.setChildren parent, children
    @detachMarks id

    return i

  # attaches a detached child to a parent
  # the child should not have a parent already
  attachChild: (id, child, index = -1) ->
    @attachChildren id, [child], index

  attachChildren: (id, new_children, index = -1) ->
    children = @getChildren id
    if index == -1
      children.push.apply children, new_children
    else
      children.splice.apply children, [index, 0].concat(new_children)
    for child in new_children
      parents = @getParents child
      parents.push id
      @store.setParents child, parents
      @attachMarks child

    @store.setChildren id, children

  firstVisible: (id = @viewRoot) ->
    if @viewable id
      children = @getChildren id
      if children.length > 0
        return children[0]
    while true
      nextsib = @getSiblingAfter id
      if nextsib != null
        return nextsib
      id = @getParent id
      if id == @viewRoot
        return null

  # last thing visible nested within id
  lastVisible: (id = @viewRoot) ->
    if not @viewable id
      return id
    children = @getChildren id
    if children.length > 0
      return @lastVisible children[children.length - 1]
    return id

  prevVisible: (id) ->
    prevsib = @getSiblingBefore id
    if prevsib != null
      return @lastVisible prevsib
    parent = @getParent id
    if parent == @viewRoot
      return null
    return parent

  # finds oldest ancestor that is visible (viewRoot itself not considered visible)
  # returns null if there is no visible ancestor (i.e. viewroot doesn't contain row)
  oldestVisibleAncestor: (id) ->
    last = id
    while true
      cur = @getParent last
      if cur == @viewRoot
        return last
      if cur == @root
        return null
      last = cur

  # finds closest ancestor that is visible (viewRoot itself not considered visible)
  # returns null if there is no visible ancestor (i.e. viewroot doesn't contain row)
  youngestVisibleAncestor: (id) ->
    answer = id
    cur = id
    while true
      cur = @getParent cur
      if cur == @viewRoot
        return answer
      if cur == @root
        return null
      if @collapsed cur
        answer = cur

  # returns whether a row is actually reachable from the root node
  # if something is not detached, it will have a parent, but the parent wont mention it as a child
  isAttached: (id) ->
    while true
      if id == @root
        return true
      if (@indexOf id) == -1
        return false
      id = @getParent id

  getSiblingBefore: (parent, id) ->
    return @getSiblingOffset parent, id, -1

  getSiblingAfter: (parent, id) ->
    return @getSiblingOffset parent, id, 1

  getSiblingOffset: (parent, id, offset) ->
    return (@getSiblingRange parent, id, offset, offset)[0]

  getSiblingRange: (parent, id, min_offset, max_offset) ->
    index = @indexOf id, parent
    return @getChildRange parent, (min_offset + index), (max_offset + index)

  getChildRange: (id, min, max) ->
    children = @getChildren id
    indices = [min..max]

    return indices.map (index) ->
      if index >= children.length
        return null
      else if index < 0
        return null
      else
        return children[index]

  addChild: (id, index = -1) ->
    child = do @store.getNew
    @attachChild id, child, index
    return child

  # this is never used, since data structure is basically persistent
  # deleteRow: (id) ->
  #   if id == @viewRoot
  #     throw 'Cannot delete view root'

  #   for child in (@getChildren id).slice()
  #     @deleteRow child

  #   @detach id
  #   @store.delete id

  _insertSiblingHelper: (id, after) ->
    if id == @viewRoot
      Logger.logger.error 'Cannot insert sibling of view root'
      return null

    parent = @getParent id
    children = @getChildren parent
    index = children.indexOf id

    return (@addChild parent, (index + after))

  insertSiblingAfter: (id) ->
    return @_insertSiblingHelper id, 1

  insertSiblingBefore: (id) ->
    return @_insertSiblingHelper id, 0

  orderedLines: () ->
    ids = []

    helper = (id) =>
      ids.push id
      for child in @getChildren id
        helper child
    helper @root
    return ids

  # find marks that start with the prefix
  findMarks: (prefix, nresults = 10) ->
    results = [] # list of rows
    for mark, row of (do @getAllMarks)
      if (mark.indexOf prefix) == 0
        results.push {
          row: row
          mark: mark
        }
        if nresults > 0 and results.length == nresults
          break
    return results

  find: (query, options = {}) ->
    nresults = options.nresults or 10
    case_sensitive = options.case_sensitive

    results = [] # list of (row_id, index) pairs

    canonicalize = (x) ->
      return if options.case_sensitive then x else x.toLowerCase()

    get_words = (char_array) ->
      words =
        (char_array.join '').split(' ')
        .filter((x) -> x.length)
        .map canonicalize
      return words

    query_words = get_words query
    if query.length == 0
      return results

    for id in do @orderedLines
      line = canonicalize (@getText id).join ''
      matches = []
      if _.all(query_words.map ((word) ->
                i = line.indexOf word
                if i >= 0
                  for j in [i...i+word.length]
                    matches.push j
                  return true
                else
                  return false
              ))
        results.push {
          row: id
          matches: matches
        }
      if nresults > 0 and results.length == nresults
        break
    return results

  #################
  # serialization #
  #################

  # important: serialized automatically garbage collects
  serialize: (id = @root, pretty=false) ->
    line = @getLine id
    text = (@getText id).join('')

    struct = {
      text: text
    }
    children = (@serialize childid, pretty for childid in @getChildren id)
    if children.length
      struct.children = children

    for property in constants.text_properties
      if _.any (line.map ((obj) -> obj[property]))
        struct[property] = ((if obj[property] then '.' else ' ') for obj in line).join ''
        pretty = false

    if id == @root and @viewRoot != @root
      struct.viewRoot = @viewRoot

    if @collapsed id
      struct.collapsed = true

    mark = @getMark id
    if mark
      struct.mark = mark

    if pretty
      if children.length == 0 and not mark
        return text
    return struct

  loadTo: (serialized, parent = @root, index = -1) ->
    id = do @store.getNew

    if id != @root
      @attachChild parent, id, index
    else
      # parent should be 0
      @store.setParents id, [@root]

    if typeof serialized == 'string'
      @setLine id, (serialized.split '')
    else
      line = (serialized.text.split '').map((char) -> {char: char})
      for property in constants.text_properties
        if serialized[property]
          for i, val of serialized[property]
            if val == '.'
              line[i][property] = true

      @setLine id, line
      @store.setCollapsed id, serialized.collapsed

      if serialized.mark
        @setMark id, serialized.mark

      if serialized.children
        for serialized_child in serialized.children
          @loadTo serialized_child, id

    return id

  load: (serialized) ->
    if serialized.viewRoot
      @viewRoot = serialized.viewRoot
    else
      @viewRoot = @root

    @loadTo serialized

# exports
module?.exports = Data
