# This module is only used to check the environment is currently a testing env
module SpecHelper
end

require "coveralls"
Coveralls.wear! unless ENV["FASTLANE_SKIP_UPDATE_CHECK"]

require "webmock/rspec"
WebMock.disable_net_connect!(allow: 'coveralls.io')

require "fastlane"
UI = FastlaneCore::UI

unless ENV["DEBUG"]
  fastlane_tests_tmpdir = "#{Dir.tmpdir}/fastlane_tests"
  $stdout.puts("Changing stdout to #{fastlane_tests_tmpdir}, set `DEBUG` environment variable to print to stdout (e.g. when using `pry`)")
  $stdout = File.open(fastlane_tests_tmpdir, "w")
end

if FastlaneCore::Helper.mac?
  xcode_path = FastlaneCore::Helper.xcode_path
  unless xcode_path.include?("Contents/Developer")
    UI.error("Seems like you didn't set the developer tools path correctly")
    UI.error("Detected path '#{xcode_path}'") if xcode_path.to_s.length > 0
    UI.error("Please run the following on your machine")
    UI.command("sudo xcode-select -s /Applications/Xcode.app")
    UI.error("Adapt the path if you have Xcode installed/named somewhere else")
    exit(1)
  end
end

(Fastlane::TOOLS + [:spaceship, :fastlane_core]).each do |tool|
  path = File.join(tool.to_s, "spec", "spec_helper.rb")
  require_relative path if File.exist?(path)
  require tool.to_s
end

my_main = self
RSpec.configure do |config|
  config.before(:each) do |current_test|
    # We don't want to call the RubyGems API at any point
    # This was a request that was added with Ruby 2.4.0
    allow(Fastlane::FastlaneRequire).to receive(:install_gem_if_needed).and_return(nil)

    ENV['FASTLANE_PLATFORM_NAME'] = nil

    # execute `before_each_*` method from spec_helper for each tool
    tool_name = current_test.id.match(%r{\.\/(\w+)\/})[1]
    method_name = "before_each_#{tool_name}".to_sym
    begin
      my_main.send(method_name)
    rescue NoMethodError
      # no method implemented
    end

    # Make sure PATH didnt get emptied during execution of previous (!) test
    expect(ENV['PATH']).to be_truthy, "PATH is missing. (Previous test probably emptied it.)"
  end

  config.after(:each) do |current_test|
    # execute `after_each_*` method from spec_helper for each tool
    tool_name = current_test.id.match(%r{\.\/(\w+)\/})[1]
    method_name = "after_each_#{tool_name}".to_sym
    begin
      my_main.send(method_name)
    rescue NoMethodError
      # no method implemented
    end
  end

  config.example_status_persistence_file_path = "#{Dir.tmpdir}/rspec_failed_tests.txt"

  # skip some tests if not running on mac
  unless FastlaneCore::Helper.mac?

    # define metadata tags that also imply :skip
    config.define_derived_metadata(:requires_xcode) do |meta|
      meta[:skip] = "Skipped: Requires Xcode to be installed (which is not possible on this platform and no workaround has been implemented)"
    end
    config.define_derived_metadata(:requires_xcodebuild) do |meta|
      meta[:skip] = "Skipped: Requires `xcodebuild` to be installed (which is not possible on this platform and no workaround has been implemented)"
    end
    config.define_derived_metadata(:requires_plistbuddy) do |meta|
      meta[:skip] = "Skipped: Requires `plistbuddy` to be installed (which is not possible on this platform and no workaround has been implemented)"
    end
    config.define_derived_metadata(:requires_keychain) do |meta|
      meta[:skip] = "Skipped: Requires `keychain` to be installed (which is not possible on this platform and no workaround has been implemented)"
    end
    config.define_derived_metadata(:requires_security) do |meta|
      meta[:skip] = "Skipped: Requires `security` to be installed (which is not possible on this platform and no workaround has been implemented)"
    end
    config.define_derived_metadata(:requires_xcodeproj) do |meta|
      meta[:skip] = "Skipped: Requires `xcodeproj` which is unfortunately broken on Windows right now: https://github.com/CocoaPods/Xcodeproj/issues/549"
    end

    # also skip `before()` for test groups that are skipped because of their tags.
    # only works for `describe` groups (that are parents of the `before`, not if the tag is set on `it`.
    # caution: has unexpected side effect on usage of `skip: false` for individual examples,
    # see https://groups.google.com/d/msg/rspec/5qeKQr_7G7k/Pb3ss2hOAAAJ
    module HookOverrides
      def before(*args)
        super unless metadata[:skip]
      end
    end
    config.extend(HookOverrides)

  end

  # skip some more tests if run on on Windows
  if FastlaneCore::Helper.windows?
    config.define_derived_metadata(:requires_xar) do |meta|
      meta[:skip] = "Skipped: Requires `xar` to be installed (which is not possible on Windows and no workaround has been implemented)"
    end
  end
end

module FastlaneSpec
  module Env
    # a wrapper to temporarily modify the values of ARGV to
    # avoid errors like: "warning: already initialized constant ARGV"
    # if no block is given, modifies ARGV for good
    # rubocop:disable Style/MethodName
    def self.with_ARGV(argv)
      copy = ARGV.dup
      ARGV.clear
      ARGV.concat(argv)
      if block_given?
        begin
          yield
        ensure
          ARGV.clear
          ARGV.concat(copy)
        end
      end
    end
    # rubocop:enable Style/MethodName
  end
end
