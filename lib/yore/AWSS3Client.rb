require 'fileutils'

gem 'buzzcore'; require 'buzzcore';
gem 'aws-s3'; require 'aws/s3'

# although this is implemented as an instantiable object, not a singleton,
# the AWS gem seems to operate as a singleton, so don't create more than one of these.
class AWSS3Client

	attr_accessor :credentials

	def initialize(aCredentials=nil)
		@credentials = aCredentials || Credentials.new()
		connect
	end

	def connect(aId=nil,aKey=nil)
		aId ||= @credentials[:s3_access_key_id]
		aKey ||= @credentials[:s3_secret_access_key]
		AWS::S3::Base.establish_connection!(
			:access_key_id     => aId,
			:secret_access_key => aKey
		)
	end

	def bucket(aName)
		return AWS::S3::Bucket.find(aName)
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

	# ensures the destination bucket exists with the right permissions for upload_backup
	# eg. @s3client.ensure_backup_bucket('a_bucket',{'email_address' => 'user@domain.com'})
	def ensure_backup_bucket(aBucketName,aOtherUserAttrs=nil)
		AWS::S3::Bucket.create(aBucketName) unless bucket_exists?(aBucketName)
		grant_bucket_permissions(aBucketName,%w(WRITE READ_ACP),aOtherUserAttrs,true) if aOtherUserAttrs
	end
	
	def new_backup_bucket(aBucketName,aOtherUserAttrs)
		AWS::S3::Bucket.create(aBucketName)
		grant_bucket_permissions(aBucketName,%w(WRITE READ_ACP),aOtherUserAttrs,true)
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

	def put_content(aFilename, aContent, aBucketName)
		AWS::S3::S3Object.store(aFilename, aContent, aBucketName)
	end
	
	def upload(aFilename,aBucketName,aObjectName=nil)
		aObjectName ||= File.basename(aFileName)
		#AWS::S3::S3Object.store(aObjectName, MiscUtils.string_from_file(aFileName), aBucketName)
		content = MiscUtils.string_from_file(aFileName)

		put_content(aObjectName, content, aBucketName)
	end	
	
	def get_content(aFilename, aBucketName)	
		return AWS::S3::S3Object.value(aFilename, aBucketName)
	end

	def download(aFilename,aBucketName,aObjectName=nil)
		aObjectName ||= File.basename(aFilename)
		#AWS::S3::S3Object.store(aObjectName, MiscUtils.string_from_file(aFilename), aBucketName)
		MiscUtils.string_to_file(get_content(aObjectName,aBucketName),aFilename)
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
		policy = AWS::S3::S3Object.acl(aObjectName,aBucketName)
		policy.grants.clear
		policy = policy_add(policy,{'id' => bucket_owner.id, 'display_name' => bucket_owner.display_name},'FULL_CONTROL')

		# replace policy with full control to bucket owner, none to test_user
 		AWS::S3::S3Object.acl(aObjectName,aBucketName,policy)
	end

end

