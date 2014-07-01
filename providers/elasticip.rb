include Onepower::AWS
#Provides elastic IP associate and dissociate for this instance alone.
#The EIP itself should have been provisioned earlier (allocate!)

action :show do
  myip=nil
  addr=findmyip
  if addr.nil?
    myip=nil 
  else
   myip=addr['publicIp'] if addr.has_key?('publicIp')
  end 
  supposed_eip=new_resource.ip
  Chef::Log.info("AWS-EC2: Supposed to have EIP=#{supposed_eip} (as per config), Currently has EIP=#{myip.nil? ? "NONE": myip}")
end

action :associate do
  addr = address(new_resource.ip)

  if addr.nil?
    raise "Elastic IP #{new_resource.ip} does not exist. First run 'allocate_address' (EC2 API) to request a new elastic IP. "
  elsif addr['instanceId'] == instance_id
    Chef::Log.debug("Elastic IP #{new_resource.ip} is already attached to the instance")
  else
    attach(new_resource.ip, new_resource.timeout) #Within attach() we will fail if EIP is alloted to another instance.
    new_resource.updated_by_last_action(true)
    node.save unless Chef::Config[:solo]
    Chef::Log.info("Attached Elastic IP #{new_resource.ip} to the instance")
  end
end

action :disassociate do
  addr = address(new_resource.ip)

  if addr.nil?
    Chef::Log.debug("Elastic IP #{new_resource.ip} does not exist, so there is nothing to detach")
  elsif addr['instanceId'] != instance_id
    Chef::Log.debug("Elastic IP #{new_resource.ip} is already detached from the instance")
  else
    Chef::Log.info("Detaching Elastic IP #{new_resource.ip} from the instance")
    detach(new_resource.ip, new_resource.timeout)
    new_resource.updated_by_last_action(true)
    node.save unless Chef::Config[:solo]
  end
end

private

def findmyip
  ec2.describe_addresses.body['addressesSet'].find{|x| x['instanceId']==instance_id}
end

def address(ip)
  #Should get a single hash like this.
  #{"domain"=>"standard", "publicIp"=>"23.23.244.20", "instanceId"=>nil}
  #OR {"domain"=>"standard", "publicIp"=>"54.24.24.5", "instanceId"=>"i-6bxxx80c"} 
  ec2.describe_addresses('public-ip' => [ ip ]).body['addressesSet'].find{|x| x['publicIp'] == ip }
end

def attach(ip, timeout)
  #We will associate this EIP to this instance ONLY if its not already associated with another.
  preassoc=address(ip)
  if !preassoc.nil? && preassoc.has_key?('instanceId') && ! preassoc['instanceId'].nil?
    raise "ElasticIP #{ip} is already attached to another instance #{preassoc['instanceId']}!"
  else
    Chef::Log.info("Trying to associate me #{instance_id} with EIP #{ip}")
    ec2.associate_address(instance_id, ip)
  end
  # block until attached
  begin
    Timeout::timeout(timeout) do
      while true
        addr = address(ip)
        if addr.nil?
          raise "Elastic IP has been deleted while waiting for attachment"
        elsif addr['instanceId'] == instance_id
          Chef::Log.debug("Elastic IP is attached to this instance")
          break
        else
          Chef::Log.debug("Elastic IP is currently attached to #{addr[:instance_id]}")
        end
        sleep 3
      end
    end
  rescue Timeout::Error
    raise "Timed out waiting for attachment after #{timeout} seconds"
  end
end

def detach(ip, timeout)
  #We will disassociate ONLY if the IP is associated with this instance.
  predissoc=address(ip)
  if predissoc.nil?
    raise "Provided ElasticIP #{ip} does'nt seem to be valid/allocated" 
  end
  if predissoc.has_key?('instanceId') && predissoc['instanceId'] != instance_id
    Chef::Log.debug("Instance #{instance_id} is trying to dissociate EIP #{ip} belonging to instance #{predissoc['instanceId']}")
    raise "Dissociating ElasticIP of other instances is NOT allowed! (EIP #{ip} belongs to #{predissoc['instanceId']} and not me!"
  else
    ec2.disassociate_address(ip)
  end

  # block until detached
  begin
    Timeout::timeout(timeout) do
      while true
        addr = address(ip)
        if addr.nil?
          Chef::Log.debug("Elastic IP has been deleted while waiting for detachment")
        elsif addr['instanceId'] != instance_id
          Chef::Log.debug("Elastic IP is detached from this instance")
          break
        else
          Chef::Log.debug("Elastic IP is still attached")
        end
        sleep 3
      end
    end
  rescue Timeout::Error
    raise "Timed out waiting for detachment of EIP #{ip} after #{timeout} seconds"
  end
end
