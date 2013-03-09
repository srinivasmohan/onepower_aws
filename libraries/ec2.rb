begin
    require 'fog'
rescue LoadError
    Chef::Log.warn("Missing fog gem!")
end
require 'json'
require 'open-uri'

#http://wiki.opscode.com/pages/viewpage.action?pageId=7274964 - Orig resource stored to provider as @new_resource
module Onepower
  module AWS
      #Given a volume id, find the latest snapshot
      def find_snapshot_id(volume_id="")
        snapshot_id = nil
        ec2.describe_snapshots.body['snapshotSet'].sort { |a,b| b['startTime'] <=> a['startTime'] }.each do |ss|
         if ss['volumeId'] == volume_id
            snapshot_id=ss['snapshotId']
          end
        end
      raise "Cannot find snapshot id for volumeid #{volume_id}" unless snapshot_id
      Chef::Log.debug("Snapshot ID is #{snapshot_id}") 
      snapshot_id
      end 
 
      def instance_id
        @@instance_id ||= find_instance_id
      end

      def instance_availability_zone
        @@instance_availability_zone ||= find_instance_az
      end

      def instance_type
        @@instance_type ||= find_instance_type
      end

      def ec2
        region=instance_availability_zone
        region=region[0..-2]
        @@ec2 ||= Fog::Compute.new(
          :provider => 'AWS',
          :region => region, 
          :aws_access_key_id => "#{new_resource.aws_access_key}",
          :aws_secret_access_key => "#{new_resource.aws_secret_access_key}"
          )
      end

      #Private
      private
      #Find my instance id
      def find_instance_id
        instance_id = open('http://169.254.169.254/latest/meta-data/instance-id'){|f| f.gets}
        raise "Could not find instance id!" unless instance_id
        Chef::Log.debug("This instance-id is #{instance_id}")
        instance_id
      end

      #Which Availability zone am I in?
      def find_instance_az
        az = open('http://169.254.169.254/latest/meta-data/placement/availability-zone/'){|f| f.gets}
        raise "Could not find availability zone!" unless az
        Chef::Log.debug("Instance #{instance_id} is in AZ #{az}")
        az
      end

      def find_instance_type
        itype=open('http://169.254.169.254/latest/meta-data/instance-type'){|f| f.gets}
        raise "Could not find instance type!" unless itype
        Chef::Log.debug("Instance type is #{itype}")
        itype
      end

    end #End of AWS

end #end of Onepower
