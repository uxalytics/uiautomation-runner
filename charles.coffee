fs = require 'fs'
{spawn} = require 'child_process'
{timeoutSet, xml_escape, spawn_with_output, mkdirp} = require './util'
global_state = require './global_state'


CHARLES_PATH = "/Applications/Charles.app/Contents/MacOS/Charles"


spawn_charles = (settings, callback) ->

  _ensure_charles_isnt_running (e) ->
    return callback e if e

    # charles.config
    {build_dir} = settings
    mkdirp build_dir, (e) ->
      return callback e if e
      config_path = "#{build_dir}/charles.config"
      _charles_config_for settings, (e, config) ->
        return callback e if e
        fs.writeFile config_path, config, (e) ->
          return callback e if e

          charles = new Charles config_path
          global_state.pids_to_kill_when_closing.push charles.p.pid
          callback null


class Charles
  constructor: (config_path) ->
    @_expectingExit = false
    @p = spawn CHARLES_PATH, [
      '-headless'
      '-config', config_path
    ]
    @p.on 'exit', (code) ->
      if code
        console.log "Charles exited with code #{code}"


_ensure_charles_isnt_running = (callback) ->
  spawn_with_output 'ps', ['ax'], (e, out, err) ->
    return callback e if e
    m = out.match /\n[ \t]*([0-9]+).*?Applications\/Charles\.app/
    if not m
      callback null
    else
      console.log "Charles is already running. Quitting and respawning it..."
      pid = parseInt m[1], 10
      process.kill pid, 'SIGTERM'
      # TODO keep `ps ax`ing until it's gone
      timeoutSet 5000, () ->
        callback null


_find_proxy_dest = (settings, callback) ->
  if not settings.device_udid
    process.nextTick () ->
      callback null, '127.0.0.1'
  else
    spawn_with_output 'ifconfig', [], (e, out, err) ->
      return callback e if e
      last_ip = null
      for group0 in out.match /inet ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/g
        ip = group0.split(' ')[1]
        if ip != '127.0.0.1'
          last_ip = ip
      return callback "Couldn't find non-localhost IP from ifconfig" if not last_ip
      callback null, last_ip


_find_charles_registration = (settings, callback) ->
  fs.readFile "#{process.env.HOME}/Library/Preferences/com.xk72.charles.config", (e, data) ->
    return callback "Couldn't find your Charles preferences" if e
    text = data.toString 'utf-8'
    m = text.match /<void property="registrationConfiguration">(\n|.)*?<string>([^<]+)<(\n|.)*?<string>([^<]+)</
    return callback "Couldn't read registration {key,name} from your Charles preferences" if not m
    key = m[2]
    name = m[4]
    callback null, key, name


_ssl_fragment_for = (name) ->
  """
    <void method="add"> 
     <object class="com.xk72.charles.lib.DefaultLocationMatch"> 
      <void property="location"> 
       <object class="com.xk72.net.Location"> 
        <void property="host"> 
         <string>*#{xml_escape(name)}*</string> 
        </void> 
       </object> 
      </void> 
     </object> 
    </void> 
  """


_map_remote_fragment_for = (name, port, proxy_dest) ->
  """
    <void method="add"> 
     <object class="com.xk72.charles.tools.MapTool$MapConfiguration$MapMapping"> 
      <void property="destLocation"> 
       <object class="com.xk72.net.Location"> 
        <void property="host"> 
         <string>#{xml_escape(proxy_dest)}</string> 
        </void> 
        <void property="port"> 
         <string>#{xml_escape("" + port)}</string> 
        </void> 
       </object> 
      </void> 
      <void property="sourceLocation"> 
       <object class="com.xk72.net.Location"> 
        <void property="host"> 
         <string>*#{xml_escape(name)}*</string> 
        </void> 
        <void property="port"> 
         <string>443</string> 
        </void> 
       </object> 
      </void> 
     </object> 
    </void> 
  """


