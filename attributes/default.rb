#We need at least fog v1.6.0 to be able to create optimized ebs volumes...
# As per https://github.com/fog/fog/blob/master/changelog.txt
default['onepower_aws']['fog_min_version']='1.6.0'
#But only if we are on ubuntu lesser than 12.10
default['onepower_aws']['ubuntu_min_version']="12.10"
