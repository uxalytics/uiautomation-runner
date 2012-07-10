zlib = require 'zlib'
{spawn} = require 'child_process'


timeoutSet = (ms, f) ->
  setTimeout f, ms


xml_escape = (s) ->
  s = s.replace /[&]/g, '&amp;'
  s = s.replace /["]/g, '&quot;'
  s = s.replace /[']/g, '&apos;'
  s = s.replace /[<]/g, '&lt;'
  s = s.replace /[>]/g, '&gt;'
  s


mkdirp = (path, callback) ->
  spawn_with_output 'mkdir', ['-p', path], callback


parent_of = (path) ->
  path.split('/').slice(0, -1).join('/')


spawn_with_output = (command, args, opt, callback) ->
  console.log ">>> #{command} #{JSON.stringify(args)}"
  if (typeof opt) == 'function'
    callback = opt
    opt = {}
  opt or= {}
  noisy = !! opt.noisy
  delete opt.noisy
  p = spawn command, args, opt
  out_arr = []
  err_arr = []
  if p.stdout
    p.stdout.on 'data', (data) ->
      if noisy
        process.stdout.write data
      out_arr.push data.toString 'utf-8'
  if p.stderr
    p.stderr.on 'data', (data) ->
      if noisy
        process.stderr.write data
      err_arr.push data.toString 'utf-8'
  p.on 'exit', (code) ->
    out = out_arr.join ''
    err = err_arr.join ''
    e = if code == 0 then null else err
    if callback
      callback e, out, err
  p


module.exports = {
  timeoutSet
  xml_escape
  mkdirp
  parent_of
  spawn_with_output
}
