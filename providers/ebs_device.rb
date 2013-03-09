include Onepower::AWS
#Provides ebs actions

action :create do
  raise "EBS Volume ID is allotted by AWS and can't be selected" if new_resource.volume_id
  if new_resource.type == 'io1'  #PIOPS volume
    raise "Optimized EBS volume needs #iops to be specified!" unless new_resource.iops
    itype=instance_type
    raise "This is a #{itype} instance and AWS does not support Optimized EBS for this!" unless supports_optimized_ebs(itype)
    n_iops=new_resource.iops.to_i
    n_size=new_resource.size.to_i
    raise ArgumentError, "IOPS must be between 100-2000" unless (n_iops>=100 && n_iops<=2000)
    raise ArgumentError, "Requested IOPS cannot exceed 10 times the volume size" if (n_iops > 10*n_size)
  else
    new_resource.type('standard') #Default to standard EBS, iops does not matter here.
  end 
  if new_resource.snapshot_id =~ /vol/
    new_resource.snapshot_id(find_snapshot_id(new_resource.snapshot_id))
  end
  nvid=volume_id_in_node_data 
  if nvid
  #Volume info in node data, but does volume exist at EC2?
    vol = volume_by_id(nvid)
    ifexists = vol && vol[:status]!="deleting"
    raise "Volume-ID #{nvid} exists in node data but not in EC2, remove this entry [:onepwr_aws][:ebs_volume][#{new_resource.name}][:volume_id] from node data" unless ifexists
  else
    #What if volume matches resource specs, is attached to instance but not in node data(something broke right after the first time it was attached)
    if new_resource.device && (attached_volume = currently_attached_volume(instance_id, new_resource.device))
      Chef::Log.debug("Instance already has a EBS volume attached as #{new_resource.device}")    
      compatible = volume_compatible_with_resource_definition?(attached_volume) 
      raise "Attached vol (#{attached_volume[:vol_id]}) attached as #{attached_volume[:device]} but does not conform to this resources specs" unless compatible
     Chef::Log.debug("The volume matches resource specs, so already created?")
      node.set[:onepwr_aws][:ebs_volume][new_resource.name][:volume_id]=attached_volume[:vol_id]
    else
      nvid = create_volume(new_resource.snapshot_id, new_resource.size, new_resource.availability_zone, new_resource.timeout,new_resource.type, new_resource.iops , new_resource.description)
      node.set[:onepwr_aws][:ebs_volume][new_resource.name][:volume_id]=nvid
      new_resource.updated_by_last_action(true)
    end
    node.save unless Chef::Config[:solo]
  end
end

action :attach do
  vol = determine_volume
  #Chef::Log.debug("Attach: VOL is #{vol.to_json}")
  if vol[:status] == "in-use"
    if vol[:instance_id] != instance_id
      raise "Volume #{vol[:vol_id]} is already attached to another instance #{vol[:instance_id]}!"
    else
      Chef::Log.debug("Volume #{vol[:vol_id]} is already attached to this instance")
    end
  else
    attach_volume(vol[:vol_id], instance_id, new_resource.device, new_resource.timeout)
    node.set[:onepwr_aws][:ebs_volume][new_resource.name][:volume_id] = vol[:vol_id]
    node.save unless Chef::Config[:solo]
    new_resource.updated_by_last_action(true)
  end
end

action :detach do
  vol = determine_volume
  return if vol[:instance_id] != instance_id
  detach_volume(vol[:vol_id], new_resource.timeout)
  new_resource.updated_by_last_action(true)
end

action :snapshot do
  vol = determine_volume
  snapshot = ec2.create_snapshot(vol[:vol_id])
  new_resource.updated_by_last_action(true)
  Chef::Log.info("Snapshot-ted volume #{vol[:aws_id]} as #{snapshot['body']['snapshotId']}")
end

