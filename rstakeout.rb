#!/usr/bin/env ruby -w
##
# Originally by Mike Clark.
#
# From http://www.pragmaticautomation.com/cgi-bin/pragauto.cgi/Monitor/StakingOutFileChanges.rdoc
#
# Runs a user-defined command when files are modified.
#
# Like autotest, but more customizable. This is useful when you want to do
# something other than run tests. For example, generate a PDF book, run
# a single test, or run a legacy Test::Unit suite in an app that also
# has an rSpec suite.
#
# Can use Ruby's Dir[] to get file glob. Quote your args to take advantage of this.
#
#  rstakeout 'rake test:recent' **/*.rb
#  => Only watches Ruby files one directory down (no quotes)
#
#  rstakeout 'rake test:recent' '**/*.rb'
#  => Watches all Ruby files in all directories and subdirectories
#
# Modified (with permission) by Geoffrey Grosenbach to call growlnotify for
# rspec and Test::Unit output.
#
# See the PeepCode screencast on rSpec or other blog articles for instructions on
# setting up growlnotify.
#
# * Added Snarl support in win32, initial implementation by Francis Fish
# * Added synchronous mode
# * Allow adjusting of sleep time
# * Fixes to work in Linux env too
# Edvard Majakari <edvard@majakari.net>

require 'optparse'
require 'ostruct'
require 'rubygems'

def require_gem(gemname)
  begin
    require gemname
  rescue LoadError
    puts "Please install gem %s" % gemname
    exit 1
  end
end

FAIL_ICON_PATH = File.join(File.dirname(__FILE__), 'failure.png')
OK_ICON_PATH = File.join(File.dirname(__FILE__), 'success.png')

case PLATFORM
when /darwin/
  require_gem 'ruby-growl'
when /win32/
  require_gem 'autosnarl'
else
  warn "Uh-oh, sorry. No Fancy-schmancy notifiers for #{PLATFORM}"
end

module GrowlNotifier
  class << self
    def notify(title, msg, img, pri=0, sticky="")
      system "growlnotify -n 'rstakeout notification' --image #{img} -p #{pri} -m #{msg.inspect} '#{title}' #{sticky}"
    end
    
    private :notify

    def notify_fail(output)
      notify "Test/Spec FAIL", "#{output}", FAIL_ICON_PATH, 2
    end

    def notify_pass(output)
      notify "Test/Spec pass", "#{output}", OK_ICON_PATH
    end
  end
end

# TODO: instead of begin/rescue, do
# module SnarlNotifier < end
# module SnarlNotifier::AutoSnarl < end
# ?
begin
  module SnarlNotifier
    # Idea by Francis Fish, http://francis.blog-city.com/
    begin
      require 'autotest'
    rescue Exception
      nil
    end
    include AutoSnarl
    module ::AutoSnarl
      def self.snarl(title, msg, ico=nil, timeout=5)
        Snarl.show_message(title, msg, icon[ico], timeout)
      end
    end

    def self.notify_fail(output)
      AutoSnarl::snarl "FAIL", "#{output}", :red, 30
    end

    def self.notify_pass(output)
      AutoSnarl::snarl "Pass", "#{output}", :green, 10
    end
  end
rescue Exception
  nil
end

module EmptyNotifier
  def self.notify_pass(output)
  end
  def self.notify_fail(output)
  end
end

Notifier = case PLATFORM
  when /linux/: EmptyNotifier
  when /win32/: SnarlNotifier
  else
    GrowlNotifier
  end

module ParseSpecResult
 def self.notify_test_unit_results(results)
    output = results.slice(/(\d+)\s+tests?,\s*(\d+)\s+assertions?,\s*(\d+)\s+failures?(,\s*(\d+)\s+errors)?/)
    if output
      $~[3].to_i + $~[5].to_i > 0 ? Notifier.notify_fail(output) : Notifier.notify_pass(output)
    end
  end

  def self.notify_rspec_results(results)
    output = results.slice(/(\d+)\s+examples?,\s*(\d+)\s+failures?(,\s*(\d+)\s+not implemented)?/)
    if output
      $~[2].to_i > 0 ? Notifier.notify_fail(output) : Notifier.notify_pass(output)
    end
  end
end

def build_mtimes_hash(globs)
  files = {}
  globs.each { |g|
    Dir[g].each { |file| files[file] = File.mtime(file) }
  }
  files
end

trap('INT') do
  puts "\nQuitting..."
  exit
end

options = OpenStruct.new(:sleep_time => 1, :reload_glob => false, :synchronous => false)

OptionParser.new do |opts|
  opts.banner = "Usage: rstakeout.rb [options] <command> <filespec>+"
  opts.on("-t", "--sleep-time T", Integer, "time to sleep after each loop iteration") do |t|
    options.sleep_time = t
  end
  opts.on("-v", "--verbose") do |v|
    options.verbose = v
  end
  opts.on("--sync", "force synchronous mode (disallow simultaneous runs)") do |s|
    options.synchronous = s
  end
end.parse!

MYTEMP = ENV['TEMP'] || '/tmp'

command = ARGV.shift
files = build_mtimes_hash(ARGV)
LOCKFILE = File.join(MYTEMP, 'rstakeout.lock')
if options.synchronous
  lock_obj = File.new(LOCKFILE, 'w')
end

if options.verbose
  p options
  puts "Watching #{files.keys.join(', ')}\n\nFiles: #{files.keys.length}"
end

def with_exclusive_lock_if_synchronous(run_synced, lockfile, &block)
  lockfile.flock(File::LOCK_EX) if run_synced
  block.call
  lockfile.flock(File::LOCK_UN) if run_synced
end

loop do
  changed_file, last_changed = files.find { |file, last_changed|
    begin
      File.mtime(file) > last_changed
    rescue Errno::ENOENT => e # file may have been moved, deleted etc. while running rstakeout
      warn e
    end
  }

  if changed_file
    with_exclusive_lock_if_synchronous(options.synchronous, lock_obj) do
      files[changed_file] = File.mtime(changed_file)
      puts "=> #{changed_file} changed, running '#{command}'"
      results = `#{command}`
      puts results

      if results.include? 'tests'
        ParseSpecResult.notify_test_unit_results(results)
      else
        ParseSpecResult.notify_rspec_results(results)
      end
      # TODO Generic snarl/growl notification for other actions
      puts "=> done"
    end
  end
  sleep options.sleep_time
end