actions :associate, :disassociate, :show

attribute :aws_access_key,        :kind_of => String, :required => true
attribute :aws_secret_access_key, :kind_of => String, :required => true
attribute :ip,                    :kind_of => String
attribute :timeout,               :default => 3*60 # 3 mins, nil or 0 for no timeout