_charles_config_for = (settings, callback) ->
  {mim_https_to_local} = settings.charles

  _find_proxy_dest settings, (e, proxy_dest) ->
    return callback e if e

    _find_charles_registration settings, (e, registration_key, registration_name) ->
      return callback e if e

      ssl_fragments = []
      map_remote_fragments = []
      for own name, port of mim_https_to_local
        ssl_fragments.push _ssl_fragment_for name
        map_remote_fragments.push _map_remote_fragment_for name, port, proxy_dest
      ssl_xml = ssl_fragments.join "\n"
      map_remote_xml = map_remote_fragments.join "\n"

      callback null, """
        <?xml version="1.0" encoding="UTF-8"?> 
        <java version="1.6.0_33" class="java.beans.XMLDecoder"> 
         <object class="com.xk72.charles.config.CharlesConfiguration"> 
          <void property="accessControlConfiguration"> 
           <void property="ipRanges"> 
            <void method="add"> 
             <object class="com.xk72.charles.lib.IPRange"> 
              <void property="ip"> 
               <array class="int" length="4"/> 
              </void> 
              <void property="mask"> 
               <array class="int" length="4"/> 
              </void> 
             </object> 
            </void> 
           </void> 
          </void> 
          <void property="proxyConfiguration"> 
           <void property="SSLLocations"> 
            <void property="locationPatterns"> 
              #{ssl_xml}
            </void> 
           </void> 
           <void property="transparentProxy"> 
            <boolean>true</boolean> 
           </void> 
          </void> 
          <void property="registrationConfiguration"> 
           <void property="key"> 
            <string>#{xml_escape(registration_key)}</string> 
           </void> 
           <void property="name"> 
            <string>#{xml_escape(registration_name)}</string> 
           </void> 
          </void> 
          <void property="startupConfiguration"> 
           <void property="currentDirectory"> 
            <string>#{process.env.HOME}</string> 
           </void> 
           <void property="lastCheckUpdates"> 
            <object class="java.util.Date"> 
             <long>1341698240244</long> 
            </object> 
           </void> 
           <void property="mainWindow"> 
            <object class="java.awt.Rectangle"> 
             <int>-6</int> 
             <int>22</int> 
             <int>1436</int> 
             <int>874</int> 
            </object> 
           </void> 
          </void> 
          <void property="throttlingConfiguration"> 
           <void property="bandwidthDown"> 
            <double>256.0</double> 
           </void> 
           <void property="bandwidthUp"> 
            <double>256.0</double> 
           </void> 
           <void property="latency"> 
            <int>4000</int> 
           </void> 
           <void property="mtu"> 
            <int>1500</int> 
           </void> 
           <void property="utilisationDown"> 
            <int>100</int> 
           </void> 
           <void property="utilisationUp"> 
            <int>100</int> 
           </void> 
          </void> 
          <void property="toolConfiguration"> 
           <void property="configs"> 
            <void method="put"> 
             <string>Map Remote</string> 
             <object class="com.xk72.charles.tools.MapTool$MapConfiguration"> 
              <void property="mappings"> 
               #{map_remote_xml}
              </void> 
              <void property="toolEnabled"> 
               <boolean>true</boolean> 
              </void> 
             </object> 
            </void> 
            <void method="put"> 
             <string>Auto Save</string> 
             <object class="com.xk72.charles.tools.AutoSaveTool$AutoSaveConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Reverse Proxies</string> 
             <object class="com.xk72.charles.tools.ReverseProxiesTool$ReverseProxiesConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Block Cookies</string> 
             <object class="com.xk72.charles.tools.lib.SelectedHostsToolConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Mirror</string> 
             <object class="com.xk72.charles.tools.MirrorTool$MirrorConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>DNS Spoofing</string> 
             <object class="com.xk72.charles.tools.DNSSpoofingTool$DNSSpoofingConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Port Forwarding</string> 
             <object class="com.xk72.charles.tools.PortForwardingTool$PortForwardingConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Breakpoints</string> 
             <object class="com.xk72.charles.tools.breakpoints.BreakpointsTool$BreakpointsConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Client Process</string> 
             <object class="com.xk72.charles.tools.lib.SelectedHostsToolConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Rewrite</string> 
             <object class="com.xk72.charles.tools.rewrite.RewriteConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Map Local</string> 
             <object class="com.xk72.charles.tools.MapLocalTool$MapLocalConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>Black List</string> 
             <object class="com.xk72.charles.tools.BlacklistTool$BlacklistConfiguration"/> 
            </void> 
            <void method="put"> 
             <string>No Caching</string> 
             <object class="com.xk72.charles.tools.lib.SelectedHostsToolConfiguration"/> 
            </void> 
           </void> 
          </void> 
          <void property="userInterfaceConfiguration"> 
           <void property="displayFont"> 
            <string>Default</string> 
           </void> 
           <void property="lookAndFeel"> 
            <string>Mac OS X</string> 
           </void> 
           <void property="properties"> 
            <void method="put"> 
             <string>sequence.maxTransactions</string> 
             <int>0</int> 
            </void> 
            <void method="put"> 
             <string>SessionFrame.splitPlane.dividerLocation.vertical</string> 
             <int>433</int> 
            </void> 
            <void method="put"> 
             <string>SessionFrame.navTabs.mode</string> 
             <string>Sequence</string> 
            </void> 
            <void method="put"> 
             <string>NavigatorJTable.TABLE_COLUMN_STATES</string> 
             <object class="com.xk72.charles.gui.lib.MemoryJTable$ColumnStates"> 
              <void property="positions"> 
               <array class="int" length="9"> 
                <void index="1"> 
                 <int>1</int> 
                </void> 
                <void index="2"> 
                 <int>2</int> 
                </void> 
                <void index="3"> 
                 <int>3</int> 
                </void> 
                <void index="4"> 
                 <int>4</int> 
                </void> 
                <void index="5"> 
                 <int>5</int> 
                </void> 
                <void index="6"> 
                 <int>6</int> 
                </void> 
                <void index="7"> 
                 <int>7</int> 
                </void> 
                <void index="8"> 
                 <int>8</int> 
                </void> 
               </array> 
              </void> 
              <void property="sizes"> 
               <array class="double" length="9"> 
                <void index="0"> 
                 <double>0.01583710407239819</double> 
                </void> 
                <void index="1"> 
                 <double>0.051181102362204724</double> 
                </void> 
                <void index="2"> 
                 <double>0.058069381598793365</double> 
                </void> 
                <void index="3"> 
                 <double>0.20615964802011313</double> 
                </void> 
                <void index="4"> 
                 <double>0.5104241552839683</double> 
                </void> 
                <void index="5"> 
                 <double>0.05128205128205128</double> 
                </void> 
                <void index="6"> 
                 <double>0.05580693815987934</double> 
                </void> 
                <void index="7"> 
                 <double>0.08220211161387632</double> 
                </void> 
                <void index="8"> 
                 <double>0.008246289169873557</double> 
                </void> 
               </array> 
              </void> 
             </object> 
            </void> 
            <void method="put"> 
             <string>SessionFrame.splitPlane.dividerLocation.horizontal</string> 
             <int>379</int> 
            </void> 
            <void method="put"> 
             <string>sequence.filterRegex</string> 
             <boolean>false</boolean> 
            </void> 
           </void> 
           <void property="showMemoryUsage"> 
            <boolean>true</boolean> 
           </void> 
           <void property="warningsSeen"> 
            <void method="put"> 
             <string>mozilla.extension</string> 
             <boolean>true</boolean> 
            </void> 
           </void> 
          </void> 
         </object> 
        </java> 
      """

module.exports = {spawn_charles}
