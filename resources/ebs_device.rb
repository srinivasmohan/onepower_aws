actions :create, :attach, :detach, :snapshot, :prune

attribute :aws_access_key,        :kind_of => String
attribute :aws_secret_access_key, :kind_of => String

attribute :size,                  :kind_of => Integer
attribute :availability_zone,     :kind_of => String
attribute :device,                :kind_of => String
attribute :type,                  :kind_of => String #Typically standard. But 'io1' if you want optimized volume
attribute :iops,                  :kind_of => Integer #How many IOPS, matters only if type='io1'
attribute :volume_id,             :kind_of => String
attribute :description,           :kind_of => String
attribute :timeout,               :default => 180 # 3 mins, nil or 0 for no timeout

attribute :snapshot_id,           :kind_of => String
attribute :snapshots_to_keep,     :default => 5
