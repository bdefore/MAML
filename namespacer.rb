#!/usr/bin/env ruby
#
# Author:   Buck DeFore
# Version:  ASYMPTOTIC TO ZERO
#
# See README for more info: https://github.com/bdefore/MAML
#
# MIT License
# 
# Copyright (c) 2011 Buck DeFore
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'ostruct'
require 'rexml/document'

def read_file(file_path)
  result = ""
  File.readlines( file_path, 'r' ).each do |line|
    result += line
  end
  $current_source_file = file_path
  return result
end  

$classpaths = Hash.new()

spark_manifest_xml = REXML::Document.new(read_file('manifests/frameworks/spark-manifest.xml'))
spark_manifest_xml.elements.each('componentPackage/component') do |ele|
  # if($classpaths[ele.attributes['id']])
  #   puts "WARNING: More than one class found for " + ele.attributes['id'] + " in the namespace table."
  # end
  $classpaths[ele.attributes['id']] = OpenStruct.new(:classpath => ele.attributes['class'], :prefix => "s:")
end

mx_manifest_xml = REXML::Document.new(read_file('manifests/frameworks/mxml-manifest.xml'))
mx_manifest_xml.elements.each('componentPackage/component') do |ele|
  # if($classpaths[ele.attributes['id']])
  #   puts "WARNING: More than one class found for " + ele.attributes['id'] + " in the namespace table."
  # end
  $classpaths[ele.attributes['id']] = OpenStruct.new(:classpath => ele.attributes['class'], :prefix => "mx:")
end