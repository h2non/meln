require! {
  fs
  oli
  ht: 'htgen'
}
{ is-object, is-array, is-string, is-undef, is-array-strings, extend, clone, has, cwd } = require './helpers'

exports = module.exports = class Compiler

  options:
    base-path: cwd!
    pretty: no
    indent: 2

  (data, options) ->
    @data = data
    @mixins = {}
    @buf = []
    @result = null
    options |> @set-options
    
  set-options: (options) ->
    @options = options |> extend (@options |> clone), _ if options

  render: ->
    (it
      |> oli.parse _, @options
      |> new Compiler _, @options).compile!

  compile: ->
    if @data |> is-object
      @result = @compile-object!
    else 
      @result = @compile-default!
    @result

  compile-object: ->

    is-valid = -> 
      (it |> is-object) or (it |> is-string)
    
    process-nodes = ~>
      if it |> is-object
        if it.mixin
          if it.body |> is-array
            @separator! |> it.body.join
          else
            it.body
        else
          @options |> it.render
      else
        it

    @buf = (@data |> @visitor |> @buf.concat)
      .filter is-valid
      .map process-nodes

    @separator! |> @buf.join

  compile-default: ->
    if @data |> is-string
      if @data |> is-doctype
        (@data |> ht).render @options
      else
        @data
    else
      @data

  visitor: (node) ->
    buf = []
    for own name, child of node when child isnt undefined then
      name = name |> normalize
      if name is 'include' and (child |> is-string)
        child |> @read-file |> @render |> buf.push
      # support in progress!
      else if name |> is-mixin
        child |> @process-mixin name, _ |> buf.push
      else if child |> is-array
        buf = child |> @process-array name, _ |> buf.concat
      else
        child |> @process name, _ |> buf.push
    buf

  process: (name, node) ->
    if node is null
      name = "!#{name}"
    else if node |> has _, '$$attributes'
      attrs = node.$$attributes
      node = node.$$body
    else if node |> is-object
      node = node |> @visitor
    ht name, attrs, node

  process-mixin: (name, node) ->
    name = name |> get-mixin-name
    throw new SyntaxError 'Missing mixin name identifier' if not name
    { 
      mixin: name
      args: node |> get-mixin-args
      body: (node |> get-mixin-body |> @visitor) 
    }

  process-array: (name, node) ->
    buf = []
    if node |> is-array-strings
      (ht.apply null, [ name, (node.join ' ') ]) |> buf.push
    else
      for item in node
        if item |> is-object
          if item.$$name and item.$$attributes and (item.$$body |> is-undef)
            item |> @process item.$$name, _ |> buf.push
          else
            (item |> @visitor) |> ht name, _ |> buf.push
        else
          item |> ht name, _ |> buf.push
    buf

  separator: ->
    if @options.pretty then '\n' else ''

  read-file: ->
    it = it |> file-ext
    it = "#{@options.base-path}/#{it}" if it.charAt(0) isnt '/'
    (it |> fs.read-file-sync).to-string!


file-ext = ->
  if not (/\.([a-z\-\_0-9]){0,10}$/i.test it)
    it += '.oli'
  else
    it

get-mixin-name = ->
  name[1] if name = it.match /^mixin ([a-z0-9\_\-\.]+)(\s+)?\(?/i

get-mixin-body = ->
  if it and it.$$attributes
    it.$$body
  else
    it

get-mixin-args = ->
  args = null
  if it |> is-object
    if it.$$attributes |> is-object
      args = it.$$attributes |> Object.keys
    else if it.$$attributes |> is-array
      args = []
      it.$$attributes.map -> (it |> Object.keys ) |> args.push
  args

normalize = -> it.replace '@', '#'

is-doctype = -> /^doctype/i.test it

is-mixin = -> /^mixin/i.test it