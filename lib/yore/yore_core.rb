require 'rubygems'
gem 'buzzcore'; require 'buzzcore';
require 'buzzcore/extra/xml_utils2'

require 'fileutils'
require 'net/smtp'

require 'yore/AWSS3Client'
require 'yaml'


THIS_FILE = File.expand_path(__FILE__)
THIS_DIR = File.dirname(THIS_FILE)

module YoreCore

  class Yore

    DEFAULT_CONFIG = {
			:kind => String,
			:basepath => String,
			:backup_id => String,
			:backup_email => String,
      :crypto_iv => "3A63775C1E3F291B0925578165EB917E",    # apparently a string of up to 32 random hex digits
      :crypto_key => "07692FC8656F04AE5518B80D38681E038A3C12050DF6CC97CEEC33D800D5E2FE",   # apparently a string of up to 64 random hex digits
      :first_hour => 4,
      :prefix => 'backup',
      :log_level => 'INFO',
			:leave_temp_files => false,
      :bucket => String,
			:email_report => false,
      :mail_host => String,
      :mail_port => 25,
      :mail_helodomain => String,
      :mail_user => String,
      :mail_password => String,
			:mail_from => String,
			:mail_from_alias => String,
			:mail_to => String,
			:mail_to_alias => String,
			:mail_auth => :plain,
			:mysqldump => 'mysqldump',
			:RAILS_ENV => String
		}

    attr_reader :config
    attr_reader :logger
    attr_reader :reporter

    def initialize(aConfig=nil)
      DEFAULT_CONFIG[:email_report] = false  # fixes some bug where this was nil

			cons = ConsoleLogger.new()
			cons.level = Logger::Severity.const_get(config[:log_level]) rescue Logger::Severity::INFO

      report_file = MiscUtils::temp_file
			@reporter = Logger.new(report_file)
			@reporter.formatter = ConsoleLogger::ReportFormatter.new
			@reporter.level = cons.level

			@logger = MultiLogger.new([cons,@reporter])
			@logger.info "Yore file and database backup tool for Amazon S3 "
			@logger.info "(c) 2009 Buzzware Solutions (www.buzzware.com.au)"
			@logger.info "-------------------------------------------------"
			@logger.info ""

      @logger.info "report file: #{report_file}"

      configure(aConfig)
    end
		
		def s3client
			return @s3client if @s3client		
			@s3client = ::AWSS3Client.new()
			logger.info "Using S3 key #{@s3client.credentials[:s3_access_key_id]}"
			@s3client			
		end
		
		#aOptions may require {:basepath => File.dirname(File.expand_path(job))}
		def self.launch(aConfigXml,aCmdOptions=nil,aOptions=nil)
			if !aConfigXml
				path = MiscUtils.canonize_path('yore.config.xml',aOptions && aOptions[:basepath])
				aConfigXml = path if File.exists?(path)				
			end
			result = Yore.new()
			result.configure(aConfigXml,aCmdOptions,aOptions)
			return result
		end

		def create_empty_config_xml()
			s = <<-EOS
				<?xml version="1.0" encoding="UTF-8"?>
				<?xml version="1.0" encoding="UTF-8"?>
				<Yore>
					<SimpleItems>
					</SimpleItems>
					<Sources>
					</Sources>
				</Yore>
			EOS
			xdoc = REXML::Document.new(s)
			return xdoc.root
		end
		
		def get_rails_db_details(aRailsPath,aRailsEnv,aFile=nil)
			return nil unless aRailsPath && aRailsEnv && aRailsEnv!=''
			yml_file = MiscUtils.path_combine(aRailsPath,aFile || 'config/database.yml')
			return nil unless dbyml = (YAML::load(File.open(yml_file)) rescue nil)	
			return dbyml[aRailsEnv] && dbyml[aRailsEnv].symbolize_keys
		end
		
		def expand_app_option(kind=nil)
			kind = config[:kind] unless kind && !kind.empty?
			return nil unless kind && !kind.empty?
			config.xmlRoot = create_empty_config_xml() if !config.xmlRoot
			xmlSources = XmlUtils.single_node(config.xmlRoot,'/Yore/Sources') || XmlUtils.add_xml_from_string('<Sources/>',XmlUtils.single_node(config.xmlRoot,'/Yore'))
			case kind
				when 'spree'
					# add file source
					strSource = <<-EOS
						<Source Type="File">
							<IncludePath BasePath="public/assets">products</IncludePath>
						</Source>
					EOS
					XmlUtils.add_xml_from_string(strSource,xmlSources)
					expand_app_option('rails')	# do again
				# 
				# if capistrano deployed, uploads are assumed to be in shared/uploads
				#
				when 'browsercms'
					# add file source
					uploadParent = MiscUtils.expand_magic_path('.../shared',config[:basepath]) || File.join(config[:basepath],'tmp')
					strSource = <<-EOS
						<Source Type="File">
							<IncludePath BasePath="#{uploadParent}">uploads</IncludePath>
						</Source>
					EOS
					XmlUtils.add_xml_from_string(strSource,xmlSources)
					expand_app_option('rails')	# do again
				when 'rails'
					# * add db source from database.yml
					# load database from config[:basepath],'config/database.yml'
					#if (dbyml = YAML::load(File.open(File.expand_path('config/database.yml',config[:basepath]))) rescue nil)
					#	if env = (config[:RAILS_ENV] && config[:RAILS_ENV]!='' && config[:RAILS_ENV])
					#		if (db_details = dbyml[env]) &&

					#<Database Name="#{db_details[:database]}" Host="#{db_details[:host]}" User="#{db_details[:username]}" Password="#{db_details[:password]}">
					strSource = <<-EOS
						<Source Type="MySql" >
							<Database Yml="config/database.yml">
								<ArchiveFile>rails_app.sql</ArchiveFile>
							</Database>
						</Source>
					EOS
					XmlUtils.add_xml_from_string(strSource,xmlSources)
			end
		end

    # read the config however its given and return a hash with values in their correct type, and either valid or nil
    # keys must be :symbols for aOptions. aConfig and aCmdOptions can be strings
    def configure(aConfig,aCmdOptions = nil,aOptions = nil)
      config_to_read = {}
			if aConfig.is_a?(String)
				aConfig = MiscUtils.canonize_path(aConfig)
				logger.info "Job file: #{aConfig}"
				op = {:basepath => File.dirname(aConfig)}
				xmlString = MiscUtils.string_from_file(aConfig)
				xmlString = XmlUtils2.clean_data(xmlString)
				xml = XmlUtils.get_xml_root(xmlString)
				return configure(xml,aCmdOptions,op)
			end

			if @config
				config_as_hash = nil
				case aConfig
					when nil then ;	# do nothing
					when Hash,::ConfigClass then config_as_hash = aConfig
					when REXML::Element then
						config_as_hash = XmlUtils.read_simple_items(aConfig,'/Yore/SimpleItems')
						config.xmlRoot = aConfig 	# overwriting previous! perhaps should merge
					else
						raise StandardError.new('unsupported type')
				end
				config_as_hash.each{|n,v| config_to_read[n.to_sym] = v} if config_as_hash					# merge given new values
			else
				@config = ConfigXmlClass.new(DEFAULT_CONFIG,aConfig)
			end		
      aCmdOptions.each{|k,v| config_to_read[k.to_sym] = v} if aCmdOptions		# merge command options
      config_to_read.merge!(aOptions) if aOptions														# merge options
			config.read(config_to_read)
			config[:basepath] = MiscUtils.canonize_path(config[:basepath],Dir.pwd)

			expand_app_option()
    end
		
		def do_action(aAction,aArgs)
			logger.info "Executing command: #{aAction} ...\n"
			begin
				send(aAction,aArgs)
			rescue Exception => e
				logger.info {e.backtrace.join("\n")}				
				logger.warn "#{e.class.to_s}: during #{aAction.to_s}(#{(aArgs && aArgs.inspect).to_s}): #{e.message.to_s}"
			end			
		end

		def shell(aCommandline,&aBlock)
			logger.debug "To shell: " + aCommandline
      result = block_given? ? POpen4::shell(aCommandline,nil,nil,&aBlock) : POpen4::shell(aCommandline)
      logger.debug "From shell: '#{result.inspect}'"
      return result[:stdout]
		end
		
    def get_log
      logger.close
      # read in log and return
    end

    def get_report
      MiscUtils::string_from_file(@reporter.logdev.filename)
    end
		
		def temp_path
			@temp_path = MiscUtils.make_temp_dir('yore') unless @temp_path
			return @temp_path
		end

    def self.filemap_from_filelist(aFiles)
      ancestor_path = MiscUtils.file_list_ancestor(aFiles)
      filemap = {}
      aFiles.each do |fp|
        filemap[fp] = MiscUtils.path_debase(fp,ancestor_path)
      end
      filemap
    end

    # By default, GNU tar suppresses a leading slash on absolute pathnames while creating or reading a tar archive. (You can suppress this with the -p option.)
    # tar : http://my.safaribooksonline.com/0596102461/I_0596102461_CHP_3_SECT_9#snippet

    # get files from wherever they are into a single file
    def compress(aSourceFiles,aDestFile,aParentDir=nil)
			logger.info "Collecting files ..."
			#logger.info aSourceFiles.join("\n")
      #filelist = filemap = nil
      #if aSourceFiles.is_a?(Hash)
      #  filelist = aSourceFiles.keys
      #  filemap = aSourceFiles
      #else  # assume array
      #  filelist = aSourceFiles
      #  filemap = Yore.filemap_from_filelist(aSourceFiles)
      #end
      #aParentDir ||= MiscUtils.file_list_ancestor(filelist)
      listfile = MiscUtils.temp_file
      MiscUtils.string_to_file(
        aSourceFiles.join("\n"),			#filelist.sort.map{|p| MiscUtils.path_debase(p, aParentDir)}.join("\n"),
        listfile
      )
      tarfile = MiscUtils.file_change_ext(aDestFile, 'tar')
			
			shell("tar cv #{aParentDir ? '--directory='+aParentDir.to_s : ''} --file=#{tarfile} --files-from=#{listfile}")
			shell("rm #{listfile}") unless config[:leave_temp_files]
			logger.info "Compressing ..."
			tarfile_size = File.size(tarfile)
			shell("bzip2 #{tarfile}; mv #{tarfile}.bz2 #{aDestFile}")
			
			logger.info "Compressed #{'%.1f' % (tarfile_size*1.0/2**10)} KB to #{'%.1f' % (File.size(aDestFile)*1.0/2**10)} KB"
    end

    def uncompress(aArchive,aDestination=nil,aArchiveContent=nil)			
			logger.info "uncompressing #{aArchive}"
      #tarfile = File.expand_path(MiscUtils.file_change_ext(File.basename(aArchive),'tar'),temp_dir)
      #shell("bunzip2 #{tarfile}; mv #{tarfile}.bz2 #{aDestFile}")
      #
			#shell("tar cv #{aParentDir ? '--directory='+aParentDir.to_s : ''} --file=#{tarfile} --files-from=#{listfile}")
			#logger.info "Compressing ..."
			#tarfile_size = File.size(tarfile)
      #shell("bzip2 #{tarfile}; mv #{tarfile}.bz2 #{aDestFile}")
			#logger.info "Compressed #{'%.1f' % (tarfile_size*1.0/2**10)} KB to #{'%.1f' % (File.size(aDestFile)*1.0/2**10)} KB"
			aDestination ||= MiscUtils.make_temp_dir('uncompress')
			FileUtils.mkdir_p(aDestination)
			shell("tar xvf #{aArchive} #{aArchiveContent.to_s} --directory=#{aDestination} --bzip2")
    end


    def pack(aFileIn,aFileOut)
			logger.info "Encrypting ..."
      shell "openssl enc -aes-256-cbc -K #{config[:crypto_key]} -iv #{config[:crypto_iv]} -in #{aFileIn} -out #{aFileOut}"
    end

    def unpack(aFileIn,aFileOut)
       shell "openssl enc -d -aes-256-cbc -K #{config[:crypto_key]} -iv #{config[:crypto_iv]} -in #{aFileIn} -out #{aFileOut}"
    end

    def ensure_bucket(aBucket=nil,aUserEmail=nil)
      aBucket ||= config[:bucket]
      aUserEmail ||= config[:bucket_user_email]
			logger.info "Ensuring S3 bucket #{aBucket} exists ..."
			s3client.ensure_backup_bucket(aBucket,aUserEmail ? {'email_address' => aUserEmail} : nil)
    end

    # uploads the given file to the current bucket as its basename
    def upload(aFile)
      #ensure_bucket()
			logger.debug "Uploading #{aFile} to S3 bucket #{config[:bucket]} ..."
			logger.info "Uploading #{File.basename(aFile)} to S3 bucket #{config[:bucket]} ..."
			s3client.upload_backup(aFile,config[:bucket],File.basename(aFile))
    end

    # downloads the given file from the current bucket as its basename
    def download(aFile)
			s3client.download(aFile,config[:bucket],File.basename(aFile))
    end

    # calculate the date (with no time component) based on :day_begins_hour and the local time
    def backup_date(aTime)
      (aTime.localtime - (config[:first_hour]*3600)).date
    end

    # generates filename based on date and config
    # config :
    #   :first_hour
    #   :
    def encode_file_name(aTimeNow=Time.now)
      "#{config[:prefix]}-#{backup_date(aTimeNow).date_numeric}.yor"
    end

    # return date based on filename
    def decode_file_name(aFilename)
      prefix,date,ext = aFilename.scan(/(.*?)\-(.*?)\.(.*)/).flatten
      return Time.from_date_numeric(date)
    end


    def clean
      
    end

		# "/usr/bin/env" sets normal vars
		# eg. 30 14 * * * /usr/bin/env ruby /Users/kip/svn/thewall/script/runner /Users/kip/svn/thewall/app/delete_old_posts.rb
		# http://www.ameravant.com/posts/recurring-tasks-in-ruby-on-rails-using-runner-and-cron-jobs

		# install gems
		# make folder with correct folder structure
		# copy in files
		# add to crontab, with just email sending, then call backup

    def report
      return unless config[:email_report]
      msg = get_report()
			logger.info "Sending report via email to #{config[:mail_to]} ..."
      MiscUtils::send_email(
        :host => config[:mail_host],
        :port => config[:mail_port],
        :helodomain => config[:mail_helodomain],
        :user => config[:mail_user],
        :password => config[:mail_password],
        :from => config[:mail_from],
        :from_alias => config[:mail_from_alias],
        :to => config[:mail_to],
        :to_alias => config[:mail_to_alias],
				:auth => config[:mail_auth],
        :subject => 'backup report',
        :message => msg
      )
    end

    def database_from_xml(aDatabaseNode)
			result = {
        :file => XmlUtils::peek_node_value(aDatabaseNode, "ToFile"),
        :archive_file => XmlUtils::peek_node_value(aDatabaseNode, "ArchiveFile")
			}
			if config[:RAILS_ENV] && (yml=aDatabaseNode.attributes['Yml'] || !aDatabaseNode.attributes['Name'])		# has yml or doesn't have database name
				raise StandardError.new("RAILS_ENV must be given to read #{yml}") if !config[:RAILS_ENV] || config[:RAILS_ENV].empty?
				db_details = get_rails_db_details(config[:basepath],config[:RAILS_ENV],yml)
				raise StandardError.new('insufficient or missing database configuration') if !db_details
				result.merge!(db_details)
			else
				result.merge!({
					:host => aDatabaseNode.attributes['Host'],
					:username => aDatabaseNode.attributes['User'],
					:password => aDatabaseNode.attributes['Password'],
					:database => aDatabaseNode.attributes['Name'],
				})
			end
			result
    end
		
		
		def collect_file_list(aSourcesXml,aTempFolder)
      filelist = []
      sourceFound = false

      if aSourcesXml
				#aSourcesXml.elements['Source'].each do |xmlSource|
				REXML::XPath.each(aSourcesXml,'Source') do |xmlSource|
					case xmlSource.attributes['Type']
						when 'File' then
							# BasePath tag provides base path for IncludePaths to be relative to. Also indicates root folder for archive 
							bp = MiscUtils.path_combine(config[:basepath],XmlUtils::peek_node_value(xmlSource, "@BasePath"))
							REXML::XPath.each(xmlSource, 'IncludePath') do |xmlPath|
								bp2 = MiscUtils.path_combine(bp,XmlUtils::peek_node_value(xmlPath,"@BasePath"))
								filelist << '-C'+bp2
								destPath = MiscUtils::path_combine(bp2,xmlPath.text)
								logger.info "saving files from #{destPath}"
								files = MiscUtils::recursive_file_list(destPath)
								files.map!{|f| MiscUtils.path_debase(f,bp2)}
								filelist += files
								sourceFound = true
							end
						when 'MySql' then
							#<Source Type="MySql" >
							#	<Database Host="" Name="" User="" Password="">
							#		<ToFile>~/dbdump.sql</ToFile>
							#	</Database>
							#</Source>
							REXML::XPath.each(xmlSource, 'Database') do |xmlDb|
								args = database_from_xml(xmlDb)
								file = args.delete(:file)							#legacy, absolute path
								arc_file = args.delete(:archive_file)	#path in archive
								unless args[:username] && args[:password] && args[:database] && (file||arc_file)
									raise StandardError.new("Invalid or missing parameter")
								end
								logger.info "saving database #{args[:database]}"
								if arc_file
									arc_file = MiscUtils.path_debase(arc_file,'/')
									sql_file = File.expand_path(arc_file,aTempFolder)
									FileUtils.mkdir_p(File.dirname(sql_file))  						# create folders as necessry							
									DatabaseUtils::save_database(args,sql_file)					#db_to_file(args,sql_file)
									filelist << '-C'+aTempFolder
									filelist << arc_file
									sourceFound = true
								else
									DatabaseUtils::save_database(args,sql_file)
									filelist << file
									sourceFound = true
								end
							end
					end
				end
			end
      raise StandardError.new("Backup source found but file list empty") if sourceFound && filelist.empty?
			return filelist	
		end

		def rails_tmp_path
			return @rails_tmp_path if @rails_tmp_path
			@rails_tmp_path = File.join(config[:basepath],'tmp/yore',Time.now.strftime('%Y%m%d-%H%M%S'))
		end
		
		def self.move_folder(aPath1,aPath2)
			path2Parent = MiscUtils.path_parent(aPath2)
			FileUtils.mkdir_p(path2Parent)
			FileUtils.mv(aPath1, path2Parent, :force => true)
		end

		def self.copy_folder(aPath1,aPath2)
			path2Parent = MiscUtils.path_parent(aPath2)
			FileUtils.mkdir_p(path2Parent)
			FileUtils.cp_r(aPath1, path2Parent)
		end

		def save_internal(aFilename)
			FileUtils.mkdir_p(files_path = File.join(temp_path,'files'))
			filelist = collect_file_list(XmlUtils.single_node(config.xmlRoot,'/Yore/Sources'),files_path)
			logger.info "files collected:\n  "+filelist.join("\n  ")
      compress(filelist,aFilename)
		end

		#
		#		ACTIONS
		#

		def save(aArgs)
			fnArchive = aArgs.is_a?(Array) ? aArgs.first : aArgs	#only supported argument
			config[:out_file] = File.expand_path(fnArchive || 'save.tgz',config[:basepath])
			save_internal(config[:out_file])
		end

    def backup(aArgs)	# was aJobFiles
      temp_file = File.expand_path('backup.tar',temp_path)
			save_internal(temp_file)
      backup_file = File.expand_path(encode_file_name(),temp_path)
      pack(temp_file,backup_file)
			shell("rm #{temp_file}") unless config[:leave_temp_files]
      upload(backup_file)
			shell("rm #{backup_file}") unless config[:leave_temp_files]
    end
				
		def load(aArgs,aCmdOptions=nil)
			fnArchive = aArgs.is_a?(Array) ? aArgs.first : aArgs	#only supported argument

			FileUtils.mkdir_p(archive_path = File.join(temp_path,'archive'))
			uncompress(fnArchive,archive_path)
			xmlSources = XmlUtils.single_node(config.xmlRoot,'/Yore/Sources')
      REXML::XPath.each(xmlSources,'Source') do |xmlSource|
        case xmlSource.attributes['Type']
					when 'File' then
						#<Source Type="File">
						#	<IncludePath>public/assets/products</IncludePath>
						#</Source>
						#
						# arcparent = parent_folder(IncludePath.text)
						# arcfolder = File.basename(IncludePath.text)
						# destination = MiscUtils.path_combine(basepath,IncludePath.text)
						bpSource = MiscUtils.path_combine(config[:basepath],XmlUtils::peek_node_value(xmlSource, "@BasePath"))
						REXML::XPath.each(xmlSource,'IncludePath') do |xmlIncludePath|
							bpInclude = MiscUtils.path_combine(bpSource,XmlUtils::peek_node_value(xmlIncludePath, "@BasePath"))

							pathArchive = xmlIncludePath.text()
							pathUncompressed = File.join(archive_path,pathArchive)
							pathTmp = File.join(rails_tmp_path,pathArchive)
							pathDest = File.join(bpInclude,pathArchive)
							logger.info "loading files into #{pathDest}"

							# move basepath/relativepath to tmp/yore/090807-010203/relativepath (out of the way)
							Yore::move_folder(pathDest,pathTmp) if File.exists?(pathDest)
							# get <IncludeFiles> and copy to basepath/relativepath
							Yore::copy_folder(pathUncompressed,pathDest) if File.exists?(pathUncompressed)
						end
					when 'MySql' then
						db_details = database_from_xml(XmlUtils.single_node(xmlSource,'Database'))
						logger.info "loading database #{db_details[:database]}"
						DatabaseUtils.load_database(db_details,File.join(archive_path,db_details[:archive_file]))
				end
			end						
		end		
		
		#def encrypt(aArgs)
		#	archive	= aArgs.delete(0)
		#	paths = aArgs
		#	# filelist from paths
    #  compress(filelist,aFilename)
		#end
		
		# needs :crypto_key, :crypto_iv
		# args :
		#		archive : source file to decrypt
		#		folder : destination folder to decrypt to
		def decrypt(aArgs)
			archive	= aArgs[0]
			folder = MiscUtils.file_no_extension(archive) unless folder = aArgs[1]
			folder = File.expand_path(folder,config[:basepath])
      temp_file = File.expand_path('file.tar',temp_path)
			unpack(archive,temp_file)
			uncompress(temp_file,folder)
		end
		
		def retrieve(aArgs)
			download(aArgs[0])
			decrypt(aArgs)
		end
		
		def new_backup_bucket(aArgs)
			bucket_name = config[:bucket]
			if s3client.bucket_exists?(bucket_name)
				puts "sorry, bucket already exists"
			else
				backup_user_attrs = {
					'id' => config[:backup_id],
					'display_name' => config[:backup_name] || 'backup_name',
					'email_address' => config[:backup_email]
				}
				raise StandardError.new("Must provide backup_id or backup_email") unless backup_user_attrs['id'] || backup_user_attrs['email_address']
				s3client.new_backup_bucket(bucket_name,backup_user_attrs)
			end	
		end
		
		def test_email(*aDb)
			args = {
        :host => config[:mail_host],
        :port => config[:mail_port],
        :helodomain => config[:mail_helodomain],
        :user => config[:mail_user],
        :password => config[:mail_password],
        :from => config[:mail_from],
        :from_alias => config[:mail_from_alias],
        :to => config[:mail_to],
        :to_alias => config[:mail_to_alias],
				:auth => config[:mail_auth],
        :subject => 'email test',
        :message => 'Just testing email sending'
			}
			logger.debug args.inspect
      MiscUtils::send_email(args)
		end

  end
    
end
