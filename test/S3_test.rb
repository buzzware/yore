require 'rubygems'
gem 'buzzcore'; require 'buzzcore';
require 'yore/yore_core'
require 'test/unit'
gem 'Shoulda'; require 'shoulda'
require 'fileutils'

def ensure_clean_bucket(aName)
  `s3cmd createbucket #{aName}`
  `s3cmd deleteall #{aName}`
end

# finwa example : yore backup /var/www/joomla/deploy-system/finwa_yore.xml >/dev/null 2>&1

class S3Test < Test::Unit::TestCase

	def setup
    @yore = YoreCore::Yore.new
  end

	should "upload and download files intact" do
		bucket = 'yore_test'
		ensure_clean_bucket(bucket)
		@yore.configure({
			:bucket => bucket
		})
		content = 'this is my test content'
		temp_dir = MiscUtils.make_temp_dir()
		temp_file = MiscUtils.make_temp_file(nil, temp_dir, content)
		puts @yore.upload(temp_file)
		orig_file = temp_file+'.orig'
		File.rename(temp_file, orig_file)
		puts @yore.download(temp_file)
		down_file_content = MiscUtils.string_from_file(temp_file)
		assert_equal content, down_file_content
	end

	should "backup and restore multiple directories of file" do
		# create a temp dir
		temp_dir = MiscUtils::make_temp_dir('yore_test')
		# create source and dest subfolders
		source_dir = File.expand_path('source',temp_dir)
		source1 = File.join(source_dir,'source1')
		source2 = File.join(source_dir,'source2')
		dest_dir = File.expand_path('dest',temp_dir)
		bucket = 'yore_test'

		FileUtils.mkdir_p([source1,source2,dest_dir])
		# create some dirs and files in source
		['a','a/1','b','c'].each {|p| FileUtils.mkdir_p(File.expand_path(p,source1))}
		%w(a/blah.txt a/1/blahblah.txt b/apples.txt c/carrots.txt).each do |f|
			MiscUtils::make_temp_file(f,source1)
		end
		['w','x/1','y/2','z'].each {|p| FileUtils.mkdir_p(File.expand_path(p,source2))}
		%w(w/zonk.txt x/1/eggs.txt y/2/bloop.txt z/zax.txt).each do |f|
			MiscUtils::make_temp_file(f,source2)
		end


		ensure_clean_bucket(bucket)

		# create job file
		job_template = <<-EOF
		<?xml version="1.0" encoding="UTF-8"?>
		<Yore>
				<SimpleItems>
						<Item Name="crypto_iv">3A63775C1E3F291B0925578165EB917E</Item>
						<Item Name="crypto_key">07692FC8656F04AE5518B80D38681E038A3C12050DF6CC97CEEC33D800D5E2FE</Item>
						<Item Name="prefix">backup</Item>
						<Item Name="log_level">INFO</Item>
						<Item Name="bucket">${BUCKET}</Item>
				</SimpleItems>
			<Sources>
						<Source Type="File" BasePath="${SOURCE_DIR}">
							<IncludePath>source1</IncludePath>
							<IncludePath>source2</IncludePath>
						</Source>
				</Sources>
		</Yore>
		EOF

		job_content = StringUtils::render_template(job_template,{
			'SOURCE_DIR' => source_dir,
			'BUCKET' => bucket
		})
		MiscUtils::string_to_file(job_content,job_file = MiscUtils::temp_file)

		# call yore script with ruby from the command line, then download result and check contents
		begin
			_xmlRoot = XmlUtils.get_xml_root(job_content)
			cmd_options = {:config => job_file}
			@yore_upload = YoreCore::Yore::launch(_xmlRoot,cmd_options,{:basepath => File.dirname(File.expand_path(job_file))})
			@yore_upload.backup([job_file])
		rescue ::StandardError => e
			flunk e.inspect
		end

		#puts result
		yore = YoreCore::Yore.new()
		yore.configure({
			:bucket => bucket
		})

		retrieved_fname = File.expand_path(yore.encode_file_name(), dest_dir)
		collection_fname = MiscUtils::temp_file

		puts yore.download(retrieved_fname)
		puts yore.unpack(retrieved_fname,collection_fname)

		filelist = MiscUtils::recursive_file_list(source_dir,false)

		# check contains filelist files
		cmd = "tar --list --file=#{collection_fname}"
		filelist_out = yore.shell(cmd)
		filelist_out = filelist_out.split("\n").sort
		assert_equal filelist, filelist_out
	end

	should "handle test_file_b" do
		aController = YoreCore::Yore.new      # main program object
		srcdir = '/tmp/yoretest'
		FileUtils.rm_rf srcdir+'/*'
		FileUtils.mkdir_p srcdir
		['a','a/1','b','c'].each {|p| FileUtils.mkdir_p(File.expand_path(p,srcdir))}
		%w(a/blah.txt a/1/blahblah.txt b/apples.txt c/carrots.txt).each do |f|
			MiscUtils::make_temp_file(f,srcdir)
		end

		job = File.expand_path('../../test/test_job_b.xml',THIS_DIR)
		aController.configure(job)
		aController.backup([job])
	end

	should "provide configurable criteria for keeping old files"

	should "clean a folder full of files, removing files that don't match configurable criteria for keeping old files"

end
