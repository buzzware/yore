require File.expand_path('test_helper',File.dirname(__FILE__))

class AWSGemTest < Test::Unit::TestCase

	def setup
		puts "setup"
		creds = Credentials.new()
		assert(creds[:s3_access_key_id] && creds[:s3_secret_access_key] && creds[:s3_yore_test_bucket])
		@s3client = AWSS3Client.new(creds)
  end	

	should "login" do
		test_bucket = @s3client.ensure_clean_bucket(@s3client.credentials[:s3_yore_test_bucket])
		puts test_bucket.inspect
		assert !test_bucket.nil?
	end

	should "upload, download and compare" do
		test_bucket = @s3client.ensure_clean_bucket(@s3client.credentials[:s3_yore_test_bucket])
		test_filename = 'up_down_compare'
		test_content = 'abc'
		#AWS::S3::S3Object.store(test_filename, test_content, test_bucket.name)
		@s3client.put_content(test_filename, test_content, test_bucket.name)
		#after_content = AWS::S3::S3Object.value test_filename, test_bucket.name
		after_content = @s3client.get_content(test_filename, test_bucket.name)
		assert_equal test_content, after_content
	end
	

	should "create bucket writable (and not readable) by another user" do
		test_user_bucket = @s3client.ensure_clean_bucket(@s3client.credentials[:s3_test_user_bucket])
		@s3client.ensure_backup_bucket(@s3client.credentials[:s3_test_user_bucket],{'email_address' => @s3client.credentials[:s3_test_user_email]})

		test_filename = 'up_down_compare'
		test_content = 'xyz'
		# reconnect as user
		@s3client.connect(@s3client.credentials[:s3_test_access_id],@s3client.credentials[:s3_test_access_key])
		temp_file = MiscUtils.make_temp_file(nil, nil, test_content)
		@s3client.upload_backup(temp_file,@s3client.credentials[:s3_test_user_bucket],test_filename)
		
		# should fail reading
		begin
			after_content = @s3client.get_content(test_filename, @s3client.credentials[:s3_test_user_bucket])
			flunk
		rescue AWS::S3::ResponseError => e
			assert_equal e.class.to_s,"AWS::S3::AccessDenied"
		end

		# should fail overwriting
		#new_content = '123'
		#begin
		#	AWS::S3::S3Object.store(test_filename, new_content, @s3client.credentials[:s3_test_user_bucket])
		#	flunk "succeeded overwriting (should fail)"
		#rescue AWS::S3::ResponseError => e
		#	assert_equal e.class.to_s,"AWS::S3::AccessDenied"
		#end

		# back to normal
		@s3client.connect

		test_user_bucket = @s3client.bucket(@s3client.credentials[:s3_test_user_bucket])
		after_content = @s3client.get_content(test_filename, test_user_bucket.name)
		assert_equal test_content, after_content
	end

	should "fail with wrong credentials" do
		test_user_bucket = @s3client.ensure_clean_bucket(@s3client.credentials[:s3_test_user_bucket])
		begin
			permission = @s3client.grant_bucket_permissions(test_user_bucket,%w(WRITE READ_ACP),{'email_address' => 'asddsad@sdsddsadsa.com'},true)
			flunk
		rescue AWS::S3::ResponseError => e
			assert_equal e.class.to_s,"AWS::S3::NoSuchBucket"
		end
	end

end
