# Generated by jeweler
# DO NOT EDIT THIS FILE
# Instead, edit Jeweler::Tasks in Rakefile, and run `rake gemspec`
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{yore}
  s.version = "0.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["buzzware"]
  s.date = %q{2009-12-08}
  s.default_executable = %q{yore}
  s.description = %q{yore (as in "days of yore") is a user data management utility for web applications.}
  s.email = %q{contact@buzzware.com.au}
  s.executables = ["yore"]
  s.extra_rdoc_files = [
    "LICENSE",
     "README.rdoc"
  ]
  s.files = [
    ".document",
     ".gitignore",
     "LICENSE",
     "README.rdoc",
     "Rakefile",
     "VERSION",
     "bin/yore",
     "lib/yore/AWSS3Client.rb",
     "lib/yore/yore_core.rb",
     "notes.txt",
     "test.crontab",
     "test/AWS_gem_test.rb",
     "test/S3_test.rb",
     "test/test_helper.rb",
     "test/test_job_a.xml",
     "test/test_job_b.xml",
     "test/upload_test_content.yor",
     "test/yore_browsercms_loadsave_test.rb",
     "test/yore_spree_loadsave_test.rb",
     "test/yore_test.rb",
     "yore.gemspec",
     "yore.vpj",
     "yore.vpw"
  ]
  s.homepage = %q{http://github.com/buzzware/yore}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{buzzware}
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{yore (as in "days of yore") is a user data management utility for web applications.}
  s.test_files = [
    "test/AWS_gem_test.rb",
     "test/S3_test.rb",
     "test/test_helper.rb",
     "test/yore_browsercms_loadsave_test.rb",
     "test/yore_spree_loadsave_test.rb",
     "test/yore_test.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<buzzcore>, [">= 0.2.5"])
      s.add_development_dependency(%q<thoughtbot-shoulda>, [">= 0"])
    else
      s.add_dependency(%q<buzzcore>, [">= 0.2.5"])
      s.add_dependency(%q<thoughtbot-shoulda>, [">= 0"])
    end
  else
    s.add_dependency(%q<buzzcore>, [">= 0.2.5"])
    s.add_dependency(%q<thoughtbot-shoulda>, [">= 0"])
  end
end
