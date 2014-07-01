#
# Cookbook Name:: onepower_aws
# Recipe:: default
#
# Copyright 2013, Srinivasan Mohan, Onepower
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#Make sure require packages in place for fog.
%w{libxslt-dev libxml2-dev}.each do |thispack|
  packinstall = package "#{thispack}" do
    action :nothing
  end
  packinstall.run_action(:install)
end
#Install required gems and load them
%w{fog}.each do |thisgem|
  r = gem_package thisgem do
    action :nothing
  end
  r.run_action(:install)
end

require "rubygems"
Gem.clear_paths
require "fog"


class Chef::Recipe
  include Onepower::AWS
end
