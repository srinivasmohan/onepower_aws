Description
===========

This cookbook provides libraries, resources and providers to configure and manage Amazon Web Services components and offerings with the EC2 API. Currently supported resources:

* EBS Volumes (`ebs_volume`)
* Elastic IPs - (`elasticip`)
* Elastic Load Balancer - TODO

This is built from the Opscode AWS cookbook with the following differences -
* Uses Fog instead of `rightaws`
* As a result, allows creation of AWS PIOPS EBS volumes (EBS with guaranteed IOPs)
* Tags created volumes if description is set (Name tag shows in console)

Requirements
============

An Amazon Web Services account is required. The Access Key and Secret Access Key are used to authenticate with EC2.

AWS Credentials
===============

In order to manage AWS components, authentication credentials need to be available to the node. There are a number of ways to handle this, such as node attributes or roles. We recommend storing these in a databag (Chef 0.8+), and loading them in the recipe where the resources are needed.

DataBag recommendation:

    % knife data bag show aws main
    {
      "id": "main",
      "aws_access_key_id": "YOUR_ACCESS_KEY",
      "aws_secret_access_key": "YOUR_SECRET_ACCESS_KEY"
    }

This can be loaded in a recipe with:

    aws = data_bag_item("aws", "main")

And to access the values:

    aws['aws_access_key_id']
    aws['aws_secret_access_key']

We'll look at specific usage below.

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

This cookbook provides two resources and corresponding providers.

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

Usage
=====

For both the `ebs_volume` and `elastic_ip` resources, put the following at the top of the recipe where they are used.

    include_recipe "onepower_aws"
    aws = data_bag_item("aws", "main")

onepower_aws_ebs_volume
-----------------------

The resource only handles manipulating the EBS volume, additional resources need to be created in the recipe to manage the attached volume as a filesystem or logical volume.

    onepower_aws_ebs_device "db_ebs_volume" do
      aws_access_key aws['aws_access_key_id']
      aws_secret_access_key aws['aws_secret_access_key']
      size 50
      device "/dev/sdi"
      action [ :create, :attach ]
    end

This will create a 50G volume, attach it to the instance as `/dev/sdi`.

    onepower_aws_ebs_device "db_ebs_volume_from_snapshot" do
      aws_access_key aws['aws_access_key_id']
      aws_secret_access_key aws['aws_secret_access_key']
      size 50
      device "/dev/sdi"
      snapshot_id "snap-ABCDEFGH"
      type "io1"
      iops "500"
      action [ :create, :attach ]
    end

This will create a new io1 type EBS volume of 50G which guarantees upto 500 iops from the snapshot ID provided and attach it as `/dev/sdi`.

onepower_aws_elasticip
----------------------

This LWRP does not "create" a new elastic IP. It can only map existing elastic IPs to an instance.
Actions:

* `:show` - Simply log Elastic IP info to chefs log
* `:associate` - Associate instance with an Elastic IP
* `:disassociate` - Dis-associate mapped Elastic IP from "this" instance.


Attributes:
* `:aws_access_key` - AWS/EC2 access key
* `:aws_secret_access_key` - AWS/EC2 Secret
* `:ip` - The elastic IP
* `:timeout` - Defaults to 3 minutes but could be set to higher if needed.

Usage

```

#Ohai reload is optional
ohai "reload-ohai-nodedata" do
	action :nothing
end

onepower_aws_elasticip "elastic-ip-setup" do
	action [ :associate,:show ]
	ip 1.2.3.4
	aws_access_key aws['aws_access_key_id']
	aws_secret_access_key aws['aws_secret_access_key']
	#notifies :reload, resources(:ohai => "reload-ohai-nodedata"), :immediately
end

```

License and Author
==================

Changes to Opscode AWS cookbook to use Fog and support IOPS Vol creation:

Author:: Srinivasan Mohan (<srinivas@onepwr.org>)

Original AWS cookbook this derived from:
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

* `v0.10` - Initial commit.
* `v0.11` - Added elasticip.