action :prune do
  vol = determine_volume
  old_ss=Array.new
  Chef::Log.info "Checking for old snapshots of volume #{vol[:vol_id]}"
  ec2.describe_snapshots['body']['snapshotSet'].sort { |a,b| b['startTime'] <=> a['startTime'] }.each do |ss|
    next unless ss['volumeId'] == vol[:vol_id]
    old_ss << ss
  end
  #Wipe out old snapshots (i.e. anything beyond latest new_resource.snapshots_to_keep)
  if old_ss.length > new_resource.snapshots_to_keep
    old_ss[new_resource.snapshots_to_keep, old_ss.length].each do |delss|
      retval=ec2.delete_snapshot(delss['snapshotId'])['body']['return'] 
      Chef::Log.info "Deleting snapshot #{delss['snapshotId']} - #{(retval ? 'OK':'Failed')}"
      new_resource.updated_by_last_action(true)
    end 
  else
    Chef::Log.info "No snapshots to delete for volume #{vol[:vol_id]}"
  end
end

#Private
private

def volume_id_in_node_data
  begin
    node[:onepwr_aws][:ebs_volume][new_resource.name][:volume_id]
  rescue NoMethodError => e
    nil
  end
end

#Return a hash with keys :type, :status, :size and :vol_id if this instance has a EBS device associated as /dev/sdXXX
def currently_attached_volume(instanceid,device)
  ec2.describe_volumes.body['volumeSet'].each do |volume|
   next unless volume.has_key?('attachmentSet') && volume['attachmentSet'].length>0
   next unless volume['attachmentSet'].first['instanceId'] == instanceid
   next unless volume['attachmentSet'].first['device'] == device
   x={
      :type => volume['volumeType'],
      :status => volume['status'],
      :size => volume['size'],
      :vol_id => volume['volumeId'],
      :az => volume['availabilityZone']
    }
    x[:attachment_status]=volume['attachmentSet'].first['status'] if volume['attachmentSet'].first.has_key?('status')
    return x 
  end
  return nil
end

#Get volume id from AWS volume_id or node data and check if this actually exists or not
def determine_volume
  vol = currently_attached_volume(instance_id, new_resource.device)
  vol_id = new_resource.volume_id || volume_id_in_node_data || ( vol ? vol[:vol_id] : nil ) 
  raise "Volume_id is not set, and no such volume attached to instance #{instance_id}" unless vol_id
  #Did we get a legit volid?
  vol = volume_by_id(vol_id)
  #Chef::Log.debug("DETVOL: #{vol.to_json}")
  raise "Vo volume matching volid #{vol_id} exists in this AZ" unless vol
  vol
end

# Given a volume ID, is there such a volume at all?
#Given a volume id, is there such a volume?
def volume_by_id(volid)
  ec2.describe_volumes.body['volumeSet'].each do |volume|
  if volume['volumeId'] == volid
      x={
        :type => volume['volumeType'],
        :status => volume['status'],
        :az => volume['availabilityZone'],
        :size => volume['size'],
        :vol_id => volid
      }
      if volume['attachmentSet'].length>0 && volume['attachmentSet'].first.has_key?('instanceId')
        x[:instance_id] = volume['attachmentSet'].first['instanceId']
        x[:attachment_status] = volume['attachmentSet'].first['status']
      end
      return x
    end
  end
  return nil
end

# Returns true if the given volume meets the resource's attributes
def volume_compatible_with_resource_definition?(volume)
  if new_resource.snapshot_id =~ /vol/
    new_resource.snapshot_id(find_snapshot_id(new_resource.snapshot_id))
  end
  (new_resource.size.nil? || new_resource.size == volume[:aws_size]) &&
  (new_resource.availability_zone.nil? || new_resource.availability_zone == volume[:az]) &&
  (new_resource.snapshot_id == volume[:snapshot_id])
end


#Only a subset of EC2 instances support optimized ebs for now...
def supports_optimized_ebs(instancetype)
  allowed=["m1.large","m1.xlarge","m2.xlarge","m2.4xlarge"]
  allowed.include?(instancetype)
end

