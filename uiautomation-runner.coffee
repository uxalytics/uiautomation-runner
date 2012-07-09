{
  timeoutSet, parent_of, mkdirp, spawn_with_output
} = require './util'
{trust_ca_certs} = require './trust'
{spawn_charles} = require './charles'
global_state = require './global_state'
async = require 'async'


PLATFORMS_DIR = "/Applications/Xcode.app/Contents/Developer/Platforms"
AUTOMATION_TEMPLATE_PATH = "#{PLATFORMS_DIR}/iPhoneOS.platform/Developer/Library/Instruments/PlugIns/AutomationInstrument.bundle/Contents/Resources/Automation.tracetemplate"


build_and_test = (settings, callback=(->)) ->
  functions = [
    spawn_charles
    quit_simulator
    delete_simulator_applications
    xcodebuild
    trust_ca_certs
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


process.on 'uncaughtException', (e) ->
  close () ->
    console.log '*** Exception ***'
    console.log e
    process.exit 1


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


run_instruments = (settings, callback=(->)) ->
  {device_udid, template, build_dir, results_dir, script_path, app_filename} = settings
  mkdirp results_dir, (e) ->
    return callback e if e
    template or= AUTOMATION_TEMPLATE_PATH
    args = []
    if device_udid
      args.push '-w', device_udid
    args.push '-t', template
    args.push "#{build_dir}/#{app_filename}"
    args.push '-e', 'UIARESULTSPATH', results_dir
    args.push '-e', 'UIASCRIPT', script_path
    spawn_with_output "instruments", args, {
      cwd: results_dir
      stdio: 'inherit'
    }, (e, out, err) ->
      callback e


delete_simulator_applications = (settings, callback) ->
  spawn_with_output 'bash', ['-c', 'rm -rf ~/Library/Application\\ Support/iPhone\\ Simulator/*/Applications/*'], callback


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
