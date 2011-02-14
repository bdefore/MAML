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

require 'optparse'
require 'ostruct'
require 'fileutils.rb'

options = OpenStruct.new(:verbose => false)

OptionParser.new do |opts|
  opts.banner = "Usage: maml.rb [options] <command> <filespec>+"
  opts.on("-v", "--verbose") do |v|
    options.verbose = v
  end
end.parse!

input_path = ARGV[0]
output_path = ARGV[1]

def to_maml(input_path, output_path)
  
  result = ""
  File.readlines( input_path, 'r' ).each do |line|
    result += line
  end

  # Strip <fx:Script> node off, put at end later. For now only fx namespace allowed for Script
  scriptNode = slice_node(result, "<fx:Script>", "</fx:Script>")
  # Strip off <?xml version="1.0" encoding="utf-8"?>
  declarations = slice_node(result, "<?", "?>")
  # Strip comments
  comments = slice_all_nodes(result, "<!--", "-->")
  puts "WARNING: Stripped " + String(comments.length) + " comments from " + input_path
  
  # Remove all whitespace outside of tags and between attributes, outside of CDATA

  result = result.gsub(/\>[\s]+\</, "><")
  result = result.gsub(/[\n\t]/, " ")
  result = result.gsub(/[ ]+/, " ")

  # Convert self closing tags to open and closed tags

  result = result.gsub(/[^>]<([A-Za-z0-9]+):([A-Za-z0-9]+) ([^>]+)\/>/, "\n\none\n\\1:\n\ntwo\n\\2 \n\nthree\n\\3>\n\none\n</\\1>");

  # Persist an indentation value, ++ every time a closing tag is found, -- when the tag that initiated the increment is closed.
  indents = 0
  indentationAmount = 4
  nestedResult = ""
  result = result[1..result.length]
  result = result.split(/\>\</)

  result.each do |nestedLevel|
    # put the split target back on
    nestedLevel = "<" + nestedLevel + ">\n"

    # determine kind of node
    selfClosingNode = nestedLevel.index(/\/>/)
    closingNode = nestedLevel.index(/<\//)
    openingNode = !closingNode

    # revert earlier increment if this is closing node of an earlier open one
    if closingNode
      indents -= 1
    end

    # now that we've got a read on how far to indent, remove brackets
    nestedLevel = nestedLevel.gsub(/<\//, "");
    nestedLevel = nestedLevel.gsub(/\/>/, "");
    nestedLevel = nestedLevel.gsub(/[\s]+>/, ">"); # whitespace before closing tag breaks the attribute split
    nestedLevel = nestedLevel.gsub(/[<>]/, "");

    # ensure one space between any = operator 
    nestedLevel = nestedLevel.gsub(/([\S])\=([\S])/, "\\1 = \\2")

    # split between class name and attributes
    twoHalves = nestedLevel.split(" ", 2)
    klass = twoHalves[0]
    attrNameValuePairs = twoHalves[1].split("\"");

    # pad with indentation at this level
    klass = klass.rjust(klass.length + (indents*indentationAmount))
    
    nestedLevelWithAttrs = klass;

    # find largest attribute name in order to pad correctly
    largestAttrNameLength = 0;

    attrs = []
    while attrNameValuePairs.length > 0
      name = attrNameValuePairs.shift()
      value = attrNameValuePairs.shift()
      if(name && value)
        largestAttrNameLength = [ name.index(/\=/), largestAttrNameLength ].max;
        attrs.push(name.lstrip + value)
      end
    end

    attrs.each do |attr|
      # - Outdent attribute values to the position just right of the longest named attribute
      attrHalves = attr.split(" = ");
      attrName = attrHalves[0]
      attrValue = attrHalves[1]
      toPad = largestAttrNameLength - attrName.length - 2
      paddedAttr = attrName.ljust(attrName.length + toPad) + " = " + attrValue;
      indentedAttr = paddedAttr.rjust(paddedAttr.length + (indents*indentationAmount))
      nestedLevelWithAttrs += "\n" + indentedAttr
    end
  
    nestedLevelWithAttrs += "\n\n"

    # append to accumulating string, ixnay the closing nodes for this formatting style
    if openingNode
      nestedResult += nestedLevelWithAttrs
    end

    # increment indentation for next node if this one never closed
    if openingNode
      indents += 1
    end

    # self-closers
    if selfClosingNode
      indents -= 1
    end
  end
  
  output = nestedResult 
  if scriptNode
    output += "\n" + scriptNode
  end
  
  write_to_file output, output_path

end

def to_mxml(input_path, output_path)

  mxmlNode = MxmlNode.new
  mxmlNode.attributes = []
  mxmlNodes = []
  isObjectDeclarationLine = true # first object must always be first line

  result = ""
  File.readlines( input_path, 'r' ).each do |line|
    result += line
  end

  scriptNode = slice_node(result, "<fx:Script>", "</fx:Script>")

  lines = result.split("\n")
  
  lines.each do |line|
    whitespace = line.match(/^[ ]+/);
    
    if(whitespace)
      # MatchData object contains full match in 0 index
      mxmlNode.indent = whitespace[0].length
    end

    # if it's an empty line, signifies end of mxml node
    if line.length == 0
      mxmlNodes.push(mxmlNode)
      mxmlNode = MxmlNode.new
      mxmlNode.attributes = []
      
      isObjectDeclarationLine = true
    else
      if isObjectDeclarationLine
        strippedLine = line.lstrip.rstrip
        if strippedLine.index(/\:/)
          tempArr = strippedLine.split(/\:/)
          mxmlNode.namespace = tempArr[0]
          mxmlNode.klass = tempArr[1]
        else
          puts "WARNING: Found MXML node without namespace declaration. This is currently experimental support!"
          mxmlNode.namespace = ""
          mxmlNode.klass = strippedLine
        end
        # further lines before empty line are attributes
        # indicate that to the logic here
        isObjectDeclarationLine = false
      else
        # is attribute line

        strippedLine = line.lstrip.rstrip
        nameValuePair = strippedLine.split("= ");
        name = nameValuePair[0].rstrip
        value = nameValuePair[1].lstrip

        attribute = MxmlNodeAttribute.new
        attribute.name = name
        attribute.value = value
        
        mxmlNode.attributes.push( attribute )
      end
    end
  end

  # if file does not end with a new line, the above loop does not
  # push the final node it's building. we check that here
  if(!isObjectDeclarationLine)
    mxmlNodes.push(mxmlNode)
  end

  # parse into mxml bracket notation
  fullOutput = ""
  nodesToCloseYet = []

  # we first pop off the mother node since she has no indentation
  # and no children that would trigger her to output her open node
  containerNode = mxmlNodes.shift()
  if(containerNode)
    containerNode.indent = 0
    fullOutput = open_mxml_node(containerNode)
    nodesToCloseYet.push(containerNode)
  end

  if scriptNode
    fullOutput += scriptNode
  end
  
  mxmlNodes.each do |mxmlNode|

    openingNode = open_mxml_node(mxmlNode)

    parentNodeFound = false
    while !parentNodeFound && nodesToCloseYet.length > 0
      
      nodeToClose = nodesToCloseYet.pop();
      
      if nodeToClose.indent >= mxmlNode.indent
        # nodeToClose is a child of previous node close it first then 
        # continue through set of nodesToClose seeking parent

        # puts "Found child of previous node that needs closing: " + nodeToClose.klass + " before " + mxmlNode.klass
        fullOutput += close_mxml_node(nodeToClose)

      elsif nodeToClose.indent == mxmlNode.indent
        # nodeToClose is a sibling. close it first then 
        # continue through set of nodesToClose seeking parent

        # puts "Found sibling: " + nodeToClose.klass + " of " + mxmlNode.klass
        fullOutput += close_mxml_node(nodeToClose)

      else
        # the nodeToClose is the parent of the current node. not ready to close yet
        # we may now write out the opening node which we are currently iterating through
        
        fullOutput += openingNode
        nodesToCloseYet.push(nodeToClose)
        parentNodeFound = true;
      end
    end

    # store closing tag, will wait to output until next object has less indentation
    nodesToCloseYet.push(mxmlNode);

  end

  # whatever parent node(s) did not have children were not found in the loop above
  # they need to be closed out now
  while nodesToCloseYet.length > 0
    fullOutput += close_mxml_node(nodesToCloseYet.pop())
  end

  write_to_file fullOutput, output_path

end

def slice_all_nodes(base_string, start_match, end_match)
  results = []
  while base_string.index(start_match)
    results.push(slice_node(base_string, start_match, end_match));
  end
  return results
end

def slice_node(base_string, start_match, end_match)
  start_point = base_string.index(start_match)
  if(start_point)
    end_point = base_string.index(end_match, start_point)

    if(end_point)
      end_point += end_match.length

      if(base_string && start_point && end_point)
        result = base_string.slice!(start_point..end_point)
      end
    end
  end
  
  return result
end

def open_mxml_node(mxmlNode)
  openingNode = "<" + mxmlNode.namespace + ":" + mxmlNode.klass
  openingNode = openingNode.rjust(openingNode.length + mxmlNode.indent);

  mxmlNode.attributes.each do |attribute|
    openingNode += " " + attribute.name + "=\"" + attribute.value + "\""
  end

  openingNode += ">\n"

  return openingNode
end

def close_mxml_node(mxmlNode)
  closingOutput = "</" + mxmlNode.namespace + ":" + mxmlNode.klass + ">"
  closingOutput = closingOutput.rjust(closingOutput.length + mxmlNode.indent) + "\n"
  return closingOutput
end

def write_to_file(output, output_path)

  if !output || output == ""
    puts "=========================================================="
    puts "== Nothing to output!"
    puts "=========================================================="
  elsif !output_path
    puts "=========================================================="
    puts "== No output_path specified, printing to std_out begins"
    puts "=========================================================="
    puts output
    puts "=========================================================="
    puts "== No output_path specified, printing to std_out complete"
    puts "=========================================================="
  else

    dirname = File.dirname(output_path)
    if !File.exist?(dirname)
      puts "Creating directory: " + dirname
      FileUtils.mkpath dirname
    end

    if !File.directory?(output_path)
      f = File.open(output_path, "w")
      f.puts output
      puts "Written successfully to " + output_path
    else
    end
  end
end

class MxmlNode
  def initialize()
  end
  attr_reader :lindent, :indent
  attr_writer :lindent, :indent
  attr_reader :lnamespace, :namespace
  attr_writer :lnamespace, :namespace
  attr_reader :lklass, :klass
  attr_writer :lklass, :klass
  attr_reader :lattributes, :attributes
  attr_writer :lattributes, :attributes
end

class MxmlNodeAttribute
  def initialize()
  end
  attr_reader :lname, :name
  attr_writer :lname, :name
  attr_reader :lvalue, :value
  attr_writer :lvalue, :value
end

def build_mtimes_hash(globs)
  files = {}
  globs.each { |g|
    Dir[g].each do |file|
      if !File.directory?(file)
        files[file] = File.mtime(file)
      end
    end
  }
  files
end

def convert(input_path, output_path)
  if input_path.upcase.index(/MXML/)
    to_maml input_path, "maml_export/" + output_path.gsub(".MXML", ".maml")
  elsif input_path.upcase.index(/MAML/)
    to_mxml input_path, "mxml_export/" + output_path.gsub(".MXML", ".mxml")
  end
end

if !input_path
  puts "================================================="
  puts "== maml.rb version ASYMPTOTIC TO ZERO"
  puts "================================================="
  puts "== Please specify a path to an MXML or MAML file,"
  puts "== and optionally a path to output to."
  puts "================================================="

else
  files = build_mtimes_hash(ARGV)
  if files
    if options.verbose 
      puts "Building #{files.keys.join(', ')}\n\nFiles: #{files.keys.length}"
    end
    files.each do |file|
      # only pass in file names to convert, not dirs
      if !File.directory?(input_path)
        convert(file[0], file[0])
      end
    end
  else
    puts "================================================="
    puts "== maml.rb version ASYMPTOTIC TO ZERO"
    puts "================================================="
    puts "== Expecting a mxml or maml file"
    puts "================================================="
  end
end