#Create a standard/optimized ebs volume and return its volume-id
def create_volume(snapshot_id, size, availability_zone, timeout, voltype, iops,desc=nil)
    availability_zone  ||= instance_availability_zone
    opts=Hash.new
    opts['SnapshotId']=snapshot_id if snapshot_id && !snapshot_id.empty?
    if (voltype=='io1')
      opts['VolumeType']='io1'
      opts['Iops']=iops.to_i
    end
    Chef::Log.debug "Creating #{size}GB EBS vol in #{availability_zone} with opts #{opts.to_json}"
    newvol=ec2.create_volume(availability_zone,size.to_i,opts)
    if (desc && desc.length>0)
      #If I ever use the console, its nice to know whats what...
      Chef::Log.info("Tagging Volume #{newvol.body['volumeId']} as Name:#{desc}")
      ec2.tags.create :key => "Name", :value => desc, :resource_id => newvol.body['volumeId']
    end
    begin
      Timeout::timeout(timeout) do
        while true
          vol = volume_by_id(newvol.body['volumeId'])
          if vol && vol[:status] != "deleting"
            if ["in-use", "available"].include?(vol[:status])
              Chef::Log.info "EBS Volume #{newvol.body['volumeId']} size=#{size},type=#{voltype},iops=#{iops} is now available"
              break
            else
              Chef::Log.debug "Volume #{newvol.body['volumeId']} is still #{vol[:status]}"
            end
            sleep 3
          else
            raise "Volume #{newvol.body['volumeId']} is no longer present!"
          end #tested vol availability

        end #end of while
      end #end of timeout
    rescue Timeout::Error
      raise "Timed out waiting for volume creation after #{timeout} seconds"
    end
  newvol.body['volumeId']
end

def attach_volume(volume_id, instance_id, device, timeout)
  Chef::Log.debug("Attaching #{volume_id} as #{device} to this instance (#{instance_id})")
  vol = volume_by_id(volume_id)
  if vol[:attachment_status] == "attached"
    #Do not mess with volume thats already attached elsewhere!
    raise "Appears volume #{volume_id} is already attached to another instance #{vol[:instance_id]}!"
  end
  ec2.attach_volume(instance_id,volume_id, device)
 
 begin
  Timeout::timeout(timeout) do
  while true
    vol = volume_by_id(volume_id)
    if vol && vol[:status] != "deleting"
      if vol[:attachment_status] == "attached"
        if vol[:instance_id] == instance_id
          Chef::Log.info("Volume #{volume_id} is now attached to instance #{instance_id}")
          break
        else
          raise "Volume #{volume_id} is attached to instance #{vol[:instance_id]} instead of this instance (#{instance_id})!"
        end
      else
          Chef::Log.debug("Volume is in state #{vol[:status]}")
      end       
      sleep 3
    else
     raise "Volume #{volume_id} no longer is present!" 
    end
  end
  end
 rescue Timeout::Error
    raise "Timed out after waiting for attachment for #{timeout} seconds"
 end 

end

def detach_volume(volume_id, timeout)
  Chef::Log.info("Trying to detach volume #{volume_id}")
  vol = volume_by_id(volume_id)
  old_instance_id=vol[:instance_id]
  #Do not detach unless volume was associated with this instance
  if old_instance_id=~/^i-/
    raise "Volume #{volume_id} is attached to a different instance #{old_instance_id} and not to me(#{instance_id})!" unless old_instance_id==instance_id
  else
    Chef::Log.warn "Volume #{volume_id} appears to be unassociated, nothing to do!"
    return
  end

  begin
    Timeout::timeout(timeout) do
      while true
        vol = volume_by_id(volume_id)
        if vol && vol[:status] != "deleting"
          if vol[:instance_id] != old_instance_id
            Chef::Log.info("Volume #{volume_id} is now detached...")
            break
          else
            Chef::Log.debug("Vol info: #{vol.inspect}")
          end
        else
          Chef::Log.debug("Volume #{volume_id} is gone...")
          break
        end
        sleep 3
      end
    end
  rescue Timeout::Error
    raise "Timed out waiting to detach volume #{volume_id} from instance #{old_instance_id}"
  end
end
