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

	# yore 
	# create bucket name
	# ensure_clean_bucket

	# test with methods for creating suitable acl

	# see http://amazon.rubyforge.org/
	#
	# policy = S3Object.acl('kiss.jpg', 'marcel')
  # pp policy.grants
  # [#<AWS::S3::ACL::Grant FULL_CONTROL to noradio>,
  #  #<AWS::S3::ACL::Grant READ to AllUsers Group>]

	#policy = S3Object.acl('kiss.jpg', 'marcel')
	#grant = ACL::Grant.new
	#grant.permission = 'READ_ACP'
	#grantee = ACL::Grantee.new
	#grant.grantee = grantee
	#policy.grants << grant
	##pp policy.grants
	#S3Object.acl('kiss.jpg', 'marcel', policy)
	## after : pp S3Object.acl('kiss.jpg', 'marcel').grants

## Add a grant to the bucket's policy
#  bucket.acl.grants << some_grant
#
#  # Write the changes to the policy
#  bucket.acl(bucket.acl)

	# eg. policy = policy_add(policy,{'id' => 'dssdfsdf'},%w(READ WRITE))
	def policy_add(aPolicy,aGranteeAttrs,aPermissions)
		aPolicy ||= AWS::S3::ACL::Policy.new
		grantee = AWS::S3::ACL::Grantee.new(aGranteeAttrs)
		#grantee.email_address = 'familyincnet@gmail.com'
		#grantee.email_address = aUserEmail
		grantee.display_name ||= 'display_name'
		aPermissions.each do |p|
			grant = AWS::S3::ACL::Grant.new
			grant.permission = p
			grant.grantee = grantee
			aPolicy.grants << grant
		end
		aPolicy
	end

		#policy = AWS::S3::Bucket.acl(aBucketName)
		#grantee = AWS::S3::ACL::Grantee.new
		##grantee.email_address = 'familyincnet@gmail.com'
		#grantee.id = aUserId
		#grantee.display_name = 'test_user'
		#aPermissions.each do |p|
		#	grant = AWS::S3::ACL::Grant.new
		#	grant.permission = p
		#	grant.grantee = grantee
		#	policy.grants << grant
		#end
		#AWS::S3::Bucket.acl(aBucketName, policy)


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

	should "login" do
		#buckets = AWS::S3::Service.buckets
		#assert !buckets.empty?
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
			grant_bucket_permissions(CREDS[:s3_test_user_bucket],%w(WRITE),{'email_address' => CREDS[:s3_test_user_email]},true)

			test_filename = 'up_down_compare'
			test_content = 'xyz'
			# reconnect as user
			AWS::S3::Base.establish_connection!(
				:access_key_id     => CREDS[:s3_test_user_id],
				:secret_access_key => CREDS[:s3_test_user_key]
			)
			#test_user_bucket = AWS::S3::Bucket.find(CREDS[:s3_test_user_bucket])
			
			AWS::S3::S3Object.store(test_filename, test_content, CREDS[:s3_test_user_bucket])
			#bucket_owner = AWS::S3::Bucket.acl(CREDS[:s3_test_user_bucket]).owner
			#require 'ruby-debug'; debugger
			#policy = policy_add(nil,{'email_address' => CREDS[:s3_test_user_email]},'FULL_CONTROL')
			policy = policy_add(nil,{'email_address' => CREDS[:s3_access_email]},'FULL_CONTROL')
			#policy.owner = bucket_owner
			# can only give the current owner here. The docs say the owner of a bucket or object cannot be changed
			policy.owner = AWS::S3::Owner.current
			#policy.owner = AWS::S3::Owner.new('id' => bucket_owner.id, 'display_name' => bucket_owner.display_name)
			# replace policy with full control to bucket owner, none to test_user
			AWS::S3::S3Object.acl(test_filename,CREDS[:s3_test_user_bucket],policy)  #S3Object.acl('kiss.jpg', 'marcel')

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
