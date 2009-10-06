require 'rubygems'
gem 'buzzware-buzzcore'; require 'buzzcore';

#gem 'RequirePaths'; require 'require_paths'
#require_paths '../../..','../lib'

require 'yore/yore_core'
require 'test/unit'
gem 'Shoulda'; require 'shoulda'
require 'fileutils'


class YoreBrowsercmsLoadsaveTest < Test::Unit::TestCase

	should "save a browsercms applications data to a file and then load it into a different project" do
		require "mysql"
		cred = Credentials.new()
		db_details = {
			:username => cred[:mysql_username],
			:password => cred[:mysql_password]
		}

		def create_spree_db(aDbDetails)
			assert mysql = Mysql.new("localhost",aDbDetails[:username],aDbDetails[:password])
			mysql.query("DROP DATABASE IF EXISTS #{aDbDetails[:database]}")
			mysql.query("CREATE DATABASE #{aDbDetails[:database]}")
			#assert mysql.query("GRANT ALL ON #{aName}.* TO rubyuser@localhost IDENTIFIED by 'ruby'")
			mysql.select_db(aDbDetails[:database])
			mysql.query("
				CREATE TABLE products (
					id int(11) NOT NULL AUTO_INCREMENT,
					name varchar(30),
					description varchar(50),
					PRIMARY KEY (id)
				)
			")
			mysql.query("INSERT INTO products (name,description) VALUES('spoon', 'golden spoon -#{aDbDetails[:database]}')")
			mysql.query("INSERT INTO products (name,description) VALUES('fork', 'silver fork -#{aDbDetails[:database]}')")
			mysql.query("
				CREATE TABLE customers (
					id int(11) NOT NULL AUTO_INCREMENT,
					name varchar(30),
					address varchar(50),
					PRIMARY KEY (id)
				)
			")
			mysql.query("INSERT INTO customers (name,address) VALUES('fred', '1 some st -#{aDbDetails[:database]}')")
			mysql.query("INSERT INTO customers (name,address) VALUES('mary', '2 another rd -#{aDbDetails[:database]}')")
			return mysql
		end
		
		def create_browsercms_db(aDbDetails)
			create_spree_db(aDbDetails) # just use the spree code for now
		end
		
		#users = [{:name => 'Bob', :permissions => ['Read']},
		#         {:name => 'Alice', :permissions => ['Read', 'Write']}]
		#
		## Serialize
		#open('users', 'w') { |f| YAML.dump(users, f) }
		#
		## And deserialize
		#users2 = open("users") { |f| YAML.load(f) }
		## => [{:permissions=>["Read"], :name=>"Bob"},
		##     {:permissions=>["Read", "Write"], :name=>"Alice"}]

		def hash_from_yaml_file(aFile)
			return YAML::load(File.open(aFile)) rescue nil
		end
		
		def yaml_file_from_hash(aName,aHash)
			open(aName, 'w') { |f| YAML.dump(aHash, f) }
		end
		
		RAND_CHARS	=	"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
		def random_string(aLength)
			rand_max = RAND_CHARS.size
			ret = "" 
			aLength.times{ ret << RAND_CHARS[rand(rand_max)] }
			ret
		end
		
		def random_filename(aPrefix=nil)
			aPrefix.to_s+random_string(8)+'.'+random_string(3)
		end
		
		def create_random_file(aPath,aLength,aName=nil)
			aName ||= random_filename()
			path = File.join(aPath,aName)
			MiscUtils.string_to_file(random_string(aLength),path)
		end
		
		# returns rails path even if aCapistranoStyle
		def create_browsercms_folder(aParentDir,aFolderName,aDatabaseParams,aCapistranoStyle=false)
			path = File.expand_path(aFolderName,aParentDir)
			if aCapistranoStyle
				FileUtils.mkdir_p(shared = File.join(path,'shared'))
				FileUtils.mkdir_p(File.join(path,'current'))
				path = File.join(path,'releases','345345435435')
			end
			FileUtils.mkdir_p(path)
			FileUtils.mkdir_p(File.join(path,'config'))
			FileUtils.mkdir_p(File.join(path,'kind'))
			uploads = aCapistranoStyle ? File.join(shared,'uploads') : File.join(path,'tmp/uploads')
			FileUtils.mkdir_p(uploads)
			
			# create database yml file
			dbs = {
				'bogus' => {
					'adapter' => 'mysql',
					'database' => 'sdsdsad',
					'username' => 'asdsadasd',
					'password' => 'dfdsgdfg'
				}
			}
			params = {'adapter' => 'mysql'}
			aDatabaseParams.values.first.each {|k,v| params[k.to_s] = v}
			dbs[aDatabaseParams.keys.first.to_s] = params
			yaml_file_from_hash(File.join(path,'config/database.yml'),dbs)

			3.times { create_random_file(File.join(path,'kind'),1+rand(100),random_filename(aFolderName+'_')) }
			3.times { create_random_file(path,1+rand(100),random_filename(aFolderName+'_')) }
			3.times { create_random_file(uploads,1+rand(100),random_filename(aFolderName+'_')) }
			return path
		end
		
		def filelist_with_sizes(aPath)
			result = MiscUtils.recursive_file_list(aPath,true)
			result.map! do |f|
				shortf = MiscUtils.path_debase(f,aPath)
				shortf + "|#{File.size?(f).to_s}"
			end
			result
		end

		tempdir = MiscUtils.make_temp_dir("yore_browsercms_test")

		# set up browsercms-like A&B (different) test databases & files
		db_a = create_browsercms_db(db_details.merge(:database=>"browsercms_test_a"))
		path_a = create_browsercms_folder(tempdir,"browsercms_test_a",{:test => db_details.merge(:database=>"browsercms_test_a")},false)
		db_b = create_browsercms_db(db_details.merge(:database=>"browsercms_test_b"))
		path_b = create_browsercms_folder(tempdir,"browsercms_test_b",{:test => db_details.merge(:database=>"browsercms_test_b")},true)

		DatabaseUtils::save_database(db_details.merge(:database=>"browsercms_test_a"),File.join(tempdir,'browsercms_test_a.sql'))
		db_a_s = MiscUtils.string_from_file(File.join(tempdir,'browsercms_test_a.sql')).gsub!(/\n--.*$/,'')
		DatabaseUtils::save_database(db_details.merge(:database=>"browsercms_test_b"),File.join(tempdir,'browsercms_test_b.sql'))
		db_b_s = MiscUtils.string_from_file(File.join(tempdir,'browsercms_test_b.sql')).gsub!(/\n--.*$/,'')
		
		files_a_s = filelist_with_sizes(path_a).join("\n")
		files_uploads_a_s = filelist_with_sizes(File.join(path_a,'tmp/uploads')).join("\n")
		files_b_s = filelist_with_sizes(path_b).join("\n")
		files_uploads_b_s = filelist_with_sizes(File.join(path_b,'../../shared/uploads')).join("\n")

		assert_not_equal files_a_s,files_b_s
		assert_not_equal files_uploads_a_s,files_uploads_b_s

		# launch yore to save A to file system equivalent to : 
		# cd browsercms_test_a; yore save --app=browsercms --RAILS_ENV=test browsercms_test_a.tgz
		@yore_a = YoreCore::Yore.launch(nil,{:kind => 'browsercms',:RAILS_ENV => 'test'},{:basepath => path_a})
		browsercms_test_a_tgz = File.join(tempdir,'browsercms_test_a.tgz')
		@yore_a.save(browsercms_test_a_tgz)

		archive_contents = `tar -tf #{browsercms_test_a_tgz}`.split("\n")
		assert archive_contents.first.begins_with?('uploads/browsercms_test_a')
		puts archive_contents.inspect

		# launch yore to load file into B
		@yore_b = YoreCore::Yore.launch(nil,{:kind => 'browsercms',:RAILS_ENV => 'test'},{:basepath => path_b})
		@yore_b.load(browsercms_test_a_tgz)

		DatabaseUtils::save_database(db_details.merge(:database=>"browsercms_test_b"),File.join(tempdir,'browsercms_test_b_after.sql'))
		db_b_after_s = MiscUtils.string_from_file(File.join(tempdir,'browsercms_test_b_after.sql')).gsub!(/\n--.*$/,'')
		
		# assert files in A & B are the same within public/assets/products, and different elsewhere
		assert_not_equal db_a_s,db_b_s
		
		db_a_s.gsub!(/\n--.*$/,'')
		db_b_after_s.gsub!(/\n--.*$/,'')
		MiscUtils.string_to_file(db_a_s,"/Users/gary/temp/db_a_s.txt")
		MiscUtils.string_to_file(db_b_after_s,"/Users/gary/temp/db_b_after_s.txt")
		assert_equal db_a_s,db_b_after_s			

		files_b_after_s = filelist_with_sizes(path_b).join("\n")
		files_uploads_b_after_s = filelist_with_sizes(File.join(path_b,'../../shared/uploads')).join("\n")
		
		assert_not_equal files_b_s,files_b_after_s		# different because of dest being backed up to tmp/yore, not because of uploads
		assert_not_equal files_uploads_b_after_s,files_uploads_b_s
		assert_equal files_uploads_a_s,files_uploads_b_after_s	
	end

end
