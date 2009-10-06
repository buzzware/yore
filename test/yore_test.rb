require 'rubygems'
gem 'buzzware-buzzcore'; require 'buzzcore';
require 'yore/yore_core'
require 'test/unit'
gem 'Shoulda'; require 'shoulda'
require 'fileutils'

class YoreTest < Test::Unit::TestCase

	def setup
    @yore = YoreCore::Yore.new
  end

  should "collect a list of files into a single file" do
    # create a temp dir
    temp_dir = MiscUtils::make_temp_dir('yore_test')
    # create source and dest subfolders
    source_dir = File.expand_path('source',temp_dir)
    dest_dir = File.expand_path('dest',temp_dir)
    FileUtils.mkdir_p([source_dir,dest_dir])
    # create some dirs and files in source
    ['a','a/1','b','c'].each {|p| FileUtils.mkdir_p(File.expand_path(p,source_dir))}
    %w(a/blah.txt a/1/blahblah.txt b/apples.txt c/carrots.txt).each do |f|
      MiscUtils::make_temp_file(f,source_dir)
    end
    # collect into dest file
    # get recursive file list, without carrots
    filelist = MiscUtils::recursive_file_list(source_dir,false) {|p| not p =~ /carrots.txt/}
    dest_file = File.join(dest_dir,'destfile.bzb')

    @yore.compress(filelist,dest_file,source_dir)

    # check contains filelist files
    cmd = "tar --list --file=#{dest_file}"
    filelist_out = `#{cmd}`
    i = 0
    filelist_out.each_line {|line|
      assert i < filelist.length
      assert_equal line.chomp("\n"), filelist[i] # .bite('/')
      i += 1
    }
  end

  should "encrypt and unencrypt a file with a standard iv but a supplied key" do
    orig_content = 'abcdef123456'
    temp_file1 = MiscUtils.make_temp_file(nil,nil,orig_content)
    temp_file2 = temp_file1+'.enc'
    temp_file3 = temp_file1+'.dec'

    @yore.pack(temp_file1,temp_file2)
    @yore.unpack(temp_file2,temp_file3)

    file3_content = MiscUtils.string_from_file(temp_file3)
    assert_equal file3_content, orig_content
  end

  should "create a backup filename combining a prefix, date, day and standard extension, and be able to decode the filename back to a date" do
    @yore.configure({
      :prefix => 'test',
      :first_hour => 4
    })
    now = Time.local(2009, 1, 1, 0, 0, 0, 0)
    exp_filename = "test-20081231.yor"
    calc_filename = @yore.encode_file_name(now)
    assert_equal calc_filename, exp_filename
    assert_equal Time.local(2008, 12, 31), @yore.decode_file_name(calc_filename)
  end

  should "provide configurable criteria for keeping old files"

  should "clean a folder full of files, removing files that don't match configurable criteria for keeping old files"

end
