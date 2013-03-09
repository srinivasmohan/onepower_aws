Description
===========

This cookbook provides libraries, resources and providers to configure and manage Amazon Web Services components and offerings with the EC2 API. While the Opscode provide aws cookbook does do this, It does'nt support creating AWS PIOPS EBS volumes (which I need!) and hence this cookbook. 

Currently supported resources:

* EBS Volumes (`ebs_volume`) - My primary need was to be able to setup [Provisioned IOPS Volumes](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSPerformance.html#benchmark_piops), so this is the only present option for now in this cookbook.
* Elastic IPs - TODO/On-the-way
* Elastic Load Balancer - TODO/On-the-way

This is built from the Opscode AWS cookbook with the following differences -
* Uses Fog instead of `rightaws`
* As a result, allows creation of AWS PIOPS EBS volumes (EBS with guaranteed IOPs)
* Tags created volumes if description is set (Name tag shows in console)

This is a drop in replacement in cookbooks that use the AWS module - However for *existing chef managed instances that had volumes crested using `aws` module*, you may need to update the node data as this module uses the node attributes `onepwr_aws/ebs_volume` to persist info on volume-ids of alloted volumes etc.

Requirements
============

An Amazon Web Services account is required. The Access Key and Secret Access Key are used to authenticate with EC2.

AWS Credentials
===============

In order to manage/provision AWS , auth credentials are needed (access key id and access key secret). You could either bake in the keys into each cookbook (pain) or else put them in a data bag (preferably encrypted; although this example shows an unencrypted one) and source it in the recipe.

DataBag recommendation:

    % knife data bag show aws main
    {
      "id": "main",
      "aws_access_key_id": "YOUR_ACCESS_KEY",
      "aws_secret_access_key": "YOUR_SECRET_ACCESS_KEY"
    }

This can be loaded in a recipe with:

    awscreds = data_bag_item("aws", "main")

And to access the values:

    awscreds['aws_access_key_id']
    awscreds['aws_secret_access_key']

More on specific usage below.

Recipes
=======

default.rb
----------

The default recipe installs the `fog` RubyGem, which this cookbook requires in order to work with the EC2 API. Make sure that the `onepower _aws` recipe is in the node or role `run_list` before any resources from this cookbook are used.

    "run_list": [
      "recipe[onepower_aws]"
    ]

The `gem_package` is created as a Ruby Object and thus installed during the Compile Phase of the Chef run.

Fog version 1.6.0 and higher supports creating IOPS/Optimized iO EBS volumes so this cookbook will attempt to install that.

Libraries
=========

The cookbook has a library module, `Onepower::AWS`, which can be included where necessary:

    include Onepower::AWS

This is needed in any providers in the cookbook. Along with some helper methods used in the providers, it sets up a class variable, `ec2` that is used along with the access and secret access keys

Resources and Providers
=======================

This cookbook provides the following:

`ebs_volume.rb`
-------------

Manage Elastic Block Store (EBS) volumes with this resource.

Actions:

* `create` - create a new volume.
* `attach` - attach the specified volume.
* `detach` - detach the specified volume.
* `snapshot` - create a snapshot of the volume.
* `prune` - prune snapshots.

Attribute Parameters:

* `aws_secret_access_key`, `aws_access_key` - passed to `Opscode::AWS:Ec2` to authenticate, required.
* `size` - size of the volume in gigabytes.
* `snapshot_id` - snapshot to build EBS volume from.
* `availability_zone` - EC2 region, and is normally automatically detected.
* `device` - local block device to attach the volume to, e.g. `/dev/sdi` but no default value, required.
* `volume_id` - specify an ID to attach, cannot be used with action `:create` because AWS assigns new volume IDs
* `timeout` - connection timeout for EC2 API.
* `snapshots_to_keep` - used with action `:prune` for number of snapshots to maintain.
* `description` - used to set the description of an EBS snapshot
* `type` - EBS volume type - Can be `io1` for IOPS volume and defaults to `standard`.
* `iops` - If volume type is `io1` then this a required param which is the number of IOPS requested.

The `ebs_volume` provider does not allow you to detach/delete volumes that dont below to `this` instance (i.e. where this is invoked)

Usage
=====

For both the `ebs_volume` resource, put the following at the top of the recipe where they are used.

    include_recipe "onepower_aws"
    awscreds = data_bag_item("aws", "main")

aws_ebs_volume
--------------

The resource only handles manipulating the EBS volume, additional resources need to be created in the recipe to manage the attached volume as a filesystem or logical volume.

    onepower_aws_ebs_device "db_ebs_volume" do
      aws_access_key awscreds['aws_access_key_id']
      aws_secret_access_key awscreds['aws_secret_access_key']
      size 50
      device "/dev/sdi"
      action [ :create, :attach ]
      description "#{node['fqdn']} /somepartition"
    end

This will create a 50G volume, attach it to the instance as `/dev/sdi`.

    onepower_aws_ebs_device "db_ebs_volume_from_snapshot" do
      aws_access_key awscreds['aws_access_key_id']
      aws_secret_access_key awscreds['aws_secret_access_key']
      size 50
      device "/dev/sdj"
      snapshot_id "snap-ABCDEFGH"
      type "io1"
      iops "500"
      action [ :create, :attach ]
      description "#{node['fqdn']} PIOPS /somepartition"
    end

This will create a new io1 type EBS volume of 50G which guarantees upto 500 iops from the snapshot ID provided and attach it as `/dev/sdj`.
In either case, the description is optional but if specified will get set as the Name tag of the Volume(so is visible in the Volumes section of the AWS Console)

License and Author
==================

This cookbook:
Author:: Srinivasan Mohan (<git@onepwr.org>)

Many thanks to the nice folks at Opscode for the original [AWS cookbook](https://github.com/opscode-cookbooks/aws) this derived from(and Chef!):
Author:: Chris Walters (<cw@opscode.com>)
Author:: AJ Christensen (<aj@opscode.com>)
Author:: Justin Huff (<jjhuff@mspin.net>)


Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Changes
=======

* `v0.10` - Initial commit, Only has support for EBS volume setup for now, ELB and Elastic IP setup coming soon.


Misc
=======
I have tested this on Ubuntu/Debian systems only although its pure Ruby so it should work on Centos/Amzn/Redhat boxes as well. This cookbook does not do wird stuff with any attributes etc so it should be safe to run on a system with Chef gem 11.x as well although I have only tested this wth chef gem until v10.24.0.

Important
====

Note that Amazon does'nt support PIOPS volumes in all regions. For example, us-west-1 does'nt support PIOPS at all while us-east-1 supports PIOPS in only 3 out of 5 Availability zones (AZs). The concept of AZ us-east-1a-e varies depending upon every individual AWS account (so your us-east-1a is not necessarily the same physical AZ as the us-east-1a I see under my account) so its pointless for me to list which AZs this would work with... 

Trying to create a PIOPs volume in a zone that does'nt support it will lead to this response:
`The specified zone does not support 'io1' volume type`

This will cause an abort in the cookbook invocation. My recommendation is to figure out which AZs support PIOPS (See test script bin/test_iops_support.rb, update auth.yml with your AWS creds and point it to a AWS region) beforehand and setup your other cookbooks accordingly.  

Also note that while standard EBS volumes allow significant burst (in terms of IOPs), PIOPS volumes seem to burst in a very limited way (e.g. a 1000 IOPS volume did not peak beyond 1030 in my tests) - The advantage of a PIOPS volume is that its performance is guaranteed to be consistently within your IOPs requested setting and thats it.

To be able to use a PIOPS volume effectively, your instance needs to be an ebs-optimized instance (not every instance is capable of being ebs-optimized so check AWS docs) 
