require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "yore"
    gem.summary = %Q{yore (as in "days of yore") is a user data management utility for web applications.}
    gem.description = %Q{yore (as in "days of yore") is a user data management utility for web applications.}
    gem.email = "contact@buzzware.com.au"
    gem.homepage = "http://github.com/buzzware/yore"
    gem.authors = ["buzzware"]
    gem.rubyforge_project = "buzzware"
    gem.add_dependency('cmdparse', '>= 2.0.2')
    gem.add_dependency('buzzcore', '>= 0.2.6')
    gem.add_dependency('nokogiri', '>= 1.3.3')
    gem.add_dependency('buzzcore', '>= 0.2.6')
    gem.add_dependency('aws-s3', '>= 0.6.2')
    gem.add_development_dependency "thoughtbot-shoulda"
		#gem.files.include %w(
		#	lib/buzzcore.rb
		#)
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::RubyforgeTasks.new do |rubyforge|
    rubyforge.doc_task = "rdoc"
  end
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: sudo gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/*_test.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  if File.exist?('VERSION')
    version = File.read('VERSION')
  else
    version = ""
  end

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "yore #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
