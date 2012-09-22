fs = require 'fs'
{exec} = require 'child_process'
{
  timeoutSet, parent_of, mkdirp, spawn_with_output
} = require './util'
{trust_ca_certs} = require './trust'
{spawn_charles} = require './charles'
global_state = require './global_state'
async = require 'async'


build_and_test = (settings, callback=(->)) ->
  functions = [
    spawn_charles
    quit_simulator
    delete_simulator_apps
    xcodebuild
    trust_ca_certs
    install_on_device
    find_tracetemplate
    run_instruments
    quit_simulator
    close
  ]
  async.forEachSeries functions, (
    (f, cb) ->
      f settings, cb
  ), callback


close = (settings, callback=(->)) ->
  if global_state.closing
    callback null
  else
    global_state.closing = true
    for pid in global_state.pids_to_kill_when_closing
      # If you SIGKILL Charles, you're [sometimes] going to have a bad time
      process.kill pid, 'SIGTERM'
    callback null


xcodebuild = (settings, callback=(->)) ->
  {xcode_workspace, xcode_scheme, xcode_configuration, device_udid, build_dir} = settings
  spawn_with_output "xcodebuild", [
    '-workspace', xcode_workspace,
    '-scheme', xcode_scheme,
    '-sdk', (if device_udid then 'iphoneos' else 'iphonesimulator'),
    '-configuration', xcode_configuration,
    'build',
    ('CONFIGURATION_BUILD_DIR=' + build_dir)
  ], {noisy:true}, callback


install_on_device = (settings, callback) ->
  {device_udid, bundle_id, build_dir, app_filename} = settings
  app_path = "#{build_dir}/#{app_filename}"
  return callback null if not device_udid
  async.forEachSeries(
    [
      ['uninstall', '--id', device_udid, '--bundle', bundle_id]
      ['install', '--id', device_udid, '--bundle', app_path]
    ],
    ((args, cb) -> spawn_with_output 'fruitstrap', args, {noisy:true}, cb),
    callback)


find_tracetemplate = (settings, callback) ->
  xcode45 = "/Applications/Xcode.app/Contents/Applications/Instruments.app/Contents/PlugIns/AutomationInstrument.bundle/Contents/Resources/Automation.tracetemplate"
  xcode44 = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Instruments/PlugIns/AutomationInstrument.bundle/Contents/Resources/Automation.tracetemplate"
  return callback null if settings.tracetemplate
  async.filter [xcode45, xcode44], fs.exists, (paths) ->
    return callback "Couldn't find a .tracetemplate" if paths.length == 0
    settings.tracetemplate = paths[0]
    callback null


run_instruments = (settings, callback=(->)) ->
  {device_udid, tracetemplate, build_dir, results_dir, script_path, app_filename} = settings
  mkdirp results_dir, (e) ->
    return callback e if e
    args = []
    if device_udid
      args.push '-w', device_udid
    args.push '-t', tracetemplate
    args.push "#{build_dir}/#{app_filename}"
    args.push '-e', 'UIARESULTSPATH', results_dir
    args.push '-e', 'UIASCRIPT', script_path
    spawn_with_output "instruments", args, {
      cwd: results_dir
      stdio: 'inherit'
    }, (e, out, err) ->
      callback e


delete_simulator_apps = (settings, callback) ->
  if settings.delete_simulator_apps
    spawn_with_output 'bash', ['-c', 'rm -rf ~/Library/Application\\ Support/iPhone\\ Simulator/*/Applications/*'], callback
  else
    callback null


quit_simulator = (settings, callback=(->)) ->
  script = 'tell application "iPhone Simulator" to quit'
  spawn_with_output 'osascript', ['-e', script], callback


bring_simulator_to_front = (settings, callback=(->)) ->
  script = 'tell application "iPhone Simulator" to activate'
  spawn_with_output 'osascript', ['-e', script], callback


module.exports = {
  build_and_test
  mkdirp, spawn_with_output
}
