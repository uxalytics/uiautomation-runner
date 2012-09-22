
## Minimal Example

    require('uiautomation-runner').build_and_test {
      build_dir:            "#{__dirname}/build/xcode"
      results_dir:          "#{__dirname}/results/#{strftime.strftimeUTC('...')}"
      script_path:          "#{__dirname}/all-the-tests.js"
      xcode_workspace:      "#{__dirname}/../MyAwesomeProduct.xcworkspace"
      xcode_scheme:         'myawesomeproduct'
      xcode_configuration:  'Test'
      app_filename:         'My Awesome Product.app'
      delete_simulator_apps: true
    }


## Some Optional Settings

    # default: Xcode's Automation.tracetemplate
    tracetemplate: ".../Foo.tracetemplate"


## [TODO] Running on a physical device

    {
      ...
      bundle_id: 'com.example.foo'
      device_udid: '...'
    }

- This requires `fruitstrap` to be on your `PATH`


## Trusting custom CA certs

    {
      ...
      trust_ca_cert_paths: [
        "#{__dirname}/ssl/demoCA/cacert.pem"
      ]
    }


## Charles

Suppose you want to man-in-the-middle HTTPS requests whose host matches `*foo*` and proxy them to `:3001`

    {
      ...
      charles: {
        mim_https_to_local: {
          foo: 3001
        }
        headless: false     # Default: true
      }
      trust_charles: true   # Works for the simulator -- for physical devices, you'll need to manually trust the cert
    }

- This will
  - create a config file at `"#{build_dir}/charles.config"`
  - run Charles while the tests are running
- You need a registered copy of Charles
- It needs to be at `/Applications/Charles.app`
