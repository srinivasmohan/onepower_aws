#!/usr/bin/ruby
require 'rubygems'
require 'yaml'
require 'json'
require 'fog'
require 'timeout'

#Given a volume id, is there such a volume?
def volume_by_id(ec2,volid)
  ec2.describe_volumes.body['volumeSet'].each do |volume|
    if volume['volumeId'] == volid
      x= {
        :type => volume['volumeType'],
        :status => volume['status'],
        :az => volume['availabilityZone'],
        :size => volume['size']
      }
      #puts "VOLINFO #{volid}\n"+volume.to_yaml
      x[:instance_id] = volume['attachmentSet'].first['instanceId'] if volume['attachmentSet'].length>0 && volume['attachmentSet'].first.has_key?('instanceId')
      return x
    end
  end
  return {}
end

def create_volume(ec2,snapshot_id, size, availability_zone, timeout, voltype, iops,desc=nil)
    opts=Hash.new
    opts['SnapshotId']=snapshot_id if snapshot_id && !snapshot_id.empty?
    if (voltype=='io1')
      opts['VolumeType']='io1'
      opts['Iops']=iops.to_i
    end 
    newvol=nil
    begin 
      newvol=ec2.create_volume(availability_zone,size.to_i,opts) 
    rescue Exception => e
      puts "Failed AZ #{availability_zone} - #{e.inspect}"
      return nil
    end
    return nil unless newvol.body['volumeId']
    if (desc && desc.length>0)
      #puts "Tagging Volume #{newvol.body['volumeId']} as #{desc}"
      ec2.tags.create :key => "Name", :value => desc, :resource_id => newvol.body['volumeId']
    end 
    begin
      Timeout::timeout(timeout) do
        while true
          vol = volume_by_id(ec2,newvol.body['volumeId'])
          if vol && vol[:status] != "deleting"
            if ["in-use", "available"].include?(vol[:status])
              #puts "Volume #{newvol.body['volumeId']} is available"
              break
            else
              puts "Volume #{newvol.body['volumeId']} is #{vol[:status]}"
            end
            sleep 2
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


creds=Hash.new

begin
  creds=YAML::load(File.open("./auth.yml"))
rescue Exception => e
  abort "Error fetching AWS auth info - #{e.inspect}"
end


abort "No region specified in config." unless (creds.has_key?(:region) )
thisregion=creds[:region]

fogobj = Fog::Compute.new(
    :provider => 'AWS',
    :region => thisregion,
    :aws_access_key_id => creds[:aws_access_key_id],
    :aws_secret_access_key => creds[:aws_secret_access_key]
)

volhash=Hash.new
["a","b","c","d","e"].each do |zone|
  $stderr.puts "Trying zone #{thisregion}#{zone}"
  begin
    volid=create_volume(fogobj,nil, 40, "#{thisregion}#{zone}", 180, "io1", 400,"TEST-iop-#{thisregion}-#{zone}")
    volhash["#{thisregion}#{zone}"]=volid unless volid.nil? 
  rescue Exception => e
   $stderr.puts "Failed #{thisregion}#{zone} - #{e.inspect}"
  end
  puts ""
end

puts "PIOPS Supported AZs are(along with test volumes created)\n"+volhash.to_yaml

volhash.keys.each do |x|
  fogobj.delete_volume(volhash[x]) 
end
