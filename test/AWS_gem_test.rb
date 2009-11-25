require 'rubygems'
gem 'buzzcore'; require 'buzzcore';
require 'yore/yore_core'
require 'test/unit'
gem 'Shoulda'; require 'shoulda'
require 'fileutils'

gem 'aws-s3'; require 'aws/s3'

#require 'aws/s3/exceptions'

class AWSGemTest < Test::Unit::TestCase

	CREDS = Credentials.new()

	def setup
		puts "setup"
		assert (CREDS[:s3_access_key_id] && CREDS[:s3_secret_access_key] && CREDS[:s3_yore_test_bucket])
		AWS::S3::Base.establish_connection!(
			:access_key_id     => CREDS[:s3_access_key_id],
			:secret_access_key => CREDS[:s3_secret_access_key]
		)		
  end	

	def bucket_exists?(aName)	
		AWS::S3::Bucket.find(aName)
		true
	rescue
		false	
	end

	def ensure_clean_bucket(aName)
		AWS::S3::Bucket.delete(aName, :force => true) if bucket_exists?(aName)
		AWS::S3::Bucket.create(aName)
		AWS::S3::Bucket.find(aName)
	end

	# eg. policy = policy_add(policy,{'id' => 'dssdfsdf'},%w(READ WRITE))
	def policy_add(aPolicy,aGranteeAttrs,aPermissions)
		aPolicy ||= AWS::S3::ACL::Policy.new
		grantee = AWS::S3::ACL::Grantee.new(aGranteeAttrs)
		grantee.display_name ||= 'display_name'
		aPermissions.each do |p|
			grant = AWS::S3::ACL::Grant.new
			grant.permission = p
			grant.grantee = grantee
			aPolicy.grants << grant
		end
		aPolicy
	end

	def grant_bucket_permissions(aBucketName,aPermissions,aGranteeAttrs,aMerge = false)
		policy = (aMerge ? AWS::S3::Bucket.acl(aBucketName) : nil)
		policy = policy_add(policy,aGranteeAttrs,aPermissions)
		policy.owner ||= Owner.current
		AWS::S3::Bucket.acl(aBucketName,policy)
		policy
	end

 	def grant_object_permissions(aBucketName,aObjectName,aPermissions,aGranteeAttrs,aMerge = false)
		policy = (aMerge ? AWS::S3::S3Object.acl(aObjectName,aBucketName) : nil)
		policy = policy_add(policy,aGranteeAttrs,aPermissions)
		policy.owner ||= Owner.current
		AWS::S3::S3Object.acl(aObjectName,aBucketName,policy)  #S3Object.acl('kiss.jpg', 'marcel')
		policy
	end

	# ensures the destination bucket exists with the right permissions for upload_backup
	def ensure_backup_bucket(aBucketName,aOtherUserAttrs=nil)
		AWS::S3::Bucket.create(aBucketName) unless bucket_exists?(aBucketName)
		grant_bucket_permissions(aBucketName,%w(WRITE READ_ACP),aOtherUserAttrs,true) if aOtherUserAttrs
	end

	# Summary: Uploads the given file to the bucket, then gives up permissions to the bucket owner
	# Details :
	#	* intended to allow files to be uploaded to S3, but not allowing the files to be interfered with should 
	#   the web server get hacked.
	# 	In truth, S3 permissions aren't adequate and the best we can do is that the file can't be read,
	# 	but can be written over. The user also can't get a listing of the bucket
	# * S3 won't allow objects (or buckets) to change owner, but we do everything else ie give FULL_CONTROL,
	# 	and remove it from self, to hand control to the bucket owner
	# * This requires the bucket to give WRITE & READ_ACP permissions to this user
	def upload_backup(aFileName,aBucketName,aObjectName = nil)
		aObjectName ||= File.basename(aFileName)
		AWS::S3::S3Object.store(aObjectName, MiscUtils.string_from_file(aFileName), aBucketName)
		bucket_owner = AWS::S3::Bucket.acl(aBucketName).owner
		policy = policy_add(nil,{'id' => bucket_owner.id, 'display_name' => bucket_owner.display_name},'FULL_CONTROL')
		policy.owner = AWS::S3::Owner.current
		# replace policy with full control to bucket owner, none to test_user
		AWS::S3::S3Object.acl(aObjectName,aBucketName,policy)
	end

	should "login" do
		test_bucket = ensure_clean_bucket(CREDS[:s3_yore_test_bucket])
		puts test_bucket.inspect
		assert !test_bucket.nil?
	end

	should "upload, download and compare" do
		test_bucket = ensure_clean_bucket(CREDS[:s3_yore_test_bucket])
		test_filename = 'up_down_compare'
		test_content = 'abc'
		AWS::S3::S3Object.store(test_filename, test_content, test_bucket.name)
		after_content = AWS::S3::S3Object.value test_filename, test_bucket.name
		assert_equal test_content, after_content
	end
	

	should "create bucket writable (and not readable) by another user" do
			test_user_bucket = ensure_clean_bucket(CREDS[:s3_test_user_bucket])
			ensure_backup_bucket(CREDS[:s3_test_user_bucket],{'email_address' => CREDS[:s3_test_user_email]})

			test_filename = 'up_down_compare'
			test_content = 'xyz'
			# reconnect as user
			AWS::S3::Base.establish_connection!(
				:access_key_id     => CREDS[:s3_test_user_id],
				:secret_access_key => CREDS[:s3_test_user_key]
			)
			temp_file = MiscUtils.make_temp_file(nil, nil, test_content)
			upload_backup(temp_file,CREDS[:s3_test_user_bucket],test_filename)
			
			# should fail reading
			begin
				after_content = AWS::S3::S3Object.value test_filename, CREDS[:s3_test_user_bucket]
				flunk
			rescue AWS::S3::ResponseError => e
				assert_equal e.class.to_s,"AWS::S3::AccessDenied"
			end

			# should fail writing but unfortunately doesn't
			#new_content = '123'
			#begin
			#	AWS::S3::S3Object.store(test_filename, new_content, CREDS[:s3_test_user_bucket])
			#	flunk "succeeded overwriting (should fail)"
			#rescue AWS::S3::ResponseError => e
			#	assert_equal e.class.to_s,"AWS::S3::AccessDenied"
			#end


			# back to normal
			AWS::S3::Base.establish_connection!(
				:access_key_id     => CREDS[:s3_access_key_id],
				:secret_access_key => CREDS[:s3_secret_access_key]
			)
			test_user_bucket = AWS::S3::Bucket.find(CREDS[:s3_test_user_bucket])
			after_content = AWS::S3::S3Object.value test_filename, test_user_bucket.name
			assert_equal test_content, after_content
	end

end
