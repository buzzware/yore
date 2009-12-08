require 'rubygems'
require 'test/unit'
require 'shoulda'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

class Test::Unit::TestCase
end

require File.expand_path('../../buzzcore/lib/buzzcore_dev.rb',File.dirname(__FILE__))

require_paths_first '../lib'	# prefer local yore over installed gem


require 'yore/AWSS3Client'
require 'yore/yore_core'
require 'fileutils'



